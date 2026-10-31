// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PHPIDE",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PHPIDE", targets: ["PHPIDE"]),
        .library(name: "PHPIDECore", targets: ["PHPIDECore"]),
    ],
    dependencies: [
        // Terminal emulation (VT100/xterm) + PTY process management for the Terminal panel.
        // 1.11.2: the last release before the Metal renderer, which needs the separately
        // downloaded Metal toolchain (Xcode 26+) to build.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.11.2"),
    ],
    targets: [
        // UI-independent pieces: LSP client, Go highlighter, text/position math, file tree.
        .target(name: "PHPIDECore"),
        // SwiftUI/AppKit application shell.
        .executableTarget(name: "PHPIDE", dependencies: ["PHPIDECore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "PHPIDECoreTests", dependencies: ["PHPIDECore"]),
        .testTarget(name: "PHPIDETests", dependencies: ["PHPIDE", "PHPIDECore"]),
    ]
)
