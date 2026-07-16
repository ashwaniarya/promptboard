import AppKit
import PromptBoardKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var promptStore: PromptStore!
    private var appState: AppState!
    private var overlayController: OverlayController!
    private var statusItemController: StatusItemController!
    private var hotKeyManager: HotKeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let dataDirectoryURL = ProcessInfo.processInfo.environment["PROMPTBOARD_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? PromptStore.defaultDirectoryURL
        promptStore = PromptStore(directoryURL: dataDirectoryURL)
        appState = AppState(store: promptStore)
        overlayController = OverlayController(appState: appState)

        statusItemController = StatusItemController(
            onOpen: { [weak self] in
                self?.overlayController.show()
            },
            onNewPrompt: { [weak self] in
                self?.overlayController.show()
                self?.appState.beginCreating()
            }
        )

        hotKeyManager = HotKeyManager { [weak self] in
            self?.overlayController.toggle()
        }
        hotKeyManager.register()

        DebugHooks.install(overlayController: overlayController)

        if ProcessInfo.processInfo.environment["PROMPTBOARD_SHOW_ON_LAUNCH"] == "1" {
            overlayController.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.teardown()
    }
}
