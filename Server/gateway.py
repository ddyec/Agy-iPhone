#!/usr/bin/env python3
"""Authenticated iPhone adapter for agy stream-json. Python 3.10+, no dependencies."""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import signal
import sqlite3
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

MAX_BODY = 256 * 1024


class Failure(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


class Gateway:
    def __init__(self, directory, key, binary, roots, default_model="", command_prefix=None):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.key = key
        if len(key) < 32:
            raise ValueError("Gateway key must contain at least 32 characters")
        self.binary = binary
        self.prefix = command_prefix or []
        self.roots = [Path(r).resolve(strict=True) for r in roots]
        self.default_model = default_model
        self.lock = threading.RLock()
        self.processes = {}
        self.active = set()
        self.stopping = set()
        self.db = sqlite3.connect(self.directory / "gateway.sqlite", check_same_thread=False)
        os.chmod(self.directory / "gateway.sqlite", 0o600)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, data TEXT NOT NULL)")
        self.db.execute("CREATE TABLE IF NOT EXISTS requests (id TEXT PRIMARY KEY, session TEXT NOT NULL, digest TEXT NOT NULL)")
        self.db.commit()
        self.models_cache = None
        # Never resubmit an admitted prompt after a crash/restart.
        for s in self.sessions():
            if s["running"]:
                s["running"] = False
                s["error"] = "服务器已重启。请检查回复后再发送，未自动重试任务。"
                self.save(s)

    def save(self, session):
        with self.lock:
            session["revision"] = session.get("revision", 0) + 1
            self.db.execute("INSERT OR REPLACE INTO sessions VALUES (?, ?)", (session["id"], json.dumps(session, ensure_ascii=False)))
            self.db.commit()

    def get(self, sid):
        with self.lock:
            row = self.db.execute("SELECT data FROM sessions WHERE id=?", (sid,)).fetchone()
            if not row:
                raise Failure(404, "会话不存在")
            return json.loads(row[0])

    def sessions(self):
        with self.lock:
            return sorted([json.loads(r[0]) for r in self.db.execute("SELECT data FROM sessions")], key=lambda s: s["modified"], reverse=True)

    def workspace(self, value):
        try:
            p = Path(value).resolve(strict=True)
        except (OSError, ValueError, TypeError):
            raise Failure(400, "工作目录不存在")
        if not p.is_dir() or not any(p == r or r in p.parents for r in self.roots):
            raise Failure(403, "工作目录不在允许范围内")
        return str(p)

    def models(self):
        with self.lock:
            if self.models_cache and time.monotonic() - self.models_cache[0] < 300:
                return self.models_cache[1]
        try:
            result = subprocess.run(self.prefix + [self.binary, "models"], capture_output=True, text=True, timeout=40, cwd=self.roots[0])
        except (OSError, subprocess.TimeoutExpired):
            raise Failure(502, "无法获取 AGY 模型，请检查服务器登录和网络")
        if result.returncode:
            raise Failure(502, "AGY 登录或模型请求失败，请在服务器检查 agy models")
        models = []
        for line in result.stdout.splitlines():
            if "\t" in line:
                mid, name = line.split("\t", 1)
                if re.fullmatch(r"[a-zA-Z0-9_.:/-]+", mid):
                    models.append({"id": mid, "name": name})
        if not models:
            raise Failure(502, "AGY 没有返回可用模型")
        with self.lock:
            self.models_cache = (time.monotonic(), models)
        return models

    def create(self, body):
        cwd = self.workspace(body.get("cwd") or str(self.roots[0]))
        model = body.get("model") or self.default_model or self.models()[0]["id"]
        if model not in {m["id"] for m in self.models()}:
            raise Failure(400, "模型不可用")
        mode = body.get("mode", "plan")
        if mode not in ("plan", "accept-edits"):
            raise Failure(400, "执行模式无效")
        session = {"id": str(uuid.uuid4()), "name": "新会话", "cwd": cwd, "model": model, "mode": mode,
                   "modified": time.time(), "messages": [], "running": False, "conversationID": "", "error": "", "revision": 0}
        self.save(session)
        return session

    def submit(self, sid, body):
        prompt = body.get("text", "")
        rid = body.get("requestID", "")
        if not isinstance(prompt, str) or not prompt.strip() or len(prompt.encode()) > 200 * 1024:
            raise Failure(400, "消息为空或过长")
        try:
            uuid.UUID(rid)
        except (ValueError, TypeError, AttributeError):
            raise Failure(400, "缺少有效请求编号")
        digest = hashlib.sha256(prompt.encode()).hexdigest()
        with self.lock:
            prior = self.db.execute("SELECT session,digest FROM requests WHERE id=?", (rid,)).fetchone()
            if prior:
                if prior != (sid, digest):
                    raise Failure(409, "请求编号已用于另一条消息")
                return self.get(sid)
            s = self.get(sid)
            if s["running"] or sid in self.active:
                raise Failure(409, "任务仍在运行")
            self.workspace(s["cwd"])
            s["messages"].append({"id": rid, "role": "user", "text": prompt})
            s["messages"].append({"id": str(uuid.uuid4()), "role": "assistant", "text": "", "tools": []})
            if s["name"] == "新会话":
                s["name"] = prompt.strip()[:40]
            s["running"], s["error"], s["modified"] = True, "", time.time()
            # One transaction admits both the user message and its deduplication key.
            self.db.execute("INSERT INTO requests VALUES (?,?,?)", (rid, sid, digest))
            self.save(s)
            self.active.add(sid)
            threading.Thread(target=self.run, args=(sid, prompt), daemon=True).start()
            return s

    def ingest(self, sid, event):
        with self.lock:
            s = self.get(sid)
            m = s["messages"][-1]
            kind = event.get("event")
            cid = event.get("conversation_id") or event.get("result", {}).get("conversation_id")
            if cid:
                try:
                    uuid.UUID(cid)
                    s["conversationID"] = cid
                except (ValueError, TypeError):
                    pass
            if kind == "step_update":
                step = event.get("step_update", {})
                if step.get("step_type") == "agent_response":
                    m["text"] += step.get("text_delta", "")
                if step.get("step_type") == "tool":
                    # Tool events may carry ACTIVE followed by DONE: replace by step identity.
                    info = step.get("tool_info", {})
                    tool = {"id": str(step.get("step_index", 0)), "name": step.get("tool_name") or info.get("name", "工具"),
                            "state": step.get("state", ""), "parameters": info.get("parameters", {}), "output": str(info.get("output", ""))[:100000]}
                    tools = [t for t in m.setdefault("tools", []) if t["id"] != tool["id"]]
                    m["tools"] = tools + [tool]
            if kind == "result":
                result = event.get("result", {})
                if result.get("response"):
                    m["text"] = result["response"]
                m["usage"] = result.get("usage", {})
                s["error"] = result.get("error", "")
                if result.get("status") != "SUCCESS" and not s["error"]:
                    s["error"] = "AGY 结束状态：" + str(result.get("status", "未知"))
            self.save(s)

    def run(self, sid, prompt):
        process, terminal, failure = None, False, ""
        try:
            s = self.get(sid)
            # stdin keeps the prompt out of process listings; no shell interpolation.
            args = self.prefix + [self.binary, "--input-format", "stream-json", "--output-format", "stream-json",
                                  "--model", s["model"], "--mode", s["mode"], "--print-timeout", "30m"]
            if s["conversationID"]:
                args += ["--conversation", s["conversationID"]]
            with self.lock:
                if sid in self.stopping:
                    raise Failure(409, "任务已停止")
                process = subprocess.Popen(args, cwd=s["cwd"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                           stderr=subprocess.DEVNULL, start_new_session=True)
                self.processes[sid] = process
            process.stdin.write((json.dumps({"event": "user", "message": {"content": prompt}}, ensure_ascii=False) + "\n").encode())
            process.stdin.close()
            while True:
                line = process.stdout.readline(4 * 1024 * 1024 + 1)
                if not line:
                    break
                if len(line) > 4 * 1024 * 1024:
                    raise Failure(502, "AGY 输出事件过大")
                event = json.loads(line)
                self.ingest(sid, event)
                terminal |= event.get("event") == "result"
            code = process.wait(timeout=10)
            if not terminal:
                failure = f"AGY 提前结束（{code}）。请检查服务器登录、模型与执行权限。"
        except Exception as error:
            failure = error.message if isinstance(error, Failure) else "AGY 执行中断，请检查会话后再试。"
        finally:
            if process and process.poll() is None:
                self.terminate(process)
            if process:
                process.stdout.close()
                if not process.stdin.closed:
                    process.stdin.close()
            with self.lock:
                s = self.get(sid)
                s["running"] = False
                s["modified"] = time.time()
                if sid in self.stopping:
                    s["error"] = "任务已停止；已执行的操作不会自动撤销。"
                elif failure:
                    s["error"] = failure
                self.save(s)
                self.processes.pop(sid, None)
                self.active.discard(sid)
                self.stopping.discard(sid)

    @staticmethod
    def terminate(process):
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=3)
        except ProcessLookupError:
            pass

    def stop(self, sid):
        with self.lock:
            s = self.get(sid)
            if s["running"]:
                self.stopping.add(sid)
            process = self.processes.get(sid)
        if process:
            self.terminate(process)
        return self.get(sid)

    def rename(self, sid, name):
        if not isinstance(name, str) or not name.strip() or len(name) > 120:
            raise Failure(400, "名称无效")
        with self.lock:
            s = self.get(sid)
            s["name"] = name.strip()
            self.save(s)
            return s

    def delete(self, sid):
        with self.lock:
            if self.get(sid)["running"] or sid in self.active:
                raise Failure(409, "请先停止任务")
            self.db.execute("DELETE FROM sessions WHERE id=?", (sid,))
            self.db.commit()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "AGYGateway/1"

    def log_message(self, *args):
        pass  # Never log URLs, messages or Authorization headers.

    def respond(self, code, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def route(self):
        self.connection.settimeout(30)
        gateway = self.server.gateway
        try:
            auth = self.headers.get("Authorization", "")
            if not hmac.compare_digest(auth.encode(), ("Bearer " + gateway.key).encode()):
                self.close_connection = True
                raise Failure(401, "连接密钥无效")
            parts = urlsplit(self.path)
            path = parts.path.rstrip("/")
            body = {}
            if self.command in ("POST", "PATCH"):
                try:
                    size = int(self.headers.get("Content-Length", "-1"))
                except ValueError:
                    raise Failure(400, "无效请求长度")
                if not 0 <= size <= MAX_BODY:
                    self.close_connection = True
                    raise Failure(413, "请求过大或缺少长度")
                try:
                    body = json.loads(self.rfile.read(size))
                    if not isinstance(body, dict):
                        raise ValueError()
                except (ValueError, UnicodeError):
                    raise Failure(400, "无效 JSON")
            if self.command == "GET" and path == "/v1/status":
                return self.respond(200, {"name": "AGY", "version": 1, "roots": list(map(str, gateway.roots)),
                                          "defaultModel": gateway.default_model, "conversationScope": "gateway"})
            if self.command == "GET" and path == "/v1/models":
                return self.respond(200, {"models": gateway.models()})
            if path == "/v1/sessions":
                if self.command == "GET":
                    sessions = [{k: v for k, v in s.items() if k != "messages"} for s in gateway.sessions()]
                    return self.respond(200, {"sessions": sessions})
                if self.command == "POST":
                    return self.respond(201, gateway.create(body))
            match = re.fullmatch(r"/v1/sessions/([a-f0-9-]{36})(?:/(messages|stop|events))?", path)
            if match:
                sid, action = match.groups()
                if self.command == "GET" and action == "events":
                    return self.events(sid, parse_qs(parts.query))
                if self.command == "GET" and action is None:
                    return self.respond(200, gateway.get(sid))
                if self.command == "POST" and action == "messages":
                    return self.respond(202, gateway.submit(sid, body))
                if self.command == "POST" and action == "stop":
                    return self.respond(200, gateway.stop(sid))
                if self.command == "PATCH" and action is None:
                    return self.respond(200, gateway.rename(sid, body.get("name")))
                if self.command == "DELETE" and action is None:
                    gateway.delete(sid)
                    return self.respond(200, {"deleted": True})
            raise Failure(404, "接口不存在")
        except Failure as error:
            self.respond(error.status, {"error": error.message})
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            pass
        except Exception:
            self.close_connection = True
            self.respond(500, {"error": "服务器内部错误"})

    def events(self, sid, query):
        # Bounded stream connections; clients reconnect with authoritative snapshots.
        gateway = self.server.gateway
        s = gateway.get(sid)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Accel-Buffering", "no")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        previous, deadline = -1, time.monotonic() + 25
        while time.monotonic() < deadline:
            if s["revision"] != previous:
                self.wfile.write(("data: " + json.dumps(s, ensure_ascii=False) + "\n\n").encode())
                self.wfile.flush()
                previous = s["revision"]
            if not s["running"]:
                break
            time.sleep(0.3)
            s = gateway.get(sid)

    do_GET = do_POST = do_PATCH = do_DELETE = route


class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, gateway):
        self.gateway = gateway
        super().__init__(address, Handler)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8766, type=int)
    parser.add_argument("--data", default=str(Path.home() / ".local/share/agy-iphone"))
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--agy", default="/opt/pi-agent/agy-runtime/agy")
    parser.add_argument("--root", action="append", required=True)
    parser.add_argument("--default-model", default="")
    args = parser.parse_args()
    key = Path(args.key_file).read_text().strip()
    gateway = Gateway(args.data, key, args.agy, args.root, args.default_model)
    server = Server((args.host, args.port), gateway)
    print(f"AGY iPhone gateway listening on {args.host}:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        for sid in list(gateway.active):
            gateway.stop(sid)
        server.server_close()


if __name__ == "__main__":
    main()
