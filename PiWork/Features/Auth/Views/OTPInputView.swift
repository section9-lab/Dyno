import SwiftUI
import AppKit
import PiWorkCore

/// 6-digit one-time-code input with the standard "boxes that auto-advance"
/// behavior. Pasting a 6-digit string anywhere in the row fills the whole
/// thing in one go; backspace on an empty box jumps back to the previous
/// one. `onComplete` fires the moment the row holds 6 digits so the host
/// view can submit without an explicit button press if it wants.
struct OTPInputView: View {
    @Binding var code: String
    let length: Int
    var onComplete: ((String) -> Void)?

    @FocusState private var focusedIndex: Int?
    @Environment(\.colorScheme) private var colorScheme

    init(code: Binding<String>, length: Int = 6, onComplete: ((String) -> Void)? = nil) {
        self._code = code
        self.length = length
        self.onComplete = onComplete
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<length, id: \.self) { index in
                digitField(index: index)
            }
        }
        .onAppear {
            focusedIndex = code.count < length ? code.count : length - 1
        }
    }

    @ViewBuilder
    private func digitField(index: Int) -> some View {
        let digit = digit(at: index)
        let isFocused = focusedIndex == index

        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isFocused ? Color.accentColor.opacity(0.7) : fieldBorder,
                                lineWidth: isFocused ? 1.5 : 1)
                )
                .frame(width: 44, height: 52)

            // A hidden text field captures input. Keystrokes are translated
            // into the shared `code` string so ⌘V (which delivers the whole
            // 6-digit blob into one field) still distributes correctly.
            OTPSingleField(
                text: Binding(
                    get: { digit },
                    set: { newValue in handleInput(newValue, at: index) }
                ),
                isFocused: $focusedIndex,
                index: index,
                onBackspace: { handleBackspace(at: index) },
                onSubmit: { handleSubmit() }
            )
            .frame(width: 44, height: 52)
        }
        .onTapGesture {
            focusedIndex = index
        }
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.92)
    }

    private var fieldBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }

    private func handleInput(_ raw: String, at index: Int) {
        let result = OTPInputProcessor.applyInput(raw, to: code, at: index, length: length)
        code = result.code
        focusedIndex = result.focusedIndex
        if result.isComplete { onComplete?(code) }
    }

    private func handleBackspace(at index: Int) {
        let result = OTPInputProcessor.applyBackspace(to: code, at: index)
        code = result.code
        focusedIndex = result.focusedIndex
    }

    private func handleSubmit() {
        if code.count == length { onComplete?(code) }
    }
}

/// AppKit-backed single-character field. The native NSTextField gives us
/// reliable keyDown handling for backspace on an empty box and Cmd+V paste
/// of multi-digit strings — both awkward to do with vanilla SwiftUI
/// `TextField` plus `onChange`.
private struct OTPSingleField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Int?>.Binding
    let index: Int
    var onBackspace: () -> Void
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = OTPTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .center
        field.font = .systemFont(ofSize: 22, weight: .semibold)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.onBackspaceWhenEmpty = { onBackspace() }
        field.onCommandReturn = { onSubmit() }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused.wrappedValue == index {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder !== nsView.currentEditor() {
                    nsView.window?.makeFirstResponder(nsView)
                    if let editor = nsView.currentEditor() as? NSTextView {
                        editor.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: OTPSingleField

        init(_ parent: OTPSingleField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

private final class OTPTextField: NSTextField {
    var onBackspaceWhenEmpty: (() -> Void)?
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 51 = delete (backspace). When the field is empty we want the
        // parent to jump focus back rather than swallowing the keystroke.
        if event.keyCode == 51 && stringValue.isEmpty {
            onBackspaceWhenEmpty?()
            return
        }
        super.keyDown(with: event)
    }
}
