import AppKit
import PromptBoardKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var libraryStore: LibraryStore!
    private var appState: AppState!
    private var overlayController: OverlayController!
    private var statusItemController: StatusItemController!
    private var hotKeyManager: HotKeyManager!
    private var quickInsertController: QuickInsertController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install()

        let dataDirectoryURL = ProcessInfo.processInfo.environment["PROMPTBOARD_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? LibraryStore.defaultDirectoryURL
        let claudeSkillsURL = ProcessInfo.processInfo.environment["PROMPTBOARD_CLAUDE_SKILLS_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? LibraryRepository.defaultClaudeSkillsURL
        libraryStore = LibraryStore(directoryURL: dataDirectoryURL, claudeSkillsURL: claudeSkillsURL)
        libraryStore.startWatchingForExternalChanges()
        appState = AppState(store: libraryStore)
        overlayController = OverlayController(appState: appState)
        quickInsertController = QuickInsertController(store: libraryStore)

        statusItemController = StatusItemController(
            onOpen: { [weak self] in
                self?.overlayController.show()
            },
            onNewPrompt: { [weak self] in
                self?.overlayController.show()
                self?.appState.beginCreating()
            }
        )

        hotKeyManager = HotKeyManager()
        hotKeyManager.register(
            keyCode: Constants.hotKeyKeyCode, modifiers: Constants.hotKeyModifiers, id: 1
        ) { [weak self] in
            self?.overlayController.toggle()
        }
        hotKeyManager.register(
            keyCode: Constants.quickInsertKeyCode, modifiers: Constants.quickInsertModifiers, id: 2
        ) { [weak self] in
            self?.quickInsertController.trigger()
        }

        DebugHooks.install(
            overlayController: overlayController, appState: appState, quickInsertController: quickInsertController
        )

        if ProcessInfo.processInfo.environment["PROMPTBOARD_SHOW_ON_LAUNCH"] == "1" {
            overlayController.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.teardown()
    }
}
