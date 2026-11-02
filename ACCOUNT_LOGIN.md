# 新 Google 账号：独立登录、验证与切换

本次没有注销、切换或覆盖服务器现有的 Google 登录。新办法是为每个账号建立独立 CLI HOME，不再复制共享 `~/.gemini` 凭据。新账号的凭据、CLI 会话、网关索引和额度缓存相互隔离。工作目录仍是你指定的服务器项目目录。

## 1. 准备新配置

SSH 登录服务器，以运行网关的普通用户执行。进入本源码目录；使用 AGY CLI **1.4.10 或更高版本**（必须支持 `--settings`）。当前服务器的网关专用程序在：

```sh
/home/ubuntu/.local/share/agy-iphone/runtime/agy --version
python3 scripts/account.py create new-account
python3 scripts/account.py login new-account
```

`new-account` 只是本地标签，不是 Google 邮箱。可以换成 1–32 个字母、数字、下划线或短横线。

## 2. 在浏览器完成 OAuth

1. CLI 检测到 SSH 后，会给出授权网址。把本次生成的网址复制到手机或电脑的**无痕窗口**。
2. 选择你的**新 Google 账号**并完成 Google 验证、授权。
3. 把浏览器显示的授权码粘回同一个 SSH 终端的 CLI 提示框。不要把密码、授权码或令牌放进源码、GitHub 或聊天记录。
4. 登录成功后，确认 CLI 顶部显示的是**新账号邮箱**，再输入 `/exit`。本地配置标签不代表实际邮箱，应以 CLI 登录显示为准。
5. 如果误登录了别的账号，创建另一个全新标签重新登录。脚本会拒绝覆盖已存在的登录，也不会调用共享账号的 `/logout` 或清空旧缓存。

这是 Google 官方的 SSH 手动网址＋授权码流程，不是把 API Key 当作个人订阅账号登录。[官方验证说明](https://antigravity.google/docs/install)

## 3. 验证新登录

```sh
python3 scripts/account.py check new-account
```

该命令从新配置读取真实模型与 `/usage` 额度，显示可用模型数量和额度分组；不发送模型任务。是否有 Gemini 4 及哪些思考强度，由新账号实际返回的清单决定。

账号资料目录：`~/.local/share/agy-iphone/accounts/new-account/home`。旧账号的 `~/.gemini` 与现有 PI 容器不被修改。不要把旧账号网关数据库或 CLI 会话目录混入新配置。

## 4. 新账号验证成功后再切换网关

本包的 App 要配套部署新版后端。先确认旧任务已结束，再停网关；HTTPS 隧道和原版 AGY Remote Control 不必停。

```sh
systemctl --user stop agy-iphone-gateway.service
python3 scripts/account.py serve new-account \
  --key-file /home/ubuntu/.local/share/agy-iphone/key \
  --root /home/ubuntu/test
```

这条命令以前台方式运行新账号网关，仍监听 `127.0.0.1:8766`。已有 `https://agy.yectech.uk` 命名隧道可以继续使用。手机沿用原网关密钥；不要拿 Google 或 Cloudflare Token 填进 App。

验证正常后，将 `agy-iphone-gateway.service` 的 `ExecStart` 改成以下命令（把源码路径和标签改成实际值）：

```ini
ExecStart=/usr/bin/python3 /home/ubuntu/test/AGY-iPhone/scripts/account.py serve new-account --key-file /home/ubuntu/.local/share/agy-iphone/key --root /home/ubuntu/test
```

退出前台测试进程后执行：

```sh
systemctl --user daemon-reload
systemctl --user start agy-iphone-gateway.service
```

需要回退时，恢复原来的 `ExecStart` 并重启网关即可；原账号和原数据库仍在。不要同时启动两个监听 8766 的网关。

App 识别到不同账号配置 ID 后，会清除本机旧会话缓存、草稿、待确认发送及额度缓存，再重新读取新账号内容，避免把旧请求重发到新账号。

## 与官方 Remote Control 的关系

本包的独立账号配置服务于原生 App 网关。原来共享登录启动的官方 `ubuntu-agy` Remote Control 不会自动换账号。如果以后也要让官方网页用新账号，需另行在同一独立 HOME 下登录并重新注册 Remote Control；这次未改它。
