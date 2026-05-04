import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import Charts

struct CSVReport: Transferable {
    let name: String
    let content: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { report in
            report.content.data(using: .utf8) ?? Data()
        }
        .suggestedFileName { report in
            "\(report.name)_Maintenance.csv"
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
    @State private var reminderToEdit: MaintenanceReminder?
    @State private var reminderToSkip: MaintenanceReminder?
    @State private var skipMileageString = ""
    private enum ImportType { case logs, schedule }
    @State private var showingFileImporter = false
    @State private var pendingImport: ImportType = .logs
    @State private var importResultMessage = ""
    @State private var showingImportResult = false
    
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

    private var csvReport: CSVReport {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        var entries: [(date: Date, row: String)] = []

        for log in vehicle.maintenanceLogs {
            let notes = log.notes.replacingOccurrences(of: "\"", with: "\"\"")
            let service = log.serviceType.replacingOccurrences(of: "\"", with: "\"\"")
            entries.append((log.date, "\(dateFormatter.string(from: log.date)),\"\(service)\",\(log.mileage),,\(log.partsCost),\(log.laborCost),\(log.totalCost),\"\(notes)\"\n"))
        }
        for fillup in vehicle.gasFillups {
            entries.append((fillup.date, "\(dateFormatter.string(from: fillup.date)),\"Gas Fill-up\",\(fillup.mileage),\(String(format: "%.3f", fillup.gallons)),,,\(String(format: "%.2f", fillup.totalCost)),\"\"\n"))
        }

        entries.sort { $0.date > $1.date }
        let csvString = "Date,Type,Mileage,Gallons,Parts Cost,Labor Cost,Total Cost,Notes\n"
            + entries.map { $0.row }.joined()
        return CSVReport(name: vehicle.displayName, content: csvString)
    }

    private var scheduleCSVReport: CSVReport {
        var csvString = "Title,Interval Type,Frequency,Mileage Interval,Month Interval,Notes\n"
        for reminder in vehicle.reminders {
            let title = reminder.title.replacingOccurrences(of: "\"", with: "\"\"")
            let notes = reminder.notes.replacingOccurrences(of: "\"", with: "\"\"")
            let row = "\"\(title)\",\(reminder.intervalType.rawValue),\(reminder.timeFrequency?.rawValue ?? ""),\(reminder.mileageInterval ?? 0),\(reminder.monthInterval ?? 0),\"\(notes)\"\n"
            csvString.append(row)
        }
        return CSVReport(name: "\(vehicle.displayName)_Schedule", content: csvString)
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
            
            Section {
                OdometerView(mileage: $vehicle.currentMileage, accentColor: Color.fromName(accentColorName))
                    .listRowBackground(Color.clear)
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
                                    ForEach(allVehicles.filter { $0.id != vehicle.id }) { other in
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
                        
                        let otherVehicles = allVehicles.filter { $0.id != vehicle.id && !$0.reminders.isEmpty }
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
                            onComplete: {
                                logToPrepopulate = reminder.title
                                showingAddLog = true
                                reminder.lastCompletedDate = Date()
                                reminder.lastCompletedMileage = vehicle.currentMileage
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
                            if reminder.intervalType == .mileage, let interval = reminder.mileageInterval {
                                Button {
                                    skipMileageString = "\(vehicle.currentMileage + interval)"
                                    reminderToSkip = reminder
                                } label: {
                                    Label("Skip", systemImage: "forward.circle")
                                }
                                .tint(.blue)
                            }
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
                    ShareLink(item: csvReport, preview: SharePreview("\(vehicle.displayName) Maintenance.csv", image: Image(systemName: "tablecells"))) {
                        Label("Export Logs", systemImage: "doc.text")
                    }
                    ShareLink(item: scheduleCSVReport, preview: SharePreview("\(vehicle.displayName) Schedule.csv", image: Image(systemName: "calendar"))) {
                        Label("Export Schedule", systemImage: "calendar")
                    }
                    Divider()
                    Button {
                        pendingImport = .logs
                        showingFileImporter = true
                    } label: {
                        Label("Import Logs", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        pendingImport = .schedule
                        showingFileImporter = true
                    } label: {
                        Label("Import Schedule", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Import / Export CSV", systemImage: "arrow.up.arrow.down")
                }
            } header: {
                Text("Data")
            }
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
                switch pendingImport {
                case .logs:     importCSV(from: url)
                case .schedule: importScheduleCSV(from: url)
                }
            case .failure:
                importResultMessage = "Could not open file."
                showingImportResult = true
            }
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importResultMessage)
        }
        .alert("Skip to Next Due Mileage", isPresented: Binding(get: { reminderToSkip != nil }, set: { if !$0 { reminderToSkip = nil } })) {
            TextField("Next due mileage", text: $skipMileageString)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Cancel", role: .cancel) { reminderToSkip = nil }
            Button("Skip") {
                if let target = Int(skipMileageString.filter { $0.isNumber }),
                   let reminder = reminderToSkip {
                    reminder.lastCompletedMileage = target - (reminder.mileageInterval ?? 0)
                    reminderToSkip = nil
                    refreshNotifications()
                }
            }
        } message: {
            if let reminder = reminderToSkip, let interval = reminder.mileageInterval {
                Text("Set the next \(reminder.title) due mileage. Current odometer: \(vehicle.currentMileage) mi, interval: \(interval) mi.")
            }
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
                monthInterval: r.monthInterval
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
        vehicle.lastModified = Date()
    }

    private func importCSV(from url: URL) {
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
        guard let dateIdx = headers.firstIndex(of: "date"),
              let typeIdx = headers.firstIndex(of: "type"),
              let mileageIdx = headers.firstIndex(of: "mileage") else {
            importResultMessage = "Unrecognized CSV format. Expected columns: Date, Type, Mileage."
            showingImportResult = true
            return
        }

        let gallonsIdx = headers.firstIndex(of: "gallons")
        let partsIdx = headers.firstIndex(of: "parts cost")
        let laborIdx = headers.firstIndex(of: "labor cost")
        let totalIdx = headers.firstIndex(of: "total cost")
        let notesIdx = headers.firstIndex(of: "notes")

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dateFormats = ["M/d/yy", "M/d/yyyy", "MM/dd/yy", "MM/dd/yyyy", "yyyy-MM-dd"]

        func parseDate(_ str: String) -> Date? {
            for fmt in dateFormats {
                dateFormatter.dateFormat = fmt
                if let d = dateFormatter.date(from: str.trimmingCharacters(in: .whitespaces)) { return d }
            }
            return nil
        }

        func col(_ row: [String], _ idx: Int?) -> String {
            guard let idx, row.indices.contains(idx) else { return "" }
            return row[idx].trimmingCharacters(in: .whitespaces)
        }

        var imported = 0
        for row in rows.dropFirst() {
            guard row.indices.contains(max(dateIdx, typeIdx, mileageIdx)) else { continue }
            guard let date = parseDate(col(row, dateIdx)) else { continue }

            let mileage = Int(col(row, mileageIdx)) ?? 0
            let type = col(row, typeIdx)
            let notes = col(row, notesIdx)

            if type.lowercased() == "gas fill-up" {
                let gallons = Double(col(row, gallonsIdx)) ?? 0
                let cost = Double(col(row, totalIdx)) ?? 0
                let fillup = GasFillup(date: date, mileage: mileage, gallons: gallons, totalCost: cost, skippedPrevious: false)
                fillup.vehicle = vehicle
                vehicle.gasFillups.append(fillup)
            } else {
                let parts = Double(col(row, partsIdx)) ?? 0
                let labor = Double(col(row, laborIdx)) ?? 0
                let log = MaintenanceLog(date: date, mileage: mileage, serviceType: type.isEmpty ? "Other" : type, notes: notes, partsCost: parts, laborCost: labor)
                log.vehicle = vehicle
                vehicle.maintenanceLogs.append(log)
            }

            if mileage > vehicle.currentMileage { vehicle.currentMileage = mileage }
            imported += 1
        }

        vehicle.lastModified = Date()
        importResultMessage = imported > 0 ? "Imported \(imported) record\(imported == 1 ? "" : "s")." : "No valid records found."
        showingImportResult = true
    }

    private func importScheduleCSV(from url: URL) {
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
        guard let titleIdx = headers.firstIndex(of: "title"),
              let intervalTypeIdx = headers.firstIndex(of: "interval type") else {
            importResultMessage = "Unrecognized format. Expected columns: Title, Interval Type."
            showingImportResult = true
            return
        }

        let freqIdx = headers.firstIndex(of: "frequency")
        let mileageIntervalIdx = headers.firstIndex(of: "mileage interval")
        let monthIntervalIdx = headers.firstIndex(of: "month interval")
        let notesIdx = headers.firstIndex(of: "notes")

        func col(_ row: [String], _ idx: Int?) -> String {
            guard let idx, row.indices.contains(idx) else { return "" }
            return row[idx].trimmingCharacters(in: .whitespaces)
        }

        var imported = 0
        for row in rows.dropFirst() {
            guard row.indices.contains(max(titleIdx, intervalTypeIdx)) else { continue }
            let title = col(row, titleIdx)
            guard !title.isEmpty else { continue }

            let intervalType = ReminderIntervalType(rawValue: col(row, intervalTypeIdx)) ?? .mileage

            let mileageInterval: Int? = {
                guard intervalType == .mileage else { return nil }
                let v = Int(col(row, mileageIntervalIdx)) ?? 0
                return v > 0 ? v : nil
            }()

            let timeFrequency: TimeFrequency? = intervalType == .time
                ? TimeFrequency(rawValue: col(row, freqIdx))
                : nil

            let monthInterval: Int? = {
                guard intervalType == .time else { return nil }
                let v = Int(col(row, monthIntervalIdx)) ?? 0
                return v > 0 ? v : nil
            }()

            let notes = col(row, notesIdx)
            let reminder = MaintenanceReminder(
                title: title,
                intervalType: intervalType,
                timeFrequency: timeFrequency,
                mileageInterval: mileageInterval,
                monthInterval: monthInterval,
                notes: notes.isEmpty ? "• " : notes
            )
            reminder.vehicle = vehicle
            vehicle.reminders.append(reminder)
            imported += 1
        }

        vehicle.lastModified = Date()
        importResultMessage = imported > 0 ? "Imported \(imported) reminder\(imported == 1 ? "" : "s")." : "No valid reminders found."
        showingImportResult = true
    }

    private func parseCSV(_ text: String) -> [[String]] {
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
                        currentField.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\r":
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\n" { i = next }
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) { rows.append(currentRow) }
                    currentRow = []
                case "\n":
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) { rows.append(currentRow) }
                    currentRow = []
                default:
                    currentField.append(char)
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

}

struct ReminderRow: View {
    let reminder: MaintenanceReminder
    let currentMileage: Int
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
                    let lastCompleted = reminder.lastCompletedMileage ?? 0
                    let nextDue = lastCompleted + interval
                    let remaining = nextDue - currentMileage
                    
                    HStack {
                        Text("Every \(interval) miles")
                        Text("•")
                        if remaining <= 0 {
                            Text("OVERDUE").foregroundStyle(.red).bold()
                        } else {
                            Text("\(remaining) miles left").foregroundStyle(.secondary)
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
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                
                Section("Interval Type") {
                    Picker("Type", selection: $intervalType) {
                        Text("Mileage").tag(ReminderIntervalType.mileage)
                        Text("Time").tag(ReminderIntervalType.time)
                    }
                    .pickerStyle(.segmented)
                }
                
                if intervalType == .mileage {
                    Section("Mileage Interval") {
                        HStack {
                            Text("\(mileageInterval) miles")
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

        if let log = editingLog {
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
            _mileage = State(initialValue: (vehicle.currentMileage / 100) * 100)
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
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Mileage")
                            Spacer()
                            TextField("Manual Entry", value: $mileage, format: .number)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .focused($isManualMileageFocused)
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
                    }
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
    @State private var isEditing = false
    @State private var tempMileageString: String = ""
    
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("ODOMETER")
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
        .alert("Update Odometer", isPresented: $isEditing) {
            TextField("Current Mileage", text: $tempMileageString)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let val = Int(tempMileageString) {
                    mileage = val
                }
            }
        } message: {
            Text("Enter the current mileage for your vehicle.")
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
    @State private var totalCost: Double = 0.0
    @State private var skippedPrevious = false

    private enum Field: Hashable { case mileage, gallons }
    @FocusState private var focus: Field?

    init(vehicles: [Vehicle], editingFillup: GasFillup? = nil) {
        self.vehicles = vehicles
        self.editingFillup = editingFillup
        if let fillup = editingFillup {
            _selectedVehicle = State(initialValue: fillup.vehicle ?? vehicles.first)
            _date = State(initialValue: fillup.date)
            _mileageString = State(initialValue: Self.formatMileage(String(fillup.mileage)))
            _gallonsString = State(initialValue: String(fillup.gallons))
            _totalCost = State(initialValue: fillup.totalCost)
            _skippedPrevious = State(initialValue: fillup.skippedPrevious)
        } else {
            _selectedVehicle = State(initialValue: vehicles.first)
        }
    }

    private static func formatMileage(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits) else { return digits }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: n)) ?? digits
    }

    private var isValid: Bool {
        selectedVehicle != nil &&
        Int(mileageString.filter { $0.isNumber }) != nil &&
        !mileageString.filter({ $0.isNumber }).isEmpty &&
        (Double(gallonsString) ?? 0) > 0
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
                                mileageString = Self.formatMileage(val)
                            }
                    }

                    LabeledContent("Gallons") {
                        TextField("", text: $gallonsString)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .gallons)
                    }

                    LabeledContent("Total Cost") {
                        CurrencyTextField(value: $totalCost)
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
                    Button { focus = .mileage } label: { Image(systemName: "chevron.up") }
                        .disabled(focus == .mileage)
                    Button { focus = .gallons } label: { Image(systemName: "chevron.down") }
                        .disabled(focus == .gallons)
                    Spacer()
                    Button("Done") { focus = nil }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mileage = Int(mileageString.filter { $0.isNumber }),
                              let gallons = Double(gallonsString) else { return }
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
    @State private var reminderToSkip: MaintenanceReminder?
    @State private var skipMileageString = ""
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
                    onComplete: {
                        logToPrepopulate = reminder.title
                        reminder.lastCompletedDate = Date()
                        reminder.lastCompletedMileage = vehicle.currentMileage
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
                    if reminder.intervalType == .mileage, let interval = reminder.mileageInterval {
                        Button {
                            skipMileageString = "\(vehicle.currentMileage + interval)"
                            reminderToSkip = reminder
                        } label: { Label("Skip", systemImage: "forward.circle") }
                        .tint(.blue)
                    }
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
        .alert("Skip to Next Due Mileage", isPresented: Binding(get: { reminderToSkip != nil }, set: { if !$0 { reminderToSkip = nil } })) {
            TextField("Next due mileage", text: $skipMileageString)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Cancel", role: .cancel) { reminderToSkip = nil }
            Button("Skip") {
                if let target = Int(skipMileageString.filter { $0.isNumber }),
                   let reminder = reminderToSkip {
                    reminder.lastCompletedMileage = target - (reminder.mileageInterval ?? 0)
                    reminderToSkip = nil
                    refreshNotifications()
                }
            }
        } message: {
            if let reminder = reminderToSkip, let interval = reminder.mileageInterval {
                Text("Set the next \(reminder.title) due mileage. Current odometer: \(vehicle.currentMileage) mi, interval: \(interval) mi.")
            }
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
                monthInterval: r.monthInterval
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

private func reminderMilesUntilDue(_ r: MaintenanceReminder, currentMileage: Int) -> Int {
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

#Preview {
    let vehicle = Vehicle(name: "Test Car", year: 2024, make: "Test", model: "Car")
    return VehicleDetailView(vehicle: vehicle)
        .modelContainer(for: Vehicle.self, inMemory: true)
}
