import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onOpen: () -> Void
    private let onNewPrompt: () -> Void
    private var launchAtLoginItem: NSMenuItem!

    init(onOpen: @escaping () -> Void, onNewPrompt: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onNewPrompt = onNewPrompt
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureMenu()
    }

    private func configureMenu() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2.fill",
            accessibilityDescription: "PromptBoard"
        )

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let openItem = NSMenuItem(title: "Open PromptBoard", action: #selector(openOverlay), keyEquivalent: " ")
        openItem.keyEquivalentModifierMask = [.option]
        openItem.target = self
        menu.addItem(openItem)

        let newPromptItem = NSMenuItem(title: "New Prompt", action: #selector(createNewPrompt), keyEquivalent: "")
        newPromptItem.target = self
        menu.addItem(newPromptItem)

        menu.addItem(.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit PromptBoard", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        launchAtLoginItem.isEnabled = LaunchAtLogin.isAvailable
        launchAtLoginItem.toolTip = LaunchAtLogin.isAvailable
            ? nil
            : "Available when running the bundled PromptBoard.app"
    }

    @objc private func openOverlay() {
        onOpen()
    }

    @objc private func createNewPrompt() {
        onNewPrompt()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
