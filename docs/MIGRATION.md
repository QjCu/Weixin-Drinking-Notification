# 课间一口 · SipTime 聊天迁移文件

更新时间：2026-10-25（Asia/Shanghai）。将本文件上传到新聊天，或把本文件的 GitHub 链接交给新助手读取。

## 给新助手的开始指令

请先阅读本文件、仓库根目录的 AGENTS.md 和 docs/version2.md，然后检查 GitHub 与工作区的实际状态。继续协助开发 SipTime，只在 version2 分支开发与同步。未经用户明确同意，不合并到 main 或 codex/siptime-mvp，不发布正式版本。不要假定所有待办都已获得实施授权；先承接用户的新需求。

本文件是上下文交接文档，不算新的功能修改。version2 已完成第 001 次功能修改，下一次功能修改应记为 002。

## 1. 项目入口与分支

- 仓库：https://github.com/QjCu/Weixin-Drinking-Notification
- 当前工作分支：https://github.com/QjCu/Weixin-Drinking-Notification/tree/version2
- 分支规则文件：AGENTS.md
- 修改记录：docs/version2.md
- 第一版草稿 PR：https://github.com/QjCu/Weixin-Drinking-Notification/pull/1
- 迁移前已核实的功能基线：98cce1e68bcc4e6a284ec5a34d37bb01c911a270。
- 该基线的提交说明：version2 001: set the 11 supplied breaks as the default timetable。
- codex/siptime-mvp 第一版提交：f048e9ab912ea9e1f8857715783683220d173e33。
- main 在最近核查时仍为最初的 README 提交。新助手需再次检查远端，不假定分支一直未变。

**用户明确约定：** 在 GitHub 新建 version2，后续修改都从 version2 继续，直到用户认为可以。保持原分支，不擅自合并。最初“只建本地 version2”的理解已被用户纠正，当前 version2 确实已经存在于 GitHub。

迁移时云环境工作区为 `/workspace/Weixin-Drinking-Notification`；新聊天不一定挂载同一环境，必要时重新克隆。用户 Mac 上此前使用 `~/Documents/Weixin-Drinking-Notification`。

## 2. 用户目标与使用情况

- 为 iPhone 开发简洁的喝水提醒 App，重点服务大学生按课间喝水。
- 支持每周、每天、单双周和不同学校的自定义作息，用户点选想要提醒的课间。
- 希望两名用户可以互留文字，在后续喝水提醒中展示。
- 用户有 Mac，有 Python 和 C++ 经验；另有一台可长期联网、供电的 Windows 电脑，计划用作服务器。
- 手机可能使用蜂窝数据或校园网，不能只依赖宿舍局域网地址。
- 用户已运行过第一版，并明确反馈已达到预期。
- 用户需要具体、逐步的 Mac/Xcode 操作说明；不要假定其熟悉 iOS 签名和设备配对。

## 3. 当前实现

### iPhone 客户端

SwiftUI，最低 iOS 17。界面为“今天 / 提醒计划 / 好友”。

- 单周、双周课间矩阵，星期一至星期日点选与互相复制。
- 自定义学校名称、学期第一周的周一、学期周数、课间时间和长度。
- 普通提醒可批量选择星期，支持每周/单周/双周。
- 暂停今天、关闭提醒、课间开始后延迟提醒。
- 最多 60 条未来本地通知；打开 App、前台定时处理、保存计划和系统时间变化时重建。
- 首页显示下一次提醒、当天剩余提醒和“已安排至”。
- 单双周依据学期周数计算，不使用自然周奇偶；普通提醒也受学期起止日期限制。
- 本地计划与留言存于 Application Support/SipTime/state.json；账号凭据在 Keychain。

### 服务端

FastAPI + SQLite，支持 Windows 运行，当前按单 worker 设计。

- 本机昵称注册，Bearer token 鉴权，服务器保存凭据摘要。
- 12 位邀请码双向绑定，一人仅绑定一位好友。
- 最长 140 字留言，每人最多 20 条待提醒留言。
- client_id 发送重试去重、收件箱隔离、收件人确认、解除绑定。
- SQLite WAL、外键与事务，注册/绑定/发送有进程内限流。
- 默认数据库：从 backend 目录启动时为 backend/data/siptime.sqlite3。

### 留言当前的准确行为

发送方提交留言 → 服务端保存 → 接收方打开 App 或手动同步 → 留言进入后续本地通知。

多条留言按顺序分别匹配后续提醒。提醒时间经过后，下次前台处理再确认；这不等于“已读”，也不能证明系统确实展示了通知。

**尚未接入 APNs。不能承诺接收方一直不打开 App 也会收到刚发的新留言。**

## 4. version2 第 001 次修改

将用户截图中的以下 11 个时段设为新计划默认作息：

| 名称 | 开始 | 结束 | 时长 |
| --- | --- | --- | --- |
| 课间1 | 08:50 | 09:00 | 10 分钟 |
| 课间2 | 09:50 | 10:10 | 20 分钟 |
| 上午课间 | 11:00 | 11:10 | 10 分钟 |
| 午休 | 12:00 | 13:00 | 60 分钟 |
| 课间3 | 13:50 | 14:00 | 10 分钟 |
| 下午课间 | 14:50 | 15:10 | 20 分钟 |
| 课间4 | 16:00 | 16:10 | 10 分钟 |
| 课间5 | 17:00 | 17:10 | 10 分钟 |
| 课间6 | 18:00 | 18:40 | 40 分钟 |
| 课间7 | 19:30 | 19:40 | 10 分钟 |
| 课间8 | 20:30 | 20:40 | 10 分钟 |

- 修改默认值，不自动覆盖已经持久化的用户作息。
- 已安装用户可选择：“提醒计划 → 学校作息表 → 选择作息模板 → 恢复默认作息 · 11 个时段”，再点选需要的课间并保存。
- 应用模板会清除原课间点选，保留普通提醒；界面会先说明这一点。
- 原示例 A/B 保留原来的 5 个时段，已与新默认作息分离。
- 未更改通知算法、留言与账号功能。
- 原通知算法规定延后分钟数达到或超过课间长度时跳过该课间；新默认中有多个 10 分钟课间，沿用此行为。

## 5. 代码入口

| 文件 | 内容 |
| --- | --- |
| ios/SipTime/Models.swift | 默认作息、规则、单双周日期算法、数据类型 |
| ios/SipTime/PlanView.swift | 课间矩阵、模板、作息编辑、普通提醒 |
| ios/SipTime/NotificationScheduler.swift | 通知权限与本地队列 |
| ios/SipTime/AppStore.swift | 持久化、同步、留言确认和串行操作 |
| ios/SipTime/APIClient.swift | 网络、URL 校验、Keychain |
| ios/SipTime/FriendView.swift | 注册、绑定、留言、服务器地址 |
| ios/SipTime/SipTimeApp.swift | 首页、导航与刷新触发 |
| ios/project.yml | XcodeGen 工程定义和 Bundle Identifier |
| ios/Package.swift | 独立 Swift 核心测试入口 |
| ios/SipTimeTests/ScheduleEngineTests.swift | 10 项课表核心测试 |
| backend/app/main.py | 服务端全部业务接口 |
| backend/tests/test_api.py | 9 项服务端测试 |
| docs/architecture.md | 数据流、限制与 APNs 后续设计 |
| docs/acceptance.md | 编译、通知、两人联调验收步骤 |

XcodeGen 生成的 .xcodeproj 不在 Git 跟踪中。用户 Mac 可能有本地 Team/签名设置，重新生成工程前应保留这些设置；持久配置优先写入 project.yml。第 001 次修改不要求重新生成工程。

## 6. 运行与检查命令

### Mac 获取当前分支

已有项目：

```bash
cd ~/Documents/Weixin-Drinking-Notification
git fetch origin
git switch version2
git pull --ff-only
```

第一次克隆：

```bash
git clone --branch version2 https://github.com/QjCu/Weixin-Drinking-Notification.git
```

### Mac 生成并打开工程

```bash
cd ios
xcodegen generate
open SipTime.xcodeproj
```

### Python 服务端（从项目根目录）

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
cd backend
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

健康检查：`http://127.0.0.1:8000/health`；接口说明：`/docs`。

### Windows 服务端（从项目根目录的 PowerShell）

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
cd backend
..\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

若需要直接供局域网访问，监听地址改为 0.0.0.0，并使用电脑局域网 IP。手机上的 localhost 不代表电脑。

若迁移原账号，先停止旧服务，再迁移原 data 目录；新建数据库不会自动包含原账号。Python 虚拟环境不跨 Mac/Windows 复制。

### 测试

服务端：安装 backend/requirements-dev.txt 后，在 backend 目录执行 `python -m unittest discover -s tests -v`。

Swift 核心：在 ios 目录执行 `swift test`。

## 7. 验证边界

- 第一版服务端 9 项 unittest 已实际通过，覆盖鉴权、绑定排他与并发、消息隔离、去重、持久化等。
- 第一版 Swift 文件做过语法解析，plist 与 XcodeGen 配置做过解析检查。
- version2 第 001 次修改的 Models.swift 和 PlanView.swift 已通过 Swift 语法解析与 git diff 检查。
- 云环境没有 Xcode 和 Swift 编译器，助手未在这里运行 Swift XCTest、完整 iOS 编译或真机通知验收。
- 用户报告第一版已经实际运行、达到预期；这不等于 version2 的每个改动都已真机验证。
- 仓库提供 GitHub Actions 配置，但本迁移文件不宣称最近 CI 已通过。需要时读取实际运行记录。

## 8. 最近未确认解决的问题：真机安装连接错误

用户尝试安装到真实 iPhone，提供以下错误：

```text
A connection to this device could not be established.
com.apple.dt.CoreDeviceError Code 4000
operationName = enablePersonalizedDDI
Not attempting AMDeviceCreateWithRemoteDeviceWithError:
an earlier AMDevicePowerAssertionCreate on this device has not responded.
Underlying Code 18004
```

当时环境为 macOS 26.7.1、Xcode 27.1、手机 iOS 26.2。该日志表明真机调试准备阶段的连接请求未响应，不能据此认定是 App 代码、免费会员或签名有效期造成。

已建议：退出 Xcode、拔线，重启 Mac 和 iPhone，解锁手机后用可靠数据线直接连接，确认信任。Xcode 27 的设备管理入口为 **Xcode → Open Developer Tool → Device Hub**，也可从运行目标下拉框进入 Manage Devices。按提示配对、启用手机开发者模式、等待设备准备完成后再运行。如仍失败，再取消配对并重新配对；下一步应查看 Device Hub 中选中手机后的具体状态。

**用户尚未反馈该问题已解决。** 不要在新聊天中把它标记为已修复，也不要直接要求删除项目或清空手机。

苹果说明：https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac

## 9. 已解决的开发环境问题

- Xcode 许可没有成功确认：用户最终通过 `sudo xcodebuild -license accept` 完成；不要把 sudo 权限与接受许可混为一谈。
- 用户原 Homebrew 位于 `~/.linuxbrew/Homebrew`，旧版本不识别 macOS 版本。
- 原清华 brew 镜像返回仓库不存在；已指导改为 https://github.com/Homebrew/brew.git 。
- 更新时发生 HTTP/2 framing 错误，针对该 Homebrew 仓库设置 `git config --local http.version HTTP/1.1` 后更新成功。
- 用户已反馈下载成功。不要让用户重复整个 Homebrew 安装流程，除非有新证据。
- backend 与 ios 是同级目录；在 backend 内去 ios 应使用 `cd ../ios`，或使用明确的项目绝对路径。

## 10. 已讨论但未实施的后续方案

### 跨网络访问 Windows

建议两人试用阶段采用 Tailscale：电脑和手机建立私有连接，通过 Tailscale Serve 提供 HTTPS。Windows 管理员终端命令：

```powershell
tailscale serve --bg http://127.0.0.1:8000
```

朋友使用自己的账号，获得 Windows 节点共享权限；不要求双方共用账号。手机用蜂窝数据/校园网时先测试 Serve 地址的 `/health`。仅持续供电联网不足以保持服务，需关闭睡眠并设置服务开机自启。

这是讨论过的方案，**未确认用户已配置完成**。校园网络可达性仍需实测。正式版 APIClient 要求 HTTPS；Debug 有本地网络例外。

### 不打开 App 的下一次提醒留言

需要新增 APNs、设备 token 注册、计划/时区/暂停状态同步、服务端持久定时任务、重试去重，以及本地/远程通知的协调。不能只加一个后台轮询或静默推送就承诺准时更新留言。避免同时触发本地与远程两条提醒。当前代码未实现这些功能，也没有已配置的 APNs 凭据。

### 会员、安装和上架

- 免费 Personal Team 的开发安装有 7 天描述文件期限；本地喝水提醒不要求付费会员。
- App Store 分发、TestFlight、付费签名、企业内部应用和免费开发签名不能混为一谈。
- TestFlight 每个构建最多 90 天；Ad Hoc 需要注册设备并受签名/描述文件期限约束。
- 已解释 AltStore Classic/AltServer 可尝试自动续签，仍有连接与后台条件，不能承诺自动续签始终成功；未指导或确认用户实际安装。
- 网页应用不使用原生开发签名，但不能直接视为当前 SwiftUI App 的替代品。
- 用户询问过付费会员与上架，没有确认已购买会员或决定上架。
- 若保留账号，上架前要补账号删除；仅解除绑定不等于删账号。还需发布资料、隐私披露、适用的用户内容机制、可审核访问的服务，以及发行地区要求。不要未经请求就开始上线或购买服务。
- 会员价格、签名规则和上架政策可能变化，实际操作前查阅苹果官方当前说明，不把历史讨论当作永久规则。

## 11. 新聊天的建议起步顺序

1. 确认能访问仓库，读取 AGENTS.md、docs/version2.md 和本文件。
2. 核对实际分支、远端 HEAD 和本地修改；保留用户 Mac 上的签名配置和自定义数据。
3. 明确本次要承接的新需求。如果继续排查真机安装，优先获取 Device Hub 的当前设备状态。
4. 功能改动继续在 version2 进行，并从 002 起记录；不得擅自更新原分支或合并发布。
5. 明确区分实际执行过的检查、用户反馈、建议方案与尚未验证的结论。
