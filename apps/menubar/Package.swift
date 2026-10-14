// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentStatus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AgentStatus", path: "Sources/AgentStatus")
    ]
)
