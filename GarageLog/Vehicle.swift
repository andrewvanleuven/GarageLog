import Foundation
import SwiftData

@Model
final class Vehicle {
    var name: String
    var year: Int
    var make: String
    var model: String
    var licensePlate: String
    var vin: String
    var imageData: Data?
    var isPinned: Bool
    var lastModified: Date
    var currentMileage: Int = 0
    var sortOrder: Int = 0
    var gasFillupDisabled: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceLog.vehicle)
    var maintenanceLogs: [MaintenanceLog] = []
    
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceReminder.vehicle)
    var reminders: [MaintenanceReminder] = []

    @Relationship(deleteRule: .cascade, inverse: \GasFillup.vehicle)
    var gasFillups: [GasFillup] = []
    
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
