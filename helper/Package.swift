// swift-tools-version:5.9
import PackageDescription
import Foundation

// Absolute path to vendor/Syphon.framework.
// Development and test runs resolve through this absolute rpath;
// build-helper.sh swaps in a relative one when packaging.
let vendorPath = Context.packageDirectory + "/../vendor"

let syphonFlags: [String] = [
    "-F", vendorPath,
    "-framework", "Syphon",
    "-Xlinker", "-rpath", "-Xlinker", vendorPath,
    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
]

let package = Package(
    name: "SyphonBridge",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "SyphonBridgeCore",
            swiftSettings: [.unsafeFlags(["-F", vendorPath])],
            linkerSettings: [.unsafeFlags(syphonFlags)]
        ),
        .executableTarget(
            name: "syphon-bridge",
            dependencies: ["SyphonBridgeCore"],
            swiftSettings: [.unsafeFlags(["-F", vendorPath])],
            linkerSettings: [.unsafeFlags(syphonFlags)]
        ),
        .executableTarget(
            name: "TestSyphonServer",
            swiftSettings: [.unsafeFlags(["-F", vendorPath])],
            linkerSettings: [.unsafeFlags(syphonFlags)]
        ),
        .testTarget(
            name: "SyphonBridgeCoreTests",
            dependencies: ["SyphonBridgeCore"],
            swiftSettings: [.unsafeFlags(["-F", vendorPath])],
            linkerSettings: [.unsafeFlags(syphonFlags)]
        ),
    ]
)
