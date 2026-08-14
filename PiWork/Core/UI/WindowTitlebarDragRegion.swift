import AppKit
import SwiftUI

/// Restores the native title-bar interactions that disappear when SwiftUI draws
/// through a hidden title bar: drag to move the window, and double-click to
/// apply the system "title bar double-click" action (zoom / minimize / none).
///
/// Install only over empty top chrome so real controls keep their own hits.
struct WindowTitlebarDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowTitlebarDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowTitlebarDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            performTitlebarDoubleClickAction()
            return
        }

        window?.performDrag(with: event)
    }

    private func performTitlebarDoubleClickAction() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }

        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize" {
        case "Minimize":
            window.miniaturize(nil)
        case "None":
            break
        default:
            // Matches the system green-button zoom behavior (fill / restore).
            window.zoom(nil)
        }
    }
}
