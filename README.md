# AGY for iPhone

独立的 SwiftUI 原生 Antigravity CLI 客户端，沿用 [Pi iPhone](https://github.com/ddyec/Pi-iPhone) 的消息展示与界面基础。iOS 17+、仅 iPhone，无第三方 Swift 依赖。Bundle ID：`com.ddyec.agy-iphone`，可与 Pi 同时安装。当前版本 1.0.1 / build 2。

App 图标、登录页、欢迎页和消息标识使用 [Google 官方 Antigravity Press Assets](https://antigravity.google/press) 全彩原图；来源与打包说明见 `Brand/README.md`。

聊天、模型选择、历史、工具详情与设置均为原生界面，不加载桌面网页。输入框跟随键盘与安全区，支持深浅色、动态字体、复制、分享、Markdown、代码和表格。

## 接入方式

当前部署的固定入口为 `https://agy.yectech.uk`，通过独立 Cloudflare 命名隧道连接服务器网关，支持持续 SSE。App 已预填该地址；连接密钥另行私密交付，不在本仓库或 IPA 中。

服务器运行 `Server/gateway.py`，通过官方 `agy --input-format stream-json --output-format stream-json` 协议执行任务，用 `--conversation <id>` 续聊。Google OAuth 凭据留在服务器。iPhone 使用独立连接密钥，并将连接信息保存在钥匙串中。网关仅监听回环地址，应由 HTTPS 反向代理或隧道对外提供访问，不要直接把明文 HTTP 端口暴露到公网。

```sh
install -d -m 700 ~/.local/share/agy-iphone
python3 -c 'import secrets,pathlib; p=pathlib.Path.home()/".local/share/agy-iphone/key"; p.write_text(secrets.token_urlsafe(48)); p.chmod(0o600)'
python3 Server/gateway.py --key-file ~/.local/share/agy-iphone/key \
  --root /path/to/workspace --agy /path/to/agy
```

`--root` 可重复指定。App 仅提供允许目录选择；服务器检查真实路径，拒绝路径穿越和越界符号链接。应使用普通用户运行网关，AGY 自身仍按工作目录加载规则与权限配置。目录范围校验约束客户端选目录，不构成操作系统沙箱。

在 App 中输入网关的 HTTPS 地址和密钥即可。初始选择“先做计划”；新建会话时可选择“允许编辑文件”。不使用 `--dangerously-skip-permissions`。无头 CLI 不支持在此网关中完成交互式工具批准，相关操作可能拒绝或中断并返回错误。

## 会话与恢复

- 网关保存自己创建的会话、消息、工具事件与 AGY conversation ID。当前不导入官方 Remote Control 网页的会话列表，也不宣称与网页双向实时同步。
- 手机退出或断网不终止服务器进程。回到前台读取权威快照，恢复流式同步；不自动重发 prompt。
- 每条消息带持久化请求编号。请求超时后可以核对会话或按原编号重试，服务器对相同编号去重，避免重复执行。
- 服务器重启后将进行中的任务标为中断，保留已收到内容，不自动重新执行。停止按钮终止网关启动的整个 CLI 进程组；已发生的文件操作不会撤销。
- 删除操作只删除网关索引，AGY 原始会话保留。

## 构建

需要 Mac + Xcode 26：

```sh
python3 scripts/generate-project.py
bash scripts/package.sh
```

GitHub Actions 同时执行网关测试、原生协议测试、iPhoneOS arm64 真机归档与 IPA 结构校验。`AGY-iPhone-resign` artifact 中的 IPA 使用临时 ad-hoc 签名，需要用户自己的签名工具重签安装。未配置 Apple 发行证书，不是 TestFlight 包。

按 Pi 项目的既有约定不运行模拟器。编译和协议测试不代表 iPhone 真机验收；需要实际验证键盘、后台切换、断线恢复及长对话滚动。

## 第一版边界

已实现文本聊天、流式回复、历史、重命名/删除、模型与工作目录选择、执行模式、工具详情、停止、断线恢复和请求去重。附件/图片输入、文件浏览下载、APNs、原生工具审批、官方 Remote Control 会话导入尚未实现，不显示不可用的操作入口。

官方协议参考：[Headless mode](https://antigravity.google/docs/cli/headless/)。当前服务器实测 CLI 版本与验证结果见 `VALIDATION.md`。
