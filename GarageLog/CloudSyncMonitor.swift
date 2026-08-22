import Foundation
import CoreData
import Combine

/// Watches SwiftData's CloudKit mirroring (built on NSPersistentCloudKitContainer
/// under the hood) so Settings can show a simple last-synced / error status.
final class CloudSyncMonitor: ObservableObject {
    static let shared = CloudSyncMonitor()

    enum Status: Equatable {
        case neverSynced
        case syncing
        case succeeded(Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .neverSynced

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            self?.handle(event)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard event.endDate != nil else {
            status = .syncing
            return
        }
        if let error = event.error {
            status = .failed(error.localizedDescription)
        } else {
            status = .succeeded(event.endDate ?? Date())
        }
    }
}
