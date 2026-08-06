import SwiftUI

/// Transcript + input box for one `StoredSession`. Purely local: entries are
/// never sent to a model or anywhere else — this is a project-scoped
/// scratchpad/journal, not an AI chat.
struct SessionDetailView: View {
    let session: StoredSession
    let entries: [StoredSessionEntry]
    var onSend: (String) -> Void
    var onDeleteEntry: (StoredSessionEntry) -> Void

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    private var sortedEntries: [StoredSessionEntry] {
        entries.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            inputBar
        }
        .background(.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(session.createdAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if sortedEntries.isEmpty {
                        emptyState
                    } else {
                        ForEach(sortedEntries, id: \.id) { entry in
                            entryRow(entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: sortedEntries.count) { _ in
                scrollToBottom(proxy)
            }
            .onAppear {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = sortedEntries.last?.id else { return }
        withAnimation {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary)
            Text("session.empty")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func entryRow(_ entry: StoredSessionEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.content)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.createdAt, style: .time)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .contextMenu {
            Button(role: .destructive) {
                onDeleteEntry(entry)
            } label: {
                Label("common.delete", systemImage: "trash")
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("session.entry.placeholder", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(10)
                .focused($inputFocused)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        draft = ""
        inputFocused = true
    }
}
