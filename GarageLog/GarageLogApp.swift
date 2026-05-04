import SwiftUI
import SwiftData

@main
struct GarageLogApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("logReminderDays") private var logReminderDays: Int = 15

    init() {
        NotificationManager.shared.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 500)
                #endif
        }
        .modelContainer(for: [
            Vehicle.self,
            MaintenanceLog.self,
            MaintenanceReminder.self,
            GasFillup.self
        ])
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                NotificationManager.shared.scheduleLogReminder(daysFromNow: logReminderDays)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
