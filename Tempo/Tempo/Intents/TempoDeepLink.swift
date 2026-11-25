//
// TempoDeepLink.swift
// Tempo
//
// The `tempo://` links the widgets (and Shortcuts) open:
//
//   tempo://open/<today|train|fuel|arena>     go to a tab
//   tempo://start/workout                     start or resume today's session
//   tempo://start/focus[?minutes=25]          start a focus timer
//
// Anything else (the Whoop sign-in callback `tempo://whoop/...`) is ignored
// here and left to the code that owns it.
//

import Foundation

enum TempoDeepLink: Equatable {
    case open(AppTab)
    case start(StartRequest)

    static let scheme = "tempo"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else {
            return nil
        }
        let name = url.pathComponents.dropFirst().first?.lowercased()
        switch (host, name) {
        case let ("open", name?):
            guard let tab = AppTab(rawValue: name) else {
                return nil
            }
            self = .open(tab)
        case ("start", "workout"):
            self = .start(.workout)
        case ("start", "focus"):
            let minutes = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "minutes" }?.value.flatMap(Int.init)
            self = .start(.focus(minutes: minutes.map { min(max($0, 1), 180) }))
        default:
            return nil
        }
    }

    /// Applies the link to the app's routing state.
    @MainActor
    func apply(to appState: AppState) {
        switch self {
        case let .open(tab): appState.open(tab)
        case let .start(request): appState.requestedStart = request
        }
    }
}
