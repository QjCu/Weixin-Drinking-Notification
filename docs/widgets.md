# iPhone 主屏幕课表小组件（006）

提供三个尺寸：小号显示下一节课（当前正在上课时显示当前课），中号显示今天接下来的两门课，大号显示完整七天课表。名称优先使用个人备注，单双周、学期和实际上课时间沿用 App 的课程与学校作息。点击小组件进入 App 的课表页。

## 首次安装配置

此次增加 WidgetKit 扩展和 App Groups 共享容器，必须重新生成 Xcode 工程。先保留你原来的 Team、Bundle Identifier，拉取 version2，然后修改本地 `ios/project.yml` 的顶层 settings/base：

```yaml
SIPTIME_BUNDLE_ID: 你之前使用的App标识
SIPTIME_APP_GROUP: group.你注册的唯一共享组标识
```

保留原 App 标识以覆盖原 App 和保留数据；小组件扩展标识自动是该标识加 `.widgets`。示例 `com.example.SipTime` 和 `group.com.example.SipTime` 只是占位值，不应直接用于自己的真机签名。

在 ios 目录运行 `xcodegen generate`，再 `open SipTime.xcodeproj`。

在 Xcode 的 **Signing & Capabilities** 中，分别选择 **SipTime** 与 **SipTimeWidgets** 两个 target，选择同一个开发团队、自动管理签名，并在 **App Groups** 中创建/勾选同一个已注册共享组。该值必须与 `SIPTIME_APP_GROUP` 完全一致。App Groups 能否使用取决于开发团队所支持的能力；如果 Xcode 提示当前 Personal Team 不支持该能力，需要先解决团队能力/签名配置，不能仅靠重编译实现跨进程同步。参见苹果[添加能力](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app)和[配置 App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)。

选择主 App 的 SipTime scheme 和 iPhone，按 ⌘R 编译安装。无需单独运行扩展。打开 App，导入/保存课表或保存提醒计划，“今天”页面会显示小组件是否已同步。配置缺失时 App 内课表仍会保存，并显示小组件暂未同步。

## 添加到主屏幕

1. 安装后至少打开一次 App，确认已有课程并显示已同步。
2. 在 iPhone 主屏幕长按空白处，选择“编辑 → 添加小组件”（不同 iOS 版本入口文字略有差异）。
3. 搜索“课间一口”，选择“课间一口课表”，左右切换小、中、大尺寸并添加。
4. 点击小组件可进入完整课表，修改课程或备注后保存会请求刷新。

## 刷新与隐私

主 App 只把课程和学校作息写入共享容器；账号 token、学校密码、好友留言不共享。既有 App 状态文件位置不变，原有数据不迁走、不删除。

小组件预先生成上课、课间、下课和午夜等边界的 timeline，数据改变后请求系统重新读取。小组件不是常驻 App，iOS 会根据刷新预算调度，不能保证秒级时间线或强制准时刷新；因此桌面不提供 App 内那条每秒移动的红线。苹果说明：[保持小组件更新](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)。

如果课表缺失，先打开 App 保存课表并检查“今天”的同步状态；如果不能共享，检查两个 target 的团队、App Groups 和自定义标识配置。系统重启后首次解锁前，数据受文件保护，小组件可能暂不可读。没有课程、学期外、作息不匹配都有提示，示例课程仅用于系统预览。
