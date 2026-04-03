// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XAISDK",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "XAISDK",
            targets: ["XAISDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "XAISDK",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(
                    name: "GRPCNIOTransportHTTP2TransportServices",
                    package: "grpc-swift-nio-transport",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .macCatalyst])
                ),
                .product(
                    name: "GRPCNIOTransportHTTP2Posix",
                    package: "grpc-swift-nio-transport",
                    condition: .when(platforms: [.linux, .windows, .android, .wasi, .openbsd])
                ),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "XAISDKTests",
            dependencies: [
                "XAISDK",
                .product(name: "GRPCInProcessTransport", package: "grpc-swift-2")
            ]
        ),
    ]
)
