// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPetCapture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "codex-pet-capture", targets: ["CodexPetCapture"]),
        .executable(name: "codex-pet-menubar", targets: ["CodexPetMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexPetCapture",
            path: "Sources/CodexPetCapture"
        ),
        .executableTarget(
            name: "CodexPetMenuBar",
            path: "Sources/CodexPetMenuBar"
        )
    ]
)
