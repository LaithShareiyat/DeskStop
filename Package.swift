// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeskStop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PresentationCore",
            path: "Sources/PresentationCore"
        ),
        .target(
            name: "SchedulingCore",
            path: "Sources/SchedulingCore"
        ),
        .target(
            name: "DisplayCore",
            path: "Sources/DisplayCore"
        ),
        .target(
            name: "IconLayoutCore",
            path: "Sources/IconLayoutCore"
        ),
        .target(
            name: "UpdateCore",
            path: "Sources/UpdateCore"
        ),
        .executableTarget(
            name: "DeskStop",
            dependencies: ["IconLayoutCore", "PresentationCore", "SchedulingCore", "DisplayCore", "UpdateCore"],
            path: "Sources/DeskStop"
        ),
        .testTarget(
            name: "PresentationCoreTests",
            dependencies: ["PresentationCore"],
            path: "Tests/PresentationCoreTests"
        ),
        .testTarget(
            name: "SchedulingCoreTests",
            dependencies: ["SchedulingCore"],
            path: "Tests/SchedulingCoreTests"
        ),
        .testTarget(
            name: "DisplayCoreTests",
            dependencies: ["DisplayCore"],
            path: "Tests/DisplayCoreTests"
        ),
        .testTarget(
            name: "UpdateCoreTests",
            dependencies: ["UpdateCore"],
            path: "Tests/UpdateCoreTests"
        ),
        .testTarget(
            name: "IconLayoutCoreTests",
            dependencies: ["IconLayoutCore"],
            path: "Tests/IconLayoutCoreTests"
        ),
    ]
)
