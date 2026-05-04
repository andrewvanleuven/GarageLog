import Foundation
import SwiftData

@Model
final class GasFillup {
    var date: Date
    var mileage: Int
    var gallons: Double
    var totalCost: Double
    // True when the user didn't log the fillup immediately before this one;
    // consecutive-pair MPG is skipped for this entry.
    var skippedPrevious: Bool = false
    var vehicle: Vehicle?

    init(date: Date = Date(), mileage: Int = 0, gallons: Double = 0, totalCost: Double = 0, skippedPrevious: Bool = false) {
        self.date = date
        self.mileage = mileage
        self.gallons = gallons
        self.totalCost = totalCost
        self.skippedPrevious = skippedPrevious
    }

    var pricePerGallon: Double {
        gallons > 0 ? totalCost / gallons : 0
    }
}

// MARK: - MPG helpers
extension Vehicle {
    struct MPGDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let mpg: Double
    }

    /// Returns one data point per consecutive fillup pair where the later fillup
    /// was NOT marked as "skipped previous". Points are sorted by date ascending.
    var mpgDataPoints: [MPGDataPoint] {
        let sorted = gasFillups.sorted { $0.mileage < $1.mileage }
        var points: [MPGDataPoint] = []
        guard sorted.count >= 2 else { return points }
        for i in 1..<sorted.count {
            let curr = sorted[i]
            guard !curr.skippedPrevious else { continue }
            let prev = sorted[i - 1]
            let miles = curr.mileage - prev.mileage
            guard miles > 0, curr.gallons > 0 else { continue }
            points.append(MPGDataPoint(date: curr.date, mpg: Double(miles) / curr.gallons))
        }
        return points
    }

    /// Returns true (improving), false (declining), or nil (not enough data).
    /// Compares the average of the most recent `window` MPG points against the `window` points before those.
    func mpgTrend(window: Int) -> Bool? {
        let points = mpgDataPoints
        guard points.count >= window * 2 else { return nil }
        let recent   = Array(points.suffix(window))
        let previous = Array(points.dropLast(window).suffix(window))
        let recentAvg   = recent.reduce(0.0)   { $0 + $1.mpg } / Double(window)
        let previousAvg = previous.reduce(0.0) { $0 + $1.mpg } / Double(window)
        guard recentAvg != previousAvg else { return nil }
        return recentAvg > previousAvg
    }

    func spendingTrend(window: Int) -> Bool? {
        let sorted = gasFillups.sorted { $0.date < $1.date }
        guard sorted.count >= window * 2 else { return nil }
        let recent   = Array(sorted.suffix(window))
        let previous = Array(sorted.dropLast(window).suffix(window))
        let recentAvg   = recent.reduce(0.0)   { $0 + $1.totalCost } / Double(window)
        let previousAvg = previous.reduce(0.0) { $0 + $1.totalCost } / Double(window)
        guard recentAvg != previousAvg else { return nil }
        return recentAvg > previousAvg  // true = spending more (up arrow)
    }

    func averageMPG(window: String) -> Double? {
        let points = mpgDataPoints
        guard !points.isEmpty else { return nil }
        let now = Date()
        let cutoff: Date
        switch window {
        case "3months":  cutoff = Calendar.current.date(byAdding: .month, value: -3,  to: now) ?? now
        case "12months": cutoff = Calendar.current.date(byAdding: .month, value: -12, to: now) ?? now
        case "lifetime": cutoff = .distantPast
        default:         cutoff = Calendar.current.date(byAdding: .month, value: -6,  to: now) ?? now
        }
        let filtered = points.filter { $0.date >= cutoff }
        guard !filtered.isEmpty else { return nil }
        return filtered.reduce(0.0) { $0 + $1.mpg } / Double(filtered.count)
    }
}
