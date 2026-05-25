import SwiftUI

/// Native SwiftUI multi-line message input.
///
/// This intentionally avoids `NSViewRepresentable`/`NSTextView` so focus stays
/// in SwiftUI's ownership when sibling controls, popovers, or model changes
/// cause the input bar to re-render.
struct MultilineMessageInput: View {
    @Binding var text: String

    let canSubmit: Bool
    let onSubmit: () -> Void
    let focusRequest: Int
    var historyProvider: () -> [String] = { [] }

    @FocusState private var isFocused: Bool
    @State private var lastFocusRequest: Int = 0
    @State private var historyIndex: Int = -1
    @State private var savedDraft: String = ""
    @State private var isApplyingHistory = false

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular))
            .foregroundColor(.primary)
            .lineLimit(1...6)
            .submitLabel(.send)
            .focused($isFocused)
            .onSubmit {
                guard canSubmit else { return }
                resetHistoryBrowsing()
                onSubmit()
            }
            .onMoveCommand(perform: handleMoveCommand)
            .onChange(of: text) { _, newValue in
                guard !isApplyingHistory else { return }
                if historyIndex >= 0 {
                    resetHistoryBrowsing()
                }
                if newValue.isEmpty {
                    resetHistoryBrowsing()
                }
            }
            .onChange(of: focusRequest) { _, newValue in
                guard lastFocusRequest != newValue else { return }
                lastFocusRequest = newValue
                isFocused = true
            }
            .onAppear {
                lastFocusRequest = focusRequest
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard isFocused else { return }

        switch direction {
        case .up:
            guard text.isEmpty || historyIndex >= 0 else { return }
            stepHistory(by: +1)
        case .down:
            guard historyIndex >= 0 else { return }
            stepHistory(by: -1)
        default:
            break
        }
    }

    private func stepHistory(by direction: Int) {
        let history = historyProvider()
        guard !history.isEmpty else { return }

        if historyIndex < 0 {
            savedDraft = text
        }

        let nextIndex: Int
        if direction > 0 {
            nextIndex = min(historyIndex + 1, history.count - 1)
        } else {
            nextIndex = historyIndex - 1
        }

        let nextText = nextIndex < 0 ? savedDraft : history[nextIndex]
        historyIndex = nextIndex

        isApplyingHistory = true
        text = nextText
        isApplyingHistory = false
    }

    private func resetHistoryBrowsing() {
        historyIndex = -1
        savedDraft = ""
    }
}
