import AppKit
import SwiftUI

/// Multi-line message text input wrapped over `NSTextView`. Auto-grows up to
/// `maximumHeight`, then scrolls. Submits on Enter (Shift+Enter inserts a
/// newline), respects IME composition (won't submit while marked text is
/// active), reports `hasMarkedText` so the parent can hide its placeholder.
///
/// Pulled out of `InputBar` so the AppKit interop lives in one focused file.
struct MultilineMessageInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat

    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let canSubmit: Bool
    let onSubmit: () -> Void
    @Binding var hasMarkedText: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = MessageTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = {
            if canSubmit {
                onSubmit()
            }
        }
        textView.onMarkedTextChange = { marked in
            DispatchQueue.main.async {
                if hasMarkedText != marked {
                    hasMarkedText = marked
                }
            }
        }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MessageTextView else { return }

        context.coordinator.parent = self
        textView.onSubmit = {
            if canSubmit {
                onSubmit()
            }
        }
        textView.onMarkedTextChange = { marked in
            DispatchQueue.main.async {
                if hasMarkedText != marked {
                    hasMarkedText = marked
                }
            }
        }

        if textView.string != text {
            textView.string = text
        }

        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineMessageInput
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(parent: MultilineMessageInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func updateHeight() {
            guard let textView, let scrollView else { return }

            let fittingWidth = max(scrollView.contentSize.width, 1)
            textView.textContainer?.containerSize = NSSize(
                width: fittingWidth,
                height: .greatestFiniteMagnitude
            )
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
            let measuredHeight = ceil(usedRect.height + textView.textContainerInset.height * 2)
            let nextHeight = min(max(measuredHeight, parent.minimumHeight), parent.maximumHeight)

            scrollView.hasVerticalScroller = measuredHeight > parent.maximumHeight
            textView.frame.size = NSSize(
                width: fittingWidth, height: max(measuredHeight, nextHeight))

            if abs(parent.height - nextHeight) > 0.5 {
                parent.height = nextHeight
            }
        }
    }
}

/// `NSTextView` subclass that surfaces submit-on-Enter and IME composition
/// state to the SwiftUI parent. File-private; only `MultilineMessageInput`
/// touches it.
private final class MessageTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onMarkedTextChange: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            // Don't intercept Enter while an IME composition is active —
            // the input method needs it to commit/select candidates.
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            if event.modifierFlags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(self)
            } else {
                onSubmit?()
            }
            return
        }

        super.keyDown(with: event)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onMarkedTextChange?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChange?(false)
    }
}
