import Foundation

enum AppConstants {
    static let apiBaseURL: URL = {
        guard let urlString = Bundle.main.infoDictionary?["TEMPO_API_BASE_URL"] as? String,
              let url = URL(string: urlString) else {
            fatalError("TEMPO_API_BASE_URL not set in xcconfig")
        }
        return url
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
