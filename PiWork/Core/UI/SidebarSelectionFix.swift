import AppKit
import SwiftUI

/// Suppresses `.listStyle(.sidebar)`'s native selection highlight so
/// `FolderRow`'s own rounded fill is the *only* highlight a selected row
/// shows. Without this, a selected row painted the system blue/gray
/// sidebar highlight edge-to-edge underneath `FolderRow`'s rounded, inset
/// fill — two conflicting highlights stacked on top of each other.
///
/// This attaches an invisible probe view via `.background()`, searches
/// down from the window for the List's backing `NSOutlineView` once it
/// exists, and turns off `selectionHighlightStyle`. It does not touch
/// `allowsEmptySelection` or the outline view's selection state — this is
/// a pure rendering change, so it can't affect click-to-select behavior.
struct SidebarSelectionFix: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        private var didConfigure = false
        private var attemptsRemaining = 20

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            didConfigure = false
            attemptsRemaining = 20
            configureIfNeeded()
        }

        func configureIfNeeded() {
            guard !didConfigure, let window else { return }
            guard let outlineView = Self.findOutlineView(in: window.contentView) else {
                // The List's AppKit backing may not exist yet on the very
                // first pass; retry briefly rather than giving up.
                attemptsRemaining -= 1
                guard attemptsRemaining > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.configureIfNeeded()
                }
                return
            }
            didConfigure = true
            outlineView.selectionHighlightStyle = .none
        }

        private static func findOutlineView(in view: NSView?) -> NSOutlineView? {
            guard let view else { return nil }
            if let outlineView = view as? NSOutlineView { return outlineView }
            for subview in view.subviews {
                if let found = findOutlineView(in: subview) { return found }
            }
            return nil
        }
    }
}
