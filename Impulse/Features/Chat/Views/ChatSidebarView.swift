import SwiftUI

struct ChatSidebarView: View {
    @Environment(\.colorScheme) private var colorScheme

    let projects: [StoredProject]
    let sessionsByProjectPath: [String: [StoredSession]]
    /// Sessions whose `projectPath` is empty — surfaced in the bottom
    /// "Conversations" section as project-less chats.
    let projectlessSessions: [StoredSession]
    let route: ChatRoute
    let isComposingDraft: Bool
    let selectedProjectPath: String?
    let selectedSessionID: String?
    let expandedProjectPaths: Set<String>
    var onAddProject: () -> Void
    var onBeginDraft: () -> Void
    var onAutoIntelligence: () -> Void
    var onKanban: () -> Void
    var onBeginDraftInProject: (StoredProject) -> Void
    var onToggleProject: (StoredProject) -> Void
    var onSelectProject: (StoredProject) -> Void
    var onRemoveProject: (StoredProject) -> Void
    var onSelectSession: (StoredProject?, StoredSession) -> Void
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    actionsSection
                    projectsSection
                    if !projectlessSessions.isEmpty || isComposingDraft {
                        conversationsSection
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }

            userAvatarSection
        }
    }

    // MARK: - Section 1: top actions

    private var actionsSection: some View {
        VStack(spacing: 4) {
            actionRow(
                id: "action.new_chat",
                title: "sidebar.action.new_chat",
                systemImage: "square.and.pencil",
                isActive: route == .chat && isComposingDraft,
                action: onBeginDraft
            )
            actionRow(
                id: "action.auto_intelligence",
                title: "sidebar.action.auto_intelligence",
                systemImage: "sparkles",
                isActive: route == .autoIntelligence,
                action: onAutoIntelligence
            )
            actionRow(
                id: "action.kanban",
                title: "sidebar.action.kanban",
                systemImage: "rectangle.3.group",
                isActive: route == .kanban,
                action: onKanban
            )
        }
    }

    private func actionRow(
        id: String,
        title: LocalizedStringKey,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isActive, isHovered: hoveredButtonId == id))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredButtonId = hovering ? id : nil
            }
        }
    }

    // MARK: - Section 2: projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(
                title: "sidebar.section.projects",
                trailingIcon: "folder.badge.plus",
                trailingHelp: "chat.add_project",
                trailingAction: onAddProject
            )

            if projects.isEmpty {
                Text("sidebar.section.projects.empty")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(projects) { project in
                        projectSection(project)
                    }
                }
            }
        }
    }

    // MARK: - Section 3: project-less conversations

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "sidebar.section.conversations")

            if isComposingDraft && (selectedSessionID == nil) && (selectedProjectPath == nil) {
                draftPlaceholderRow
            }

            ForEach(projectlessSessions) { session in
                conversationRow(session)
            }
        }
    }

    private var draftPlaceholderRow: some View {
        HStack(spacing: 6) {
            SessionStatusBadge(sessionID: "")
            Text("sidebar.draft.unsent")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selectedBackgroundColor)
        )
    }

    private func conversationRow(_ session: StoredSession) -> some View {
        let id = "conv::\(session.id)"
        let isSelected = session.id == selectedSessionID
        let isHovered = hoveredButtonId == id

        return Button {
            onSelectSession(nil, session)
        } label: {
            HStack(spacing: 6) {
                SessionStatusBadge(sessionID: session.id)
                Text(previewText(for: session.title))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredButtonId = hovering ? id : nil
            }
        }
        .contextMenu {
            Button("common.rename", systemImage: "pencil") { onRenameSession(session) }
            Button("common.delete", systemImage: "trash", role: .destructive) { onDeleteSession(session) }
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(
        title: LocalizedStringKey,
        trailingIcon: String? = nil,
        trailingHelp: LocalizedStringKey? = nil,
        trailingAction: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.none)
            Spacer()
            if let trailingIcon, let trailingAction {
                Button(action: trailingAction) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(trailingHelp ?? "")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Project row + nested sessions

    private func projectSection(_ project: StoredProject) -> some View {
        let isSelected = project.path == selectedProjectPath && selectedSessionID == nil && !isComposingDraft
        let isHovered = hoveredButtonId == project.path
        let isExpanded = expandedProjectPaths.contains(project.path)
        let showsCreateSessionButton = isHovered || isSelected
        let sessions = sessionsByProjectPath[project.path] ?? []

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Button {
                    onToggleProject(project)
                    onSelectProject(project)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        Text(project.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onBeginDraftInProject(project)
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
                .padding(.horizontal, 12)
                .help("chat.start_session")
                .opacity(showsCreateSessionButton ? 1 : 0)
                .allowsHitTesting(showsCreateSessionButton)
                .accessibilityHidden(!showsCreateSessionButton)

                if project.isMissing {
                    Text("chat.project_missing")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.trailing, 12)
                }
            }
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
                    if isComposingDraft && selectedProjectPath == project.path && selectedSessionID == nil {
                        draftPlaceholderRow
                    }

                    if sessions.isEmpty && !(isComposingDraft && selectedProjectPath == project.path) {
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
                                    SessionStatusBadge(sessionID: session.id)
                                    Text(previewText(for: session.title))
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundColor(.primary)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - User avatar footer

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
            .popover(isPresented: $showUserPopover, arrowEdge: .top) {
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

/// Live-pulse indicator shown to the left of a session title while its
/// `SessionAgent` is producing a response. Reserves a fixed 10pt slot so
/// titles don't shift horizontally when a task starts or stops.
private struct SessionStatusBadge: View {
    let sessionID: String
    @ObservedObject private var pool = AgentManager.shared.pool

    var body: some View {
        ZStack {
            if !sessionID.isEmpty, let sessionAgent = pool.sessionAgents[sessionID] {
                SessionLivePulse(sessionAgent: sessionAgent)
            }
        }
        .frame(width: 10, height: 10)
    }
}

private struct SessionLivePulse: View {
    @ObservedObject var sessionAgent: SessionAgent
    @State private var rotation: Double = 0

    private let segmentCount = 8

    var body: some View {
        if sessionAgent.isResponding {
            ZStack {
                ForEach(0..<segmentCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 1.5, height: 3)
                        .offset(y: -3.5)
                        .opacity(0.18 + 0.72 * Double(i) / Double(segmentCount - 1))
                        .rotationEffect(.degrees(Double(i) / Double(segmentCount) * 360))
                }
            }
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}
