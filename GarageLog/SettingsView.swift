import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts
import UserNotifications

struct SettingsView: View {
    @Query private var vehicles: [Vehicle]
    @Environment(\.modelContext) private var modelContext
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
    @AppStorage("showNextUpBulletin") private var showNextUpBulletin: Bool = true
    #if os(iOS)
    @AppStorage("iconCycleMode") private var iconCycleMode: IconCycleMode = .fixed
    @AppStorage("fixedIconCar") private var fixedIconCar: String = AppIconManager.defaultCar
    @AppStorage("selectedIconCars") private var selectedIconCarsRaw: String = AppIconManager.allCars.joined(separator: ",")
    #endif

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingRestoreImporter = false
    @State private var restoreResultMessage = ""
    @State private var showingRestoreResult = false
    @State private var pendingRestoreURL: URL?
    @State private var showingRestoreModeDialog = false
    @Environment(\.openURL) private var openURL
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared

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
        .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url): pendingRestoreURL = url; showingRestoreModeDialog = true
            case .failure: restoreResultMessage = "Could not open file."; showingRestoreResult = true
            }
        }
        .confirmationDialog("Restore Mode", isPresented: $showingRestoreModeDialog, titleVisibility: .visible) {
            Button("Merge — Skip Duplicates") {
                if let url = pendingRestoreURL { importGarageBackup(from: url, mode: .merge) }
            }
            Button("Fresh Restore — Wipe & Replace", role: .destructive) {
                if let url = pendingRestoreURL { importGarageBackup(from: url, mode: .fresh) }
            }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("How would you like to restore this backup?")
        }
        .alert("Restore Complete", isPresented: $showingRestoreResult) {
            Button("OK", role: .cancel) { }
        } message: { Text(restoreResultMessage) }
        #else
        Form {
            appearanceSection
            appIconSection
            fuelSection
            notificationsSection
            cloudSyncSection
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
        .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url): pendingRestoreURL = url; showingRestoreModeDialog = true
            case .failure: restoreResultMessage = "Could not open file."; showingRestoreResult = true
            }
        }
        .confirmationDialog("Restore Mode", isPresented: $showingRestoreModeDialog, titleVisibility: .visible) {
            Button("Merge — Skip Duplicates") {
                if let url = pendingRestoreURL { importGarageBackup(from: url, mode: .merge) }
            }
            Button("Fresh Restore — Wipe & Replace", role: .destructive) {
                if let url = pendingRestoreURL { importGarageBackup(from: url, mode: .fresh) }
            }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("How would you like to restore this backup?")
        }
        .alert("Restore Complete", isPresented: $showingRestoreResult) {
            Button("OK", role: .cancel) { }
        } message: { Text(restoreResultMessage) }
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
        Form {
            cloudSyncSection
            dataSection
        }
        .padding()
    }
    #endif

    // MARK: - Shared sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle("Dark Mode", isOn: $isDarkMode)
            Toggle("Show \"Next Up\" Bulletin", isOn: $showNextUpBulletin)

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

    private var cloudSyncSection: some View {
        Section("iCloud Sync") {
            HStack {
                Image(systemName: cloudSyncIcon)
                    .foregroundStyle(cloudSyncColor)
                Text(cloudSyncStatusText)
                    .foregroundStyle(.secondary)
                Spacer()
                if cloudSync.status == .syncing {
                    ProgressView()
                }
            }
        }
    }

    private var cloudSyncIcon: String {
        switch cloudSync.status {
        case .neverSynced: return "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .succeeded: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private var cloudSyncColor: Color {
        switch cloudSync.status {
        case .neverSynced: return .secondary
        case .syncing: return .blue
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private var cloudSyncStatusText: String {
        switch cloudSync.status {
        case .neverSynced: return "Not yet synced"
        case .syncing: return "Syncing…"
        case .succeeded(let date):
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .full
            return "Synced \(fmt.localizedString(for: date, relativeTo: Date()))"
        case .failed(let message): return "Sync error: \(message)"
        }
    }

    private var dataSection: some View {
        let accent = Color.fromName(accentColorName)
        let photoURLs = vehiclePhotoURLs
        return Section("Data Management") {
            #if os(iOS)
            let retiredCount = vehicles.filter { $0.isRetired }.count
            if retiredCount > 0 {
                NavigationLink {
                    RetiredVehiclesView()
                } label: {
                    Label("Retired Vehicles (\(retiredCount))", systemImage: "archivebox")
                        .foregroundStyle(accent)
                }
            }
            #endif

            ShareLink(item: garageBackupCSV, preview: SharePreview("GarageLog_Backup.csv", image: Image(systemName: "externaldrive"))) {
                Label("Back Up Garage", systemImage: "square.and.arrow.up")
                    .foregroundStyle(accent)
            }

            Button {
                showingRestoreImporter = true
            } label: {
                Label("Restore from Backup", systemImage: "square.and.arrow.down")
                    .foregroundStyle(accent)
            }

            if !photoURLs.isEmpty {
                ShareLink(items: photoURLs, preview: { url in
                    SharePreview(url.deletingPathExtension().lastPathComponent, image: Image(systemName: "photo"))
                }) {
                    Label("Export Vehicle Photos (\(photoURLs.count))", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(accent)
                }
            }

            Menu {
                ShareLink(item: logTemplateCSV, preview: SharePreview("GarageLog_Log_Template.csv", image: Image(systemName: "doc.badge.plus"))) {
                    Label("Log Template", systemImage: "doc.badge.plus")
                }
                ShareLink(item: scheduleTemplateCSV, preview: SharePreview("GarageLog_Schedule_Template.csv", image: Image(systemName: "calendar.badge.plus"))) {
                    Label("Schedule Template", systemImage: "calendar.badge.plus")
                }
            } label: {
                Label("Export Import Template", systemImage: "doc.badge.arrow.up")
                    .foregroundStyle(accent)
            }
        }
    }

    private var vehiclePhotoURLs: [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gl-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return vehicles.compactMap { v in
            guard let data = v.imageData else { return nil }
            let safeName = v.displayName.filter { $0.isLetter || $0.isNumber || $0 == " " }
            let url = dir.appendingPathComponent(safeName).appendingPathExtension("jpg")
            try? data.write(to: url)
            return url
        }
    }

    #if os(iOS)
    private var appIconSection: some View {
        Section {
            NavigationLink("App Icon") {
                AppIconPickerView()
            }
        }
    }
    #endif

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
        // Cols: RecordType(0) | Nickname-CurrentMileage(1-8) | Date(9) | ServiceType(10) | Mileage(11) |
        //       Gallons(12) | PartsCost(13) | LaborCost(14) | TotalCost(15) | Notes(16) | SkippedPrevious(17)
        let rows = [
            "log,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,1/15/22,\"Oil Change\",45230,,15.99,0,15.99,\"Valvoline 5W-30, OEM filter\"",
            "log,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,3/22/22,\"Tire Rotation\",46100,,0,25.00,25.00,\"\"",
            "log,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,6/1/22,\"Brake Service\",47500,,89.99,150.00,239.99,\"Front pads and rotors\"",
            "fillup,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,11/5/22,,49100,12.531,,,47.50,\"\",false",
        ].joined(separator: "\n")
        return CSVReport(name: "GarageLog_Log_Template", content: garageCSVHeader() + rows + "\n")
    }

    private var scheduleTemplateCSV: CSVReport {
        // Cols: RecordType(0) | Nickname-CurrentMileage(1-8) | Date(9-blank) | ServiceType(10=title) |
        //       Mileage-SkippedPrevious(11-17 blank) | IntervalType(18) | Frequency(19) |
        //       MileageInterval(20) | MonthInterval(21) | LastCompletedMileage(22) |
        //       LastCompletedDate(23) | NextReminderMileage(24) | NextReminderDate(25)
        let rows = [
            "reminder,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,,\"Oil Change\",,,,,,,\"0W-20 full synthetic\",,mileage,,5000,0,,,",
            "reminder,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,,\"Tire Rotation\",,,,,,,,mileage,,5000,0,,,",
            "reminder,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,,\"Spark Plugs\",,,,,,,\"Iridium plugs\",mileage,,60000,0,,,",
            "reminder,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,,\"Snow Tires\",,,,,,,\"Install Oct — remove Apr\",time,Annual,,10,,,",
            "reminder,\"My Car\",2020,\"Toyota\",\"Camry\",\"\",\"\",true,49100,,\"Inspection\",,,,,,,,time,Annual,,6,,,",
        ].joined(separator: "\n")
        return CSVReport(name: "GarageLog_Schedule_Template", content: garageCSVHeader() + rows + "\n")
    }

    private var garageBackupCSV: CSVReport {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "M/d/yy"
        var content = garageCSVHeader()
        for v in vehicles.sorted(by: { $0.displayName < $1.displayName }) {
            content += vehicleCSVRows(v, using: df)
        }
        return CSVReport(name: "GarageLog_Backup", content: content)
    }

    private func importGarageBackup(from url: URL, mode: ImportMode) {
        guard url.startAccessingSecurityScopedResource() else {
            restoreResultMessage = "Permission denied for file."
            showingRestoreResult = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            restoreResultMessage = "Could not read file."
            showingRestoreResult = true
            return
        }
        let rows = parseCSV(content)
        guard rows.count > 1 else {
            restoreResultMessage = "No records found in file."
            showingRestoreResult = true
            return
        }
        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard headers.first == "recordtype" else {
            restoreResultMessage = "Unrecognized format. Only the universal backup format is supported for garage restore."
            showingRestoreResult = true
            return
        }

        if mode == .fresh {
            for v in vehicles { modelContext.delete(v) }
            try? modelContext.save()
        }

        func col(_ row: [String], _ idx: Int?) -> String {
            guard let idx, row.indices.contains(idx) else { return "" }
            return row[idx].trimmingCharacters(in: .whitespaces)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        let fmts = ["M/d/yy", "M/d/yyyy", "MM/dd/yy", "MM/dd/yyyy", "yyyy-MM-dd"]
        func parseDate(_ s: String) -> Date? {
            for fmt in fmts { df.dateFormat = fmt; if let d = df.date(from: s.trimmingCharacters(in: .whitespaces)) { return d } }
            return nil
        }

        var workingVehicles: [Vehicle] = mode == .fresh ? [] : vehicles

        func findOrCreate(nickname: String, year: Int, make: String, model: String,
                          vin: String, plate: String, trackFuel: Bool) -> Vehicle {
            if !vin.isEmpty, let v = workingVehicles.first(where: { !$0.vin.isEmpty && $0.vin.uppercased() == vin.uppercased() }) { return v }
            if let v = workingVehicles.first(where: { $0.make.lowercased() == make.lowercased() && $0.model.lowercased() == model.lowercased() && $0.year == year }) { return v }
            let v = Vehicle(name: nickname, year: year, make: make, model: model,
                            licensePlate: plate.uppercased(), vin: vin.uppercased())
            v.gasFillupDisabled = !trackFuel
            modelContext.insert(v)
            workingVehicles.append(v)
            return v
        }

        let cal = Calendar.current
        var imported = 0
        for row in rows.dropFirst() {
            let year = Int(col(row, 2)) ?? 2000
            let trackFuel = col(row, 7).lowercased() != "false"
            let vehicle = findOrCreate(
                nickname: col(row, 1), year: year, make: col(row, 3), model: col(row, 4),
                vin: col(row, 5), plate: col(row, 6), trackFuel: trackFuel)

            switch col(row, 0).lowercased() {
            case "log":
                guard let date = parseDate(col(row, 9)) else { continue }
                let svc = col(row, 10); guard !svc.isEmpty else { continue }
                let mileage = Int(col(row, 11)) ?? 0
                if mode == .merge {
                    let dup = vehicle.maintenanceLogs.contains { cal.isDate($0.date, inSameDayAs: date) && $0.serviceType == svc && $0.mileage == mileage }
                    if dup { continue }
                }
                let log = MaintenanceLog(date: date, mileage: mileage, serviceType: svc,
                    notes: col(row, 16),
                    partsCost: Double(col(row, 13)) ?? 0, laborCost: Double(col(row, 14)) ?? 0)
                log.vehicle = vehicle; vehicle.maintenanceLogs.append(log)
                if mileage > vehicle.currentMileage { vehicle.currentMileage = mileage }
                imported += 1
            case "fillup":
                guard let date = parseDate(col(row, 9)) else { continue }
                let gallons = Double(col(row, 12)) ?? 0; guard gallons > 0 else { continue }
                let mileage = Int(col(row, 11)) ?? 0
                if mode == .merge {
                    let dup = vehicle.gasFillups.contains { cal.isDate($0.date, inSameDayAs: date) && $0.mileage == mileage }
                    if dup { continue }
                }
                let fillup = GasFillup(date: date, mileage: mileage, gallons: gallons,
                    totalCost: Double(col(row, 15)) ?? 0,
                    skippedPrevious: col(row, 17).lowercased() == "true")
                fillup.vehicle = vehicle; vehicle.gasFillups.append(fillup)
                if mileage > vehicle.currentMileage { vehicle.currentMileage = mileage }
                imported += 1
            case "reminder":
                let title = col(row, 10); guard !title.isEmpty else { continue }
                if mode == .merge {
                    let dup = vehicle.reminders.contains { $0.title.lowercased() == title.lowercased() }
                    if dup { continue }
                }
                let itype = ReminderIntervalType(rawValue: col(row, 18)) ?? .mileage
                let mi = Int(col(row, 20)).flatMap { $0 > 0 ? $0 : nil }
                let mo = Int(col(row, 21)).flatMap { $0 > 0 ? $0 : nil }
                let n = col(row, 16)
                let reminder = MaintenanceReminder(title: title, intervalType: itype,
                    timeFrequency: TimeFrequency(rawValue: col(row, 19)),
                    mileageInterval: mi, monthInterval: mo, notes: n.isEmpty ? "• " : n)
                reminder.lastCompletedMileage = Int(col(row, 22))
                reminder.lastCompletedDate    = parseDate(col(row, 23))
                reminder.nextReminderMileage  = Int(col(row, 24))
                reminder.nextReminderDate     = parseDate(col(row, 25))
                reminder.vehicle = vehicle; vehicle.reminders.append(reminder)
                imported += 1
            default: continue
            }
        }

        for v in workingVehicles { v.lastModified = Date() }
        try? modelContext.save()
        restoreResultMessage = imported > 0 ? "Restored \(imported) record\(imported == 1 ? "" : "s") across \(workingVehicles.count) vehicle\(workingVehicles.count == 1 ? "" : "s")." : "No valid records found."
        showingRestoreResult = true
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
                        .chartYAxis {
                            AxisMarks(values: .automatic) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let d = value.as(Double.self) {
                                        Text("$\(d, specifier: "%.2f")")
                                    }
                                }
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
