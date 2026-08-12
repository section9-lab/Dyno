import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var sessionStore: SessionStore
    @ObservedObject private var installedExtensionsStore: InstalledExtensionsStore
    @ObservedObject private var scheduleStore: ScheduleStore
    private let scheduleRunner: ScheduleRunner
    @StateObject private var projectStore = ProjectStore()
    @State private var workSession = WorkSessionSelection()
    @State private var selectedTab: SidebarTab = .work
    @State private var selectedCustomDestination: SidebarCustomDestination?
    @StateObject private var skillsCatalogStore = SkillsCatalogStore()
    @StateObject private var extensionsCatalogStore = ExtensionsCatalogStore()
    @State private var sidebarCollapsed = false
    @State private var didBootstrapChat = false
    @State private var bootstrappedWorkProjectPaths: Set<String> = []
    @State private var sessionOpeningState = SessionOpeningState()
    @State private var sessionOpenTask: Task<Void, Never>?
    @State private var agentError: String?

    init(
        sessionStore: SessionStore,
        installedExtensionsStore: InstalledExtensionsStore,
        scheduleStore: ScheduleStore,
        scheduleRunner: ScheduleRunner
    ) {
        _sessionStore = ObservedObject(wrappedValue: sessionStore)
        _installedExtensionsStore = ObservedObject(wrappedValue: installedExtensionsStore)
        _scheduleStore = ObservedObject(wrappedValue: scheduleStore)
        self.scheduleRunner = scheduleRunner
    }

    var body: some View {
        ZStack {
            AppBackgroundGradient()

            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    SidebarPanel {
                        SidebarView(
                            projectStore: projectStore,
                            selectedProject: $workSession.selectedProject,
                            selectedTab: selectedTabBinding,
                            onAddFolder: pickFolder,
                            onNewSession: startNewSession,
                            onNewProjectSession: startNewSession(for:),
                            chatSessions: sessionStore.chatSessions,
                            selectedChatSessionId: sessionStore.selectedChatSessionId,
                            pendingChatSessionId: sessionOpeningState.pendingChatSessionID,
                            onSelectChatSession: openChatSession,
                            onDeleteChatSession: deleteChatSession,
                            workSessionsByProjectPath: sessionStore.workSessionsByProjectPath,
                            activeSessionIDs: activeSessionIDs,
                            selectedWorkSidebarItem: workSession.sidebarItem,
                            pendingWorkSidebarItem: sessionOpeningState.pendingWorkSidebarItem,
                            onSelectWorkSession: openWorkSession,
                            onDeleteWorkSession: deleteWorkSession,
                            onDeleteWorkProject: deleteWorkProject,
                            onSelectCustomDestination: {
                                if $0 != nil { cancelSessionOpening() }
                                selectedCustomDestination = $0
                            }
                        )
                    }
                    .transition(.move(edge: .leading))
                }

                ZStack(alignment: .top) {
                    Group {
                        if selectedTab == .work, selectedCustomDestination == .schedule {
                            ScheduleView(
                                store: scheduleStore,
                                runner: scheduleRunner,
                                projects: projectStore.projects
                            )
                        } else if selectedTab == .work, selectedCustomDestination == .skills {
                            SkillsCatalogView(store: skillsCatalogStore)
                        } else if selectedTab == .work,
                                  selectedCustomDestination == .connectedApps {
                            ExtensionsCatalogView(
                                store: extensionsCatalogStore,
                                installedStore: installedExtensionsStore
                            )
                        } else {
                            ChatView(
                                mode: selectedTab,
                                projects: projectStore.projects,
                                selectedProject: $workSession.selectedProject,
                                sessionStore: sessionStore,
                                hostError: agentError,
                                isLoadingSession: isOpeningSelectedSession,
                                onSelectProject: startNewSession(for:),
                                onAddFolder: pickFolder
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // The reference puts the sidebar toggle in the content
                    // area's top-left corner (not inside the sidebar), where
                    // it stays put whether the sidebar is open or collapsed.
                    HStack {
                        SidebarToggleButton {
                            withAnimation(.easeInOut(duration: 0.22)) { sidebarCollapsed.toggle() }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 0)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(
                        width: (sidebarCollapsed ? 0 : SidebarPanelMetrics.columnWidth) + 96
                    )
                    .allowsHitTesting(false)

                WindowTitlebarDragRegion()
            }
            .frame(height: 52)
            .ignoresSafeArea(edges: .top)
        }
        .background(TrafficLightPositioner(offset: SidebarPanelMetrics.trafficLightOffset))
        .task {
            await bootstrapChatIfNeeded()
            await bootstrapWorkProjects()
        }
    }

    private var activeSessionIDs: Set<String> {
        Set(
            sessionStore.records.values.compactMap { record in
                record.runState.showsSidebarActivity ? record.id : nil
            }
        )
    }

    private var selectedTabBinding: Binding<SidebarTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                guard tab != selectedTab else { return }
                cancelSessionOpening()
                selectedTab = tab
            }
        )
    }

    private func startNewSession() {
        cancelSessionOpening()
        selectedCustomDestination = nil
        switch selectedTab {
        case .chat:
            Task { await createChatSession() }
        case .work:
            workSession.startNewSession()
        }
    }

    private func startNewSession(for project: PiProject) {
        cancelSessionOpening()
        selectedTab = .work
        selectedCustomDestination = nil
        workSession.startNewSession(for: project)
        Task { await createWorkSession(for: project) }
    }

    private var isOpeningSelectedSession: Bool {
        guard let target = sessionOpeningState.target else { return false }
        switch (selectedTab, target.profile) {
        case (.chat, .chat):
            return true
        case (.work, .work):
            return true
        default:
            return false
        }
    }

    private func openChatSession(_ session: AgentHostSessionSummary) {
        selectedCustomDestination = nil
        guard !selectCachedSessionIfAvailable(session, profile: .chat) else { return }
        beginOpeningSession(session, profile: .chat)
    }

    private func bootstrapChatIfNeeded() async {
        guard !didBootstrapChat else { return }
        didBootstrapChat = true
        do {
            let directory = try prepareChatWorkingDirectory()
            try await sessionStore.bootstrap(
                cwd: directory.path,
                sessionDirectory: nil,
                profile: .chat
            )
            if sessionStore.selectedChatSessionId == nil {
                if let session = sessionStore.chatSessions.first {
                    try await sessionStore.openSession(
                        session,
                        profile: .chat,
                        sessionDirectory: nil
                    )
                } else {
                    _ = try await sessionStore.createDraft(
                        cwd: directory.path,
                        sessionDirectory: nil,
                        profile: .chat
                    )
                }
            }
            agentError = nil
        } catch {
            agentError = String(describing: error)
        }
    }

    private func createChatSession() async {
        do {
            let directory = try prepareChatWorkingDirectory()
            _ = try await sessionStore.createDraft(
                cwd: directory.path,
                sessionDirectory: nil,
                profile: .chat
            )
            agentError = nil
        } catch {
            agentError = String(describing: error)
        }
    }

    private func bootstrapWorkProjects() async {
        for project in projectStore.projects {
            await bootstrapWorkProjectIfNeeded(project)
        }
    }

    private func bootstrapWorkProjectIfNeeded(_ project: PiProject) async {
        guard !bootstrappedWorkProjectPaths.contains(project.path) else { return }
        bootstrappedWorkProjectPaths.insert(project.path)
        do {
            try await sessionStore.bootstrap(
                cwd: project.path,
                sessionDirectory: nil,
                profile: .work
            )
            agentError = nil
        } catch {
            bootstrappedWorkProjectPaths.remove(project.path)
            agentError = String(describing: error)
        }
    }

    private func createWorkSession(for project: PiProject) async {
        await bootstrapWorkProjectIfNeeded(project)
        do {
            _ = try await sessionStore.createDraft(
                cwd: project.path,
                sessionDirectory: nil,
                profile: .work
            )
            agentError = nil
        } catch {
            agentError = String(describing: error)
        }
    }

    private func openWorkSession(
        _ project: PiProject,
        _ session: AgentHostSessionSummary
    ) {
        selectedTab = .work
        selectedCustomDestination = nil
        guard !selectCachedSessionIfAvailable(
            session,
            profile: .work,
            project: project
        ) else { return }
        beginOpeningSession(session, profile: .work, project: project)
    }

    private func selectCachedSessionIfAvailable(
        _ session: AgentHostSessionSummary,
        profile: AgentHostSessionProfile,
        project: PiProject? = nil
    ) -> Bool {
        guard sessionStore.records[session.id] != nil else { return false }
        cancelSessionOpening()
        do {
            try sessionStore.selectOpenSession(
                sessionId: session.id,
                profile: profile,
                cwd: session.cwd
            )
            if let project {
                workSession.selectSession(session.id, in: project)
            }
            agentError = nil
        } catch {
            agentError = String(describing: error)
        }
        return true
    }

    private func beginOpeningSession(
        _ session: AgentHostSessionSummary,
        profile: AgentHostSessionProfile,
        project: PiProject? = nil
    ) {
        sessionOpenTask?.cancel()
        let request = sessionOpeningState.begin(
            SessionOpeningTarget(
                sessionID: session.id,
                profile: profile,
                cwd: session.cwd,
                projectID: project?.id
            )
        )
        sessionOpenTask = Task { @MainActor in
            await Task.yield()
            do {
                try await sessionStore.openSession(
                    session,
                    profile: profile,
                    sessionDirectory: nil,
                    selectSession: false
                )
                try Task.checkCancellation()
                guard sessionOpeningState.isCurrent(request) else { return }
                try commitSessionSelection(for: request.target)
                sessionOpeningState.complete(request)
                agentError = nil
            } catch is CancellationError {
                return
            } catch {
                guard sessionOpeningState.complete(request) else { return }
                agentError = String(describing: error)
            }
        }
    }

    private func commitSessionSelection(for target: SessionOpeningTarget) throws {
        let project = target.projectID.flatMap { projectID in
            projectStore.projects.first { $0.id == projectID && $0.path == target.cwd }
        }
        if target.profile == .work, project == nil {
            throw SessionStoreError.sessionNotOpen(target.sessionID)
        }
        try sessionStore.selectOpenSession(
            sessionId: target.sessionID,
            profile: target.profile,
            cwd: target.cwd
        )
        if let project {
            workSession.selectSession(target.sessionID, in: project)
        }
    }

    private func cancelSessionOpening() {
        sessionOpenTask?.cancel()
        sessionOpenTask = nil
        sessionOpeningState.cancel()
    }

    private func deleteChatSession(_ session: AgentHostSessionSummary) {
        Task {
            do {
                try await sessionStore.deleteSession(
                    session,
                    profile: .chat,
                    sessionDirectory: nil
                )
                agentError = nil
            } catch {
                agentError = String(describing: error)
            }
        }
    }

    private func deleteWorkSession(
        _ project: PiProject,
        _ session: AgentHostSessionSummary
    ) {
        guard project.path == session.cwd else { return }
        Task {
            do {
                try await sessionStore.deleteSession(
                    session,
                    profile: .work,
                    sessionDirectory: nil
                )
                agentError = nil
            } catch {
                agentError = String(describing: error)
            }
        }
    }

    private func deleteWorkProject(_ project: PiProject) {
        Task {
            do {
                try await sessionStore.deleteWorkSessions(
                    cwd: project.path,
                    sessionDirectory: nil
                )
                if workSession.selectedProject?.id == project.id {
                    workSession.startNewSession()
                }
                bootstrappedWorkProjectPaths.remove(project.path)
                projectStore.removeProject(project)
                agentError = nil
            } catch {
                agentError = String(describing: error)
            }
        }
    }

    private func prepareChatWorkingDirectory() throws -> URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pi-work/Chat", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.string("sidebar.add_mac_folder")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectStore.addProject(path: url.path)
        guard let project = projectStore.projects.first(where: { $0.path == url.path }) else { return }
        startNewSession(for: project)
    }
}

/// Geometry + surface colors for the floating sidebar panel, kept in one
/// place so the inset and the corner radius can be tuned together.
private enum SidebarPanelMetrics {
    /// Gap between the panel and the window edges — the window gradient
    /// shows through here, which is what makes the panel read as floating.
    static let inset: CGFloat = 9
    static let cornerRadius: CGFloat = 16
    static let contentWidth: CGFloat = 236
    static var columnWidth: CGFloat { contentWidth + inset * 2 }

    /// The traffic lights belong to the window, so AppKit parks them in the
    /// window's own corner — which lands them on the panel's rounded corner
    /// once the panel is inset. The downward nudge is capped by the title
    /// bar's own height (see `TrafficLightPositioner`), so the horizontal
    /// nudge is kept modest too, to stay visually balanced.
    static let trafficLightOffset = CGSize(width: 10, height: 6)

    /// Clearance the sidebar's own content keeps below the traffic lights so
    /// the tab header doesn't crowd them.
    static let contentTopInset: CGFloat = 6

    static let surface = AppPalette.sidebarSurface
}

/// The reference design's sidebar is a rounded card inset from every window
/// edge, hovering above the content gradient rather than being a flush
/// column with a split divider.
///
/// macOS 26 renders `NavigationSplitView` sidebars this way natively, but
/// only for apps linked against the macOS 26 SDK — and on macOS 13-25 there
/// is no system affordance for it at all (the split view always paints an
/// edge-to-edge column plus a divider, and its automatic toolbar toggle
/// cannot be removed before macOS 14). So the panel *chrome* is drawn here
/// while the panel's interior stays a real system `List(.sidebar)`.
///
/// The card deliberately ignores the safe area so it runs the full height of
/// the window, behind the traffic lights, while `content` stays inside the
/// safe area so the tab header clears them.
private struct SidebarPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            adaptiveRoundedShape(cornerRadius: SidebarPanelMetrics.cornerRadius)
                .fill(SidebarPanelMetrics.surface)
                .overlay(
                    adaptiveRoundedShape(cornerRadius: SidebarPanelMetrics.cornerRadius)
                        .stroke(AppPalette.panelBorder, lineWidth: 0.5)
                )
                .shadow(color: AppPalette.raisedShadow, radius: 9, y: 2)
                .padding(SidebarPanelMetrics.inset)
                .ignoresSafeArea()

            content
                .padding(.horizontal, SidebarPanelMetrics.inset)
                .padding(.top, SidebarPanelMetrics.contentTopInset)
                .padding(.bottom, SidebarPanelMetrics.inset)
        }
        .frame(width: SidebarPanelMetrics.columnWidth)
    }
}

/// Floating rounded-square button that collapses/expands the sidebar. Drawn
/// by hand rather than using `NavigationSplitView`'s automatic toolbar
/// toggle, which sits in the title bar and can't be restyled or moved.
private struct SidebarToggleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 32, height: 32)
                .background(
                    adaptiveRoundedShape(cornerRadius: 9)
                        .fill(AppPalette.raisedSurface)
                        .shadow(color: AppPalette.subtleShadow, radius: 3, y: 1)
                )
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 10))
    }
}

/// Single window-spanning gradient drawn once behind the sidebar + content
/// split, so the two panels share one continuous background instead of each
/// drawing its own — matching the reference design's unified backdrop.
/// See `AppPalette.windowGradient` for the light/dark stops.
struct AppBackgroundGradient: View {
    var body: some View {
        AppPalette.windowGradient
            .ignoresSafeArea()
    }
}

#Preview {
    let service = AgentHostService(
        executableURL: URL(fileURLWithPath: "/usr/bin/false"),
        requiredCapabilities: []
    )
    let sessionStore = SessionStore(service: service)
    let scheduleStore = ScheduleStore()
    ContentView(
        sessionStore: sessionStore,
        installedExtensionsStore: InstalledExtensionsStore(service: service),
        scheduleStore: scheduleStore,
        scheduleRunner: ScheduleRunner(
            store: scheduleStore,
            executor: ScheduleAgentExecutor(sessionClient: sessionStore)
        )
    )
}
