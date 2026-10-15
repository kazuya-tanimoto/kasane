// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kasane",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Kasane", targets: ["Kasane"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // OS に依存しないロジック（あいまい検索、FIFO/LIFO キュー）。Linux でもテストできる
        .target(
            name: "KasaneCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 履歴の保存（SQLite / GRDB）。AppKit に依存しないので Linux でもテストできる
        .target(
            name: "KasaneStore",
            dependencies: [
                "KasaneCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Kasane",
            dependencies: [
                "KasaneCore",
                "KasaneStore",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KasaneCoreTests",
            dependencies: ["KasaneCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KasaneStoreTests",
            dependencies: ["KasaneStore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
