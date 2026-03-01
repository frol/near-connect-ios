// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NEARConnect",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "NEARConnect",
            targets: ["NEARConnect"]
        ),
    ],
    targets: [
        .target(
            name: "NEARConnect",
            resources: [
                .copy("Resources/near-connect-bridge.html"),
                .copy("Resources/ledger-executor.js"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ]
)
