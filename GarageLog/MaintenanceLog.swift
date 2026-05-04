import Foundation
import SwiftData

@Model
final class MaintenanceLog {
    var date: Date
    var mileage: Int
    var serviceType: String
    var notes: String
    var partsCost: Double
    var laborCost: Double
    var vehicle: Vehicle?
    var receiptPhotoData: Data? = nil

    var totalCost: Double {
        partsCost + laborCost
    }

    init(date: Date = Date(), mileage: Int = 0, serviceType: String = "", notes: String = "• ", partsCost: Double = 0.0, laborCost: Double = 0.0) {
        self.date = date
        self.mileage = mileage
        self.serviceType = serviceType
        self.notes = notes
        self.partsCost = partsCost
        self.laborCost = laborCost
    }
}
