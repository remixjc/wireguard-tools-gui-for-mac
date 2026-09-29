// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WireGuardTray",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // 核心逻辑库：配置解析、命令执行、网卡枚举、PostUp/PostDown 编辑（可单测）
        .target(
            name: "WireGuardCore"
        ),
        // 可执行 App：SwiftUI 状态栏菜单 + 窗口
        .executableTarget(
            name: "WireGuardTray",
            dependencies: ["WireGuardCore"]
        ),
        .testTarget(
            name: "WireGuardCoreTests",
            dependencies: ["WireGuardCore"]
        ),
    ]
)
