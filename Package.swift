// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Toolbelt",
    platforms: [.macOS(.v13)],
    targets: [
        // Plain Swift logic with no AppKit, so it can be unit tested.
        .target(name: "ToolbeltCore"),
        // The menu bar app itself.
        .executableTarget(
            name: "Toolbelt",
            dependencies: ["ToolbeltCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(name: "ToolbeltCoreTests", dependencies: ["ToolbeltCore"]),
    ]
)
