#if DEBUG
import Foundation
import CoreData
import CloudKit

/// Prints the CloudKit sync story to stdout, where a cabled
/// `devicectl device process launch --console` can actually see it.
///
/// This exists because the sync question was undiagnosable for weeks: the
/// fallback printed to a console nobody watches, the mirroring engine logs to
/// os_log (invisible over the launch console), and the Settings readout was
/// built but only ever read by hand. SwiftData wraps
/// NSPersistentCloudKitContainer, and that container posts
/// `eventChangedNotification` for every setup/import/export attempt with the
/// real error attached, so listening to the notification center gets us the
/// truth without touching the container object SwiftData hides.
///
/// DEBUG-only, print-only, no behavior. Reading it: `[cloud] event ...
/// succeeded=true` for an EXPORT is sync WORKING; `succeeded=false` carries
/// the reason in `error=`.
enum CloudSyncProbe {

    private static var observer: NSObjectProtocol?

    static func start() {
        print("[cloud] persistence mode: \(Persistence.mode.label)")
        if case .localFallback(let why) = Persistence.mode {
            print("[cloud] fallback reason: \(why)")
        }
        Task {
            let status = await CloudStatus.read()
            print("[cloud] container: \(status.container)")
            print("[cloud] iCloud account: \(status.account)")
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let kind: String
            switch event.type {
            case .setup:  kind = "setup"
            case .import: kind = "import"
            case .export: kind = "export"
            @unknown default: kind = "unknown"
            }
            // endDate nil means the event just STARTED; the finished event
            // follows with succeeded/error filled in.
            if event.endDate == nil {
                print("[cloud] event \(kind) started")
            } else {
                print("[cloud] event \(kind) finished succeeded=\(event.succeeded)"
                      + (event.error.map { " error=\($0)" } ?? ""))
            }
        }
    }
}
#endif
