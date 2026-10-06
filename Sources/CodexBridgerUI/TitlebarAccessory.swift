import SwiftUI
import AppKit

/// Pins a control to the trailing end of the window title bar.
///
/// Why this exists: a trailing toolbar item cannot be placed here while the title is a
/// `.principal` toolbar item. Five configurations were built and measured, and every one with a
/// principal title dragged the action button into the same centred cluster — 340pt short of the
/// corner — whatever the placement, the order, or which view supplied it. Dropping the principal
/// item puts the button back at the corner (28pt away) but throws the title 214pt left of centre.
/// `NSTitlebarAccessoryViewController` with `.right` is the AppKit mechanism that does not have
/// that coupling, so the title stays centred and the button stays in the corner.
struct TitlebarAccessory<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> NSView {
        // An invisible anchor; the accessory is attached once the window is known.
        let anchor = NSView(frame: .zero)
        DispatchQueue.main.async { attach(from: anchor, context: context) }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hosting?.rootView = content
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var accessory: NSTitlebarAccessoryViewController?
        var hosting: NSHostingView<Content>?
    }

    private func attach(from anchor: NSView, context: Context) {
        guard context.coordinator.accessory == nil,
              let window = anchor.window else { return }
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 40, height: 28)
        let controller = NSTitlebarAccessoryViewController()
        controller.view = hosting
        controller.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(controller)
        context.coordinator.accessory = controller
        context.coordinator.hosting = hosting
    }
}