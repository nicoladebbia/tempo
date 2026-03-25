import Vapor
import Fluent
import FluentPostgresDriver

func configure(_ app: Application) async throws {
    // Content configuration
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase
    ContentConfiguration.global.use(encoder: encoder, for: .json)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    app.routes.defaultMaxBodySize = "1mb"

    // Database — PostgreSQL
    let dbConfig: SQLPostgresConfiguration
    if let databaseURL = Environment.get("DATABASE_URL") {
        dbConfig = try SQLPostgresConfiguration(url: databaseURL)
    } else {
        dbConfig = SQLPostgresConfiguration(
            hostname: Environment.get("DB_HOST") ?? "localhost",
            port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5432,
            username: Environment.get("DB_USER") ?? "tempo",
            password: Environment.get("DB_PASSWORD") ?? "tempo_dev",
            database: Environment.get("DB_NAME") ?? "tempo",
            tls: .disable
        )
    }

    app.databases.use(
        .postgres(configuration: dbConfig),
        as: .psql
    )

    // Routes
    try routes(app)
}
