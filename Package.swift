// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SelectTranslate",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/tisfeng/SelectedTextKit.git", from: "2.6.6"),
        .package(path: "Vendor/KeyboardShortcuts"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SelectTranslate",
            dependencies: [
                .product(name: "SelectedTextKit", package: "SelectedTextKit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SelectTranslate",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework is copied into Contents/Frameworks by scripts/build-app.sh
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
