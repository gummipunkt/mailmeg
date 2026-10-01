// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MailmegKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MailmegKit", targets: ["MailmegKit"]),
    ],
    targets: [
        .target(name: "MailmegKit"),
        .testTarget(name: "MailmegKitTests", dependencies: ["MailmegKit"]),
    ]
)
