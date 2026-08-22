import SwiftUI
import SwiftData

struct RetiredVehiclesView: View {
    @Query private var allVehicles: [Vehicle]
    @Environment(\.modelContext) private var modelContext

    private var retiredVehicles: [Vehicle] {
        allVehicles.filter { $0.isRetired }.sorted { $0.lastModified > $1.lastModified }
    }

    var body: some View {
        List {
            ForEach(retiredVehicles) { vehicle in
                NavigationLink {
                    VehicleDetailView(vehicle: vehicle)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicle.displayName)
                            .font(.headline)
                        Text("\(String(vehicle.year)) \(vehicle.make) \(vehicle.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        vehicle.isRetired = false
                        try? modelContext.save()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.green)
                }
            }
        }
        .overlay {
            if retiredVehicles.isEmpty {
                ContentUnavailableView {
                    Label("No Retired Vehicles", systemImage: "archivebox")
                } description: {
                    Text("Vehicles you retire stay here with all their history intact.")
                }
            }
        }
        .navigationTitle("Retired Vehicles")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
