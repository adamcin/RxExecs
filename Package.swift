// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RxExecs",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "RxExecs",
            targets: ["RxExecs"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/ReactiveX/RxSwift.git", "4.0.0" ..< "5.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "RxExecs",
            dependencies: ["RxSwift", "RxCocoa", "RxBlocking"]),
        .testTarget(
            name: "RxExecsTests",
            dependencies: ["RxExecs", "RxSwift", "RxCocoa", "RxBlocking"]),
    ]
)
