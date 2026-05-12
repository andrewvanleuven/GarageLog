import UserNotifications

struct ReminderNotifData {
    let vehicleName: String
    let title: String
    let intervalType: ReminderIntervalType
    let mileageInterval: Int?
    let lastCompletedMileage: Int?
    let currentMileage: Int
    let timeFrequency: TimeFrequency?
    let monthInterval: Int?
    let nextReminderMileage: Int?
    let nextReminderDate: Date?

    var notifPrefix: String {
        let safe = "\(vehicleName)-\(title)".lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "gl-\(safe)"
    }
}

class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func refresh(vehicleName: String, currentMileage: Int, reminders: [ReminderNotifData]) {
        guard isEnabled else { return }
        let prefix = vehiclePrefix(vehicleName)
        UNUserNotificationCenter.current().getPendingNotificationRequests { existing in
            let toCancel = existing.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: toCancel)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                for r in reminders { self.schedule(r) }
            }
        }
    }

    private func schedule(_ r: ReminderNotifData) {
        switch r.intervalType {
        case .mileage:
            guard let interval = r.mileageInterval else { return }
            let dueAt = r.nextReminderMileage ?? ((r.lastCompletedMileage ?? 0) + interval)
            let remaining = dueAt - r.currentMileage
            guard remaining <= 500 else { return }

            let content = UNMutableNotificationContent()
            content.sound = .default
            if remaining <= 0 {
                content.title = "\(r.title) Overdue"
                content.body = "\(r.vehicleName) — overdue by \(-remaining) miles."
            } else {
                content.title = "\(r.title) Due Soon"
                content.body = "\(r.vehicleName) — due in \(remaining) miles."
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: r.notifPrefix, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

        case .time:
            if let nextDate = r.nextReminderDate {
                let content = UNMutableNotificationContent()
                content.title = "\(r.title) Due"
                content.body = "\(r.vehicleName) — \(r.title) is due."
                content.sound = .default
                var dc = Calendar.current.dateComponents([.year, .month, .day], from: nextDate)
                dc.hour = 9
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let req = UNNotificationRequest(identifier: "\(r.notifPrefix)-pinned", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
                return
            }
            guard let freq = r.timeFrequency else { return }
            let start = r.monthInterval ?? 1
            let months: [Int]
            switch freq {
            case .annual:    months = [start]
            case .quarterly: months = [start, start + 3, start + 6, start + 9].map { (($0 - 1) % 12) + 1 }
            case .monthly:   months = Array(1...12)
            }
            for (i, month) in months.enumerated() {
                var dc = DateComponents()
                dc.month = month; dc.day = 1; dc.hour = 9
                let content = UNMutableNotificationContent()
                content.title = "\(r.title) Due"
                content.body = "\(r.vehicleName) — \(r.title) is due this month."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                let request = UNNotificationRequest(identifier: "\(r.notifPrefix)-t\(i)", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
            }
        }
    }

    // Reschedule on every app foreground — always X days from *now*, so it resets each time the user opens the app.
    func scheduleLogReminder(daysFromNow: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [logReminderID])
        guard daysFromNow > 0, isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to Log Your Vehicles"
        content.body = "Don't forget to log any recent fill-ups or maintenance to keep your records up to date."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(daysFromNow * 86_400), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: logReminderID, content: content, trigger: trigger)
        )
    }

    private let logReminderID = "gl-log-reminder"

    private func vehiclePrefix(_ name: String) -> String {
        "gl-\(name.lowercased().filter { $0.isLetter || $0.isNumber })"
    }
}
