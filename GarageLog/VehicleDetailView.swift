import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import Charts

struct CSVReport: Transferable {
    let name: String
    let content: String
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { report in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(report.name)
                .appendingPathExtension("csv")
            try (report.content.data(using: .utf8) ?? Data()).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

struct VehicleDetailView: View {
    @Bindable var vehicle: Vehicle
    @Environment(\.modelContext) private var modelContext
    @Query private var allVehicles: [Vehicle]
    
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("gasFillupEnabled") private var gasFillupEnabled: Bool = true
    @AppStorage("showFillupsInLog") private var showFillupsInLog: Bool = false
    @AppStorage("mpgGraphStyle") private var mpgGraphStyle: String = "line"
    @AppStorage("mpgAverageWindow") private var mpgAverageWindow: String = "6months"
    @AppStorage("mpgTrendWindow") private var mpgTrendWindow: Int = 2
    @AppStorage("fuelViewMode") private var fuelViewMode: String = "economy"
    @AppStorage("pdfIncludeCosts") private var pdfIncludeCosts: Bool = true

    @State private var showingAddLog = false
    @State private var showingAddFillup = false
    @State private var logToEdit: MaintenanceLog?
    @State private var fillupToEdit: GasFillup?
    @State private var logToPrepopulate: String?
    @State private var isEditingVehicle = false
    @AppStorage("schedulePreviewCount") private var schedulePreviewCount: Int = 3
    @AppStorage("scheduleSortOrder") private var scheduleSortOrder: String = "nextUp"
    @State private var showingAddReminder = false
    @State private var showingClearSchedule = false
    @State private var showingScheduleSettings = false
    @State private var showingRetireConfirm = false
    @State private var reminderToEdit: MaintenanceReminder?
    @State private var reminderToSetNext: MaintenanceReminder?
    @State private var showingFileImporter = false
    @State private var importResultMessage = ""
    @State private var showingImportResult = false
    @State private var pendingImportURL: URL?
    @State private var showingImportModeDialog = false
    
    // Editable vehicle state
    @State private var editName: String = ""
    @State private var editYear: Int = 0
    @State private var editMake: String = ""
    @State private var editModel: String = ""
    @State private var editLicensePlate: String = ""
    @State private var editVin: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var editImageData: Data?
    @State private var editGasFillupDisabled: Bool = false
    @State private var editMileageUnit: MileageUnit = .miles

    private enum EditField: Hashable { case name, make, model }
    @FocusState private var editFocus: EditField?
    @State private var editLicensePlateFocused = false
    @State private var editVinFocused = false

    private func dismissEditKeyboard() {
        editFocus = nil
        editLicensePlateFocused = false
        editVinFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    enum LogEntry: Identifiable {
        case maintenance(MaintenanceLog)
        case fillup(GasFillup)

        var id: String {
            switch self {
            case .maintenance(let log): return "m\(ObjectIdentifier(log).hashValue)"
            case .fillup(let f):        return "f\(ObjectIdentifier(f).hashValue)"
            }
        }
        var date: Date {
            switch self {
            case .maintenance(let log): return log.date
            case .fillup(let f):        return f.date
            }
        }
    }

    var sortedLogs: [MaintenanceLog] {
        vehicle.maintenanceLogs.sorted { $0.date > $1.date }
    }

    var sortedScheduleReminders: [MaintenanceReminder] {
        switch scheduleSortOrder {
        case "az":
            return vehicle.reminders.sorted { $0.title < $1.title }
        case "recentlyCompleted":
            return vehicle.reminders.sorted {
                ($0.lastCompletedDate ?? .distantPast) > ($1.lastCompletedDate ?? .distantPast)
            }
        case "intervalLength":
            return vehicle.reminders.sorted {
                reminderEffectiveInterval($0) < reminderEffectiveInterval($1)
            }
        default: // nextUp
            return vehicle.reminders.sorted {
                reminderMilesUntilDue($0, currentMileage: vehicle.currentMileage) <
                reminderMilesUntilDue($1, currentMileage: vehicle.currentMileage)
            }
        }
    }

    var fillupActiveForVehicle: Bool {
        gasFillupEnabled && !vehicle.gasFillupDisabled
    }

    var allLogEntries: [LogEntry] {
        var entries: [LogEntry] = vehicle.maintenanceLogs.map { .maintenance($0) }
        if fillupActiveForVehicle && showFillupsInLog {
            entries += vehicle.gasFillups.map { .fillup($0) }
        }
        return entries.sorted { $0.date > $1.date }
    }

    var displayedEntries: [LogEntry] {
        Array(allLogEntries.prefix(3))
    }
    
    private var mpgWindowCutoff: Date {
        let now = Date()
        switch mpgAverageWindow {
        case "3months":  return Calendar.current.date(byAdding: .month, value: -3,  to: now) ?? now
        case "12months": return Calendar.current.date(byAdding: .month, value: -12, to: now) ?? now
        case "lifetime":
            let earliest = vehicle.mpgDataPoints.min(by: { $0.date < $1.date })?.date
            return Calendar.current.date(byAdding: .day, value: -30, to: earliest ?? now) ?? now
        default:         return Calendar.current.date(byAdding: .month, value: -6,  to: now) ?? now
        }
    }

    private var mpgWindowLabel: String {
        switch mpgAverageWindow {
        case "3months":  return "3-Month"
        case "12months": return "12-Month"
        case "lifetime": return "Lifetime"
        default:         return "6-Month"
        }
    }

    private func cycleMPGWindow() {
        switch mpgAverageWindow {
        case "3months":  mpgAverageWindow = "6months"
        case "6months":  mpgAverageWindow = "12months"
        case "12months": mpgAverageWindow = "lifetime"
        default:         mpgAverageWindow = "3months"
        }
    }

    private var vehicleBackupCSV: CSVReport {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "M/d/yy"
        let content = garageCSVHeader() + vehicleCSVRows(vehicle, using: df)
        return CSVReport(name: "\(vehicle.displayName)_Backup", content: content)
    }

    var body: some View {
        List {
            Section {
                if isEditingVehicle {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        if let editImageData, let img = imageFromData(editImageData) {
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Label("Change Photo", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                    .onChange(of: selectedItem) { old, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                #if canImport(UIKit)
                                if let image = UIImage(data: data) {
                                    let cropped = image.cropTo16x9()
                                    editImageData = cropped.jpegData(compressionQuality: 0.8)
                                }
                                #else
                                editImageData = data
                                #endif
                            }
                        }
                    }

                    TextField("Nickname", text: $editName)
                        .focused($editFocus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { editFocus = .make }
                    Picker("Year", selection: $editYear) {
                        ForEach(Array(1900...2026).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    TextField("Make", text: $editMake)
                        .focused($editFocus, equals: .make)
                        .submitLabel(.next)
                        .onSubmit { editFocus = .model }
                    TextField("Model", text: $editModel)
                        .focused($editFocus, equals: .model)
                        .submitLabel(.next)
                        .onSubmit { editFocus = nil; editLicensePlateFocused = true }
                    #if os(iOS)
                    AllCapsTextField(placeholder: "License Plate", text: $editLicensePlate,
                                     isFocused: editLicensePlateFocused,
                                     returnKeyType: .next,
                                     onReturn: { editLicensePlateFocused = false; editVinFocused = true })
                    AllCapsTextField(placeholder: "VIN", text: $editVin,
                                     isFocused: editVinFocused,
                                     returnKeyType: .done,
                                     onReturn: { editVinFocused = false })
                    #else
                    TextField("License Plate", text: $editLicensePlate)
                        .autocorrectionDisabled()
                    TextField("VIN", text: $editVin)
                        .autocorrectionDisabled()
                    #endif

                    if gasFillupEnabled {
                        Toggle("Track Gas Fill-ups", isOn: Binding(get: { !editGasFillupDisabled }, set: { editGasFillupDisabled = !$0 }))
                    }

                    Picker("Mileage Unit", selection: $editMileageUnit) {
                        Text("Miles (Odometer)").tag(MileageUnit.miles)
                        Text("Hours (Hour Meter)").tag(MileageUnit.hours)
                        Text("None (Time-Only)").tag(MileageUnit.none)
                    }

                    Button("Save Changes") {
                        saveVehicleChanges()
                        isEditingVehicle = false
                    }
                    .font(.headline)
                } else {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(String(vehicle.year)) \(vehicle.make) \(vehicle.model)")
                                .font(.headline)
                            if !vehicle.licensePlate.isEmpty {
                                Text("Plate: \(vehicle.licensePlate)").font(.caption)
                            }
                        }
                        Spacer()
                        Button("Edit") {
                            startEditing()
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Text("Vehicle Info")
            }
            
            if vehicle.mileageUnit.tracksMileage {
                Section {
                    OdometerView(mileage: $vehicle.currentMileage,
                                 accentColor: Color.fromName(accentColorName),
                                 unitLabel: vehicle.mileageUnit.label)
                        .listRowBackground(Color.clear)
                }
            }

            if fillupActiveForVehicle {
                Section {
                    Picker("", selection: $fuelViewMode) {
                        Text("Fuel Economy").tag("economy")
                        Text("Fuel Spending").tag("spending")
                    }
                    .pickerStyle(.segmented)

                    let now = Date()
                    let cutoff = mpgWindowCutoff
                    let accentColor = Color.fromName(accentColorName)

                    if fuelViewMode == "economy" {
                        let allDataPoints = vehicle.mpgDataPoints
                        if allDataPoints.isEmpty {
                            Text("Add consecutive gas fill-ups to see your fuel economy here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            let filteredPoints = allDataPoints.filter { $0.date >= cutoff }
                            if filteredPoints.isEmpty {
                                Text("No fill-ups in this window — tap to expand.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                                    .onTapGesture { cycleMPGWindow() }
                            } else {
                                if mpgGraphStyle == "bar" {
                                    Chart(filteredPoints) { point in
                                        BarMark(x: .value("Date", point.date, unit: .day),
                                                y: .value("MPG", point.mpg))
                                            .foregroundStyle(accentColor)
                                    }
                                    .chartXScale(domain: cutoff...now)
                                    .frame(height: 180)
                                    .chartXAxis {
                                        AxisMarks(values: .automatic) { _ in
                                            AxisGridLine()
                                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                        }
                                    }
                                    .onTapGesture { cycleMPGWindow() }
                                } else {
                                    Chart(filteredPoints) { point in
                                        LineMark(x: .value("Date", point.date),
                                                 y: .value("MPG", point.mpg))
                                            .foregroundStyle(accentColor)
                                        PointMark(x: .value("Date", point.date),
                                                  y: .value("MPG", point.mpg))
                                            .foregroundStyle(accentColor)
                                    }
                                    .chartXScale(domain: cutoff...now)
                                    .frame(height: 180)
                                    .chartXAxis {
                                        AxisMarks(values: .automatic) { _ in
                                            AxisGridLine()
                                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                        }
                                    }
                                    .onTapGesture { cycleMPGWindow() }
                                }

                                if let avg = vehicle.averageMPG(window: mpgAverageWindow) {
                                    HStack(spacing: 0) {
                                        Text("\(mpgWindowLabel) Average:")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(accentColor)
                                        Text(" ")
                                            .font(.system(.subheadline, design: .monospaced))
                                        HStack(spacing: 0) {
                                            Text(String(format: "%.1f mpg", avg))
                                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                                .foregroundStyle(.black)
                                            Text(" ")
                                                .font(.system(.subheadline, design: .monospaced))
                                            let trend = vehicle.mpgTrend(window: mpgTrendWindow)
                                            Image(systemName: trend == false ? "arrowtriangle.down.circle.fill" : trend == true ? "arrowtriangle.up.circle.fill" : "minus.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(.white.opacity(trend == nil ? 0.35 : 1.0))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(accentColor.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                    } else {
                        let allFillups = vehicle.gasFillups.sorted { $0.date < $1.date }
                        if allFillups.isEmpty {
                            Text("Add gas fill-ups to track your fuel spending here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            let filteredFillups = allFillups.filter { $0.date >= cutoff }
                            if filteredFillups.isEmpty {
                                Text("No fill-ups in this window — tap to expand.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                                    .onTapGesture { cycleMPGWindow() }
                            } else {
                                Chart(filteredFillups) { fillup in
                                    LineMark(x: .value("Date", fillup.date),
                                             y: .value("Total Cost ($)", fillup.totalCost))
                                        .foregroundStyle(accentColor)
                                    PointMark(x: .value("Date", fillup.date),
                                              y: .value("Total Cost ($)", fillup.totalCost))
                                        .foregroundStyle(accentColor)
                                }
                                .chartXScale(domain: cutoff...now)
                                .frame(height: 180)
                                .chartXAxis {
                                    AxisMarks(values: .automatic) { _ in
                                        AxisGridLine()
                                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                    }
                                }
                                .onTapGesture { cycleMPGWindow() }

                                let totalSpent = filteredFillups.reduce(0.0) { $0 + $1.totalCost }
                                HStack(spacing: 0) {
                                    Text("\(mpgWindowLabel) Total:")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(accentColor)
                                    Text(" ")
                                        .font(.system(.subheadline, design: .monospaced))
                                    HStack(spacing: 0) {
                                        Text(totalSpent, format: .currency(code: "USD"))
                                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                            .foregroundStyle(.black)
                                        Text(" ")
                                            .font(.system(.subheadline, design: .monospaced))
                                        let spendTrend = vehicle.spendingTrend(window: mpgTrendWindow)
                                        Image(systemName: spendTrend == false ? "arrowtriangle.down.circle.fill" : spendTrend == true ? "arrowtriangle.up.circle.fill" : "minus.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.white.opacity(spendTrend == nil ? 0.35 : 1.0))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(accentColor.opacity(0.85))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                } header: {
                    Text("Fuel")
                }
            }

            Section("Maintenance Schedule") {
                if !allVehicles.isEmpty {
                    HStack {
                        Spacer()
                        Menu {
                            Button {
                                showingAddReminder = true
                            } label: {
                                Label("Add New Reminder", systemImage: "plus")
                            }

                            Button {
                                showingScheduleSettings = true
                            } label: {
                                Label("Edit View...", systemImage: "slider.horizontal.3")
                            }

                            if allVehicles.count > 1 {
                                Menu("Import Schedule from...") {
                                    ForEach(allVehicles.filter { $0.id != vehicle.id && !$0.isRetired }) { other in
                                        Button(other.displayName) {
                                            importReminders(from: other)
                                        }
                                    }
                                }
                            }

                            if !vehicle.reminders.isEmpty {
                                Divider()
                                Button(role: .destructive) {
                                    showingClearSchedule = true
                                } label: {
                                    Label("Clear Schedule...", systemImage: "trash")
                                }
                            }
                        } label: {
                            Label("Add / Import", systemImage: "ellipsis.circle")
                                .font(.caption)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 16))
                }

                if vehicle.reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            showingAddReminder = true
                        } label: {
                            Label("Add first reminder...", systemImage: "plus.circle")
                        }
                        
                        let otherVehicles = allVehicles.filter { $0.id != vehicle.id && !$0.isRetired && !$0.reminders.isEmpty }
                        if !otherVehicles.isEmpty {
                            Menu {
                                ForEach(otherVehicles) { other in
                                    Button("Import from \(other.displayName)") {
                                        importReminders(from: other)
                                    }
                                }
                            } label: {
                                Label("Import from another vehicle...", systemImage: "square.and.arrow.down")
                                    .font(.caption)
                            }
                        }
                    }
                } else {
                    let displayedReminders = Array(sortedScheduleReminders.prefix(schedulePreviewCount))
                    ForEach(displayedReminders) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            currentMileage: vehicle.currentMileage,
                            unitLabel: vehicle.mileageUnit.label,
                            onComplete: {
                                logToPrepopulate = reminder.title
                                showingAddLog = true
                                reminder.lastCompletedDate = Date()
                                reminder.lastCompletedMileage = vehicle.currentMileage
                                reminder.nextReminderMileage = nil
                                reminder.nextReminderDate = nil
                            },
                            onEdit: {
                                reminderToEdit = reminder
                            },
                            onDelete: {
                                modelContext.delete(reminder)
                                refreshNotifications()
                            }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(reminder)
                                refreshNotifications()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                reminderToEdit = reminder
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                reminderToSetNext = reminder
                            } label: {
                                Label("Set Next", systemImage: "pin")
                            }
                            .tint(.blue)
                        }
                    }

                    if vehicle.reminders.count > schedulePreviewCount {
                        NavigationLink {
                            AllRemindersView(vehicle: vehicle)
                        } label: {
                            Text("See all (\(vehicle.reminders.count))")
                                .font(.caption)
                        }
                    }

                    Button {
                        showingAddReminder = true
                    } label: {
                        Label("Add Reminder", systemImage: "plus.circle")
                    }
                    .font(.caption)
                }
            }
            
            Section {
                if allLogEntries.isEmpty {
                    Text("No maintenance logs yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedEntries) { entry in
                        switch entry {
                        case .maintenance(let log):
                            MaintenanceLogRow(log: log)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            modelContext.delete(log)
                                            vehicle.lastModified = Date()
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        logToEdit = log
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                        case .fillup(let fillup):
                            GasFillupRow(fillup: fillup)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            modelContext.delete(fillup)
                                            vehicle.lastModified = Date()
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        fillupToEdit = fillup
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }

                    if allLogEntries.count > 3 {
                        NavigationLink {
                            AllLogsView(vehicle: vehicle)
                        } label: {
                            Text("See all (\(allLogEntries.count))")
                                .font(.caption)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Maintenance Logs")
                    Spacer()
                    if fillupActiveForVehicle && !vehicle.gasFillups.isEmpty {
                        Button {
                            withAnimation { showFillupsInLog.toggle() }
                        } label: {
                            Image(systemName: showFillupsInLog ? "fuelpump.fill" : "fuelpump")
                                .font(.caption)
                        }
                        .padding(.trailing, 4)
                    }
                    if fillupActiveForVehicle {
                        Menu {
                            Button {
                                logToPrepopulate = nil
                                showingAddLog = true
                            } label: {
                                Label("Add Maintenance Log", systemImage: "wrench.and.screwdriver")
                            }
                            Button {
                                showingAddFillup = true
                            } label: {
                                Label("Add Gas Fill-up", systemImage: "fuelpump")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    } else {
                        Button {
                            logToPrepopulate = nil
                            showingAddLog = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            
            Section {
                Menu {
                    ShareLink(item: vehicleBackupCSV, preview: SharePreview("\(vehicle.displayName) Backup.csv", image: Image(systemName: "tablecells"))) {
                        Label("Export Vehicle Backup", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Import Vehicle Backup", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Import / Export", systemImage: "arrow.up.arrow.down")
                }
                #if os(iOS)
                Menu {
                    Section {
                        if let pdfData = generateVehiclePDF(vehicle: vehicle, includeSchedule: true, includeLog: false, includeCosts: pdfIncludeCosts) {
                            ShareLink(item: pdfData, preview: SharePreview("\(vehicle.displayName) Schedule.pdf", image: Image(systemName: "doc.richtext"))) {
                                Label("Maintenance Schedule", systemImage: "calendar")
                            }
                        }
                        if let pdfData = generateVehiclePDF(vehicle: vehicle, includeSchedule: false, includeLog: true, includeCosts: pdfIncludeCosts) {
                            ShareLink(item: pdfData, preview: SharePreview("\(vehicle.displayName) Log.pdf", image: Image(systemName: "doc.richtext"))) {
                                Label("Maintenance Log", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        if let pdfData = generateVehiclePDF(vehicle: vehicle, includeSchedule: true, includeLog: true, includeCosts: pdfIncludeCosts) {
                            ShareLink(item: pdfData, preview: SharePreview("\(vehicle.displayName) Full Report.pdf", image: Image(systemName: "doc.richtext"))) {
                                Label("Both (Full Report)", systemImage: "doc.text.below.ecg")
                            }
                        }
                    }
                    Section {
                        Toggle("Include Costs", isOn: $pdfIncludeCosts)
                    }
                } label: {
                    Label("Export PDF Report", systemImage: "doc.richtext")
                }
                #endif
            } header: {
                Text("Data")
            }

            Section {
                if vehicle.isRetired {
                    Button {
                        vehicle.isRetired = false
                        refreshNotifications()
                        try? modelContext.save()
                    } label: {
                        Label("Restore to Garage", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        showingRetireConfirm = true
                    } label: {
                        Label("Retire Vehicle", systemImage: "archivebox")
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .confirmationDialog(
            "Retire \(vehicle.displayName)?",
            isPresented: $showingRetireConfirm,
            titleVisibility: .visible
        ) {
            Button("Retire", role: .destructive) {
                vehicle.isRetired = true
                NotificationManager.shared.refresh(vehicleName: vehicle.displayName, currentMileage: vehicle.currentMileage, reminders: [])
                try? modelContext.save()
            }
        } message: {
            Text("This hides it from your garage and cancels its reminders. All its history stays intact — find it anytime in Settings → Retired Vehicles.")
        }
        .navigationTitle(vehicle.displayName)
        .sheet(isPresented: $showingAddLog) {
            AddMaintenanceLogView(vehicle: vehicle, initialServiceType: logToPrepopulate)
        }
        .sheet(isPresented: $showingAddFillup) {
            AddGasFillupView(vehicles: [vehicle])
        }
        .sheet(item: $logToEdit) { log in
            AddMaintenanceLogView(vehicle: vehicle, editingLog: log)
        }
        .sheet(item: $fillupToEdit) { fillup in
            AddGasFillupView(vehicles: [vehicle], editingFillup: fillup)
        }
        .sheet(isPresented: $showingAddReminder, onDismiss: refreshNotifications) {
            AddReminderView(vehicle: vehicle)
        }
        .sheet(item: $reminderToEdit, onDismiss: refreshNotifications) { reminder in
            AddReminderView(vehicle: vehicle, editingReminder: reminder)
        }
        .sheet(item: $reminderToSetNext, onDismiss: refreshNotifications) { reminder in
            SetNextReminderSheet(reminder: reminder, currentMileage: vehicle.currentMileage, unitLabel: vehicle.mileageUnit.label)
        }
        .sheet(isPresented: $showingClearSchedule) {
            ClearScheduleSheet {
                for reminder in vehicle.reminders { modelContext.delete(reminder) }
                vehicle.reminders.removeAll()
                refreshNotifications()
            }
        }
        .sheet(isPresented: $showingScheduleSettings) {
            ScheduleViewSettingsSheet()
        }
        .toolbar {
            ToolbarItem(placement: {
                #if os(iOS)
                return ToolbarItemPlacement.topBarTrailing
                #else
                return ToolbarItemPlacement.primaryAction
                #endif
            }()) {
                NavigationLink {
                    VehicleStatsView(vehicle: vehicle)
                } label: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    switch editFocus {
                    case .make:  editFocus = .name
                    case .model: editFocus = .make
                    default:     break
                    }
                } label: { Image(systemName: "chevron.up") }
                    .disabled(editFocus == .name || editFocus == nil)
                Button {
                    switch editFocus {
                    case .name:  editFocus = .make
                    case .make:  editFocus = .model
                    case .model: editFocus = nil; editLicensePlateFocused = true
                    case nil:    break
                    }
                } label: { Image(systemName: "chevron.down") }
                    .disabled(editFocus == nil)
                Spacer()
                Button("Done") { dismissEditKeyboard() }
            }
            #endif
        }
        .onChange(of: vehicle.currentMileage) { _, _ in refreshNotifications() }
        .tint(Color.fromName(accentColorName))
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText]
        ) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                showingImportModeDialog = true
            case .failure:
                importResultMessage = "Could not open file."
                showingImportResult = true
            }
        }
        .confirmationDialog("Import Mode", isPresented: $showingImportModeDialog, titleVisibility: .visible) {
            Button("Merge — Skip Duplicates") {
                if let url = pendingImportURL { importVehicleCSV(from: url, mode: .merge) }
            }
            Button("Fresh Restore — Replace All Data", role: .destructive) {
                if let url = pendingImportURL { importVehicleCSV(from: url, mode: .fresh) }
            }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text("How would you like to import this file?")
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importResultMessage)
        }
    }
    
    private func refreshNotifications() {
        let data = vehicle.reminders.map { r in
            ReminderNotifData(
                vehicleName: vehicle.displayName,
                title: r.title,
                intervalType: r.intervalType,
                mileageInterval: r.mileageInterval,
                lastCompletedMileage: r.lastCompletedMileage,
                currentMileage: vehicle.currentMileage,
                timeFrequency: r.timeFrequency,
                monthInterval: r.monthInterval,
                nextReminderMileage: r.nextReminderMileage,
                nextReminderDate: r.nextReminderDate
            )
        }
        NotificationManager.shared.refresh(vehicleName: vehicle.displayName, currentMileage: vehicle.currentMileage, reminders: data)
    }

    private func importReminders(from other: Vehicle) {
        for reminder in other.reminders {
            let newReminder = reminder.copy()
            newReminder.vehicle = vehicle
            vehicle.reminders.append(newReminder)
        }
    }
    
    private func startEditing() {
        editName = vehicle.name
        editYear = vehicle.year
        editMake = vehicle.make
        editModel = vehicle.model
        editLicensePlate = vehicle.licensePlate
        editVin = vehicle.vin
        editImageData = vehicle.imageData
        editGasFillupDisabled = vehicle.gasFillupDisabled
        editMileageUnit = vehicle.mileageUnit
        isEditingVehicle = true
    }

    private func saveVehicleChanges() {
        vehicle.name = editName
        vehicle.year = editYear
        vehicle.make = editMake
        vehicle.model = editModel
        vehicle.licensePlate = editLicensePlate.uppercased()
        vehicle.vin = editVin.uppercased()
        vehicle.imageData = editImageData
        vehicle.gasFillupDisabled = editGasFillupDisabled
        vehicle.mileageUnit = editMileageUnit
        vehicle.lastModified = Date()
    }

    private func importVehicleCSV(from url: URL, mode: ImportMode) {
        guard url.startAccessingSecurityScopedResource() else {
            importResultMessage = "Permission denied for file."
            showingImportResult = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            importResultMessage = "Could not read file."
            showingImportResult = true
            return
        }
        let rows = parseCSV(content)
        guard rows.count > 1 else {
            importResultMessage = "No records found in file."
            showingImportResult = true
            return
        }
        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

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

        if mode == .fresh {
            vehicle.maintenanceLogs.forEach { modelContext.delete($0) }
            vehicle.gasFillups.forEach { modelContext.delete($0) }
            vehicle.reminders.forEach { modelContext.delete($0) }
            vehicle.maintenanceLogs = []
            vehicle.gasFillups = []
            vehicle.reminders = []
        }

        var imported = 0

        if headers.first == "recordtype" {
            // Universal format
            for row in rows.dropFirst() {
                switch col(row, 0).lowercased() {
                case "log":
                    guard let date = parseDate(col(row, 9)) else { continue }
                    let svc = col(row, 10); guard !svc.isEmpty else { continue }
                    let mileage = Int(col(row, 11)) ?? 0
                    if mode == .merge {
                        let cal = Calendar.current
                        let dup = vehicle.maintenanceLogs.contains {
                            cal.isDate($0.date, inSameDayAs: date) && $0.serviceType == svc && $0.mileage == mileage
                        }
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
                        let cal = Calendar.current
                        let dup = vehicle.gasFillups.contains {
                            cal.isDate($0.date, inSameDayAs: date) && $0.mileage == mileage
                        }
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
        } else if headers.contains("date") && (headers.contains("type") || headers.contains("service type")) {
            // Old logs format
            guard let dateIdx = headers.firstIndex(of: "date"),
                  let typeIdx = headers.first(where: { $0 == "type" || $0 == "service type" }).flatMap({ headers.firstIndex(of: $0) }),
                  let mileageIdx = headers.firstIndex(of: "mileage") else {
                importResultMessage = "Unrecognized format."; showingImportResult = true; return
            }
            let gallonsIdx = headers.firstIndex(of: "gallons")
            let partsIdx   = headers.firstIndex(of: "parts cost")
            let laborIdx   = headers.firstIndex(of: "labor cost")
            let totalIdx   = headers.firstIndex(of: "total cost")
            let notesIdx   = headers.firstIndex(of: "notes")
            let cal = Calendar.current
            for row in rows.dropFirst() {
                guard let date = parseDate(col(row, dateIdx)) else { continue }
                let mileage = Int(col(row, mileageIdx)) ?? 0
                let type = col(row, typeIdx)
                if type.lowercased() == "gas fill-up" {
                    if mode == .merge {
                        let dup = vehicle.gasFillups.contains { cal.isDate($0.date, inSameDayAs: date) && $0.mileage == mileage }
                        if dup { continue }
                    }
                    let fillup = GasFillup(date: date, mileage: mileage,
                        gallons: Double(col(row, gallonsIdx)) ?? 0,
                        totalCost: Double(col(row, totalIdx)) ?? 0, skippedPrevious: false)
                    fillup.vehicle = vehicle; vehicle.gasFillups.append(fillup)
                } else {
                    if mode == .merge {
                        let dup = vehicle.maintenanceLogs.contains { cal.isDate($0.date, inSameDayAs: date) && $0.serviceType == type && $0.mileage == mileage }
                        if dup { continue }
                    }
                    let log = MaintenanceLog(date: date, mileage: mileage,
                        serviceType: type.isEmpty ? "Other" : type,
                        notes: col(row, notesIdx),
                        partsCost: Double(col(row, partsIdx)) ?? 0,
                        laborCost: Double(col(row, laborIdx)) ?? 0)
                    log.vehicle = vehicle; vehicle.maintenanceLogs.append(log)
                }
                if mileage > vehicle.currentMileage { vehicle.currentMileage = mileage }
                imported += 1
            }
        } else if headers.contains("title") && headers.contains("interval type") {
            // Old schedule format
            guard let titleIdx = headers.firstIndex(of: "title"),
                  let itypeIdx = headers.firstIndex(of: "interval type") else {
                importResultMessage = "Unrecognized format."; showingImportResult = true; return
            }
            let freqIdx   = headers.firstIndex(of: "frequency")
            let miIdx     = headers.firstIndex(of: "mileage interval")
            let moIdx     = headers.firstIndex(of: "month interval")
            let notesIdx  = headers.firstIndex(of: "notes")
            for row in rows.dropFirst() {
                let title = col(row, titleIdx); guard !title.isEmpty else { continue }
                if mode == .merge {
                    let dup = vehicle.reminders.contains { $0.title.lowercased() == title.lowercased() }
                    if dup { continue }
                }
                let itype = ReminderIntervalType(rawValue: col(row, itypeIdx)) ?? .mileage
                let mi: Int? = { let v = Int(col(row, miIdx)) ?? 0; return v > 0 ? v : nil }()
                let mo: Int? = { let v = Int(col(row, moIdx)) ?? 0; return v > 0 ? v : nil }()
                let n = col(row, notesIdx)
                let reminder = MaintenanceReminder(title: title, intervalType: itype,
                    timeFrequency: itype == .time ? TimeFrequency(rawValue: col(row, freqIdx)) : nil,
                    mileageInterval: itype == .mileage ? mi : nil,
                    monthInterval: itype == .time ? mo : nil,
                    notes: n.isEmpty ? "• " : n)
                reminder.vehicle = vehicle; vehicle.reminders.append(reminder)
                imported += 1
            }
        } else {
            importResultMessage = "Unrecognized file format."
            showingImportResult = true
            return
        }

        vehicle.lastModified = Date()
        importResultMessage = imported > 0 ? "Imported \(imported) record\(imported == 1 ? "" : "s")." : "No valid records found."
        showingImportResult = true
    }

}

struct ReminderRow: View {
    let reminder: MaintenanceReminder
    let currentMileage: Int
    var unitLabel: String = "mi"
    var onComplete: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    
    @State private var showingQuickView = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(reminder.title)
                    .font(.headline)
                
                if reminder.intervalType == .mileage, let interval = reminder.mileageInterval {
                    let isPinned = reminder.nextReminderMileage != nil
                    let nextDue = reminder.nextReminderMileage ?? ((reminder.lastCompletedMileage ?? 0) + interval)
                    let remaining = nextDue - currentMileage

                    HStack {
                        Text("Every \(interval) \(unitLabel)")
                        Text("•")
                        if isPinned { Image(systemName: "pin.fill").font(.caption2) }
                        if remaining <= 0 {
                            Text("OVERDUE").foregroundStyle(.red).bold()
                        } else if isPinned {
                            Text("Due at \(nextDue) \(unitLabel)").foregroundStyle(.secondary)
                        } else {
                            Text("\(remaining) \(unitLabel) left").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                } else if reminder.intervalType == .time, let freq = reminder.timeFrequency {
                    let detail: String = {
                        let monthIdx = max(1, min(12, reminder.monthInterval ?? 1)) - 1
                        switch freq {
                        case .annual:
                            return "Every \(Calendar.current.monthSymbols[monthIdx])"
                        case .quarterly:
                            return "Quarterly (Starts \(Calendar.current.monthSymbols[monthIdx]))"
                        case .monthly:
                            return "Every Month"
                        }
                    }()
                    if let nextDate = reminder.nextReminderDate {
                        HStack {
                            Text(detail)
                            Text("•")
                            Image(systemName: "pin.fill").font(.caption2)
                            Text(nextDate, format: .dateTime.month(.abbreviated).day().year())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                onComplete()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            showingQuickView = true
        })
        .popover(isPresented: $showingQuickView) {
            VStack(alignment: .leading, spacing: 12) {
                Text(reminder.title)
                    .font(.headline)
                Divider()
                Text(reminder.notes)
                    .font(.body)
                Spacer()
            }
            .padding()
            .presentationDetents([.medium, .large])
        }
    }
}

struct AddReminderView: View {
    let vehicle: Vehicle
    var editingReminder: MaintenanceReminder?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = "Oil Change"
    @State private var intervalType: ReminderIntervalType = .mileage
    @State private var timeFrequency: TimeFrequency = .annual
    @State private var mileageInterval = 5000
    @State private var selectedMonth = 10
    @State private var notes = "• "
    
    let commonTitles = ["Oil Change", "Tire Rotation", "Air Filter", "Cabin Filter", "Snow Tires", "Spark Plugs"]
    
    init(vehicle: Vehicle, editingReminder: MaintenanceReminder? = nil) {
        self.vehicle = vehicle
        self.editingReminder = editingReminder

        if let editing = editingReminder {
            _title = State(initialValue: editing.title)
            _intervalType = State(initialValue: editing.intervalType)
            _timeFrequency = State(initialValue: editing.timeFrequency ?? .annual)
            _mileageInterval = State(initialValue: editing.mileageInterval ?? 5000)
            _selectedMonth = State(initialValue: editing.monthInterval ?? 1)
            _notes = State(initialValue: editing.notes)
        } else if vehicle.mileageUnit == .none {
            _intervalType = State(initialValue: .time)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("What to track?") {
                    Picker("Service", selection: $title) {
                        ForEach(commonTitles, id: \.self) { title in
                            Text(title).tag(title)
                        }
                        Text("Other").tag("Other")
                    }
                    if !commonTitles.contains(title) && title != "Other" {
                        TextField("Reminder Name", text: $title)
                    } else if title == "Other" {
                        TextField("Reminder Name", text: $title)
                    }
                }
                
                if vehicle.mileageUnit.tracksMileage {
                    Section("Interval Type") {
                        Picker("Type", selection: $intervalType) {
                            Text(vehicle.mileageUnit == .hours ? "Hours" : "Mileage").tag(ReminderIntervalType.mileage)
                            Text("Time").tag(ReminderIntervalType.time)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if intervalType == .mileage && vehicle.mileageUnit.tracksMileage {
                    let unitLabel = vehicle.mileageUnit.label
                    Section(vehicle.mileageUnit == .hours ? "Hour Interval" : "Mileage Interval") {
                        HStack {
                            Text("\(mileageInterval) \(unitLabel)")
                            Spacer()
                            Stepper("", value: $mileageInterval, in: 2500...100000, step: 2500)
                        }
                        Slider(value: Binding(get: { Double(mileageInterval) }, set: { mileageInterval = Int($0) }), in: 2500...100000, step: 2500)
                    }
                }
 else {
                    Section("Frequency") {
                        Picker("Frequency", selection: $timeFrequency) {
                            ForEach(TimeFrequency.allCases, id: \.self) { freq in
                                Text(freq.rawValue).tag(freq)
                            }
                        }
                        
                        if timeFrequency == .annual || timeFrequency == .quarterly {
                            Picker(timeFrequency == .annual ? "Month" : "Start Month", selection: $selectedMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                                }
                            }
                        }
                    }
                }

                Section("Reference Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .onChange(of: notes) { old, newValue in
                            if newValue.hasSuffix("\n") {
                                notes.append("• ")
                            }
                        }
                }
            }
            .navigationTitle(editingReminder == nil ? "New Reminder" : "Edit Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let editing = editingReminder {
                            editing.title = title
                            editing.intervalType = intervalType
                            editing.timeFrequency = timeFrequency
                            editing.mileageInterval = intervalType == .mileage ? mileageInterval : nil
                            editing.monthInterval = intervalType == .time ? selectedMonth : nil
                            editing.notes = notes
                        } else {
                            let reminder = MaintenanceReminder(title: title, intervalType: intervalType, timeFrequency: timeFrequency, mileageInterval: intervalType == .mileage ? mileageInterval : nil, monthInterval: intervalType == .time ? selectedMonth : nil, notes: notes)
                            reminder.vehicle = vehicle
                            vehicle.reminders.append(reminder)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MaintenanceLogRow: View {
    let log: MaintenanceLog
    @State private var showingReceipt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.serviceType)
                    .font(.headline)
                Spacer()
                if log.receiptPhotoData != nil {
                    Image(systemName: "doc.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture { showingReceipt = true }
                }
                Text(log.totalCost, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(log.date, format: .dateTime.month().day().year())
                Text("•")
                Text("\(log.mileage) miles")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if log.partsCost > 0 || log.laborCost > 0 {
                HStack {
                    if log.partsCost > 0 {
                        Text("Parts: \(log.partsCost, format: .currency(code: "USD"))")
                    }
                    if log.laborCost > 0 {
                        Text("Labor: \(log.laborCost, format: .currency(code: "USD"))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !log.notes.isEmpty && log.notes != "• " {
                Text(log.notes)
                    .font(.caption)
                    .padding(.top, 2)
            }
        }
        .sheet(isPresented: $showingReceipt) {
            if let data = log.receiptPhotoData, let img = imageFromData(data) {
                NavigationStack {
                    ScrollView {
                        img
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    .navigationTitle("Receipt")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingReceipt = false }
                        }
                    }
                }
            }
        }
    }
}

struct AddMaintenanceLogView: View {
    let vehicle: Vehicle
    var initialServiceType: String?
    var editingLog: MaintenanceLog?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var mileage: Int
    @State private var serviceType: String
    @State private var customServiceType = ""
    @State private var notes = "• "
    @State private var partsCost = 0.0
    @State private var laborCost = 0.0
    @State private var isDIY = true

    @FocusState private var isManualMileageFocused: Bool
    @State private var mileageString: String
    @State private var receiptItem: PhotosPickerItem?
    @State private var receiptImageData: Data?

    let serviceCategories = [
        "Oil Change", "Tire Rotation", "Brake Service", "Battery Replacement",
        "Air Filter", "Cabin Filter", "Spark Plugs", "Coolant Flush",
        "Transmission Fluid", "Alignment", "Suspension", "Belts/Hoses",
        "Inspection", "Detailing", "Other"
    ]

    init(vehicle: Vehicle, initialServiceType: String? = nil, editingLog: MaintenanceLog? = nil) {
        self.vehicle = vehicle
        self.initialServiceType = initialServiceType
        self.editingLog = editingLog

        let categories = [
            "Oil Change", "Tire Rotation", "Brake Service", "Battery Replacement",
            "Air Filter", "Cabin Filter", "Spark Plugs", "Coolant Flush",
            "Transmission Fluid", "Alignment", "Suspension", "Belts/Hoses",
            "Inspection", "Detailing", "Other"
        ]

        let initialMileage: Int
        if let log = editingLog {
            initialMileage = log.mileage
            _date = State(initialValue: log.date)
            _mileage = State(initialValue: log.mileage)
            _notes = State(initialValue: log.notes)
            _partsCost = State(initialValue: log.partsCost)
            _laborCost = State(initialValue: log.laborCost)
            _isDIY = State(initialValue: log.laborCost == 0)
            _receiptImageData = State(initialValue: log.receiptPhotoData)
            if categories.contains(log.serviceType) {
                _serviceType = State(initialValue: log.serviceType)
            } else {
                _serviceType = State(initialValue: "Other")
                _customServiceType = State(initialValue: log.serviceType)
            }
        } else {
            initialMileage = (vehicle.currentMileage / 100) * 100
            _mileage = State(initialValue: initialMileage)
            if let prepop = initialServiceType {
                if categories.contains(prepop) {
                    _serviceType = State(initialValue: prepop)
                } else {
                    _serviceType = State(initialValue: "Other")
                    _customServiceType = State(initialValue: prepop)
                }
            } else {
                _serviceType = State(initialValue: "Oil Change")
            }
        }
        _mileageString = State(initialValue: formatMileage("\(initialMileage)"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service Info") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    
                    Picker("Service Type", selection: $serviceType) {
                        ForEach(serviceCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    
                    if serviceType == "Other" {
                        TextField("Specify Service", text: $customServiceType)
                    }
                    
                    if vehicle.mileageUnit.tracksMileage { VStack(alignment: .leading) {
                        HStack {
                            Text(vehicle.mileageUnit == .hours ? "Hours" : "Mileage")
                            Spacer()
                            TextField("Manual Entry", text: $mileageString)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .focused($isManualMileageFocused)
                                .onChange(of: mileageString) { _, val in
                                    mileageString = formatMileage(val)
                                    if let n = Int(val.filter { $0.isNumber }) { mileage = n }
                                }
                        }

                        Picker("Mileage Picker", selection: $mileage) {
                            let start = max(0, (mileage / 25) * 25 - 500)
                            let end = (mileage / 25) * 25 + 5000
                            ForEach(stride(from: start, through: end, by: 25).map { $0 }, id: \.self) { val in
                                Text("\(val)").tag(val)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        .frame(height: 100)
                        #else
                        .pickerStyle(.menu)
                        #endif
                        .onChange(of: mileage) { _, val in
                            let f = formatMileage("\(val)")
                            if mileageString != f { mileageString = f }
                        }
                    } }  // closes VStack + if vehicle.mileageUnit.tracksMileage
                }

                Section("Costs") {
                    HStack {
                        Text("Cost of Parts")
                        Spacer()
                        CurrencyTextField(value: $partsCost)
                    }

                    VStack {
                        HStack {
                            Text("Cost of Labor")
                            Spacer()
                            CurrencyTextField(value: $laborCost, isDisabled: isDIY)
                        }
                        
                        Toggle(isOn: $isDIY) {
                            Text("DIY")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .onChange(of: isDIY) { old, newValue in
                            if newValue { laborCost = 0.0 }
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .onChange(of: notes) { old, newValue in
                            if newValue.hasSuffix("\n") {
                                notes.append("• ")
                            }
                        }
                }

                Section("Receipt Photo") {
                    PhotosPicker(selection: $receiptItem, matching: .images) {
                        if let data = receiptImageData, let img = imageFromData(data) {
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Label("Add Receipt Photo", systemImage: "doc.viewfinder")
                        }
                    }
                    .onChange(of: receiptItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                receiptImageData = data
                            }
                        }
                    }
                    if receiptImageData != nil {
                        Button(role: .destructive) {
                            receiptImageData = nil
                            receiptItem = nil
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editingLog == nil ? "Add Log" : "Edit Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isManualMileageFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let finalType = serviceType == "Other" ? customServiceType : serviceType
                        if let log = editingLog {
                            log.date = date
                            log.mileage = mileage
                            log.serviceType = finalType
                            log.notes = notes
                            log.partsCost = partsCost
                            log.laborCost = laborCost
                            log.receiptPhotoData = receiptImageData
                            vehicle.lastModified = Date()
                        } else {
                            let newLog = MaintenanceLog(date: date, mileage: mileage, serviceType: finalType, notes: notes, partsCost: partsCost, laborCost: laborCost)
                            newLog.receiptPhotoData = receiptImageData
                            newLog.vehicle = vehicle
                            vehicle.maintenanceLogs.append(newLog)
                            vehicle.lastModified = Date()
                        }
                        if mileage > vehicle.currentMileage { vehicle.currentMileage = mileage }
                        dismiss()
                    }
                    .disabled(serviceType == "Other" && customServiceType.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }
}

struct OdometerView: View {
    @Binding var mileage: Int
    let accentColor: Color
    var unitLabel: String = "mi"
    @State private var isEditing = false
    @State private var tempMileageString: String = ""

    private var headerLabel: String { unitLabel == "hr" ? "HOUR METER" : "ODOMETER" }
    private var alertTitle: String { unitLabel == "hr" ? "Update Hour Meter" : "Update Odometer" }
    private var alertPrompt: String { unitLabel == "hr" ? "Enter current hours." : "Enter the current mileage for your vehicle." }
    private var alertPlaceholder: String { unitLabel == "hr" ? "Current Hours" : "Current Mileage" }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(headerLabel)
                .font(.caption2.bold())
                .tracking(2)
                .foregroundStyle(.secondary)
            
            Button {
                tempMileageString = "" // Blank slate as requested
                isEditing = true
            } label: {
                HStack(spacing: 4) {
                    let digits = String(format: "%06d", mileage).map { String($0) }
                    ForEach(0..<digits.count, id: \.self) { index in
                        Text(digits[index])
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .frame(width: 35, height: 50)
                            .background(.black)
                            .foregroundStyle(.white)
                            .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        
                        if index == 2 {
                            Text(",")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, -2)
                        }
                    }
                }
                .padding(8)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor, lineWidth: 2)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .alert(alertTitle, isPresented: $isEditing) {
            TextField(alertPlaceholder, text: $tempMileageString)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let val = Int(tempMileageString.filter { $0.isNumber }), val > 0 {
                    mileage = val
                }
            }
        } message: {
            Text(alertPrompt)
        }
    }
}

struct GasFillupRow: View {
    let fillup: GasFillup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Gas Fill-up", systemImage: "fuelpump.fill")
                    .font(.headline)
                Spacer()
                Text(fillup.totalCost, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(fillup.date, format: .dateTime.month().day().year())
                Text("•")
                Text("\(fillup.mileage) miles")
                Text("•")
                Text(String(format: "%.3f gal", fillup.gallons))
                if fillup.pricePerGallon > 0 {
                    Text("•")
                    Text(String(format: "$%.3f/gal", fillup.pricePerGallon))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if fillup.skippedPrevious {
                Text("Missed a previous fill-up — not counted in MPG")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct AddGasFillupView: View {
    let vehicles: [Vehicle]
    var editingFillup: GasFillup?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVehicle: Vehicle?
    @State private var date = Date()
    @State private var mileageString = ""
    @State private var gallonsString = ""
    @State private var totalCostString = ""
    @State private var skippedPrevious = false

    private enum Field: Hashable, CaseIterable { case mileage, gallons, totalCost }
    @FocusState private var focus: Field?

    init(vehicles: [Vehicle], editingFillup: GasFillup? = nil) {
        self.vehicles = vehicles
        self.editingFillup = editingFillup
        if let fillup = editingFillup {
            _selectedVehicle = State(initialValue: fillup.vehicle ?? vehicles.first)
            _date = State(initialValue: fillup.date)
            _mileageString = State(initialValue: formatMileage(String(fillup.mileage)))
            _gallonsString = State(initialValue: formatGallons(String(Int((fillup.gallons * 1000).rounded()))))
            _totalCostString = State(initialValue: formatCost(String(Int((fillup.totalCost * 100).rounded()))))
            _skippedPrevious = State(initialValue: fillup.skippedPrevious)
        } else {
            _selectedVehicle = State(initialValue: vehicles.first)
        }
    }

    private var gallons: Double {
        Double(gallonsString.filter { $0.isNumber }).map { $0 / 1000 } ?? 0
    }

    private var totalCost: Double {
        Double(totalCostString.filter { $0.isNumber }).map { $0 / 100 } ?? 0
    }

    private var isValid: Bool {
        selectedVehicle != nil &&
        Int(mileageString.filter { $0.isNumber }) != nil &&
        !mileageString.filter({ $0.isNumber }).isEmpty &&
        gallons > 0
    }

    private var previousField: Field? {
        guard let focus, let idx = Field.allCases.firstIndex(of: focus), idx > 0 else { return nil }
        return Field.allCases[idx - 1]
    }

    private var nextField: Field? {
        guard let focus, let idx = Field.allCases.firstIndex(of: focus), idx < Field.allCases.count - 1 else { return nil }
        return Field.allCases[idx + 1]
    }

    var body: some View {
        NavigationStack {
            Form {
                if vehicles.count > 1 && editingFillup == nil {
                    Section("Vehicle") {
                        Picker("Vehicle", selection: $selectedVehicle) {
                            ForEach(vehicles) { v in
                                Text(v.name.isEmpty ? "\(v.make) \(v.model)" : v.name).tag(Optional(v))
                            }
                        }
                    }
                }

                Section("Fill-up Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    LabeledContent("Mileage") {
                        TextField("", text: $mileageString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .mileage)
                            .onChange(of: mileageString) { _, val in
                                mileageString = formatMileage(val)
                            }
                    }

                    LabeledContent("Gallons") {
                        TextField("0.000", text: $gallonsString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .gallons)
                            .onChange(of: gallonsString) { _, val in
                                gallonsString = formatGallons(val)
                            }
                    }

                    LabeledContent("Total Cost") {
                        TextField("$0.00", text: $totalCostString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .totalCost)
                            .onChange(of: totalCostString) { _, val in
                                totalCostString = formatCost(val)
                            }
                    }
                }

                Section {
                    Toggle(isOn: $skippedPrevious) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I missed a previous fill-up")
                                .font(.body)
                            Text("There was an unlogged fill-up before this one — MPG won't be calculated for this entry.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(editingFillup == nil ? "Gas Fill-up" : "Edit Fill-up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Button { if let previousField { focus = previousField } } label: { Image(systemName: "chevron.up") }
                        .disabled(previousField == nil)
                    Button { if let nextField { focus = nextField } } label: { Image(systemName: "chevron.down") }
                        .disabled(nextField == nil)
                    Spacer()
                    Button("Done") { focus = nil }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mileage = Int(mileageString.filter { $0.isNumber }) else { return }
                        if let fillup = editingFillup {
                            fillup.date = date
                            fillup.mileage = mileage
                            fillup.gallons = gallons
                            fillup.totalCost = totalCost
                            fillup.skippedPrevious = skippedPrevious
                            if let v = fillup.vehicle {
                                if mileage > v.currentMileage { v.currentMileage = mileage }
                                v.lastModified = Date()
                            }
                        } else {
                            guard let vehicle = selectedVehicle else { return }
                            let fillup = GasFillup(date: date, mileage: mileage, gallons: gallons, totalCost: totalCost, skippedPrevious: skippedPrevious)
                            fillup.vehicle = vehicle
                            vehicle.gasFillups.append(fillup)
                            if mileage > vehicle.currentMileage { vehicle.currentMileage = mileage }
                            vehicle.lastModified = Date()
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }
}

struct AllRemindersView: View {
    let vehicle: Vehicle
    @Environment(\.modelContext) private var modelContext
    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("scheduleSortOrder") private var scheduleSortOrder: String = "nextUp"

    @State private var reminderToEdit: MaintenanceReminder?
    @State private var reminderToSetNext: MaintenanceReminder?
    @State private var showingAddReminder = false
    @State private var showingClearSchedule = false
    @State private var showingScheduleSettings = false
    @State private var showingAddLog = false
    @State private var logToPrepopulate: String?

    var sortedReminders: [MaintenanceReminder] {
        switch scheduleSortOrder {
        case "az":
            return vehicle.reminders.sorted { $0.title < $1.title }
        case "recentlyCompleted":
            return vehicle.reminders.sorted {
                ($0.lastCompletedDate ?? .distantPast) > ($1.lastCompletedDate ?? .distantPast)
            }
        case "intervalLength":
            return vehicle.reminders.sorted {
                reminderEffectiveInterval($0) < reminderEffectiveInterval($1)
            }
        default:
            return vehicle.reminders.sorted {
                reminderMilesUntilDue($0, currentMileage: vehicle.currentMileage) <
                reminderMilesUntilDue($1, currentMileage: vehicle.currentMileage)
            }
        }
    }

    var body: some View {
        List {
            ForEach(sortedReminders) { reminder in
                ReminderRow(
                    reminder: reminder,
                    currentMileage: vehicle.currentMileage,
                    unitLabel: vehicle.mileageUnit.label,
                    onComplete: {
                        logToPrepopulate = reminder.title
                        reminder.lastCompletedDate = Date()
                        reminder.lastCompletedMileage = vehicle.currentMileage
                        reminder.nextReminderMileage = nil
                        reminder.nextReminderDate = nil
                        showingAddLog = true
                    },
                    onEdit: { reminderToEdit = reminder },
                    onDelete: {
                        modelContext.delete(reminder)
                        refreshNotifications()
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(reminder)
                        refreshNotifications()
                    } label: { Label("Delete", systemImage: "trash") }
                    Button { reminderToEdit = reminder } label: { Label("Edit", systemImage: "pencil") }
                        .tint(.orange)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        reminderToSetNext = reminder
                    } label: { Label("Set Next", systemImage: "pin") }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Maintenance Schedule")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingAddReminder = true } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                    Button { showingScheduleSettings = true } label: {
                        Label("Edit View...", systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingClearSchedule = true
                    } label: {
                        Label("Clear Schedule...", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddReminder, onDismiss: refreshNotifications) {
            AddReminderView(vehicle: vehicle)
        }
        .sheet(item: $reminderToEdit, onDismiss: refreshNotifications) { reminder in
            AddReminderView(vehicle: vehicle, editingReminder: reminder)
        }
        .sheet(item: $reminderToSetNext, onDismiss: refreshNotifications) { reminder in
            SetNextReminderSheet(reminder: reminder, currentMileage: vehicle.currentMileage, unitLabel: vehicle.mileageUnit.label)
        }
        .sheet(isPresented: $showingScheduleSettings) {
            ScheduleViewSettingsSheet()
        }
        .sheet(isPresented: $showingClearSchedule) {
            ClearScheduleSheet {
                for reminder in vehicle.reminders { modelContext.delete(reminder) }
                vehicle.reminders.removeAll()
                refreshNotifications()
            }
        }
        .sheet(isPresented: $showingAddLog) {
            AddMaintenanceLogView(vehicle: vehicle, initialServiceType: logToPrepopulate)
        }
        .tint(Color.fromName(accentColorName))
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    private func refreshNotifications() {
        let data = vehicle.reminders.map { r in
            ReminderNotifData(
                vehicleName: vehicle.displayName,
                title: r.title,
                intervalType: r.intervalType,
                mileageInterval: r.mileageInterval,
                lastCompletedMileage: r.lastCompletedMileage,
                currentMileage: vehicle.currentMileage,
                timeFrequency: r.timeFrequency,
                monthInterval: r.monthInterval,
                nextReminderMileage: r.nextReminderMileage,
                nextReminderDate: r.nextReminderDate
            )
        }
        NotificationManager.shared.refresh(vehicleName: vehicle.displayName, currentMileage: vehicle.currentMileage, reminders: data)
    }
}

struct ClearScheduleSheet: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""

    private var isConfirmed: Bool {
        confirmText.lowercased() == "delete"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("This will permanently delete all reminders in the schedule. This cannot be undone.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }

                Section("Type DELETE to confirm") {
                    TextField("DELETE", text: $confirmText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                }

                Section {
                    Button(role: .destructive) {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Delete All Reminders")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(!isConfirmed)
                }
            }
            .navigationTitle("Clear Schedule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 280)
        #endif
    }
}

// MARK: - Schedule sort helpers (shared by VehicleDetailView + AllRemindersView)

func reminderMilesUntilDue(_ r: MaintenanceReminder, currentMileage: Int) -> Int {
    if let nextMileage = r.nextReminderMileage {
        return nextMileage - currentMileage
    }
    if let nextDate = r.nextReminderDate {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 0
        return days * 30
    }
    switch r.intervalType {
    case .mileage:
        let last = r.lastCompletedMileage ?? 0
        let interval = r.mileageInterval ?? 5000
        return (last + interval) - currentMileage
    case .time:
        guard let freq = r.timeFrequency else { return Int.max }
        let months: Int
        switch freq {
        case .annual:    months = 12
        case .quarterly: months = 3
        case .monthly:   months = 1
        }
        if let lastDate = r.lastCompletedDate {
            let elapsed = Calendar.current.dateComponents([.month], from: lastDate, to: Date()).month ?? 0
            return (months - elapsed) * 1000
        } else {
            return -999_999
        }
    }
}

private func reminderEffectiveInterval(_ r: MaintenanceReminder) -> Int {
    switch r.intervalType {
    case .mileage:
        return r.mileageInterval ?? 0
    case .time:
        guard let freq = r.timeFrequency else { return Int.max }
        switch freq {
        case .monthly:   return 1_000
        case .quarterly: return 3_000
        case .annual:    return 12_000
        }
    }
}

struct ScheduleViewSettingsSheet: View {
    @AppStorage("schedulePreviewCount") private var schedulePreviewCount: Int = 3
    @AppStorage("scheduleSortOrder") private var scheduleSortOrder: String = "nextUp"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview Count") {
                    Stepper("\(schedulePreviewCount) items shown", value: $schedulePreviewCount, in: 3...10)
                }
                Section("Sort Order") {
                    Picker("Sort", selection: $scheduleSortOrder) {
                        Text("Next Up").tag("nextUp")
                        Text("A–Z").tag("az")
                        Text("Recently Completed").tag("recentlyCompleted")
                        Text("Interval Length").tag("intervalLength")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Schedule Display")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 260)
        #endif
    }
}

struct SetNextReminderSheet: View {
    let reminder: MaintenanceReminder
    let currentMileage: Int
    var unitLabel: String = "mi"
    @Environment(\.dismiss) private var dismiss

    enum OverrideType { case odometer, date }
    @State private var overrideType: OverrideType
    @State private var odometerString: String
    @State private var targetDate: Date

    init(reminder: MaintenanceReminder, currentMileage: Int, unitLabel: String = "mi") {
        self.reminder = reminder
        self.currentMileage = currentMileage
        self.unitLabel = unitLabel

        let defaultType: OverrideType = reminder.nextReminderDate != nil || reminder.intervalType == .time ? .date : .odometer
        _overrideType = State(initialValue: defaultType)

        let smartMileage = reminder.nextReminderMileage
            ?? max(currentMileage + 1, (reminder.lastCompletedMileage ?? currentMileage) + (reminder.mileageInterval ?? 5000))
        _odometerString = State(initialValue: formatMileage("\(smartMileage)"))

        _targetDate = State(initialValue: reminder.nextReminderDate ?? Date())
    }

    private var isSaveDisabled: Bool {
        overrideType == .odometer && (Int(odometerString.filter { $0.isNumber }) ?? 0) <= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $overrideType) {
                        Text(unitLabel == "hr" ? "Hour Meter" : "Odometer").tag(OverrideType.odometer)
                        Text("Date").tag(OverrideType.date)
                    }
                    .pickerStyle(.segmented)
                }

                if overrideType == .odometer {
                    Section(unitLabel == "hr" ? "Next Due Hours" : "Next Due Mileage") {
                        TextField(unitLabel == "hr" ? "Hour meter reading" : "Odometer reading", text: $odometerString)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .onChange(of: odometerString) { _, val in
                                odometerString = formatMileage(val)
                            }
                    }
                } else {
                    Section("Next Due Date") {
                        DatePicker("", selection: $targetDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                }

                if reminder.nextReminderMileage != nil || reminder.nextReminderDate != nil {
                    Section {
                        Button(role: .destructive) {
                            reminder.nextReminderMileage = nil
                            reminder.nextReminderDate = nil
                            dismiss()
                        } label: {
                            Label("Clear Override", systemImage: "pin.slash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle("Set Next Reminder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if overrideType == .odometer {
                            let parsed = Int(odometerString.filter { $0.isNumber })
                            reminder.nextReminderMileage = (parsed ?? 0) > 0 ? parsed : nil
                            reminder.nextReminderDate = nil
                        } else {
                            reminder.nextReminderDate = targetDate
                            reminder.nextReminderMileage = nil
                        }
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }
}

enum ImportMode { case merge, fresh }

// MARK: - Shared helpers (accessible from SettingsView and VehicleDetailView)

func formatMileage(_ raw: String) -> String {
    let digits = raw.filter { $0.isNumber }
    guard !digits.isEmpty, let n = Int(digits) else { return digits }
    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    return fmt.string(from: NSNumber(value: n)) ?? digits
}

/// ATM-style entry: digits shift in from the right with 3 implied decimal
/// places, so typing "1034" reads as 1.034.
func formatGallons(_ raw: String) -> String {
    let digits = raw.filter { $0.isNumber }
    guard !digits.isEmpty, let n = Int(digits) else { return "" }
    let capped = min(n, 999_999)
    return String(format: "%d.%03d", capped / 1000, capped % 1000)
}

/// ATM-style entry: digits shift in from the right with 2 implied decimal
/// places (cents), so typing "150" reads as $1.50.
func formatCost(_ raw: String) -> String {
    let digits = raw.filter { $0.isNumber }
    guard !digits.isEmpty, let n = Int(digits) else { return "" }
    let capped = min(n, 9_999_999)
    return String(format: "$%d.%02d", capped / 100, capped % 100)
}

func garageCSVHeader() -> String {
    "RecordType,Nickname,Year,Make,Model,VIN,LicensePlate,TrackFuel,CurrentMileage,Date,ServiceType,Mileage,Gallons,PartsCost,LaborCost,TotalCost,Notes,SkippedPrevious,IntervalType,Frequency,MileageInterval,MonthInterval,LastCompletedMileage,LastCompletedDate,NextReminderMileage,NextReminderDate\n"
}

func vehicleCSVRows(_ vehicle: Vehicle, using df: DateFormatter) -> String {
    func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
    let v = [esc(vehicle.name), "\(vehicle.year)", esc(vehicle.make), esc(vehicle.model),
             esc(vehicle.vin), esc(vehicle.licensePlate),
             vehicle.gasFillupDisabled ? "false" : "true",
             "\(vehicle.currentMileage)"].joined(separator: ",")

    var dated: [(Date, String)] = []
    for log in vehicle.maintenanceLogs {
        let row = ["log", v, df.string(from: log.date), esc(log.serviceType),
                   "\(log.mileage)", "", "\(log.partsCost)", "\(log.laborCost)",
                   "\(log.totalCost)", esc(log.notes)].joined(separator: ",") + "\n"
        dated.append((log.date, row))
    }
    for fillup in vehicle.gasFillups {
        let row = ["fillup", v, df.string(from: fillup.date),
                   "", "\(fillup.mileage)", String(format: "%.3f", fillup.gallons),
                   "", "", String(format: "%.2f", fillup.totalCost), "",
                   fillup.skippedPrevious ? "true" : "false"].joined(separator: ",") + "\n"
        dated.append((fillup.date, row))
    }
    dated.sort { $0.0 > $1.0 }
    var result = dated.map { $0.1 }.joined()

    for r in vehicle.reminders {
        let row = ["reminder", v, "", esc(r.title), "", "", "", "", esc(r.notes), "",
                   r.intervalType.rawValue,
                   r.timeFrequency?.rawValue ?? "",
                   "\(r.mileageInterval ?? 0)",
                   "\(r.monthInterval ?? 0)",
                   r.lastCompletedMileage.map { "\($0)" } ?? "",
                   r.lastCompletedDate.map { df.string(from: $0) } ?? "",
                   r.nextReminderMileage.map { "\($0)" } ?? "",
                   r.nextReminderDate.map { df.string(from: $0) } ?? ""].joined(separator: ",") + "\n"
        result += row
    }
    return result
}

func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var currentRow: [String] = []
    var currentField = ""
    var inQuotes = false
    var i = text.startIndex
    while i < text.endIndex {
        let char = text[i]
        if inQuotes {
            if char == "\"" {
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "\"" {
                    currentField.append("\""); i = text.index(after: next); continue
                } else { inQuotes = false }
            } else { currentField.append(char) }
        } else {
            switch char {
            case "\"": inQuotes = true
            case ",": currentRow.append(currentField); currentField = ""
            case "\r":
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "\n" { i = next }
                currentRow.append(currentField); currentField = ""
                if !currentRow.allSatisfy({ $0.isEmpty }) { rows.append(currentRow) }
                currentRow = []
            case "\n":
                currentRow.append(currentField); currentField = ""
                if !currentRow.allSatisfy({ $0.isEmpty }) { rows.append(currentRow) }
                currentRow = []
            default: currentField.append(char)
            }
        }
        i = text.index(after: i)
    }
    if !currentField.isEmpty || !currentRow.isEmpty {
        currentRow.append(currentField)
        if !currentRow.allSatisfy({ $0.isEmpty }) { rows.append(currentRow) }
    }
    return rows
}

#if os(iOS)
import UIKit

struct PDFReport: Transferable {
    let name: String
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { r in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(r.name).appendingPathExtension("pdf")
            try r.data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}

func generateVehiclePDF(vehicle: Vehicle, includeSchedule: Bool = true, includeLog: Bool = true, includeCosts: Bool = true) -> PDFReport? {
    let pageW: CGFloat = 612, pageH: CGFloat = 792, margin: CGFloat = 44
    let contentW = pageW - margin * 2
    let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none

    let fSec    = UIFont.systemFont(ofSize: 13, weight: .semibold)
    let fBody   = UIFont.systemFont(ofSize: 10, weight: .regular)
    let fSmall  = UIFont.systemFont(ofSize: 8,  weight: .regular)
    let fColHdr = UIFont.systemFont(ofSize: 9,  weight: .semibold)
    let nf      = NumberFormatter(); nf.numberStyle = .decimal

    // Explicit light-mode colors — adaptive UIColor (label, systemGray6, etc.) can render
    // as dark/invisible in dark-mode trait context during PDF generation.
    func resolveAccentUIColor() -> UIColor {
        let name = UserDefaults.standard.string(forKey: "accentColorName") ?? "blue"
        if name == "custom" {
            let h = (UserDefaults.standard.string(forKey: "customAccentColorHex") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
            if h.count == 6, let rgb = UInt64(h, radix: 16) {
                return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                               green: CGFloat((rgb >> 8)  & 0xFF) / 255,
                               blue:  CGFloat( rgb        & 0xFF) / 255, alpha: 1)
            }
        }
        switch name {
        case "red":    return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green":  return .systemGreen
        case "teal":   return .systemTeal
        case "indigo": return .systemIndigo
        case "purple": return .systemPurple
        case "pink":   return .systemPink
        default:       return .systemBlue
        }
    }
    let rawAccent = resolveAccentUIColor()
    // Yellow and other pale colors don't contrast on white — fall back to near-black
    var _r: CGFloat = 0, _g: CGFloat = 0, _b: CGFloat = 0, _a: CGFloat = 0
    rawAccent.getRed(&_r, green: &_g, blue: &_b, alpha: &_a)
    let accent = (0.2126 * _r + 0.7152 * _g + 0.0722 * _b) > 0.72
        ? UIColor(white: 0.15, alpha: 1)
        : rawAccent
    let shade     = UIColor(white: 0.95, alpha: 1)
    let secondary = UIColor(white: 0.45, alpha: 1)
    let textBlack = UIColor(white: 0.10, alpha: 1)
    let headerBg  = UIColor(white: 0.82, alpha: 1)

    var y: CGFloat = 0
    var pageNum = 0

    let pdfData = UIGraphicsPDFRenderer(
        bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH)
    ).pdfData { ctx in

        func newPage() {
            ctx.beginPage()
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageW, height: pageH)).fill()
            pageNum += 1
            if pageNum > 1 {
                accent.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageW, height: 26)).fill()
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.white]
                ("\(vehicle.displayName) — Service Record" as NSString)
                    .draw(in: CGRect(x: margin, y: 5, width: contentW, height: 16), withAttributes: a)
            }
            y = pageNum == 1 ? 0 : 38
        }

        func footerPageNum() {
            let s = "Page \(pageNum)" as NSString
            let a: [NSAttributedString.Key: Any] = [.font: fSmall, .foregroundColor: secondary]
            let sz = s.size(withAttributes: a)
            s.draw(at: CGPoint(x: pageW - margin - sz.width, y: pageH - margin + 6), withAttributes: a)
        }

        func needsBreak(_ h: CGFloat) -> Bool { y + h > pageH - margin - 20 }

        func breakPage() { footerPageNum(); newPage() }

        func sectionHeader(_ title: String) {
            if needsBreak(44) { breakPage() }
            let barRect = CGRect(x: margin, y: y, width: contentW, height: 22)
            accent.withAlphaComponent(0.10).setFill()
            UIBezierPath(roundedRect: barRect, cornerRadius: 3).fill()
            accent.setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: 4, height: 22)).fill()
            let a: [NSAttributedString.Key: Any] = [.font: fSec, .foregroundColor: accent]
            (title as NSString).draw(in: CGRect(x: margin + 12, y: y + 4, width: contentW - 16, height: 16), withAttributes: a)
            y += 28
        }

        func labelValue(_ label: String, _ value: String) {
            if needsBreak(17) { breakPage() }
            let la: [NSAttributedString.Key: Any] = [.font: fSmall, .foregroundColor: secondary]
            let va: [NSAttributedString.Key: Any] = [.font: fBody,  .foregroundColor: textBlack]
            (label.uppercased() as NSString).draw(in: CGRect(x: margin, y: y, width: 110, height: 14), withAttributes: la)
            (value as NSString).draw(in: CGRect(x: margin + 118, y: y, width: contentW - 118, height: 14), withAttributes: va)
            y += 17
        }

        typealias Col = (String, CGFloat, NSTextAlignment)

        func tableHeader(_ cols: [Col]) {
            if needsBreak(20) { breakPage() }
            headerBg.setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: contentW, height: 20)).fill()
            var x = margin + 6
            for (t, w, _) in cols {
                let a: [NSAttributedString.Key: Any] = [.font: fColHdr, .foregroundColor: textBlack]
                (t as NSString).draw(in: CGRect(x: x, y: y + 4, width: w - 8, height: 14), withAttributes: a)
                x += w
            }
            y += 20
        }

        func tableRow(_ cols: [Col], idx: Int, rowH: CGFloat, redFlag: Bool = false) {
            if needsBreak(rowH) { footerPageNum(); newPage() }
            if idx % 2 == 1 {
                shade.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: contentW, height: rowH)).fill()
            }
            var x = margin + 6
            for (colIdx, (text, w, align)) in cols.enumerated() {
                let isLastCol = colIdx == cols.count - 1
                let fg: UIColor = redFlag && isLastCol ? .systemRed : textBlack
                let f: UIFont  = redFlag && isLastCol ? UIFont.systemFont(ofSize: 10, weight: .bold) : fBody
                let para = NSMutableParagraphStyle()
                para.alignment = align
                para.lineBreakMode = isLastCol ? .byWordWrapping : .byTruncatingTail
                let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: fg, .paragraphStyle: para]
                (text as NSString).draw(in: CGRect(x: x, y: y + 3, width: w - 8, height: rowH - 4), withAttributes: a)
                x += w
            }
            y += rowH
        }

        // ── PAGE 1 ───────────────────────────────────────────────────────
        newPage()

        let headerH: CGFloat = 84
        accent.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageW, height: headerH)).fill()

        let titleA: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.white, .kern: 0.4
        ]
        // Wide letter-spacing gives a small-caps feel for the make/model line
        let subLine = vehicle.name.isEmpty
            ? "\(vehicle.year)"
            : "\(vehicle.year)  \(vehicle.make.uppercased())  \(vehicle.model.uppercased())"
        let subA: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.80),
            .kern: 1.6
        ]
        let smallA: [NSAttributedString.Key: Any] = [
            .font: fSmall, .foregroundColor: UIColor.white.withAlphaComponent(0.70)
        ]

        (vehicle.displayName as NSString).draw(in: CGRect(x: margin, y: 14, width: contentW * 0.75, height: 30), withAttributes: titleA)
        (subLine as NSString).draw(in: CGRect(x: margin, y: 48, width: contentW * 0.75, height: 16), withAttributes: subA)

        let gen = "Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))"
        let genSz = (gen as NSString).size(withAttributes: smallA)
        (gen as NSString).draw(at: CGPoint(x: pageW - margin - genSz.width, y: headerH - 14), withAttributes: smallA)

        y = headerH + 18

        // ── VEHICLE DETAILS ──────────────────────────────────────────────
        sectionHeader("Vehicle Details")
        let odomStr = nf.string(from: NSNumber(value: vehicle.currentMileage)) ?? "\(vehicle.currentMileage)"
        let unitLabel = vehicle.mileageUnit == .none ? "N/A" : "\(odomStr) \(vehicle.mileageUnit.label)"
        let detailRows: [(String, String)] = [
            ("Year",    "\(vehicle.year)"),
            ("Make",    vehicle.make.isEmpty ? "—" : vehicle.make),
            ("Model",   vehicle.model.isEmpty ? "—" : vehicle.model),
            ("Nickname", vehicle.name.isEmpty ? "—" : vehicle.name),
            ("License Plate", vehicle.licensePlate.isEmpty ? "—" : vehicle.licensePlate),
            ("VIN",     vehicle.vin.isEmpty ? "—" : vehicle.vin),
            (vehicle.mileageUnit == .hours ? "Current Hours" : "Current Mileage", unitLabel),
            ("Fuel Tracking", vehicle.gasFillupDisabled ? "Disabled" : "Enabled"),
        ]
        for (l, v2) in detailRows { labelValue(l, v2) }
        y += 10

        // ── SCHEDULED MAINTENANCE ────────────────────────────────────────
        if includeSchedule {
            sectionHeader("Scheduled Maintenance")

            let sCols: [Col] = [("Reminder", 160, .left), ("Interval", 110, .left), ("Last Completed", 120, .left), ("Status", 142, .left)]

            if vehicle.reminders.isEmpty {
                if needsBreak(16) { breakPage() }
                let a: [NSAttributedString.Key: Any] = [.font: fBody, .foregroundColor: secondary]
                ("No reminders scheduled." as NSString).draw(in: CGRect(x: margin, y: y, width: contentW, height: 16), withAttributes: a)
                y += 22
            } else {
                let sorted = vehicle.reminders.sorted { reminderMilesUntilDue($0, currentMileage: vehicle.currentMileage) < reminderMilesUntilDue($1, currentMileage: vehicle.currentMileage) }
                tableHeader(sCols)
                for (i, r) in sorted.enumerated() {
                    let due = reminderMilesUntilDue(r, currentMileage: vehicle.currentMileage)
                    let intervalStr: String
                    if r.intervalType == .mileage, let mi = r.mileageInterval {
                        intervalStr = "Every \(nf.string(from: NSNumber(value: mi)) ?? "\(mi)") \(vehicle.mileageUnit.label)"
                    } else if let freq = r.timeFrequency { intervalStr = freq.rawValue }
                    else { intervalStr = "—" }
                    let lastStr: String
                    if let d = r.lastCompletedDate { lastStr = df.string(from: d) }
                    else if let m = r.lastCompletedMileage {
                        lastStr = "\(nf.string(from: NSNumber(value: m)) ?? "\(m)") \(vehicle.mileageUnit.label)"
                    } else { lastStr = "Never" }
                    let statusStr = due <= 0 ? "OVERDUE" : r.intervalType == .mileage
                        ? "\(nf.string(from: NSNumber(value: due)) ?? "\(due)") \(vehicle.mileageUnit.label) left"
                        : "Upcoming"
                    if needsBreak(18) { footerPageNum(); newPage(); tableHeader(sCols) }
                    tableRow([(r.title, 160, .left), (intervalStr, 110, .left), (lastStr, 120, .left), (statusStr, 142, .left)], idx: i, rowH: 18, redFlag: due <= 0)
                }
            }
            y += 12
        }

        // ── MAINTENANCE HISTORY ──────────────────────────────────────────
        if includeLog {
            if needsBreak(60) { footerPageNum(); newPage() }
            sectionHeader("Maintenance History")

            let notesColW: CGFloat = includeCosts ? 188 : 250
            let lCols: [Col] = includeCosts
                ? [("Date", 74, .left), ("Service", 158, .left), ("Mileage", 70, .right), ("Cost", 62, .right), ("Notes", notesColW, .left)]
                : [("Date", 74, .left), ("Service", 158, .left), ("Mileage", 70, .right), ("Notes", notesColW, .left)]
            let logs = vehicle.maintenanceLogs.sorted { $0.date > $1.date }

            if logs.isEmpty {
                if needsBreak(16) { breakPage() }
                let a: [NSAttributedString.Key: Any] = [.font: fBody, .foregroundColor: secondary]
                ("No maintenance records yet." as NSString).draw(in: CGRect(x: margin, y: y, width: contentW, height: 16), withAttributes: a)
                y += 16
            } else {
                func notesRowHeight(_ text: String) -> CGFloat {
                    guard !text.isEmpty else { return 18 }
                    let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
                    let bounds = (text as NSString).boundingRect(
                        with: CGSize(width: notesColW - 8, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: fBody, .paragraphStyle: para], context: nil)
                    return max(18, min(ceil(bounds.height) + 8, 72))
                }
                tableHeader(lCols)
                for (i, log) in logs.enumerated() {
                    let notes = log.notes.replacingOccurrences(of: "• ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let rowH = notesRowHeight(notes)
                    if needsBreak(rowH) { footerPageNum(); newPage(); tableHeader(lCols) }
                    let mStr = vehicle.mileageUnit == .none ? "—" : (nf.string(from: NSNumber(value: log.mileage)) ?? "\(log.mileage)")
                    if includeCosts {
                        let cStr = log.totalCost > 0 ? String(format: "$%.2f", log.totalCost) : "—"
                        tableRow([(df.string(from: log.date), 74, .left), (log.serviceType, 158, .left), (mStr, 70, .right), (cStr, 62, .right), (notes, notesColW, .left)], idx: i, rowH: rowH)
                    } else {
                        tableRow([(df.string(from: log.date), 74, .left), (log.serviceType, 158, .left), (mStr, 70, .right), (notes, notesColW, .left)], idx: i, rowH: rowH)
                    }
                }
            }
        }
        footerPageNum()
    }

    let reportName: String
    if includeSchedule && includeLog {
        reportName = "\(vehicle.displayName)_Report"
    } else if includeSchedule {
        reportName = "\(vehicle.displayName)_Schedule"
    } else {
        reportName = "\(vehicle.displayName)_Log"
    }

    return PDFReport(name: reportName, data: pdfData)
}
#endif

#Preview {
    let vehicle = Vehicle(name: "Test Car", year: 2024, make: "Test", model: "Car")
    return VehicleDetailView(vehicle: vehicle)
        .modelContainer(for: Vehicle.self, inMemory: true)
}
