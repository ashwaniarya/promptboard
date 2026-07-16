import AppKit
import Carbon

enum Constants {
    static let bundleIdentifier = "com.arya.PromptBoard"
    static let hotKeyKeyCode = UInt32(kVK_Space)
    static let hotKeyModifiers = UInt32(optionKey)
    static let blurMaterial: NSVisualEffectView.Material = .fullScreenUI
    static let searchFieldPlaceholder = "Search prompts…"
    static let editorTitlePlaceholder = "Prompt title"
}
