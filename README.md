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

**Maintenance Logs**
- Log any service with date, mileage, service type, parts/labor costs, and optional receipt photo
- 14 preset service types plus free-text "Other"
- ATM-style currency input — type digits, decimal places itself automatically
- Auto-advances the odometer when you log a higher mileage

**Maintenance Schedule**
- Set mileage-based or time-based reminders (annual, quarterly, monthly)
- Shows miles remaining or **OVERDUE** in red
- Tap the checkmark to mark complete and pre-fill a new log entry in one step
- Skip a reminder, copy a full schedule from another vehicle, or import via CSV

**Gas Fill-up Tracking**
- Log gallons, total cost, and mileage per fill-up
- MPG calculated automatically from consecutive fill-ups
- Line or bar chart for fuel economy and spending, switchable between 3/6/12-month and lifetime windows
- Historic fuel cost scatter plot

**Stats**
- Lifetime cost breakdown: parts, labor, gas, grand total, cost-per-mile
- Mileage-over-time line chart showing accumulation rate across all vehicles

**CSV Import / Export**
- Export logs or schedule for any vehicle to a shareable CSV
- Import logs or a full maintenance schedule from CSV (accepts multiple date formats)
- Template exports designed for LLM-assisted data entry

**Notifications**
- Mileage-based alerts when a service is ≤500 miles away or overdue
- Time-based reminders fire on the 1st of the due month
- Log reminder: nudges you to record service if the app goes untouched for a set interval

**Settings**
- Dark/Light mode toggle
- 8 accent color choices
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
| `ContentView.swift` | Garage grid, vehicle cards, add vehicle sheet |
| `VehicleDetailView.swift` | Vehicle detail, all add/edit sheets, CSV import/export |
| `AllLogsView.swift` | Full searchable log list |
| `VehicleStatsView.swift` | Lifetime cost + mileage-over-time chart |
| `SettingsView.swift` | Settings form, historic fuel cost chart |
| `NotificationManager.swift` | UNUserNotificationCenter scheduling |
| `CurrencyTextField.swift` | ATM-style UIViewRepresentable currency input |
| `Vehicle.swift` | SwiftData model |
| `MaintenanceLog.swift` | SwiftData model |
| `MaintenanceReminder.swift` | SwiftData model |
| `GasFillup.swift` | SwiftData model |
| `PlatformImage.swift` | Cross-platform image helper |
| `UIImage+Extensions.swift` | `cropTo16x9()` for vehicle photos |

## Notes

- **iCloud sync** is not yet enabled (requires Apple Developer Program). The one-line code change is ready — just needs the CloudKit entitlement.
- This is a personal project. No App Store release is planned.
