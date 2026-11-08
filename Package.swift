// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrismaMusic", platforms: [.macOS(.v26)],
    products: [.executable(name: "PrismaMusic", targets: ["PrismaMusic"])],
    targets: [
        .executableTarget(
            name: "PrismaMusic", resources: [.copy("Resources/Demo"), .copy("Resources/Version.plist")],
            swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "PrismaMusicTests", dependencies: ["PrismaMusic"]),
    ])
