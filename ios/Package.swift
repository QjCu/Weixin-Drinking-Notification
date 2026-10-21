// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SipTimeCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SipTimeCore", targets: ["SipTimeCore"])],
    targets: [
        .target(name: "SipTimeCore", path: "SipTime",
                exclude: ["APIClient.swift", "AppStore.swift", "FriendView.swift", "NotificationScheduler.swift",
                          "PlanView.swift", "SipTimeApp.swift", "Info.plist", "Info-Debug.plist"],
                sources: ["Models.swift"]),
        .testTarget(name: "SipTimeCoreTests", dependencies: ["SipTimeCore"], path: "SipTimeTests")
    ]
)
