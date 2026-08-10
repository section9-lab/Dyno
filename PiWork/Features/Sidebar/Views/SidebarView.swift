import AppKit
import SwiftUI

/// Left sidebar: a segmented tab header, and — depending on which tab is
/// selected — either the "Chat" conversation-history list or the "Work"
/// folder workspace (nav placeholders + linked project folders), plus a
/// bottom-anchored account row. Layout mirrors the reference design.
///
/// The scrollable/selectable portion is a real system sidebar list
/// (`List(selection:)` + `.listStyle(.sidebar)`), not a hand-rolled
/// `ScrollView`/`VStack` — this gets keyboard navigation, hover states, and
/// accessibility for free from AppKit, while row content still renders our
/// own custom look via `.listRowBackground(Color.clear)` +
/// `.listRowInsets(EdgeInsets())`.

/// Which of the two sidebar surfaces is currently shown below the tab
/// header. `.chat` is project-free conversation; `.work` adds linked-folder
/// selection and project tools.
enum SidebarTab: Int, Hashable {
    case chat = 0
    case work = 1

    var showsProjectSelection: Bool { self == .work }
}

enum SidebarCustomDestination: Hashable {
    case schedule
    case skills
    case connectedApps

    var title: String {
        switch self {
        case .schedule: return L10n.string("sidebar.schedule")
        case .skills: return L10n.string("sidebar.skills")
        case .connectedApps: return L10n.string("sidebar.extensions")
        }
    }

    var icon: String {
        switch self {
        case .schedule: return "clock"
        case .skills: return "doc.text"
        case .connectedApps: return "puzzlepiece.extension"
        }
    }
}

struct SidebarView: View {
    @ObservedObject var projectStore: ProjectStore
    @Binding var selectedProject: PiProject?
    @Binding var selectedTab: SidebarTab
    var onAddFolder: () -> Void
    var onNewSession: () -> Void
    var onNewProjectSession: (PiProject) -> Void
    var chatSessions: [AgentHostSessionSummary] = []
    var selectedChatSessionId: String?
    var onSelectChatSession: (AgentHostSessionSummary) -> Void = { _ in }
    var onDeleteChatSession: (AgentHostSessionSummary) -> Void = { _ in }
    var workSessionsByProjectPath: [String: [AgentHostSessionSummary]] = [:]
    var activeSessionIDs: Set<String> = []
    var selectedWorkSidebarItem: WorkSidebarItem? = nil
    var onSelectWorkSession: (PiProject, AgentHostSessionSummary) -> Void = { _, _ in }
    var onDeleteWorkSession: (PiProject, AgentHostSessionSummary) -> Void = { _, _ in }
    var onDeleteWorkProject: (PiProject) -> Void = { _ in }
    var onSelectCustomDestination: (SidebarCustomDestination?) -> Void = { _ in }

    @State private var selectedCustomDestination: SidebarCustomDestination?
    @State private var projectDisclosureState = ProjectDisclosureState()

    var body: some View {
        VStack(spacing: 0) {
            SidebarTabHeader(selectedTab: $selectedTab)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .compositingGroup()

            switch selectedTab {
            case .chat:
                List(selection: $selectedProject) {
                    Section {
                        NavRow(
                            icon: "square.and.pencil",
                            title: L10n.string("sidebar.new"),
                            isSelected: false
                        ) {
                            selectedCustomDestination = nil
                            onSelectCustomDestination(nil)
                            onNewSession()
                        }
                    }

                    Section {
                        ForEach(chatSessions) { session in
                            ChatSessionRow(
                                session: session,
                                isSelected: selectedChatSessionId == session.id,
                                action: {
                                    selectedProject = nil
                                    selectedCustomDestination = nil
                                    onSelectCustomDestination(nil)
                                    onSelectChatSession(session)
                                },
                                onDelete: { onDeleteChatSession(session) }
                            )
                        }
                    } header: {
                        SectionLabel(L10n.string("sidebar.history"))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(SidebarSelectionFix())

            case .work:
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        navigationRow(.schedule)
                        navigationRow(.skills)
                        navigationRow(.connectedApps)
                    }
                    .padding(.top, 8)

                    LinkedFoldersHeader(onAddFolder: onAddFolder)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 2)

                    List {
                        Section {
                            ForEach(projectStore.projects) { project in
                                let sessions = workSessionsByProjectPath[project.path] ?? []
                                let isExpanded = projectDisclosureState.isExpanded(project.id)
                                FolderRow(
                                    project: project,
                                    isSelected: selectedProject?.id == project.id
                                        && selectedWorkSidebarItem == .project(project.id),
                                    isExpanded: isExpanded,
                                    onToggle: { toggleProject(project.id) },
                                    onNewSession: {
                                        expandProject(project.id)
                                        onNewProjectSession(project)
                                    },
                                    onDelete: { onDeleteWorkProject(project) }
                                )

                                if isExpanded {
                                    if sessions.isEmpty {
                                        WorkSessionEmptyState()
                                    } else {
                                        ForEach(sessions) { session in
                                            WorkSessionRow(
                                                session: session,
                                                showsActivity: activeSessionIDs.contains(session.id),
                                                isSelected: selectedProject?.id == project.id
                                                    && selectedWorkSidebarItem == .session(
                                                        projectID: project.id,
                                                        sessionID: session.id
                                                    ),
                                                action: {
                                                    selectedCustomDestination = nil
                                                    onSelectCustomDestination(nil)
                                                    onSelectWorkSession(project, session)
                                                },
                                                onDelete: { onDeleteWorkSession(project, session) }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(SidebarSelectionFix())
                }
            }

            UserFooterView()
                .padding(.horizontal, 15)
                .padding(.top, 8)
                .padding(.bottom, 18)
                .compositingGroup()
                .frame(maxWidth: .infinity)
        }
        .onChange(of: selectedProject?.id) { projectID in
            if projectID != nil { selectedCustomDestination = nil }
        }
    }

    private func navigationRow(_ destination: SidebarCustomDestination) -> some View {
        NavRow(
            icon: destination.icon,
            title: destination.title,
            isSelected: selectedCustomDestination == destination
        ) {
            selectedProject = nil
            selectedCustomDestination = destination
            onSelectCustomDestination(destination)
        }
    }

    private func toggleProject(_ projectID: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            projectDisclosureState.toggle(projectID)
        }
    }

    private func expandProject(_ projectID: UUID) {
        guard !projectDisclosureState.isExpanded(projectID) else { return }
        toggleProject(projectID)
    }
}

// MARK: - Pieces

/// Full-width segmented control at the top of the sidebar. Switches
/// `selectedTab` between conversation history ("Chat") and the folder
/// workspace ("Work"), which drives what the `List` below shows.
private struct SidebarTabHeader: View {
    @Binding var selectedTab: SidebarTab

    var body: some View {
        HStack(spacing: 0) {
            tab(title: L10n.string("sidebar.chat"), tab: .chat)
            tab(title: L10n.string("sidebar.work"), tab: .work)
        }
        .padding(3)
        .background(AppPalette.segmentedTrack)
        .clipShape(Capsule())
    }

    private func tab(title: String, tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(isSelected ? 0.9 : 0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? AppPalette.raisedSurface : Color.clear)
                    .shadow(color: isSelected ? AppPalette.subtleShadow : .clear, radius: 2, y: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 17))
    }
}

private struct NavRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 10, isSelected: isSelected))
        .padding(.horizontal, 4)
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.42))
            .compositingGroup()
    }
}

private struct ChatSessionRow: View {
    let session: AgentHostSessionSummary
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(session.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 10, isSelected: isSelected))
        .padding(.horizontal, 4)
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("chat-session-\(session.id)")
        .sessionContextMenu(sessionID: session.id, onDelete: onDelete)
    }
}

private struct FolderRow: View {
    let project: PiProject
    let isSelected: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onNewSession: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onToggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                        .frame(width: 18)
                    Text(project.name)
                        .font(.system(size: 14))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded
                ? L10n.format("sidebar.collapse_project", project.name)
                : L10n.format("sidebar.expand_project", project.name))
            .accessibilityLabel(isExpanded
                ? L10n.format("sidebar.collapse_project", project.name)
                : L10n.format("sidebar.expand_project", project.name))
            .accessibilityIdentifier("project-disclosure-\(project.id.uuidString)")

            Button(action: onNewSession) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 7))
            .opacity(showsHoverAction ? 1 : 0)
            .allowsHitTesting(showsHoverAction)
            .help(L10n.format("sidebar.new_project_session", project.name))
            .accessibilityLabel(L10n.format("sidebar.new_project_session", project.name))
            .accessibilityIdentifier("new-session-\(project.id.uuidString)")
            .accessibilityHidden(!showsHoverAction)
            .animation(.easeOut(duration: 0.12), value: showsHoverAction)
        }
        .foregroundStyle(Color.primary.opacity(0.78))
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(
            adaptiveRoundedShape(cornerRadius: 10)
                .fill(isSelected ? AppPalette.selectedRowFill : (isHovering ? AppPalette.hoverRowFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label(L10n.string("sidebar.remove_project"), systemImage: "trash")
            }
        }
        .confirmationDialog(
            L10n.format("sidebar.remove_project_title", project.name),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.string("sidebar.remove_project_action"), role: .destructive) {
                onDelete()
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("sidebar.remove_project_message"))
        }
        .padding(.leading, 0)
        .padding(.trailing, 4)
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var showsHoverAction: Bool {
        SidebarHoverActionVisibility(isHovering: isHovering).showsAction
    }
}

private struct WorkSessionRow: View {
    let session: AgentHostSessionSummary
    let showsActivity: Bool
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(session.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsActivity {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.primary.opacity(0.55))
                        .accessibilityLabel(Text(L10n.string("chat.tool.running")))
                }
            }
            .foregroundStyle(Color.primary.opacity(0.72))
            .padding(.leading, 20)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 9, isSelected: isSelected))
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("work-session-\(session.id)")
        .sessionContextMenu(sessionID: session.id, onDelete: onDelete)
    }
}

private extension View {
    func sessionContextMenu(
        sessionID: String,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(SessionContextMenuModifier(sessionID: sessionID, onDelete: onDelete))
    }
}

private struct SessionContextMenuModifier: ViewModifier {
    let sessionID: String
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(SessionContextMenuFocusModifier())
            .contextMenu {
                Button(action: copySessionID) {
                    Label {
                        Text(L10n.string("sidebar.copy_session_id"))
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                }

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label {
                        Text(L10n.string("sidebar.delete_session"))
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
    }

    private func copySessionID() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sessionID, forType: .string)
    }
}

private struct SessionContextMenuFocusModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content.focusable(false)
        }
    }
}

private struct WorkSessionEmptyState: View {
    var body: some View {
        HStack(spacing: 0) {
            Text(L10n.string("sidebar.no_session"))
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.34))
            Spacer(minLength: 0)
        }
        .padding(.leading, 32)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("work-session-empty")
    }
}

private struct LinkedFoldersHeader: View {
    let onAddFolder: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.string("sidebar.project_folders"))
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.42))

            Spacer(minLength: 0)

            Button(action: onAddFolder) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 7))
            .opacity(showsHoverAction ? 1 : 0)
            .allowsHitTesting(showsHoverAction)
            .help(L10n.string("sidebar.add_mac_folder"))
            .accessibilityLabel(L10n.string("sidebar.add_mac_folder"))
            .accessibilityIdentifier("add-linked-folder")
            .accessibilityHidden(!showsHoverAction)
            .animation(.easeOut(duration: 0.12), value: showsHoverAction)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .compositingGroup()
    }

    private var showsHoverAction: Bool {
        SidebarHoverActionVisibility(isHovering: isHovering).showsAction
    }
}

/// Bottom-of-sidebar account row. Shows the signed-in user and opens the
/// account popover (settings / help / sign out).
private struct UserFooterView: View {
    @ObservedObject private var authSession = AuthSession.shared
    @State private var isPopoverPresented = false

    private var displayName: String {
        authSession.user?.displayName ?? "pi-work"
    }

    private var initial: String {
        authSession.user?.avatarInitial ?? "p"
    }

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                AccountAvatarImage(
                    url: authSession.user?.avatarURL,
                    fallbackInitial: initial,
                    fallbackFontSize: 15
                )
                .frame(width: 30, height: 30)
                Text(displayName)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 10))
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            UserAccountPopover(
                isPresented: $isPopoverPresented,
                accountName: displayName,
                accountSubtitle: authSession.provider.accountSubtitle,
                accountInitial: initial,
                accountAvatarURL: authSession.user?.avatarURL,
                onSettings: {
                    openLegacySettings()
                },
                onHelp: { isPopoverPresented = false },
                onLogout: {
                    isPopoverPresented = false
                    authSession.signOut()
                }
            )
        }
    }

    private func openLegacySettings() {
        let opened = NSApp.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        if !opened {
            NSApp.sendAction(
                Selector(("showPreferencesWindow:")),
                to: nil,
                from: nil
            )
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
