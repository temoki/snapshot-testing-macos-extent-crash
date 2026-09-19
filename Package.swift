// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapshotTestingMacOSIssue",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.4")
    ],
    targets: [
        // Two test targets on purpose: SwiftPM runs each .xctest bundle in its own
        // process, so the uncaught Objective-C exception in one does not hide the
        // other's result.
        .testTarget(name: "CoreImageExtentTests"),
        .testTarget(
            name: "PerceptualCompareTests",
            dependencies: [.product(name: "SnapshotTesting", package: "swift-snapshot-testing")]
        ),
    ]
)
