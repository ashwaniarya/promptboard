import AppKit
import Carbon

enum Constants {
    static let bundleIdentifier = "com.arya.PromptBoard"
    static let hotKeyKeyCode = UInt32(kVK_Space)
    static let hotKeyModifiers = UInt32(optionKey)
    static let quickInsertKeyCode = UInt32(kVK_ANSI_Slash)
    static let quickInsertModifiers = UInt32(optionKey)
    static let blurMaterial: NSVisualEffectView.Material = .fullScreenUI
    static let searchFieldPlaceholder = "Search prompts…"
    static let toolbarControlHeight: CGFloat = 44
    static let editorTitlePlaceholder = "Prompt title"
}
