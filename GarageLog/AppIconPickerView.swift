#if os(iOS)
import SwiftUI

struct AppIconPickerView: View {
    @AppStorage("iconCycleMode") private var iconCycleMode: IconCycleMode = .fixed
    @AppStorage("fixedIconCar") private var fixedIconCar: String = AppIconManager.defaultCar
    @AppStorage("selectedIconCars") private var selectedIconCarsRaw: String = AppIconManager.allCars.joined(separator: ",")

    private var selectedIconPool: Set<String> {
        Set(selectedIconCarsRaw.split(separator: ",").map(String.init))
    }

    private func togglePoolMembership(_ car: String) {
        var set = selectedIconPool
        if set.contains(car) { set.remove(car) } else { set.insert(car) }
        if set.isEmpty { set = [AppIconManager.defaultCar] } // never allow an empty pool
        selectedIconCarsRaw = AppIconManager.allCars.filter { set.contains($0) }.joined(separator: ",")
    }

    var body: some View {
        Form {
            Section {
                Picker("Icon Behavior", selection: $iconCycleMode) {
                    Text("Fixed").tag(IconCycleMode.fixed)
                    Text("New Icon Every Launch").tag(IconCycleMode.perLaunch)
                    Text("New Icon Once a Day").tag(IconCycleMode.daily)
                }
                .onChange(of: iconCycleMode) { _, _ in AppIconManager.applyLaunchIcon() }

                if iconCycleMode == .fixed {
                    Text("Choose an icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose which icons to cycle through — a random one is picked \(iconCycleMode == .daily ? "once a day" : "every time you open the app").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136, maximum: 160), spacing: 14)], spacing: 16) {
                    ForEach(AppIconManager.allCars, id: \.self) { car in
                        let isSelected = iconCycleMode == .fixed ? (fixedIconCar == car) : selectedIconPool.contains(car)
                        ZStack(alignment: .bottomTrailing) {
                            Image("IconPreview_\(car)")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 136, height: 136)
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 4)
                                )
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white, Color.accentColor)
                                    .background(Circle().fill(.white))
                                    .offset(x: 6, y: 6)
                            }
                        }
                        .onTapGesture {
                            if iconCycleMode == .fixed {
                                fixedIconCar = car
                                AppIconManager.setIcon(to: car)
                            } else {
                                togglePoolMembership(car)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("App Icon")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
#endif
