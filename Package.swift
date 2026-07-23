// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ITWingSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "ITWingSDK", targets: ["ITWingSDK"])
    ],
    dependencies: [
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", from: "13.6.0"),
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.5.0")
    ],
    targets: [
        .target(
            name: "ITWingSDK",
            dependencies: [
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "Lottie", package: "lottie-ios")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ITWingSDKTests",
            dependencies: ["ITWingSDK"]
        )
    ]
)
