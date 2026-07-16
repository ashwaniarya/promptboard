import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = Constants.blurMaterial
        // The default .followsWindowActiveState renders no blur at all, because a
        // nonactivating panel's app is never active
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
