import SwiftUI
import SwiftData

struct AllLogsView: View {
    let vehicle: Vehicle
    @Environment(\.modelContext) private var modelContext
    @AppStorage("gasFillupEnabled") private var gasFillupEnabled: Bool = true
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    @State private var searchText = ""
    @State private var logToEdit: MaintenanceLog?
    @State private var fillupToEdit: GasFillup?

    private var fillupActive: Bool { gasFillupEnabled && !vehicle.gasFillupDisabled }

    private var allEntries: [VehicleDetailView.LogEntry] {
        var entries = vehicle.maintenanceLogs.map { VehicleDetailView.LogEntry.maintenance($0) }
        if fillupActive { entries += vehicle.gasFillups.map { .fillup($0) } }
        return entries.sorted { $0.date > $1.date }
    }

    private var filtered: [VehicleDetailView.LogEntry] {
        guard !searchText.isEmpty else { return allEntries }
        let q = searchText.lowercased()
        return allEntries.filter { entry in
            switch entry {
            case .maintenance(let log):
                return log.serviceType.lowercased().contains(q) || log.notes.lowercased().contains(q)
            case .fillup:
                return "gas fill-up".contains(q) || "fuel".contains(q)
            }
        }
    }

    var body: some View {
        List(filtered) { entry in
            switch entry {
            case .maintenance(let log):
                MaintenanceLogRow(log: log)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(log)
                            vehicle.lastModified = Date()
                        } label: { Label("Delete", systemImage: "trash") }
                        Button { logToEdit = log } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.orange)
                    }
            case .fillup(let fillup):
                GasFillupRow(fillup: fillup)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(fillup)
                            vehicle.lastModified = Date()
                        } label: { Label("Delete", systemImage: "trash") }
                        Button { fillupToEdit = fillup } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.orange)
                    }
            }
        }
        .searchable(text: $searchText, prompt: "Search by service type or notes")
        .navigationTitle("Maintenance Logs")
        .sheet(item: $logToEdit) { log in
            AddMaintenanceLogView(vehicle: vehicle, editingLog: log)
        }
        .sheet(item: $fillupToEdit) { fillup in
            AddGasFillupView(vehicles: [vehicle], editingFillup: fillup)
        }
        .tint(Color.fromName(accentColorName))
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}
