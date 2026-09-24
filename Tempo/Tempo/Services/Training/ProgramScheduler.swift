//
// ProgramScheduler.swift
// Tempo
//
// Places trainer sessions that came without a weekday ("Lifting 1",
// "Aerobic run") around the athlete's football days. Days the source gave a
// weekday are never moved. Lifts are spread across free days first, then
// conditioning fills the remaining free days; if the week has more sessions
// than free days, extra conditioning is stacked onto lift days as a second
// session (lift + conditioning), furthest from football first.
//

import Foundation

enum ProgramScheduler {
    /// ISO weekdays (1 = Monday … 7 = Sunday) of the recurring football days.
    static func isoWeekdays(of days: ActiveDays) -> Set<Int> {
        Set((1 ... 7).filter { days.rawValue & (1 << ($0 - 1)) != 0 })
    }

    static func place(weeks: [ProgramWeek], footballWeekdays: Set<Int>) -> [ProgramWeek] {
        weeks.map { place(week: $0, footballWeekdays: footballWeekdays) }
    }

    static func place(week: ProgramWeek, footballWeekdays: Set<Int>) -> ProgramWeek {
        var week = week
        let guessed = week.days.indices.filter { week.days[$0].weekdayGuessed == true }
        guard !guessed.isEmpty else {
            return week
        }
        let fixed = Set(week.days.indices.filter { week.days[$0].weekdayGuessed != true }.map { week.days[$0].weekday })
        var free = (1 ... 7).filter { !footballWeekdays.contains($0) && !fixed.contains($0) }
        if free.isEmpty {
            // Football every day (or everything fixed): fall back to any day
            // without a fixed session so nothing is silently dropped.
            free = (1 ... 7).filter { !fixed.contains($0) }
        }
        if free.isEmpty {
            free = Array(1 ... 7)
        }

        let strength = guessed.filter { week.days[$0].isStrength }
        let conditioning = guessed.filter { !week.days[$0].isStrength }

        // 1. Lifts: evenly spread over the free days, keeping program order.
        let liftDays = spread(count: min(strength.count, free.count), over: free)
        var used: [Int] = []
        for (offset, dayIndex) in strength.enumerated() {
            let weekday = offset < liftDays.count ? liftDays[offset] : liftDays.last ?? free[0]
            week.days[dayIndex].weekday = weekday
            used.append(weekday)
        }

        // 2. Conditioning: remaining free days, spread; overflow stacks on
        //    lift days, those furthest from football first.
        let remaining = free.filter { !used.contains($0) }
        let condDays = spread(count: min(conditioning.count, remaining.count), over: remaining)
        let stackOrder = Array(Set(used)).sorted {
            distanceToFootball($0, footballWeekdays) > distanceToFootball($1, footballWeekdays)
        }
        for (offset, dayIndex) in conditioning.enumerated() {
            if offset < condDays.count {
                week.days[dayIndex].weekday = condDays[offset]
            } else if !stackOrder.isEmpty {
                week.days[dayIndex].weekday = stackOrder[(offset - condDays.count) % stackOrder.count]
            } else {
                week.days[dayIndex].weekday = free[offset % free.count]
            }
        }
        return week
    }

    /// `count` weekdays picked from `days` (sorted) as evenly as possible.
    static func spread(count: Int, over days: [Int]) -> [Int] {
        let sorted = days.sorted()
        guard count > 0, !sorted.isEmpty else {
            return []
        }
        guard count < sorted.count else {
            return sorted
        }
        if count == 1 {
            return [sorted[0]]
        }
        let step = Double(sorted.count - 1) / Double(count - 1)
        var picked: [Int] = []
        for i in 0 ..< count {
            let candidate = sorted[Int((Double(i) * step).rounded())]
            if !picked.contains(candidate) {
                picked.append(candidate)
            }
        }
        // Rounding collisions: top up with the first unused days.
        for day in sorted where picked.count < count && !picked.contains(day) {
            picked.append(day)
        }
        return picked.sorted()
    }

    /// Days (circular week) to the nearest football day; 7 when there is none.
    private static func distanceToFootball(_ weekday: Int, _ football: Set<Int>) -> Int {
        guard !football.isEmpty else {
            return 7
        }
        return football.map { f in
            let d = abs(f - weekday)
            return min(d, 7 - d)
        }.min() ?? 7
    }
}
