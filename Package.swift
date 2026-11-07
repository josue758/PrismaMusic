// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "PrismaMusic", platforms: [.macOS(.v26)], products: [.executable(name: "PrismaMusic", targets: ["PrismaMusic"])], targets: [.executableTarget(name: "PrismaMusic", resources: [.copy("Resources/Demo")], swiftSettings: [.swiftLanguageMode(.v5)]), .testTarget(name: "PrismaMusicTests", dependencies: ["PrismaMusic"])])
