// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SipTimeCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SipTimeCore", targets: ["SipTimeCore"])],
    targets: [
        .target(name: "SipTimeCore", path: ".",
                exclude: ["SipTimeWidgets", "SipTimeTests", "Shared/AppGroups.entitlements", "project.yml", "Package.swift", "SipTime/APIClient.swift", "SipTime/AppStore.swift", "SipTime/FriendView.swift", "SipTime/NotificationScheduler.swift",
                          "SipTime/PlanView.swift", "SipTime/SipTimeApp.swift", "SipTime/CourseTimetableView.swift", "SipTime/CourseImportView.swift",
                          "SipTime/CourseCapture.swift", "SipTime/Info.plist", "SipTime/Info-Debug.plist"],
                sources: ["SipTime/Models.swift", "SipTime/CourseModels.swift", "SipTime/CourseImportParser.swift", "SipTime/CourseWebNavigationPolicy.swift", "Shared/WidgetData.swift"]),
        .testTarget(name: "SipTimeCoreTests", dependencies: ["SipTimeCore"], path: "SipTimeTests")
    ]
)
