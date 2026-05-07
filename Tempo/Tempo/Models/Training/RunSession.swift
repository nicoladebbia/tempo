//
// RunSession.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - RunSession

@Model
final class RunSession {
    @Attribute(.unique)
    var id: UUID

    var date: Date

    var distanceMeters: Double

    var durationSeconds: Int

    var avgPaceSecondsPerKm: Double?

    var splitsJSON: Data?

    var routePolyline: String?

    var avgHR: Double?

    var maxHR: Double?

    var calories: Double?

    var elevationGainMeters: Double?

    var avgCadence: Double?

    // MARK: - Computed

    @Transient
    var distanceKm: Double {
        distanceMeters / 1000.0
    }

    @Transient
    var durationFormatted: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    @Transient
    var splits: [Double] {
        get {
            guard let data = splitsJSON,
                  let decoded = try? JSONDecoder().decode([Double].self, from: data)
            else {
                return []
            }
            return decoded
        }
        set {
            splitsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var avgPaceFormatted: String? {
        guard let pace = avgPaceSecondsPerKm else {
            return nil
        }
        let mins = Int(pace) / 60
        let secs = Int(pace) % 60
        return String(format: "%d:%02d /km", mins, secs)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        distanceMeters: Double,
        durationSeconds: Int,
        avgPaceSecondsPerKm: Double? = nil,
        splits: [Double] = [],
        routePolyline: String? = nil,
        avgHR: Double? = nil,
        maxHR: Double? = nil,
        calories: Double? = nil,
        elevationGainMeters: Double? = nil,
        avgCadence: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.avgPaceSecondsPerKm = avgPaceSecondsPerKm
        splitsJSON = try? JSONEncoder().encode(splits)
        self.routePolyline = routePolyline
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.calories = calories
        self.elevationGainMeters = elevationGainMeters
        self.avgCadence = avgCadence
    }
}

// MARK: - DTO

extension RunSession {
    struct DTO: Codable {
        let id: UUID
        let date: Date
        let distance_meters: Double
        let duration_seconds: Int
        let avg_pace_seconds_per_km: Double?
        let splits: [Double]
        let route_polyline: String?
        let avg_hr: Double?
        let max_hr: Double?
        let calories: Double?
        let elevation_gain_meters: Double?
        let avg_cadence: Double?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            distance_meters: distanceMeters,
            duration_seconds: durationSeconds,
            avg_pace_seconds_per_km: avgPaceSecondsPerKm,
            splits: splits,
            route_polyline: routePolyline,
            avg_hr: avgHR,
            max_hr: maxHR,
            calories: calories,
            elevation_gain_meters: elevationGainMeters,
            avg_cadence: avgCadence
        )
    }
}
