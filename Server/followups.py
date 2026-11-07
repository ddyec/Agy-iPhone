"""Durable user follow-ups; guidance enters through official invocation hooks."""
import hashlib
import json
import mimetypes
import time
import uuid


class Followups:
    def __init__(self, gateway):
        self.g = gateway
        gateway.db.execute('CREATE TABLE IF NOT EXISTS inbox (id TEXT PRIMARY KEY, session TEXT NOT NULL, data TEXT NOT NULL)')
        # Never replay an execution or context injection after a process crash.
        for rid, raw in gateway.db.execute('SELECT id,data FROM inbox').fetchall():
            item = json.loads(raw)
            if item['status'] in ('pending', 'dispatching', 'running'):
                item['status'] = 'unknown' if item['status'] != 'pending' else 'held'
                item['error'] = '服务器已重启，请核对后手动继续。'
                self.write(item)
        gateway.db.commit()

    def write(self, item):
        self.g.db.execute('INSERT INTO inbox VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data', (item['id'], item['sessionID'], json.dumps(item, ensure_ascii=False)))

    def items(self, sid):
        return [json.loads(raw) for (raw,) in self.g.db.execute('SELECT data FROM inbox WHERE session=? ORDER BY rowid', (sid,))]

    def snapshot(self, sid):
        items = self.items(sid)
        active = [v for v in items if v['status'] in ('pending', 'held', 'unknown', 'dispatching', 'running')]
        recent = [v for v in items if v['status'] in ('delivered', 'done')][-10:]
        keys = ('id', 'sessionID', 'delivery', 'status', 'text', 'createdAt', 'error', 'attachmentCount')
        return [{k: v[k] for k in keys} for v in active + recent]

    def touch(self, sid):
        self.g.save(self.g.get(sid))

    def prepare(self, sid, body):
        g = self.g
        s = g.get(sid)
        prompt = body.get('text', '')
        attachments = body.get('attachments', [])
        references = body.get('references', [])
        Failure = g.failure_type
        MAX_ATTACHMENTS, MAX_TOTAL = g.max_attachments, g.max_total
        if not isinstance(prompt, str) or len(prompt.encode()) > 200*1024:
            raise Failure(400, '消息过长或格式无效')
        for values, title in [(attachments, '附件'), (references, '引用')]:
            if not isinstance(values, list) or len(values)>MAX_ATTACHMENTS or any(not isinstance(v,str) for v in values) or len(set(values))!=len(values):
                raise Failure(400, '最多添加 8 个不同'+title)
        if not (prompt.strip() or attachments or references): raise Failure(400, '消息为空')
        g.workspace(s['cwd'])
        attached = [g.attachment(sid, aid) for aid in attachments]
        if sum(a['size'] for a in attached)>MAX_TOTAL: raise Failure(413, '附件合计不能超过 50 MB')
        for path in references:
            directory = False
            try:
                _, name, size = g.open_file(sid, path, directory=True); directory = True
            except Failure:
                stream, name, size = g.open_file(sid, path)
                with stream: pass
            attached.append({'name':name,'path':path,'mime':'inode/directory' if directory else mimetypes.guess_type(name)[0] or 'application/octet-stream'})
        context = '\n'.join(json.dumps({'name':a['name'],'path':a['path'],'type':'directory' if a['mime']=='inode/directory' else 'file'},ensure_ascii=False) for a in attached)
        return (prompt or '请查看引用的文件。') + ('\n\nUser-selected file context:\n'+context if context else '')

    def add(self, sid, body):
        g = self.g
        Failure = g.failure_type
        mode = body.get('delivery')
        if mode not in ('queue','steer'): raise Failure(400, '发送方式无效')
        rid = body.get('requestID')
        try: uuid.UUID(rid)
        except (ValueError, TypeError, AttributeError): raise Failure(400, '缺少有效请求编号')
        digest = hashlib.sha256(json.dumps(body,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
        with g.lock:
            old = g.db.execute('SELECT session,data FROM inbox WHERE id=?',(rid,)).fetchone()
            if old:
                item = json.loads(old[1])
                if old[0]!=sid or item['digest']!=digest: raise Failure(409, '请求编号已用于另一条消息')
                return g.get(sid)
            if g.db.execute('SELECT 1 FROM requests WHERE id=?',(rid,)).fetchone(): raise Failure(409, '请求编号已使用')
            if mode=='steer' and g.review is None: raise Failure(503, '请先部署支持引导的独立账号网关')
            if sum(v['status'] in ('pending','held','unknown','dispatching','running') for v in self.items(sid))>=20:
                raise Failure(409, '待处理消息已达 20 条，请先处理或取消')
            prompt = self.prepare(sid,body)
            item = dict(id=rid, sessionID=sid, delivery=mode, status='pending', text=body.get('text',''),
                        createdAt=time.time(), error='', attachmentCount=len(body.get('attachments',[]))+len(body.get('references',[])),
                        body=body, prompt=prompt, digest=digest)
            self.write(item); self.touch(sid)
            if not g.get(sid)['running'] and sid not in g.active: self.dispatch_next(sid)
            return g.get(sid)

    def claim(self, sid):
        g = self.g
        with g.lock:
            if not g.get(sid)['running'] or sid not in g.active: return []
            selected = []
            total = 0
            for item in self.items(sid):
                if item['delivery']!='steer' or item['status']!='pending': continue
                size = len(item['prompt'].encode())
                if selected and total+size>512*1024: break
                selected.append(item); total += size
            if not selected: return []
            s = g.get(sid); message = s['messages'][-1]
            indices = [v.get('index',0) for v in message.get('steps',[])]+[int(t['id']) for t in message.get('tools',[]) if str(t['id']).isdigit()]
            position = max(indices, default=-1)+1
            for item in selected:
                item['status']='delivered'; self.write(item)
                message.setdefault('guidance',[]).append({'id':item['id'],'index':position,'text':item['text'] or '补充文件引用'})
            g.save(s)
            return [{'userMessage':v['prompt']} for v in selected]

    def change(self, sid, rid, action):
        g = self.g
        Failure = g.failure_type
        with g.lock:
            g.get(sid)
            found = g.db.execute('SELECT data FROM inbox WHERE id=? AND session=?',(rid,sid)).fetchone()
            if not found: raise Failure(404, '待处理消息不存在')
            item=json.loads(found[0])
            if action=='cancel':
                if item['status']=='cancelled': return g.get(sid)
                if item['status'] not in ('pending','held'): raise Failure(409, '这条消息已递交或结果待确认，无法取消')
                item['status']='cancelled'
            elif action=='resume':
                if item['status']!='held': raise Failure(409, '请先核对递交结果，不能自动重发')
                self.prepare(sid,item['body'])
                item['status']='pending'; item['error']=''
            else: raise Failure(400,'操作无效')
            self.write(item); self.touch(sid)
            if action=='resume' and not g.get(sid)['running'] and sid not in g.active: self.dispatch_next(sid)
            return g.get(sid)

    def hold(self, sid, reason):
        for item in self.items(sid):
            if item['status']=='pending':
                item['status']='held'; item['error']=reason; self.write(item)
        self.touch(sid)

    def finished(self, sid, successful):
        g = self.g
        with g.lock:
            for item in self.items(sid):
                if item['status'] in ('running','delivered'):
                    item['status']='done'; self.write(item)
            if not successful:
                self.hold(sid, '当前任务停止或出错，后续消息已暂停。')
            else: self.dispatch_next(sid)

    def dispatch_next(self, sid):
        g = self.g
        # Called with the gateway RLock held: no competing admission can steal
        # the idle slot between selecting a queued message and its submit.
        if g.get(sid)['running'] or sid in g.active: return
        candidates = [v for v in self.items(sid) if v['status']=='pending']
        if not candidates: return
        item = candidates[0]
        item['status']='dispatching'; self.write(item); g.db.commit()
        body = dict(item['body']); body.pop('delivery',None)
        try:
            g.submit(sid,body)
            item['status']='running'; self.write(item); self.touch(sid)
        except Exception:
            admitted = g.db.execute('SELECT 1 FROM requests WHERE id=?',(item['id'],)).fetchone()
            item['status']='unknown' if admitted else 'held'
            item['error']='递交结果待确认，请核对会话。' if admitted else '自动接续未执行，请核对文件和会话后继续。'
            self.write(item)
            self.hold(sid,'前一条排队消息未能执行，后续已暂停。')
