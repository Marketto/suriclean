// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SuriClean",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "SuriClean",
            path: "Sources/SuriClean"
        )
    ]
)
