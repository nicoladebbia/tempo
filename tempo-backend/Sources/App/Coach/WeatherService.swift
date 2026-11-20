import Foundation
import Vapor

// MARK: - Weather

struct WeatherConditions: Sendable, Equatable {
    let temperatureC: Double
    let relativeHumidityPercent: Double
}

struct WeatherHour: Sendable, Equatable {
    let time: Date // start of the hour, UTC
    let temperatureC: Double
    let relativeHumidityPercent: Double
}

/// Where the temperature and humidity of a session come from. The coach only needs them for the
/// breathing-water term, which moves a sweat estimate by about 1%, so a failure here must never block a result.
protocol WeatherProviding: Sendable {
    func conditions(latitude: Double, longitude: Double, from: Date, to: Date, on req: Request) async throws -> WeatherConditions?
}

enum WeatherMath {
    /// ~0.1 degree is about 11 km: enough for weather, too coarse to say where someone is.
    static func roundedCoordinate(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// Plain mean over the hours touching [from, to]; nil when none of them is known.
    static func average(_ hours: [WeatherHour], from: Date, to: Date) -> WeatherConditions? {
        let startHour = floorToHour(from)
        let touching = hours.filter { $0.time >= startHour && $0.time <= to }
        guard !touching.isEmpty else { return nil }
        let n = Double(touching.count)
        return WeatherConditions(
            temperatureC: touching.map(\.temperatureC).reduce(0, +) / n,
            relativeHumidityPercent: touching.map(\.relativeHumidityPercent).reduce(0, +) / n
        )
    }

    static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    /// Open-Meteo hourly JSON requested with `timezone=UTC`: times look like "2026-11-20T14:00".
    static func parseOpenMeteo(_ data: Data) throws -> [WeatherHour] {
        struct Body: Decodable {
            struct Hourly: Decodable {
                let time: [String]
                let temperature2m: [Double?]
                let relativeHumidity2m: [Double?]
                enum CodingKeys: String, CodingKey {
                    case time
                    case temperature2m = "temperature_2m"
                    case relativeHumidity2m = "relative_humidity_2m"
                }
            }
            let hourly: Hourly
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var out: [WeatherHour] = []
        for (index, text) in body.hourly.time.enumerated() {
            guard index < body.hourly.temperature2m.count, index < body.hourly.relativeHumidity2m.count,
                  let date = formatter.date(from: text),
                  let t = body.hourly.temperature2m[index], let rh = body.hourly.relativeHumidity2m[index]
            else { continue }
            out.append(WeatherHour(time: date, temperatureC: t, relativeHumidityPercent: rh))
        }
        return out
    }
}

/// Open-Meteo forecast API with `past_days`, which also returns the last days of observed hours.
/// LICENCE: free for NON-COMMERCIAL use only. Before Tempo ships publicly, swap in WeatherKit or a paid
/// Open-Meteo plan behind this same protocol.
struct OpenMeteoWeather: WeatherProviding {
    func conditions(latitude: Double, longitude: Double, from: Date, to: Date, on req: Request) async throws -> WeatherConditions? {
        let lat = WeatherMath.roundedCoordinate(latitude)
        let lon = WeatherMath.roundedCoordinate(longitude)
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&hourly=temperature_2m,relative_humidity_2m&past_days=3&forecast_days=1&timezone=UTC"
        // A slow weather server must never hold up the recovery answer: give up after 2.5 s.
        let client = req.client
        let response = try await withTimeout(2.5) { try await client.get(URI(string: url)) }
        guard response.status == .ok, var body = response.body else { return nil }
        let data = body.readData(length: body.readableBytes) ?? Data()
        return WeatherMath.average(try WeatherMath.parseOpenMeteo(data), from: from, to: to)
    }
}

private struct WeatherProviderKey: StorageKey { typealias Value = any WeatherProviding }

extension Application {
    var weatherProvider: any WeatherProviding {
        get { storage[WeatherProviderKey.self] ?? OpenMeteoWeather() }
        set { storage[WeatherProviderKey.self] = newValue }
    }
}
