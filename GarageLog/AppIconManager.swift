import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum IconCycleMode: String, CaseIterable {
    case fixed
    case perLaunch
    case daily
}

/// Manages the "log + car" alternate app icon set (see icon_options/ for the
/// generation script). "gmc" is the primary/default icon; every other car is
/// a bundled alternate icon declared in Info.plist's CFBundleAlternateIcons.
enum AppIconManager {
    static let defaultCar = "gmc"

    static let allCars: [String] = [
        "gmc", "acura", "bmw", "buick", "chevy", "chevy2", "dodge", "dodge2",
        "ford", "ford2", "honda", "jeep", "mazda", "mb", "mitsubishi", "nissan",
        "plymouth", "pontiac", "porsche", "subaru", "toyota", "volvo", "vw"
    ]

    static func displayName(for car: String) -> String {
        switch car {
        case "gmc": return "GMC"
        case "bmw": return "BMW"
        case "mb": return "Mercedes-Benz"
        case "vw": return "Volkswagen"
        case "chevy": return "Chevrolet"
        case "chevy2": return "Chevrolet (Classic)"
        case "dodge2": return "Dodge (Classic)"
        case "ford2": return "Ford (Classic)"
        default: return car.capitalized
        }
    }

    private static let modeKey = "iconCycleMode"
    private static let poolKey = "selectedIconCars"
    private static let fixedKey = "fixedIconCar"
    private static let lastCycleKey = "lastIconCycleDate"

    static var mode: IconCycleMode {
        get { IconCycleMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .fixed }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// The pool of cars to randomly cycle through (perLaunch/daily modes).
    static var pool: [String] {
        get {
            let raw = UserDefaults.standard.string(forKey: poolKey) ?? ""
            let cars = raw.split(separator: ",").map(String.init).filter { allCars.contains($0) }
            return cars.isEmpty ? [defaultCar] : cars
        }
        set { UserDefaults.standard.set(newValue.joined(separator: ","), forKey: poolKey) }
    }

    /// The single car to show when mode == .fixed.
    static var fixedCar: String {
        get { UserDefaults.standard.string(forKey: fixedKey) ?? defaultCar }
        set { UserDefaults.standard.set(newValue, forKey: fixedKey) }
    }

    private static var lastCycleDate: Date? {
        get {
            let interval = UserDefaults.standard.double(forKey: lastCycleKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastCycleKey) }
    }

    /// Applies the icon according to the current cycle mode. Call once per launch.
    static func applyLaunchIcon() {
        switch mode {
        case .fixed:
            setIcon(to: fixedCar)
        case .perLaunch:
            setIcon(to: pool.randomElement() ?? defaultCar)
        case .daily:
            if let last = lastCycleDate, Calendar.current.isDateInToday(last) {
                return // already cycled today — leave the current icon alone
            }
            setIcon(to: pool.randomElement() ?? defaultCar)
            lastCycleDate = Date()
        }
    }

    static func setIcon(to car: String) {
        #if canImport(UIKit)
        let alternateName = car == defaultCar ? nil : "AppIcon_\(car)"
        guard UIApplication.shared.alternateIconName != alternateName else { return }
        UIApplication.shared.setAlternateIconName(alternateName) { error in
            if let error {
                print("AppIconManager: failed to set icon \(car): \(error.localizedDescription)")
            }
        }
        #endif
    }
}
