import AppKit

@MainActor
enum DebugHooks {
    static let toggleNotification = "com.arya.PromptBoard.debug.toggle"
    static let snapshotNotification = "com.arya.PromptBoard.debug.snapshot"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PROMPTBOARD_DEBUG"] == "1"
    }

    static func install(overlayController: OverlayController) {
        guard isEnabled else { return }
        let center = DistributedNotificationCenter.default()

        center.addObserver(forName: Notification.Name(toggleNotification), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                overlayController.toggle()
            }
        }

        center.addObserver(forName: Notification.Name(snapshotNotification), object: nil, queue: .main) { notification in
            let outputPath = notification.object as? String ?? "/tmp/promptboard-snapshot.png"
            MainActor.assumeIsolated {
                overlayController.writeContentSnapshot(to: outputPath)
            }
        }
    }
}
