@testable import App
import Foundation
import Testing
import Vapor

// Live hit-rate check against the REAL databases. Off by default (network);
//   TEMPO_LIVE_LOOKUP=1 swift test --filter SupplementLiveLookup
// Barcodes were read from real DSLD labels (Oct 2026) plus the products Nicola
// tried on his phone. Each is also tried in the EAN-13 form a phone camera
// reports.

struct SupplementLiveLookupTests {
    static let barcodes: [(upc: String, brand: String)] = [
        ("748927028669", "Optimum Nutrition"), // Gold Standard Whey, Double Rich Chocolate
        ("748927053081", "Optimum"), // Gold Standard Whey, Strawberry
        ("748927023855", "Optimum"), // Micronized Creatine
        ("031604026165", "Nature Made"), // CoQ10
        ("031604026974", "Nature Made"), // Ultra Fish Oil
        ("031604024352", "Nature Made"),
        ("768990017926", "Nordic Naturals"), // Ultimate Omega-D3
        ("768990027932", "Nordic Naturals"), // Ultimate Omega
        ("693749015116", "Thorne"), // Creatine
        ("631656343946", "MuscleTech"),
        ("658010114011", "Garden of Life"),
        ("300054756503", "Centrum"),
        ("737870179832", "Life Extension"),
        ("033984010383", "Solgar"),
        ("842595112627", "Cellucor"),
        ("074312000782", "Nature"),
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TEMPO_LIVE_LOOKUP"] == "1"))
    func realBarcodesResolve() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        let client = SupplementLookupAPIClient()
        var hits = 0
        for (upc, brand) in Self.barcodes {
            let req = Request(application: app, on: app.eventLoopGroup.next())
            // Phone cameras report UPC-A as EAN-13 with a leading zero.
            let dto = try await client.lookup(upc: "0" + upc, on: req)
            print("LIVE \(upc) -> \(dto.map { "\($0.source) | \($0.brand ?? "-") | \($0.name) | \($0.dosePerServing ?? "-") | \($0.servingsPerContainer.map { "\($0)" } ?? "-")" } ?? "MISS")")
            if let dto {
                hits += 1
                #expect(dto.brand == nil || dto.brand?.localizedCaseInsensitiveContains(brand) == true, "\(upc) brand \(dto.brand ?? "nil")")
            }
        }
        print("LIVE hit rate \(hits)/\(Self.barcodes.count)")
        #expect(hits == Self.barcodes.count)
    }
}
