// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiteCounter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SiteCounter",
            path: "Sources/SiteCounter"
        )
    ]
)
