// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CameraStream",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CameraStream", targets: ["CameraStream"]),
        .executable(name: "CameraSSHAskpass", targets: ["CameraSSHAskpass"])
    ],
    targets: [
        .executableTarget(
            name: "CameraStream",
            linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("VideoToolbox"), .linkedFramework("Network")]
        ),
        .executableTarget(
            name: "CameraSSHAskpass"
        )
    ]
)
