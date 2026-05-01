import SwiftUI

struct ChatSidebarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let projects: [StoredProject]
    /// Sessions for each project, indexed by project path. Pre-grouped by
    /// the parent so the sidebar doesn't have to re-filter.
    let sessionsByProjectPath: [String: [StoredSession]]
    let selectedProjectPath: String?
    let selectedSessionID: String?
    let expandedProjectPaths: Set<String>
    var onAddProject: () -> Void
    var onCreateSession: (StoredProject) -> Void
    var onToggleProject: (StoredProject) -> Void
    var onSelectProject: (StoredProject) -> Void
    var onRemoveProject: (StoredProject) -> Void
    var onSelectSession: (StoredProject, StoredSession) -> Void
    var onRenameSession: (StoredSession) -> Void
    var onDeleteSession: (StoredSession) -> Void
    var onSettings: () -> Void
    var onHelp: () -> Void
    var accountName: String
    var accountSubtitle: LocalizedStringKey
    var accountInitial: String
    var accountAvatarURL: URL?
    var onLogout: () -> Void

    @State private var hoveredButtonId: String?
    @State private var showUserPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButtons

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(projects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }

            userAvatarSection
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            sidebarActionButton(
                id: "add_project",
                title: "chat.add_project",
                systemImage: "folder.badge.plus",
                enabled: true,
                action: onAddProject
            )
        }
        .padding(.top, 12)
    }

    private func projectSection(_ project: StoredProject) -> some View {
        let isSelected = project.path == selectedProjectPath && selectedSessionID == nil
        let isHovered = hoveredButtonId == project.path
        let isExpanded = expandedProjectPaths.contains(project.path)
        let showsCreateSessionButton = isHovered || isSelected
        let sessions = sessionsByProjectPath[project.path] ?? []

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    onToggleProject(project)
                    onSelectProject(project)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .foregroundColor(.primary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onCreateSession(project)
                } label: {
                    Label("chat.new_session", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .background(newSessionButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("chat.start_session")
                .opacity(showsCreateSessionButton ? 1 : 0)
                .allowsHitTesting(showsCreateSessionButton)
                .accessibilityHidden(!showsCreateSessionButton)

                if project.isMissing {
                    Text("chat.project_missing")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(projectBackgroundColor(isSelected: isSelected, isHovered: isHovered))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredButtonId = hovering ? project.path : nil
                }
            }
            .contextMenu {
                Button("chat.remove_project", systemImage: "trash", role: .destructive) {
                    onRemoveProject(project)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if sessions.isEmpty {
                        Text("chat.no_sessions")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(sessions) { session in
                            Button {
                                onSelectSession(project, session)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(previewText(for: session.title))
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundColor(.primary)
                                    Spacer(minLength: 0)
                                    SessionStatusBadge(sessionID: session.id)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 14)
                            }
                            .buttonStyle(
                                SidebarRowButtonStyle(
                                    isSelected: project.path == selectedProjectPath && session.id == selectedSessionID,
                                    isHovered: hoveredButtonId == "\(project.path)::\(session.id)"
                                )
                            )
                            .onHover { isHovered in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredButtonId = isHovered ? "\(project.path)::\(session.id)" : nil
                                }
                            }
                            .contextMenu {
                                Button("common.rename", systemImage: "pencil") {
                                    onRenameSession(session)
                                }
                                Button("common.delete", systemImage: "trash", role: .destructive) {
                                    onDeleteSession(session)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sidebarActionButton(
        id: String,
        title: LocalizedStringKey,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(enabled ? .primary : .secondary)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!enabled)
        .buttonStyle(SidebarRowButtonStyle(isSelected: false, isHovered: hoveredButtonId == id))
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredButtonId = isHovered ? id : nil
            }
        }
    }

    private var userAvatarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    showUserPopover.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    avatarView
                        .frame(width: 32, height: 32)

                    Text(accountName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hoveredButtonId == "user_avatar" ? hoverBackgroundColor : Color.clear)
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
                    accountName: accountName,
                    accountSubtitle: accountSubtitle,
                    accountInitial: accountInitial,
                    accountAvatarURL: accountAvatarURL,
                    onSettings: onSettings,
                    onHelp: onHelp,
                    onLogout: onLogout
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = accountAvatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    avatarFallback
                @unknown default:
                    avatarFallback
                }
            }
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay {
                Text(accountInitial)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
    }

    private func previewText(for text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? L10n.tr("chat.empty_session") : singleLine
    }

    private func projectBackgroundColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return selectedBackgroundColor
        } else if isHovered {
            return hoverBackgroundColor
        }
        return Color.clear
    }

    private var hoverBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.04)
    }

    private var selectedBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.085) : Color.black.opacity(0.06)
    }

    private var newSessionButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.6)
    }
}

struct SidebarRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

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
            return colorScheme == .dark ? Color.white.opacity(0.085) : Color.black.opacity(0.06)
        } else if isHovered {
            return colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.04)
        }
        return Color.clear
    }
}

/// Tiny dot/spinner shown next to a session row when its SessionAgent
/// is currently producing a response. Looks up the agent on every render
/// (cheap dictionary lookup) so it reflects state for *all* parallel sessions,
/// not just the focused one.
private struct SessionStatusBadge: View {
    let sessionID: String
    @ObservedObject private var manager = AgentManager.shared

    var body: some View {
        if let sessionAgent = manager.sessionAgents[sessionID], sessionAgent.isResponding {
            ResponsiveSessionDot(sessionAgent: sessionAgent)
        }
    }
}

private struct ResponsiveSessionDot: View {
    @ObservedObject var sessionAgent: SessionAgent

    var body: some View {
        if sessionAgent.isResponding {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .opacity(0.85)
                .transition(.opacity)
        }
    }
}
