// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "RadialCore", targets: ["RadialCore"]),
]
var targets: [Target] = [
    .target(name: "RadialCore"),
    .testTarget(name: "RadialCoreTests", dependencies: ["RadialCore"]),
]

#if os(macOS)
products.append(.executable(name: "SafariRadial", targets: ["SafariRadial"]))
targets.append(.executableTarget(name: "SafariRadial", dependencies: ["RadialCore"]))
#endif

let package = Package(
    name: "SafariRadial",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
