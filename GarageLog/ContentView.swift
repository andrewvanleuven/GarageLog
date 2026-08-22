import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vehicles: [Vehicle]

    @State private var showingAddVehicle = false
    @State private var showingAddFillup = false
    @State private var showingReorderSheet = false
    @AppStorage("garageSortType") private var sortType: SortType = .lastModified
    @State private var selectedVehicle: Vehicle?
    @State private var selectedVehicleID: PersistentIdentifier?

    @AppStorage("accentColorName") private var accentColorName: String = "blue"
    @AppStorage("customAccentColorHex") private var customAccentColorHex: String = ""
    @AppStorage("isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("gasFillupEnabled") private var gasFillupEnabled: Bool = true
    @AppStorage("showNextUpBulletin") private var showNextUpBulletin: Bool = true

    enum SortType: String {
        case lastModified, nameAZ, customOrder
    }

    var sortedVehicles: [Vehicle] {
        let active = vehicles.filter { !$0.isRetired }
        switch sortType {
        case .lastModified: return active.sorted { $0.lastModified > $1.lastModified }
        case .nameAZ:       return active.sorted { $0.name < $1.name }
        case .customOrder:  return active.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    let columns = [GridItem(.adaptive(minimum: 320), spacing: 15)]

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    private func initCustomOrderIfNeeded() {
        let allSame = Set(vehicles.map { $0.sortOrder }).count <= 1
        guard allSame else { return }
        let ordered = vehicles.sorted { $0.lastModified > $1.lastModified }
        for (i, v) in ordered.enumerated() { v.sortOrder = i }
        try? modelContext.save()
    }

    // MARK: - macOS: sidebar + detail

    #if os(macOS)
    private var macBody: some View {
        NavigationSplitView {
            List(selection: $selectedVehicleID) {
                ForEach(sortedVehicles) { vehicle in
                    VehicleSidebarRow(vehicle: vehicle)
                        .tag(vehicle.persistentModelID)
                        .contextMenu {
                            Button {
                                vehicle.isRetired = true
                                NotificationManager.shared.refresh(vehicleName: vehicle.displayName, currentMileage: vehicle.currentMileage, reminders: [])
                                if selectedVehicleID == vehicle.persistentModelID { selectedVehicleID = nil }
                                try? modelContext.save()
                            } label: {
                                Label("Retire Vehicle", systemImage: "archivebox")
                            }
                            Divider()
                            Button(role: .destructive) {
                                if selectedVehicleID == vehicle.persistentModelID { selectedVehicleID = nil }
                                modelContext.delete(vehicle)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .overlay {
                if sortedVehicles.isEmpty {
                    ContentUnavailableView {
                        Label("Empty Garage", systemImage: "car.side.fill")
                    } description: {
                        Text("Add a vehicle to get started.")
                    }
                }
            }
            .navigationTitle("Garage Log")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        Picker("Sort", selection: $sortType) {
                            Label("Last Modified", systemImage: "clock").tag(SortType.lastModified)
                            Label("A–Z", systemImage: "textformat.abc").tag(SortType.nameAZ)
                            Label("Custom Order", systemImage: "list.number").tag(SortType.customOrder)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                if sortType == .customOrder {
                    ToolbarItem(placement: .navigation) {
                        Button { showingReorderSheet = true } label: {
                            Image(systemName: "pencil.and.list.clipboard")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        if gasFillupEnabled && vehicles.contains(where: { !$0.gasFillupDisabled }) {
                            Button { showingAddFillup = true } label: {
                                Image(systemName: "fuelpump.fill")
                            }
                        }
                        Button { showingAddVehicle = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        } detail: {
            if let id = selectedVehicleID,
               let vehicle = sortedVehicles.first(where: { $0.persistentModelID == id }) {
                VehicleDetailView(vehicle: vehicle)
            } else {
                ContentUnavailableView("No Vehicle Selected",
                    systemImage: "car.side.fill",
                    description: Text("Select a vehicle from the sidebar."))
            }
        }
        .sheet(isPresented: $showingAddVehicle) { AddVehicleView() }
        .sheet(isPresented: $showingAddFillup) {
            AddGasFillupView(vehicles: sortedVehicles.filter { !$0.gasFillupDisabled })
        }
        .sheet(isPresented: $showingReorderSheet) { reorderSheet }
        .onChange(of: sortType) { _, newType in
            if newType == .customOrder { initCustomOrderIfNeeded() }
        }
        .tint(Color.fromName(accentColorName))
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    #endif

    // MARK: - iOS: card grid

    #if os(iOS)
    private var iosBody: some View {
        NavigationStack {
            Group {
                if sortedVehicles.isEmpty {
                    ContentUnavailableView {
                        Label("Your Garage is Empty", systemImage: "car.side.fill")
                    } description: {
                        Text("Add your first vehicle to start logging maintenance.")
                    } actions: {
                        Button("Add Vehicle") { showingAddVehicle = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.fromName(accentColorName))
                    }
                } else {
                    ScrollView {
                        if showNextUpBulletin {
                            NextUpSection(vehicles: sortedVehicles)
                        }
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(sortedVehicles) { vehicle in
                                NavigationLink {
                                    VehicleDetailView(vehicle: vehicle)
                                } label: {
                                    VehicleCard(vehicle: vehicle)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    if sortType == .customOrder {
                                        Button { showingReorderSheet = true } label: {
                                            Label("Edit Order…", systemImage: "list.number")
                                        }
                                        Divider()
                                    }
                                    Button {
                                        vehicle.isRetired = true
                                        NotificationManager.shared.refresh(vehicleName: vehicle.displayName, currentMileage: vehicle.currentMileage, reminders: [])
                                        try? modelContext.save()
                                    } label: {
                                        Label("Retire Vehicle", systemImage: "archivebox")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        modelContext.delete(vehicle)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Garage Log")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sortType) {
                            Label("Last Modified", systemImage: "clock").tag(SortType.lastModified)
                            Label("A–Z", systemImage: "textformat.abc").tag(SortType.nameAZ)
                            Label("Custom Order", systemImage: "list.number").tag(SortType.customOrder)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                if sortType == .customOrder {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingReorderSheet = true } label: {
                            Image(systemName: "pencil.and.list.clipboard")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        if gasFillupEnabled && vehicles.contains(where: { !$0.gasFillupDisabled }) {
                            Button { showingAddFillup = true } label: {
                                Image(systemName: "fuelpump.fill")
                            }
                        }
                        Button { showingAddVehicle = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddVehicle) { AddVehicleView() }
            .sheet(isPresented: $showingAddFillup) {
                AddGasFillupView(vehicles: sortedVehicles.filter { !$0.gasFillupDisabled })
            }
            .sheet(isPresented: $showingReorderSheet) { reorderSheet }
            .onChange(of: sortType) { _, newType in
                if newType == .customOrder {
                    initCustomOrderIfNeeded()
                    showingReorderSheet = true
                }
            }
            .tint(Color.fromName(accentColorName))
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
    #endif

    // MARK: - Reorder sheet

    private var reorderSheet: some View {
        NavigationStack {
            List {
                ForEach(sortedVehicles) { vehicle in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vehicle.name.isEmpty ? "\(vehicle.make) \(vehicle.model)" : vehicle.name)
                                .font(.headline)
                            Text(vehicle.name.isEmpty
                                 ? String(vehicle.year)
                                 : "\(vehicle.year) \(vehicle.make) \(vehicle.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { from, to in
                    var ordered = sortedVehicles
                    ordered.move(fromOffsets: from, toOffset: to)
                    for (i, v) in ordered.enumerated() { v.sortOrder = i }
                    try? modelContext.save()
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Custom Order")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingReorderSheet = false }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
    }
}

// MARK: - Sidebar row (macOS)

struct VehicleSidebarRow: View {
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vehicle.name.isEmpty ? "\(vehicle.make) \(vehicle.model)" : vehicle.name)
                .font(.headline)
            Text(vehicle.name.isEmpty
                 ? String(vehicle.year)
                 : "\(vehicle.year) \(vehicle.make) \(vehicle.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Card (iOS)

struct VehicleCard: View {
    let vehicle: Vehicle

    var body: some View {
        RoundedRectangle(cornerRadius: 25)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 220)
            .overlay(
                Group {
                    if let data = vehicle.imageData, let img = imageFromData(data) {
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "car.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.gray.opacity(0.4))
                    }
                }
            )
            .overlay(
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .center)
            )
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.name.isEmpty ? "\(vehicle.make) \(vehicle.model)" : vehicle.name)
                        .font(.title2.bold())
                    if !vehicle.name.isEmpty {
                        Text("\(String(vehicle.year)) \(vehicle.make) \(vehicle.model)")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(String(vehicle.year))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(25),
                alignment: .bottomLeading
            )
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Add Vehicle

struct AddVehicleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var make = ""
    @State private var model = ""
    @State private var licensePlate = ""
    @State private var vin = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var imageData: Data?

    private enum Field: Hashable { case name, make, model }
    @FocusState private var focus: Field?
    @State private var licensePlateFocused = false
    @State private var vinFocused = false

    let currentYear = Calendar.current.component(.year, from: Date())
    var years: [Int] { Array(1900...(currentYear + 1)).reversed() }

    private func dismissKeyboard() {
        focus = nil
        licensePlateFocused = false
        vinFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        if let imageData, let img = imageFromData(imageData) {
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                        } else {
                            Label("Select Car Photo", systemImage: "photo")
                        }
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                #if canImport(UIKit)
                                if let image = UIImage(data: data) {
                                    let cropped = image.cropTo16x9()
                                    imageData = cropped.jpegData(compressionQuality: 0.8)
                                }
                                #else
                                imageData = data
                                #endif
                            }
                        }
                    }
                }

                Section("Vehicle Info") {
                    TextField("Nickname (optional)", text: $name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .make }
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    #else
                    .pickerStyle(.menu)
                    #endif

                    TextField("Make", text: $make)
                        .focused($focus, equals: .make)
                        .submitLabel(.next)
                        .onSubmit { focus = .model }
                    TextField("Model", text: $model)
                        .focused($focus, equals: .model)
                        .submitLabel(.next)
                        .onSubmit {
                            focus = nil
                            licensePlateFocused = true
                        }
                    #if os(iOS)
                    AllCapsTextField(placeholder: "License Plate", text: $licensePlate,
                                     isFocused: licensePlateFocused,
                                     returnKeyType: .next,
                                     onReturn: { licensePlateFocused = false; vinFocused = true })
                    AllCapsTextField(placeholder: "VIN", text: $vin,
                                     isFocused: vinFocused,
                                     returnKeyType: .done,
                                     onReturn: { vinFocused = false })
                    #else
                    TextField("License Plate", text: $licensePlate)
                        .autocorrectionDisabled()
                    TextField("VIN", text: $vin)
                        .autocorrectionDisabled()
                    #endif
                }
            }
            .navigationTitle("Add Vehicle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newVehicle = Vehicle(name: name, year: year, make: make, model: model,
                                                 licensePlate: licensePlate.uppercased(), vin: vin.uppercased(), imageData: imageData)
                        modelContext.insert(newVehicle)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(make.isEmpty || model.isEmpty)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Button { focus = (focus == .make) ? .name : (focus == .model ? .make : .name) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(focus == .name || focus == nil)
                    Button {
                        switch focus {
                        case .name:  focus = .make
                        case .make:  focus = .model
                        case .model: focus = nil; licensePlateFocused = true
                        case nil:    break
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(focus == nil)
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }
}

// MARK: - All-caps, no-autocorrect text field (UIViewRepresentable on iOS)
// SwiftUI modifiers cannot reliably disable spellcheck/autocorrect; UITextField
// properties are the only approach that matches what password/username fields do.

#if canImport(UIKit)
struct AllCapsTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool = false
    var returnKeyType: UIReturnKeyType = .done
    var onReturn: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.autocapitalizationType = .allCharacters
        tf.smartInsertDeleteType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.keyboardType = .asciiCapable
        tf.returnKeyType = returnKeyType
        tf.font = UIFont.preferredFont(forTextStyle: .body)
        tf.backgroundColor = .clear
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.placeholderText]
        )
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.returnKeyType = returnKeyType
        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onReturn: onReturn) }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onReturn: (() -> Void)?

        init(text: Binding<String>, onReturn: (() -> Void)?) {
            _text = text
            self.onReturn = onReturn
        }

        @objc func textChanged(_ tf: UITextField) {
            let upper = (tf.text ?? "").uppercased()
            tf.text = upper
            text = upper
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onReturn?()
            return true
        }
    }
}
#endif

// MARK: - Next Up Section

#if os(iOS)
struct NextUpSection: View {
    let vehicles: [Vehicle]
    @AppStorage("accentColorName") private var accentColorName: String = "blue"

    fileprivate struct DueItem: Identifiable {
        let id = UUID()
        let vehicle: Vehicle
        let reminder: MaintenanceReminder
        let urgency: Int
    }

    private var dueItems: [DueItem] {
        var items: [DueItem] = []
        for v in vehicles {
            for r in v.reminders {
                let val = reminderMilesUntilDue(r, currentMileage: v.currentMileage)
                if val == -999_999 { continue } // time reminder, never completed — sort sentinel only
                let threshold: Int = r.intervalType == .mileage ? 500 : 3000
                if val <= threshold {
                    items.append(DueItem(vehicle: v, reminder: r, urgency: val))
                }
            }
        }
        // Genuinely overdue/due-soon first, then untracked (never-logged mileage reminders)
        return items.sorted { a, b in
            let aUntracked = a.reminder.intervalType == .mileage && a.reminder.lastCompletedMileage == nil && a.reminder.nextReminderMileage == nil
            let bUntracked = b.reminder.intervalType == .mileage && b.reminder.lastCompletedMileage == nil && b.reminder.nextReminderMileage == nil
            if aUntracked != bUntracked { return !aUntracked }
            return a.urgency < b.urgency
        }
    }

    private func isUntracked(_ item: DueItem) -> Bool {
        item.reminder.intervalType == .mileage
            && item.reminder.lastCompletedMileage == nil
            && item.reminder.nextReminderMileage == nil
    }

    private func statusText(_ item: DueItem) -> String {
        if isUntracked(item) { return "Not yet logged" }
        let val = item.urgency
        if val <= 0 {
            let over = -val
            if item.reminder.intervalType == .mileage {
                return over == 0 ? "Due now" : "\(over) \(item.vehicle.mileageUnit.label) overdue"
            } else {
                return "Overdue"
            }
        }
        switch item.reminder.intervalType {
        case .mileage:
            return "in \(val) \(item.vehicle.mileageUnit.label)"
        case .time:
            if let nextDate = item.reminder.nextReminderDate {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 0
                return days <= 0 ? "Today" : "in \(days) day\(days == 1 ? "" : "s")"
            }
            let months = max(0, val / 1000)
            return months == 0 ? "This month" : "in \(months) mo"
        }
    }

    private func cardColor(_ item: DueItem) -> Color {
        if isUntracked(item) { return Color.fromName(accentColorName) }
        if item.urgency <= 0 { return .red }
        if item.reminder.intervalType == .mileage && item.urgency <= 100 { return .orange }
        if item.reminder.intervalType == .time && item.urgency <= 1000 { return .orange }
        return Color.fromName(accentColorName)
    }

    var body: some View {
        if dueItems.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Next Up", systemImage: "wrench.and.screwdriver.fill")
                        .font(.headline)
                        .foregroundStyle(Color.fromName(accentColorName))
                    Spacer()
                    Text("\(dueItems.count) item\(dueItems.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(dueItems) { item in
                            NavigationLink {
                                VehicleDetailView(vehicle: item.vehicle)
                            } label: {
                                NextUpCard(item: item, statusText: statusText(item), statusColor: cardColor(item), borderColor: Color.fromName(accentColorName))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 4)
        }
    }
}

private struct NextUpCard: View {
    let item: NextUpSection.DueItem
    let statusText: String
    let statusColor: Color
    let borderColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.vehicle.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(item.reminder.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
        }
        .padding(14)
        .frame(width: 150, height: 100, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor.opacity(0.3), lineWidth: 1)
        )
    }
}
#endif
