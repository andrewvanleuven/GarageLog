import SwiftUI
import Charts

struct VehicleStatsView: View {
    let vehicle: Vehicle
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true

    struct MileagePoint: Identifiable {
        let id = UUID()
        let date: Date
        let mileage: Int
    }

    private var totalParts: Double { vehicle.maintenanceLogs.reduce(0) { $0 + $1.partsCost } }
    private var totalLabor: Double { vehicle.maintenanceLogs.reduce(0) { $0 + $1.laborCost } }
    private var totalGas: Double { vehicle.gasFillups.reduce(0) { $0 + $1.totalCost } }
    private var totalSpend: Double { totalParts + totalLabor + totalGas }

    private var costPerMile: Double? {
        guard vehicle.currentMileage > 0 && totalSpend > 0 else { return nil }
        return totalSpend / Double(vehicle.currentMileage)
    }

    private var mileagePoints: [MileagePoint] {
        var pts = vehicle.maintenanceLogs.map { MileagePoint(date: $0.date, mileage: $0.mileage) }
        pts += vehicle.gasFillups.map { MileagePoint(date: $0.date, mileage: $0.mileage) }
        return pts.sorted { $0.date < $1.date }
    }

    var body: some View {
        let accent = Color.fromName(accentColorName)
        List {
            Section("Lifetime Cost") {
                LabeledContent("Parts", value: totalParts, format: .currency(code: "USD"))
                LabeledContent("Labor", value: totalLabor, format: .currency(code: "USD"))
                LabeledContent("Gas", value: totalGas, format: .currency(code: "USD"))
                Divider()
                LabeledContent("Total", value: totalSpend, format: .currency(code: "USD"))
                    .bold()
                if let cpm = costPerMile {
                    LabeledContent("Cost per Mile", value: cpm, format: .currency(code: "USD"))
                        .foregroundStyle(.secondary)
                }
            }

            if mileagePoints.count >= 2 {
                Section("Mileage Over Time") {
                    Chart(mileagePoints) { pt in
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("Miles", pt.mileage)
                        )
                        .foregroundStyle(accent)
                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value("Miles", pt.mileage)
                        )
                        .foregroundStyle(accent)
                        .symbolSize(25)
                    }
                    .frame(height: 220)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Stats")
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}
