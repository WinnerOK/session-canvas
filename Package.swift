// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionCanvas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SessionCanvas", targets: ["SessionCanvas"]),
        .executable(name: "SessionCanvasProbe", targets: ["SessionCanvasProbe"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "CanvasCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "SessionCanvas", dependencies: ["CanvasCore"]),
        .executableTarget(name: "SessionCanvasProbe", dependencies: ["CanvasCore"]),
        .testTarget(name: "CanvasCoreTests", dependencies: ["CanvasCore"]),
        .testTarget(name: "CanvasRuntimeTests", dependencies: ["SessionCanvas", "CanvasCore"])
    ],
    swiftLanguageModes: [.v5]
)
