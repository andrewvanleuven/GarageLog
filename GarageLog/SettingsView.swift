import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts
import UserNotifications

struct SettingsView: View {
    @Query private var vehicles: [Vehicle]
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("customAccentColorHex") private var customAccentColorHex: String = ""
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @State private var customPickerColor: Color = .blue
    @AppStorage("gasFillupEnabled") private var gasFillupEnabled: Bool = true
    @AppStorage("mpgGraphStyle") private var mpgGraphStyle: String = "line"
    @AppStorage("mpgTrendWindow") private var mpgTrendWindow: Int = 2
    @AppStorage("historicFuelWindow") private var historicFuelWindow: String = "6months"
    @AppStorage("logReminderDays") private var logReminderDays: Int = 15
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL

    let colorOptions: [(name: String, color: Color)] = [
        ("blue", .blue), ("red", .red), ("green", .green), ("orange", .orange),
        ("pink", .pink), ("purple", .purple), ("indigo", .indigo), ("yellow", .yellow)
    ]

    var body: some View {
        #if os(macOS)
        TabView {
            appearanceForm
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            fuelForm
                .tabItem { Label("Fuel", systemImage: "fuelpump") }
            notificationsForm
                .tabItem { Label("Notifications", systemImage: "bell") }
            dataForm
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(minWidth: 500, minHeight: 280)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifStatus = settings.authorizationStatus
        }
        .onChange(of: logReminderDays) { _, days in
            NotificationManager.shared.scheduleLogReminder(daysFromNow: days)
        }
        #else
        Form {
            appearanceSection
            fuelSection
            notificationsSection
            dataSection
            aboutSection
        }
        .navigationTitle("Settings")
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifStatus = settings.authorizationStatus
        }
        .onChange(of: logReminderDays) { _, days in
            NotificationManager.shared.scheduleLogReminder(daysFromNow: days)
        }
        #endif
    }

    // MARK: - macOS tab forms

    #if os(macOS)
    private var appearanceForm: some View {
        Form {
            appearanceSection
            aboutSection
        }
        .padding()
    }

    private var fuelForm: some View {
        Form { fuelSection }
            .padding()
    }

    private var notificationsForm: some View {
        Form { notificationsSection }
            .padding()
    }

    private var dataForm: some View {
        Form { dataSection }
            .padding()
    }
    #endif

    // MARK: - Shared sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle("Dark Mode", isOn: $isDarkMode)

            LabeledContent("Accent Color") {
                HStack(spacing: 10) {
                    ForEach(colorOptions, id: \.name) { option in
                        ZStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 28, height: 28)
                            if accentColorName == option.name {
                                Circle()
                                    .stroke(isDarkMode ? Color.white : Color.black, lineWidth: 2)
                                    .frame(width: 35, height: 35)
                            }
                        }
                        .onTapGesture { accentColorName = option.name }
                    }

                    // Custom color swatch — ColorPicker handles the tap
                    ZStack {
                        ColorPicker("Custom", selection: Binding(
                            get: { customPickerColor },
                            set: { newColor in
                                customPickerColor = newColor
                                if let hex = newColor.toHex() {
                                    customAccentColorHex = hex
                                    accentColorName = "custom"
                                }
                            }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 28, height: 28)

                        Circle()
                            .fill(
                                customAccentColorHex.isEmpty
                                    ? AnyShapeStyle(AngularGradient(
                                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                        center: .center))
                                    : AnyShapeStyle(customPickerColor)
                            )
                            .frame(width: 28, height: 28)
                            .allowsHitTesting(false)

                        if accentColorName == "custom" {
                            Circle()
                                .stroke(isDarkMode ? Color.white : Color.black, lineWidth: 2)
                                .frame(width: 35, height: 35)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            if let color = Color(hex: customAccentColorHex) {
                customPickerColor = color
            }
        }
    }

    private var fuelSection: some View {
        Section("Gas Fill-up") {
            Toggle("Enable Gas Fill-up Tracking", isOn: $gasFillupEnabled)

            if gasFillupEnabled {
                Picker("MPG Graph Style", selection: $mpgGraphStyle) {
                    Text("Line").tag("line")
                    Text("Bar").tag("bar")
                }

                LabeledContent("Trend Window") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { Double(mpgTrendWindow) },
                                set: { mpgTrendWindow = Int($0.rounded()) }
                            ),
                            in: 1...10, step: 1
                        )
                        .tint(Color.fromName(accentColorName))
                        .frame(maxWidth: 200)
                        Text("\(mpgTrendWindow) fill-up\(mpgTrendWindow == 1 ? "" : "s")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    HistoricFuelCostsView(vehicles: vehicles)
                } label: {
                    Label("Historic Fuel Costs", systemImage: "chart.dots.scatter")
                        .foregroundStyle(Color.fromName(accentColorName))
                }
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            if notifStatus == .denied {
                HStack(spacing: 12) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notifications Blocked")
                            .font(.subheadline.weight(.semibold))
                        Text("Enable notifications for GarageLog in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        #if canImport(UIKit)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                        #else
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            openURL(url)
                        }
                        #endif
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } else {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            NotificationManager.shared.scheduleLogReminder(daysFromNow: logReminderDays)
                        } else {
                            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                        }
                    }

                if notificationsEnabled {
                    Picker("Remind me after", selection: $logReminderDays) {
                        Text("Never").tag(0)
                        Text("5 days").tag(5)
                        Text("15 days").tag(15)
                        Text("1 month").tag(30)
                        Text("90 days").tag(90)
                    }
                    Text("Nudge you to log fill-ups if the app hasn't been opened in this long. Resets on every launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dataSection: some View {
        Section("Data Management") {
            ShareLink(item: allDataCSV, preview: SharePreview("GarageLog Export.csv", image: Image(systemName: "tablecells"))) {
                Label("Export All Logs (CSV)", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Color.fromName(accentColorName))
            }

            ShareLink(item: logTemplateCSV, preview: SharePreview("GarageLog_Log_Template.csv", image: Image(systemName: "doc.badge.plus"))) {
                Label("Export Maintenance Log Template", systemImage: "doc.badge.plus")
                    .foregroundStyle(Color.fromName(accentColorName))
            }

            ShareLink(item: scheduleTemplateCSV, preview: SharePreview("GarageLog_Schedule_Template.csv", image: Image(systemName: "calendar.badge.plus"))) {
                Label("Export Schedule Template", systemImage: "calendar.badge.plus")
                    .foregroundStyle(Color.fromName(accentColorName))
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0.0")
            Text("Bespoke vehicle maintenance tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - CSV data

    private var logTemplateCSV: CSVReport {
        let content = """
        Date,Type,Mileage,Gallons,Parts Cost,Labor Cost,Total Cost,Notes
        1/15/2022,"Oil Change",45230,,15.99,0,15.99,"Valvoline 5W-30 full synthetic, OEM filter"
        3/22/2022,"Tire Rotation",46100,,0,25.00,25.00,""
        6/1/2022,"Brake Service",47500,,89.99,150.00,239.99,"Front pads and rotors replaced"
        8/10/2022,"Battery Replacement",48200,,189.99,0,189.99,"Interstate 24F-3 — 3yr/100k warranty"
        11/5/2022,"Gas Fill-up",49100,12.531,,,47.50,""
        """
        return CSVReport(name: "GarageLog_Log_Template", content: content)
    }

    private var scheduleTemplateCSV: CSVReport {
        let content = """
        Title,Interval Type,Frequency,Mileage Interval,Month Interval,Notes
        "Oil Change",mileage,,5000,0,"0W-20 full synthetic"
        "Tire Rotation",mileage,,5000,0,""
        "Air Filter",mileage,,30000,0,""
        "Cabin Filter",mileage,,15000,0,""
        "Spark Plugs",mileage,,60000,0,"Iridium plugs"
        "Snow Tires",time,Annual,0,10,"Install October — remove April"
        "Inspection",time,Annual,0,6,""
        """
        return CSVReport(name: "GarageLog_Schedule_Template", content: content)
    }

    private var allDataCSV: CSVReport {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        var csvString = "Vehicle,Date,Type,Mileage,Gallons,Parts Cost,Labor Cost,Total Cost,Notes\n"

        for vehicle in vehicles {
            let vName = vehicle.name.replacingOccurrences(of: "\"", with: "\"\"")
            var entries: [(date: Date, row: String)] = []

            for log in vehicle.maintenanceLogs {
                let notes = log.notes.replacingOccurrences(of: "\"", with: "\"\"")
                let service = log.serviceType.replacingOccurrences(of: "\"", with: "\"\"")
                entries.append((log.date, "\"\(vName)\",\(dateFormatter.string(from: log.date)),\"\(service)\",\(log.mileage),,\(log.partsCost),\(log.laborCost),\(log.totalCost),\"\(notes)\"\n"))
            }
            for fillup in vehicle.gasFillups {
                entries.append((fillup.date, "\"\(vName)\",\(dateFormatter.string(from: fillup.date)),\"Gas Fill-up\",\(fillup.mileage),\(String(format: "%.3f", fillup.gallons)),,,\(String(format: "%.2f", fillup.totalCost)),\"\"\n"))
            }

            entries.sort { $0.date > $1.date }
            for entry in entries { csvString.append(entry.row) }
        }
        return CSVReport(name: "GarageLog_All_Data", content: csvString)
    }
}

struct HistoricFuelCostsView: View {
    let vehicles: [Vehicle]
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("historicFuelWindow") private var historicFuelWindow: String = "6months"

    private var cutoff: Date {
        let now = Date()
        switch historicFuelWindow {
        case "3months":  return Calendar.current.date(byAdding: .month, value: -3,  to: now) ?? now
        case "12months": return Calendar.current.date(byAdding: .month, value: -12, to: now) ?? now
        case "lifetime":
            let earliest = vehicles.flatMap { $0.gasFillups }.map { $0.date }.min()
            return Calendar.current.date(byAdding: .day, value: -30, to: earliest ?? now) ?? now
        default:         return Calendar.current.date(byAdding: .month, value: -6,  to: now) ?? now
        }
    }

    private var windowLabel: String {
        switch historicFuelWindow {
        case "3months":  return "3-Month"
        case "12months": return "12-Month"
        case "lifetime": return "Lifetime"
        default:         return "6-Month"
        }
    }

    private func cycleWindow() {
        switch historicFuelWindow {
        case "3months":  historicFuelWindow = "6months"
        case "6months":  historicFuelWindow = "12months"
        case "12months": historicFuelWindow = "lifetime"
        default:         historicFuelWindow = "3months"
        }
    }

    var body: some View {
        let allFillups = vehicles.flatMap { $0.gasFillups }.filter { $0.pricePerGallon > 0 }
        let accentColor = Color.fromName(accentColorName)
        let now = Date()

        List {
            Section {
                if allFillups.isEmpty {
                    Text("Add gas fill-ups to see historic fuel costs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let filtered = allFillups.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
                    if filtered.isEmpty {
                        Text("No fill-ups in this window — click to expand.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                            .onTapGesture { cycleWindow() }
                    } else {
                        Chart(filtered) { fillup in
                            PointMark(x: .value("Date", fillup.date),
                                      y: .value("$/gal", fillup.pricePerGallon))
                                .foregroundStyle(accentColor)
                        }
                        .chartXScale(domain: cutoff...now)
                        .frame(height: 260)
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .onTapGesture { cycleWindow() }

                        Text("\(windowLabel) — click chart to change")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .navigationTitle("Historic Fuel Costs")
    }
}

extension Color {
    static func fromName(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "purple": return .purple
        case "indigo": return .indigo
        case "yellow": return .yellow
        case "custom":
            let hex = UserDefaults.standard.string(forKey: "customAccentColorHex") ?? ""
            return Color(hex: hex) ?? .blue
        default: return .blue
        }
    }

    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double(int         & 0xFF) / 255
        )
    }

    func toHex() -> String? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #else
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = rgb.redComponent
        let g = rgb.greenComponent
        let b = rgb.blueComponent
        #endif
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}
