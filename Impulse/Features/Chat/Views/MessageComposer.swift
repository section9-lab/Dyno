import AppKit
import SwiftUI

/// Multi-line message text input wrapped over `NSTextView`. Auto-grows up to
/// `maximumHeight`, then scrolls. Submits on Enter (Shift+Enter inserts a
/// newline), respects IME composition (won't submit while marked text is
/// active), reports `hasMarkedText` so the parent can hide its placeholder.
///
/// Up / Down arrows recall previous user messages when the cursor is at the
/// first / last line — same model as a shell history. The list comes from
/// `historyProvider`, expected to be sorted most-recent first; the closure
/// is invoked lazily so the parent can recompute every render without paying
/// allocation cost when the user isn't browsing.
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
    var historyProvider: () -> [String] = { [] }

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
        textView.historyProvider = historyProvider
        textView.onProgrammaticTextChange = { newValue in
            DispatchQueue.main.async {
                if context.coordinator.parent.text != newValue {
                    context.coordinator.parent.text = newValue
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
        textView.historyProvider = historyProvider
        textView.onProgrammaticTextChange = { newValue in
            DispatchQueue.main.async {
                if context.coordinator.parent.text != newValue {
                    context.coordinator.parent.text = newValue
                }
            }
        }

        // Don't sync `text` into `textView.string` while the user is in the
        // middle of an IME composition — assigning .string clears marked
        // text and the user loses the in-flight character.
        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
            // SwiftUI just cleared the field (e.g. after submit) — reset
            // history-browse state so the next ↑ starts from the freshly
            // appended message rather than continuing an old browse.
            if text.isEmpty {
                textView.resetHistoryBrowsing()
            }
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

/// `NSTextView` subclass that surfaces submit-on-Enter, IME composition
/// state, and shell-style ↑/↓ history recall to the SwiftUI parent.
/// File-private; only `MultilineMessageInput` touches it.
private final class MessageTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onMarkedTextChange: ((Bool) -> Void)?
    var historyProvider: () -> [String] = { [] }
    /// Fired when this view rewrites `string` itself (e.g. recalling a prior
    /// message via ↑). The SwiftUI binding doesn't observe direct
    /// `NSTextView.string` mutations, so the wrapper installs this callback
    /// to mirror the change back into `@Binding var text`.
    var onProgrammaticTextChange: ((String) -> Void)?

    /// `-1` = not browsing; `0...` = index into the most-recent-first
    /// history list returned by `historyProvider`. Reset on any direct user
    /// edit (typing / deletion / submit) so a fresh ↑ press always starts
    /// from "the last message I sent" rather than continuing an old walk.
    private var historyIndex: Int = -1
    /// What the input held when the user first pressed ↑ — restored if they
    /// ↓-walk all the way back to the present.
    private var savedDraft: String = ""

    /// Drop history-browsing state. Called when the parent clears `text`
    /// (post-submit), or internally when the user types and diverges.
    func resetHistoryBrowsing() {
        historyIndex = -1
        savedDraft = ""
    }

    override func keyDown(with event: NSEvent) {
        // Don't intercept anything during IME composition — input methods
        // own Enter/arrow keys for candidate selection and committal.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        // Enter = submit (Shift+Enter = newline).
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(self)
            } else {
                resetHistoryBrowsing()
                onSubmit?()
            }
            return
        }

        // ↑ — recall older message when at top of input.
        if event.keyCode == 126, shouldInterceptHistoryUp() {
            stepHistory(by: +1)
            return
        }

        // ↓ — recall newer message (only while already browsing, so a
        //     bottom-line ↓ in a multi-line draft still moves the caret).
        if event.keyCode == 125, historyIndex >= 0 {
            stepHistory(by: -1)
            return
        }

        super.keyDown(with: event)
    }

    /// Once the user types a character, we abandon the history walk. The
    /// recalled text stays as the new draft; further ↑ presses restart the
    /// walk from the most recent message.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if historyIndex >= 0 {
            historyIndex = -1
            savedDraft = ""
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Same reasoning as `insertText` — deletion edits the recalled message.
    override func deleteBackward(_ sender: Any?) {
        if historyIndex >= 0 {
            historyIndex = -1
            savedDraft = ""
        }
        super.deleteBackward(sender)
    }

    private func shouldInterceptHistoryUp() -> Bool {
        // Already browsing — stay in the walk regardless of caret position.
        if historyIndex >= 0 { return true }
        // Not browsing yet — only intercept when the caret is on the first
        // line. This preserves normal ↑ caret-up behaviour mid-message.
        let selection = selectedRange()
        if selection.location == 0 { return true }
        let prefix = (string as NSString).substring(to: selection.location)
        return !prefix.contains("\n")
    }

    private func stepHistory(by direction: Int) {
        let history = historyProvider()
        guard !history.isEmpty else { return }

        if historyIndex < 0 {
            // Starting a fresh walk — remember whatever the user had typed
            // so ↓-back-to-present restores it.
            savedDraft = string
        }

        let nextIndex: Int = {
            if direction > 0 {
                return min(historyIndex + 1, history.count - 1)
            } else {
                return historyIndex - 1
            }
        }()

        let nextText: String
        if nextIndex < 0 {
            nextText = savedDraft
        } else {
            nextText = history[nextIndex]
        }

        historyIndex = nextIndex
        replaceTextProgrammatically(with: nextText)
    }

    private func replaceTextProgrammatically(with newText: String) {
        string = newText
        let end = (string as NSString).length
        setSelectedRange(NSRange(location: end, length: 0))
        // `string =` does not post `NSText.didChangeNotification`, so the
        // SwiftUI binding never sees the recalled text. Notify explicitly
        // via the wrapper-installed callback.
        onProgrammaticTextChange?(newText)
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
