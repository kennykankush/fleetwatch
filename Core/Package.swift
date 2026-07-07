// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StockpileCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RulesKit", targets: ["RulesKit"]),
        .library(name: "ScannerKit", targets: ["ScannerKit"]),
        .library(name: "InventoryKit", targets: ["InventoryKit"]),
        .library(name: "LedgerKit", targets: ["LedgerKit"]),
    ],
    targets: [
        .target(
            name: "LedgerKit"
        ),
        .target(
            name: "RulesKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "ScannerKit",
            dependencies: ["RulesKit"]
        ),
        .target(
            name: "InventoryKit"
        ),
        .testTarget(
            name: "RulesKitTests",
            dependencies: ["RulesKit"]
        ),
        .testTarget(
            name: "ScannerKitTests",
            dependencies: ["ScannerKit"]
        ),
        .testTarget(
            name: "InventoryKitTests",
            dependencies: ["InventoryKit"]
        ),
        .testTarget(
            name: "LedgerKitTests",
            dependencies: ["LedgerKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
