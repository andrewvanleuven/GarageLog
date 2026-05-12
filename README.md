<p align="center">
  <img src="glog-hero.png" width="300" alt="GarageLog logo">
</p>

<h1 align="center">GarageLog</h1>

<p align="center">
  A bespoke personal vehicle maintenance tracker for iOS and macOS.
</p>

---

GarageLog is a SwiftUI app for keeping track of every vehicle you own — maintenance history, upcoming service reminders, fuel economy, and lifetime costs — all in one place. Built for personal use, not the App Store.

## Features

**Garage**
- Visual card grid of all your vehicles with 16:9 photo, nickname, year/make/model
- Pin vehicles to the top; sort by last modified or A–Z
- Quick-add a gas fill-up from the toolbar without opening a vehicle
- **Next Up bulletin**: scrollable strip of due/overdue reminders across all vehicles at the top of the screen (can be hidden in Settings)

**Vehicle Setup**
- Optional nickname — if blank, the app uses "Make Model" everywhere automatically
- **Mileage unit** per vehicle: Miles (Odometer), Hours (Hour Meter), or None (time-only vehicles like tractors with no hour meter)
- License plate, VIN, 16:9 vehicle photo

**Maintenance Logs**
- Log any service with date, mileage, service type, parts/labor costs, and optional receipt photo
- 14 preset service types plus free-text "Other"
- ATM-style currency input — type digits, decimal places itself automatically
- Auto-advances the odometer when you log a higher mileage

**Maintenance Schedule**
- Set mileage-based or time-based reminders (annual, quarterly, monthly)
- Shows miles/hours remaining or **OVERDUE** in red
- Tap the checkmark to mark complete and pre-fill a new log entry in one step
- Skip a reminder without logging, copy a full schedule from another vehicle, or import via CSV
- Configurable sort order: Next Up, A–Z, Recently Completed, or Interval Length
- **Clear Schedule** with type-to-confirm safety gate

**Gas Fill-up Tracking**
- Log gallons, total cost, and mileage per fill-up
- MPG calculated automatically from consecutive fill-ups
- Line or bar chart for fuel economy and spending, switchable between 3/6/12-month and lifetime windows
- Historic fuel cost scatter plot

**Stats**
- Lifetime cost breakdown: parts, labor, gas, grand total, cost-per-mile
- Mileage-over-time line chart showing accumulation rate across all vehicles

**PDF Report** *(iOS)*
- Export a formatted PDF for any vehicle: cover with vehicle name, scheduled maintenance table, full log history
- Accent color matches your app theme; notes column word-wraps; mileage uses thousands separators

**CSV Import / Export**
- Universal 26-column schema covers logs, fill-ups, and reminders in one file
- Per-vehicle export/import, or garage-wide full backup/restore
- **Merge** (skip duplicates) or **Fresh Restore** (wipe and replace) import modes
- Template CSVs for bulk data entry via LLM

**Photo Export**
- Export all vehicle photos as individual JPEGs via the share sheet (useful for phone migration)

**Notifications**
- Mileage-based alerts when a service is ≤500 miles away or overdue
- Time-based reminders fire on the 1st of the due month
- Log reminder: nudges you to record service if the app goes untouched for a set interval

**Settings**
- Dark/Light mode toggle
- 8 accent color presets + custom color picker
- macOS: tabbed preferences window (⌘,)

## Tech Stack

| | |
|---|---|
| UI | SwiftUI |
| Data | SwiftData (lightweight migration) |
| Charts | Swift Charts |
| Photos | PhotosUI |
| Notifications | UserNotifications |
| Platforms | iOS 17.4+ · macOS (native, not Catalyst) |

## Project Structure

| File | Purpose |
|------|---------|
| `GarageLogApp.swift` | App entry, model container, scene lifecycle |
| `ContentView.swift` | Garage grid, vehicle cards, add vehicle sheet, Next Up bulletin |
| `VehicleDetailView.swift` | Vehicle detail, all add/edit sheets, CSV import/export, PDF export |
| `AllLogsView.swift` | Full searchable log list |
| `AllRemindersView.swift` | Full schedule list with edit/skip/delete |
| `VehicleStatsView.swift` | Lifetime cost + mileage-over-time chart |
| `SettingsView.swift` | Settings form, historic fuel cost chart, garage backup/restore |
| `NotificationManager.swift` | UNUserNotificationCenter scheduling |
| `CurrencyTextField.swift` | ATM-style UIViewRepresentable currency input |
| `Vehicle.swift` | SwiftData model (includes `MileageUnit`, `displayName`) |
| `MaintenanceLog.swift` | SwiftData model |
| `MaintenanceReminder.swift` | SwiftData model |
| `GasFillup.swift` | SwiftData model |
| `PlatformImage.swift` | Cross-platform image helper |
| `UIImage+Extensions.swift` | `cropTo16x9()` for vehicle photos |

## Notes

- **iCloud sync** is not yet enabled (requires Apple Developer Program). The one-line code change is ready — just needs the CloudKit entitlement.
- This is a personal project. No App Store release is planned.
