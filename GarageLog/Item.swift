//
//  Item.swift
//  GarageLog
//
//  Created by Andrew Van Leuven on 4/17/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
