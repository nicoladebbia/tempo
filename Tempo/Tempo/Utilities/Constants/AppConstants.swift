import Foundation

enum AppConstants {
    static let apiBaseURL: URL = {
        if let urlString = Bundle.main.infoDictionary?["TEMPO_API_BASE_URL"] as? String,
           let url = URL(string: urlString) {
            return url
        }
        // Fallback for unit tests or missing xcconfig
        return URL(string: "http://localhost:8080")!
    }()

    static let environment: String = {
        Bundle.main.infoDictionary?["TEMPO_ENVIRONMENT"] as? String ?? "development"
    }()

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
