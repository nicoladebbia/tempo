//
// AppConstants.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

enum AppConstants {
    static let apiBaseURL: URL = {
        #if DEBUG && targetEnvironment(simulator)
            // `scripts/sim.sh qa --local` points a simulator run at the local
            // test server (scripts/testenv.sh). It's remembered (a cold launch
            // from a notification has no launch args) until a run without
            // --local passes `-tempoAPIBaseURL off`; a bare Xcode ⌘R on the
            // simulator keeps it. Nicola's iPhone can't take this path at all.
            if let override = TestServer.baseURLOverride {
                return override
            }
        #endif
        if let urlString = Bundle.main.infoDictionary?["TEMPO_API_BASE_URL"] as? String,
           let url = URL(string: urlString)
        {
            return url
        }
        // Fallback for unit tests or missing xcconfig
        return URL(string: "http://localhost:8080")!
    }()

    static let environment: String = Bundle.main.infoDictionary?["TEMPO_ENVIRONMENT"] as? String ?? "development"

    static var isDebug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
}
