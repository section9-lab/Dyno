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

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
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
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            Divider()

            inputBar
        }
        .onAppear { viewModel.ensureStarted() }
        .onDisappear { viewModel.stop() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "folder.fill").foregroundStyle(.blue)
            Text(viewModel.project.name).font(.system(size: 14, weight: .semibold))
            Spacer()
            if viewModel.isAgentBusy {
                ProgressView().controlSize(.small)
            }
            Circle()
                .fill(viewModel.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("向 pi 描述你想做的事…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(10)
            }
        case .assistant:
            HStack(alignment: .top) {
                Text(message.text.isEmpty ? "…" : message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(10)
                Spacer(minLength: 40)
            }
        case .tool:
            Text(message.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        case .system:
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
