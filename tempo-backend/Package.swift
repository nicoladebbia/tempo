// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "tempo-backend",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Vapor core
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),

        // Fluent ORM + PostgreSQL driver
        .package(url: "https://github.com/vapor/fluent.git", from: "4.11.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),

        // JWT (ES256 signing + verification)
        .package(url: "https://github.com/vapor/jwt.git", from: "5.0.0"),

        // Redis
        .package(url: "https://github.com/vapor/redis.git", from: "4.0.0"),

        // Queues (background jobs) + Redis driver
        .package(url: "https://github.com/vapor/queues.git", from: "1.16.0"),
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.1.0"),

        // APNs push notifications
        .package(url: "https://github.com/vapor/apns.git", from: "4.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "Redis", package: "redis"),
                .product(name: "Queues", package: "queues"),
                .product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
                .product(name: "VaporAPNS", package: "apns"),
            ],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            path: "Tests/AppTests"
        ),
    ]
)
