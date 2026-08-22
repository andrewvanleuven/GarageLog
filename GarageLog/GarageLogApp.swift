import SwiftUI
import SwiftData

@main
struct GarageLogApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("logReminderDays") private var logReminderDays: Int = 15

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vehicle.self,
            MaintenanceLog.self,
            MaintenanceReminder.self,
            GasFillup.self
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    init() {
        NotificationManager.shared.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 500)
                #endif
                .task {
                    AppIconManager.applyLaunchIcon()
                }
        }
        .modelContainer(Self.sharedModelContainer)
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
