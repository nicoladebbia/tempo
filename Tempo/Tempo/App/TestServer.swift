//
// TestServer.swift
// Tempo
//
// Local test server hooks (scripts/testenv.sh + `scripts/sim.sh qa --local`).
// DEBUG simulator builds only: the iPhone and every Release build compile
// none of this and always talk to the xcconfig's production URL.
//
// sim.sh signs the simulator in on the test server itself (POST
// /v1/test/login, no Sign in with Apple) and launches with:
//   -tempoAPIBaseURL      http://127.0.0.1:58080   ("off" = back to production)
//   -tempoTestDeviceID    sim-<udid>               (the id the tokens were minted for)
//   -tempoTestAccessToken / -tempoTestRefreshToken / -tempoTestUserID
// The URL and device id are remembered, so a cold launch from a notification
// tap still reaches the local server. The tokens are stored once, in Keychain.
//

import Foundation

#if DEBUG && targetEnvironment(simulator)
    enum TestServer {
        private enum Arg {
            static let baseURL = "-tempoAPIBaseURL"
            static let deviceID = "-tempoTestDeviceID"
            static let accessToken = "-tempoTestAccessToken"
            static let refreshToken = "-tempoTestRefreshToken"
            static let userID = "-tempoTestUserID"
        }

        private enum Saved {
            static let baseURL = "tempo.testServer.baseURL"
            static let deviceID = "tempo.testServer.deviceID"
        }

        static func argument(_ name: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        /// Only loopback hosts: a typo can't point a debug build at some
        /// other server with test tokens.
        static func loopbackURL(_ raw: String?) -> URL? {
            guard let raw, let url = URL(string: raw), let host = url.host,
                  ["127.0.0.1", "localhost"].contains(host)
            else {
                return nil
            }
            return url
        }

        static var baseURLOverride: URL? {
            if let raw = argument(Arg.baseURL) {
                return loopbackURL(raw)
            }
            return loopbackURL(UserDefaults.standard.string(forKey: Saved.baseURL))
        }

        static var deviceIDOverride: String? {
            guard baseURLOverride != nil else {
                return nil
            }
            return argument(Arg.deviceID) ?? UserDefaults.standard.string(forKey: Saved.deviceID)
        }

        /// Remember (or forget) the local server, and store the test session
        /// sim.sh minted. Runs first in TempoApp.init, before ServiceContainer
        /// builds AuthService (which restores the session from Keychain).
        @MainActor
        static func prepare() {
            let defaults = UserDefaults.standard
            if let raw = argument(Arg.baseURL) {
                if let url = loopbackURL(raw) {
                    defaults.set(url.absoluteString, forKey: Saved.baseURL)
                    defaults.set(argument(Arg.deviceID), forKey: Saved.deviceID)
                } else {
                    defaults.removeObject(forKey: Saved.baseURL)
                    defaults.removeObject(forKey: Saved.deviceID)
                }
            }
            guard baseURLOverride != nil,
                  let access = argument(Arg.accessToken),
                  let refresh = argument(Arg.refreshToken),
                  let userID = argument(Arg.userID)
            else {
                return
            }
            AuthService.adoptTestSession(accessToken: access, refreshToken: refresh, userID: userID)
        }
    }
#endif
