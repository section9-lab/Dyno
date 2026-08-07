import AppKit
import SwiftUI

/// Nudges the window's traffic lights inward so they sit inside the floating
/// sidebar panel instead of hugging the window's own corner.
///
/// There is no SwiftUI API for this. The buttons are plain `NSButton`s that
/// AppKit lays out inside the title bar, and it re-runs that layout whenever
/// the window resizes or leaves full screen, so the offset has to be
/// re-applied rather than set once.
///
/// The nudge is deliberately kept inside the title bar's existing bounds. A
/// button pushed past them draws clipped and stops receiving clicks, and
/// resizing the title bar to make room costs the window its full-size content
/// layout — AppKit then shrinks the content view away from the top edge,
/// leaving a transparent strip across the window. So the offset is clamped
/// instead, and `maximumOffset` reports the ceiling.
struct TrafficLightPositioner: NSViewRepresentable {
    /// How far to move the buttons right and down from AppKit's own layout.
    /// Clamped to whatever the title bar can actually contain.
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

    /// AppKit's own origins, captured before the first nudge so repeated
    /// applications stay absolute instead of compounding.
    private var defaultOrigins: [CGPoint] = []
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
        guard buttons.count == 3, let titleBar = buttons[0].superview else { return }

        let isFullScreen = window.styleMask.contains(.fullScreen)

        if defaultOrigins.count != buttons.count, !isFullScreen {
            defaultOrigins = buttons.map { $0.frame.origin }
        }
        guard defaultOrigins.count == buttons.count else { return }

        // Full screen drops the panel chrome entirely, so hand the layout back.
        let requested = isFullScreen ? .zero : offset

        // The title bar's coordinates are bottom-up, so moving a button down
        // eats into the gap below it — that gap is the whole budget.
        let headroom = zip(buttons, defaultOrigins).reduce(CGSize(width: CGFloat.infinity, height: CGFloat.infinity)) { limit, pair in
            let (button, origin) = pair
            return CGSize(
                width: min(limit.width, titleBar.bounds.maxX - (origin.x + button.frame.width)),
                height: min(limit.height, origin.y)
            )
        }
        let delta = CGSize(
            width: max(0, min(requested.width, headroom.width)),
            height: max(0, min(requested.height, headroom.height))
        )

        for (button, origin) in zip(buttons, defaultOrigins) {
            button.setFrameOrigin(CGPoint(x: origin.x + delta.width, y: origin.y - delta.height))
        }
    }
}
