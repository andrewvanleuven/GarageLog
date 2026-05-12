import SwiftUI
import Charts

struct VehicleStatsView: View {
    let vehicle: Vehicle
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @State private var mileageRange: MileageRange = .lifetime

    enum MileageRange: CaseIterable {
        case threeMonths, sixMonths, twelveMonths, lifetime
        var label: String {
            switch self {
            case .threeMonths: return "3mo"
            case .sixMonths: return "6mo"
            case .twelveMonths: return "12mo"
            case .lifetime: return "Lifetime"
            }
        }
        var months: Int? {
            switch self {
            case .threeMonths: return 3
            case .sixMonths: return 6
            case .twelveMonths: return 12
            case .lifetime: return nil
            }
        }
    }

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

    private var allMileagePoints: [MileagePoint] {
        var pts = vehicle.maintenanceLogs.map { MileagePoint(date: $0.date, mileage: $0.mileage) }
        pts += vehicle.gasFillups.map { MileagePoint(date: $0.date, mileage: $0.mileage) }
        return pts.sorted { $0.date < $1.date }
    }

    private var mileagePoints: [MileagePoint] {
        guard let months = mileageRange.months else { return allMileagePoints }
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        return allMileagePoints.filter { $0.date >= cutoff }
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

            if allMileagePoints.count >= 2 {
                Section("Mileage Over Time") {
                    let visiblePoints = mileagePoints.count >= 2 ? mileagePoints : allMileagePoints
                    Chart(visiblePoints) { pt in
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("Miles", pt.mileage)
                        )
                        .foregroundStyle(accent)
                    }
                    .frame(height: 220)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .topTrailing) {
                        Text(mileageRange.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .padding([.top, .trailing], 12)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let all = MileageRange.allCases
                        let idx = all.firstIndex(of: mileageRange)!
                        mileageRange = all[(idx + 1) % all.count]
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}
