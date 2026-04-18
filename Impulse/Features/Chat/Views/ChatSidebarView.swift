import SwiftUI

struct ChatSidebarView: View {
    let conversations: [ConversationThread]
    let selectedID: String?
    var onNewChat: () -> Void
    var onSelect: (ConversationThread) -> Void
    var onRename: (ConversationThread) -> Void
    var onDelete: (ConversationThread) -> Void
    var onSettings: () -> Void
    var onHelp: () -> Void
    var onLogout: () -> Void

    @State private var hoveredButtonId: String?
    @State private var showUserPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onNewChat) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarRowButtonStyle(isSelected: false, isHovered: hoveredButtonId == "new_chat"))
            .onHover { isHovered in
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredButtonId = isHovered ? "new_chat" : nil
                }
            }
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if conversations.isEmpty {
                        EmptyView()
                    } else {
                        ForEach(conversations) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                Text(previewText(for: conversation.title))
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SidebarRowButtonStyle(
                                isSelected: conversation.id == selectedID,
                                isHovered: hoveredButtonId == conversation.id
                            ))
                            .onHover { isHovered in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredButtonId = isHovered ? conversation.id : nil
                                }
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") {
                                    onRename(conversation)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    onDelete(conversation)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }

            userAvatarSection
        }
    }

    private var userAvatarSection: some View {
        Button {
            showUserPopover.toggle()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text("G")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }

                Text("Guest")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hoveredButtonId == "user_avatar" ? Color.white.opacity(0.4) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredButtonId = hovering ? "user_avatar" : nil
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .popover(isPresented: $showUserPopover, arrowEdge: .bottom) {
            UserAccountPopover(
                isPresented: $showUserPopover,
                onSettings: onSettings,
                onHelp: onHelp,
                onLogout: onLogout
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func previewText(for text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.isEmpty { return "(empty)" }
        return singleLine
    }
}

struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor())
            )
    }
    
    private func backgroundColor() -> Color {
        if isSelected {
            return Color.white.opacity(0.55)
        } else if isHovered {
            return Color.white.opacity(0.6)
        }
        return Color.clear
    }
}
