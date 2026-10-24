# 课间一口 · SipTime

适合大学生的 iPhone 喝水提醒原型。SwiftUI + FastAPI，iOS 17+，Python 3.10+（建议 3.12）。

当前开发分支为 GitHub 上的 `version2`。第 001 次修改设定 11 个默认课间，第 002 次加入课表导入与按周显示；后续开发与同步继续使用此分支，用户确认前不合并到原有分支。记录见 [version2 修改记录](docs/version2.md)。

已实现：单双周课间矩阵、周一至周日点选、自定义学校作息、单/双周复制、批量普通提醒、学期周数、延后提醒、暂停今天、本地通知、邀请码绑定、140 字留言、同步缓存、发送重试去重，以及课程截图、网页和文字导入。界面分为“今天 / 课表 / 提醒计划 / 好友”，跟随系统深色模式。课表按学期周显示，非本周课程淡化，同一节有本周课程时只显示本周课程。默认作息为用户提供的 11 个课间，同时保留两套示例作息。

**这是源代码原型，第 002 次修改尚未完成 Xcode 编译、实际截图识别与真机验收。** 已在 Linux Swift 6.0.3 运行 Swift 核心测试，另有服务端测试与 Swift 语法检查；这些检查不能替代 iOS 界面和系统框架验收。请在 Mac 完成下面的检查后再用于日常提醒。

课表导入当前适配北京大学选课结果表，支持手机本地截图识别、App 内登录网页后读取、HTML/文本文件及粘贴内容，先预览校正再保存。详见 [课表导入与学校适配](docs/course-import.md)。

## 1. Mac 启动服务端

在项目根目录执行：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
cd backend
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

打开 `http://127.0.0.1:8000/health`，应返回 `{"status":"ok"}`；接口文档在 `/docs`。默认数据库为 `backend/data/siptime.sqlite3`，重启不会丢失数据，不要删除该文件。可通过 `SIPTIME_DB` 环境变量指定路径。

## 2. Mac 运行 iPhone App

安装 Xcode 并首次打开，完成组件安装。安装了 Homebrew 后执行：

```bash
brew install xcodegen
cd ios
xcodegen generate
open SipTime.xcodeproj
```

1. 在 Xcode 选择 **SipTime** scheme 和一个 iPhone 模拟器，按 **⌘R**。
2. 首页点击“允许喝水通知”。
3. 到“提醒计划”设置学期第一周的周一、学期周数，点选课间，再点右上角“保存”。
4. 到“好友”填写 `http://localhost:8000` 和昵称，点击“创建本机账号”。

装到真机：在 Signing & Capabilities 选择你的 Apple Development Team，把 Bundle Identifier 改成自己的唯一值。连接 iPhone、开启开发者模式，选择设备运行。个人 Apple ID 通常可用于个人真机开发；长期分发与 APNs 能力需要另行配置开发者账号。

当前没有正式 App 图标和 App Store 发布配置。

已有项目升级第 002 次修改时，先拉取 `version2`，保留本地签名设置，再重新运行 XcodeGen；本次新增 Swift 文件需要重新生成工程才能加入编译。具体步骤见 [更新已有 Mac 工程](docs/course-import.md#更新已有-mac-工程)。

## 3. Windows 作为服务器

复制项目到 Windows 并安装 Python，在项目根目录的 PowerShell 执行：

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
cd backend
..\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Windows 和 iPhone 连接同一个可信 Wi-Fi。运行 `ipconfig` 查看电脑 IPv4 地址，例如 `192.168.1.10`；App 填 `http://192.168.1.10:8000`。**真机不能用 localhost 访问电脑。** Mac 作为真机服务器也需要以 `--host 0.0.0.0` 启动，并使用 Mac 的局域网地址。

若防火墙阻止访问，可添加仅针对专用网络、本地子网的 TCP 8000 入站规则。在管理员 PowerShell 执行：

```powershell
New-NetFirewallRule -DisplayName "SipTime LAN 8000" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8000 -Profile Private -RemoteAddress LocalSubnet
```

排查顺序：电脑访问 `/health` → 手机 Safari 访问同一地址 → App 连接，并允许“本地网络”权限。校园 Wi-Fi 可能隔离设备，可使用个人路由器或热点测试。建议为服务器保留固定局域网地址。

电脑睡眠、关机后不能同步留言，已安排好的本地通知仍有效。局域网 HTTP 仅用于可信网络开发，不要直接把开发服务暴露到公网。跨网络使用应先部署 HTTPS。Release 客户端拒绝 HTTP；Debug 仅设置本地网络例外，没有关闭全局传输安全。

## 4. 两人联调

1. 使用两台 iPhone 或两个独立模拟器，连接同一服务端，分别创建账号。
2. A 把邀请码发给 B；B 输入后双向绑定，A 同步即可看到好友。
3. A 发送留言。B 打开 App 或点击“同步留言与账号”。
4. B 添加今天未来两三分钟的普通提醒并保存，锁屏检查通知。
5. B 再次打开 App，已经过提醒时间的留言会确认结束，不会再次安排。

每条留言依次占用一次后续提醒。暂停今天、关闭提醒或修改时间时，尚未经过提醒时间的留言会保留，等待下一次有效提醒。

凭据保存在 iOS Keychain，按服务器地址隔离。第一版没有密码登录、换机恢复和找回功能，不能假定卸载后一定能找回账号。电脑 IP 变化时可在好友页更新服务器地址，会核对原账号；迁移服务器需要保留数据库。

## 5. 提醒边界

- 单双周按学期周数计算，不用自然周奇偶，跨年也不重置。日期会自动对齐到所在周的周一。
- 提醒遵循手机当前时区，普通提醒也受学期日期限制。假期可关闭提醒；暂未实现独立假期区间和调休补课。
- 每次安排最多 60 条本地通知，在前台每分钟、重新打开、系统时间变化和保存计划时补充。**用完后不会在后台自动无限补充。** 请在首页“已安排至”之前再次打开 App。
- 留言成功同步后才会进入通知。**没有接入 APNs，不保证接收方一直不打开 App 时看到最新留言。** 喝水提醒本身不依赖服务器。
- 留言确认表示“安排的提醒时间已经经过”，不等于已阅读或实际展示。专注模式、摘要和权限设置都会影响显示。
- 解除绑定删除服务端双方留言；另一台设备需要同步，才会移除已下载、已安排的留言。
- 上线前需要 HTTPS、备份、日志与监控、账号恢复和消息保留策略。详见架构文档。

## 6. 检查命令

服务端，在项目根目录执行前两条，再进入 backend 测试：

```bash
python -m pip install -r backend/requirements-dev.txt
cd backend
python -m unittest discover -s tests -v
```

课表核心测试，在 Mac 上从项目根目录执行：

```bash
cd ios
swift test
```

完整模拟器编译，在 ios 目录执行：

```bash
xcodegen generate
xcodebuild -project SipTime.xcodeproj -scheme SipTime -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Xcode 中 **⌘U** 可运行 XCTest。已附 GitHub Actions 配置，推送或创建 Pull Request 后可运行服务端测试、Swift 核心测试和模拟器编译。

参见 [架构与后续计划](docs/architecture.md)、[真机验收清单](docs/acceptance.md)。

```text
ios/SipTime/          SwiftUI、通知、网络、Keychain、本地 JSON
ios/SipTimeTests/     课表算法测试
ios/project.yml      XcodeGen 工程定义
ios/Package.swift    独立运行核心测试
backend/app/main.py  FastAPI + SQLite
backend/tests/       权限、并发与持久化测试
docs/                架构和验收说明
```
