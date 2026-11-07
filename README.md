# AGY for iPhone

基于 SwiftUI 编写的 **Antigravity CLI 原生 iPhone 客户端**（支持 iOS 17+）。

采用纯原生界面实现聊天、模型与思考强度切换、工具审批、文件浏览上传与灵动岛实时活动，不依赖网页套壳。应用 Bundle ID 为 `com.ddyec.agy-iphone`，可与 [Pi for iPhone](https://github.com/ddyec/Pi-iPhone) 同时安装。

---

## 主要功能

当前版本：**1.5.0 / build 10**。

- **运行中追加消息**：点击发送可选择“立即引导（下一次思考生效）”或“排队跟进”。正在执行的命令不中断；排队消息在当前轮成功结束后按顺序接续。可取消未递交项；停止、出错或服务器重启后暂停队列，手动核对再继续。

- **思考与执行时间线**：
  - 对话流按实际执行顺序展示“思考摘要 → 可折叠工具调用组 → 下一段思考”，任务完成后自动收起中间执行过程，突出最终回复。
  - 原生支持 Markdown、代码块自动换行与复制、表格、图片放大查看，以及基于 SwiftDraw 的 SVG 原生矢量预览。
  - 手势感知滚动：手动向上翻阅历史消息时自动停止底部跟随，避免阅读被流式输出打断。
- **锁屏与灵动岛实时活动（Live Activities）**：
  - 实时显示当前任务的运行状态、耗时、最新进展与待审批提醒，点击即可回到对应会话。
  - 默认隐藏具体任务正文以保护隐私，可在设置中开启内容预览或关闭实时活动。
  - 进展到达即更新，前台运行时每 8 秒核对状态；在 iOS 允许的短时后台执行期间每 5 秒核对一次（主动上限 25 秒，系统可提前结束）。挂起后显示最近状态与更新时间。当前没有 APNs，不能保证长时间锁屏后的持续刷新。
- **原生文件页与 `@` 引用**：
  - 在“文件”标签页直接浏览服务器工作区、从系统相册或“文件”App 上传附件、预览或下载生成的产物。
  - 下载的文件保存在“文件 App → 我的 iPhone → AGY → 下载”，也可选择“存储到文件”写入任意目录（自动校验写入结果，同名文件自动另存，不覆盖原文件）。
  - 在输入框输入 `@` 或在文件列表中点击 `@`，即可在对话中引用单个文件或整个文件夹。
- **模型、思考强度与审批策略**：
  - 先选择模型，再选择该模型支持的思考强度（对应 CLI 的 `--model` 与 `--effort`）。
  - **审批模式**：支持 **Restriction Mode**（每次工具调用弹出原生允许/拒绝卡片）与 **Turbo Mode**（自动执行常规操作）。
  - **执行方式**：独立切换“先做计划”与“直接实施”。
  - 所有偏好设置按服务器地址与账号独立记忆。

---

## 服务端部署与多账号管理

客户端需配合本仓库 `Server/` 目录下的网关使用。网关支持多账号隔离，每个账号使用独立的 CLI HOME 与会话数据库，互不干扰。

管理账号命令（详见 [ACCOUNT_LOGIN.md](ACCOUNT_LOGIN.md)）：

```bash
python3 scripts/account.py create <account-name>
python3 scripts/account.py login <account-name>
python3 scripts/account.py check <account-name>
```

网关默认仅监听本机回环地址，通过 Cloudflare Tunnel 等方式对外提供 HTTPS 访问。详细接口协议说明见 [Server/API.md](Server/API.md)（要求 AGY CLI 1.4.10 及以上版本）。

---

## 构建与安装

### GitHub Actions 自动构建
推送代码或手动运行工作流会自动执行后端与核心测试，并归档生成待重签的 `AGY-iPhone.ipa`。

### Mac 本地构建
需要 Xcode 与 iOS 17+ SDK：

```bash
bash scripts/check-local.sh
bash scripts/package.sh
```

> **重签注意事项**：使用自签工具签名安装时，请务必保留并一并签署 `AGYLiveActivity.appex` 扩展，以确保灵动岛与锁屏实时活动正常可用。

---

## 相关文档与声明

- [与 Pi 客户端的功能对照](PI_COMPARISON.md)
- [接口协议说明](Server/API.md)
- [账号登录与切换指南](ACCOUNT_LOGIN.md)
- [品牌资源来源说明](Brand/README.md)
- [测试与验证记录](VALIDATION.md)

> 本项目为个人开发的独立第三方客户端，非 Google 官方应用；应用内使用的 Antigravity 品牌图标源自 [Google Antigravity Press Assets](https://antigravity.google/press)。
