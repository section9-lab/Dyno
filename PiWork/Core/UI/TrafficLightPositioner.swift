import AppKit
import SwiftUI

/// Moves the window's traffic lights inward so they sit inside the floating
/// sidebar panel instead of hugging the window's own corner.
///
/// There is no SwiftUI API for this. The buttons are plain `NSButton`s that
/// AppKit lays out inside the title bar, and it re-runs that layout whenever
/// the window resizes or leaves full screen, so the offset has to be
/// re-applied rather than set once.
struct TrafficLightPositioner: NSViewRepresentable {
    /// How far to move the buttons right and down from AppKit's own layout.
    var offset: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = TrafficLightAnchorView()
        view.offset = offset
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrafficLightAnchorView)?.offset = offset
    }
}

private final class TrafficLightAnchorView: NSView {
    var offset: CGSize = .zero {
        didSet { applyOffset() }
    }

    /// AppKit's own geometry, captured before the first nudge so repeated
    /// applications stay absolute instead of compounding.
    private struct DefaultLayout {
        /// Button centers as distances from the window's top-left corner.
        /// Anchoring to the window rather than to the title bar's own
        /// coordinate space keeps the math correct no matter how AppKit
        /// re-lays out the views in between.
        var centersFromTopLeft: [CGPoint]
        var titleBarHeight: CGFloat
        var containerFrame: CGRect
    }

    private var defaults: DefaultLayout?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()

        guard let window else { return }
        let events: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification
        ]
        observers = events.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.applyOffset()
            }
        }

        DispatchQueue.main.async { [weak self] in self?.applyOffset() }
    }

    private func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    deinit { stopObserving() }

    private func applyOffset() {
        guard let window else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3,
              let titleBar = buttons[0].superview,
              let container = titleBar.superview
        else { return }

        let windowHeight = window.frame.height
        let isFullScreen = window.styleMask.contains(.fullScreen)

        if defaults == nil, !isFullScreen {
            defaults = DefaultLayout(
                centersFromTopLeft: buttons.map { button in
                    let inWindow = titleBar.convert(button.frame, to: nil)
                    return CGPoint(x: inWindow.midX, y: windowHeight - inWindow.midY)
                },
                titleBarHeight: titleBar.frame.height,
                containerFrame: container.frame
            )
        }
        guard let defaults else { return }

        // Full screen drops the panel chrome entirely, so hand the layout back.
        guard !isFullScreen else {
            container.frame = defaults.containerFrame
            return
        }

        // A lowered button would otherwise fall outside the title bar's
        // bounds, where it draws clipped and stops receiving clicks, so the
        // title bar has to grow to keep containing it.
        var grownContainer = defaults.containerFrame
        grownContainer.origin.y -= offset.height
        grownContainer.size.height += offset.height
        container.frame = grownContainer
        titleBar.frame = CGRect(origin: .zero, size: grownContainer.size)

        for (button, center) in zip(buttons, defaults.centersFromTopLeft) {
            let targetInWindow = CGPoint(
                x: center.x + offset.width,
                y: windowHeight - (center.y + offset.height)
            )
            let target = titleBar.convert(targetInWindow, from: nil)
            button.setFrameOrigin(
                CGPoint(x: target.x - button.frame.width / 2,
                        y: target.y - button.frame.height / 2)
            )
        }

    }
}
