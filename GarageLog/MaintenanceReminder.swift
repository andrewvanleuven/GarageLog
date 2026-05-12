import Foundation
import SwiftData

@Model
final class MaintenanceReminder {
    var title: String
    var intervalType: ReminderIntervalType
    var timeFrequency: TimeFrequency?
    var mileageInterval: Int?
    var monthInterval: Int?
    var lastCompletedMileage: Int?
    var lastCompletedDate: Date?
    var nextReminderMileage: Int?
    var nextReminderDate: Date?
    var notes: String
    var vehicle: Vehicle?
    
    init(title: String = "", intervalType: ReminderIntervalType = .mileage, timeFrequency: TimeFrequency? = nil, mileageInterval: Int? = nil, monthInterval: Int? = nil, notes: String = "• ") {
        self.title = title
        self.intervalType = intervalType
        self.timeFrequency = timeFrequency
        self.mileageInterval = mileageInterval
        self.monthInterval = monthInterval
        self.notes = notes
    }
    
    func copy() -> MaintenanceReminder {
        return MaintenanceReminder(
            title: self.title,
            intervalType: self.intervalType,
            timeFrequency: self.timeFrequency,
            mileageInterval: self.mileageInterval,
            monthInterval: self.monthInterval,
            notes: self.notes
        )
    }
}

enum ReminderIntervalType: String, Codable {
    case mileage
    case time
}

enum TimeFrequency: String, Codable, CaseIterable {
    case annual = "Annual"
    case quarterly = "Quarterly"
    case monthly = "Monthly"
}
