// swift-tools-version: 5.9
// Standalone probe for the TVS P360 data path. Not part of the widget app.

import PackageDescription

let package = Package(
    name: "TVSProbe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "tvs-probe", path: "Sources/tvs-probe"),
    ]
)
