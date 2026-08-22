import Foundation
import SwiftData

enum MileageUnit: String, Codable {
    case miles = "miles"
    case hours = "hours"
    case none = "none"

    var label: String {
        switch self {
        case .miles: return "mi"
        case .hours: return "hr"
        case .none: return ""
        }
    }

    var tracksMileage: Bool { self != .none }
}

@Model
final class Vehicle {
    var name: String = ""
    var year: Int = 2024
    var make: String = ""
    var model: String = ""
    var licensePlate: String = ""
    var vin: String = ""
    var imageData: Data?
    var isPinned: Bool = false
    var lastModified: Date = Date()
    var currentMileage: Int = 0
    var sortOrder: Int = 0
    var gasFillupDisabled: Bool = false
    var mileageUnitRaw: String = "miles"
    var isRetired: Bool = false

    var mileageUnit: MileageUnit {
        get { MileageUnit(rawValue: mileageUnitRaw) ?? .miles }
        set { mileageUnitRaw = newValue.rawValue }
    }
    
    // Stored as Optional because CloudKit integration requires ALL relationships
    // (including to-many) to be optional. The non-optional computed properties
    // below keep every existing call site working unchanged.
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceLog.vehicle)
    var maintenanceLogsStorage: [MaintenanceLog]?

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceReminder.vehicle)
    var remindersStorage: [MaintenanceReminder]?

    @Relationship(deleteRule: .cascade, inverse: \GasFillup.vehicle)
    var gasFillupsStorage: [GasFillup]?

    var maintenanceLogs: [MaintenanceLog] {
        get { maintenanceLogsStorage ?? [] }
        set { maintenanceLogsStorage = newValue }
    }

    var reminders: [MaintenanceReminder] {
        get { remindersStorage ?? [] }
        set { remindersStorage = newValue }
    }

    var gasFillups: [GasFillup] {
        get { gasFillupsStorage ?? [] }
        set { gasFillupsStorage = newValue }
    }

    var displayName: String {
        name.isEmpty ? "\(make) \(model)" : name
    }

    init(name: String = "", year: Int = 2024, make: String = "", model: String = "", licensePlate: String = "", vin: String = "", imageData: Data? = nil, isPinned: Bool = false, currentMileage: Int = 0) {
        self.name = name
        self.year = year
        self.make = make
        self.model = model
        self.licensePlate = licensePlate
        self.vin = vin
        self.imageData = imageData
        self.isPinned = isPinned
        self.currentMileage = currentMileage
        self.lastModified = Date()
    }
}
