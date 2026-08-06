import SwiftUI

/// The active chat/session pane for a selected project: scrolling
/// transcript driven by `PiChatViewModel` (which in turn drives a real
/// `pi --mode rpc` subprocess), plus an input bar at the bottom.
struct ChatView: View {
    @StateObject private var viewModel: PiChatViewModel
    @State private var draft = ""

    init(project: PiProject) {
        _viewModel = StateObject(wrappedValue: PiChatViewModel(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
            }

            inputBar
                .frame(maxWidth: 720)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .onAppear { viewModel.ensureStarted() }
        .onDisappear { viewModel.stop() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.65))
            Text(viewModel.project.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))

            if viewModel.isAgentBusy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        // Clears the floating sidebar-toggle / Beta badge row above.
        .padding(.top, 58)
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 0) {
            TextField("向 pi 描述你想做的事…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...6)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.primary.opacity(0.25)
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
    }

    private func send() {
        let text = draft
        draft = ""
        viewModel.send(text)
    }
}

private struct ChatMessageRow: View {
    let message: PiChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            }
        case .assistant:
            HStack(alignment: .top) {
                Text(message.text.isEmpty ? "…" : message.text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                Spacer(minLength: 60)
            }
        case .tool:
            Text(message.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.5))
        case .system:
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.5))
        }
    }
}
