// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PresentlyKit",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PresentlyKit", targets: ["PresentlyKit"])],
    targets: [
        .target(name: "PresentlyKit"),
        .testTarget(name: "PresentlyKitTests", dependencies: ["PresentlyKit"])
    ],
    swiftLanguageModes: [.v6]
)
