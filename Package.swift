// swift-tools-version: 6.0
import PackageDescription

// Заметочки - минималистичные заметки: синий фон, белый Caveat, мягкий звук печати.
// Полностью локальные: шрифт лежит в бандле, заметки - JSON-файлы в Application Support/Zametki.
// Собирается без Xcode, только Command Line Tools: ./build.sh
let package = Package(
    name: "Zametki",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Zametki",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
