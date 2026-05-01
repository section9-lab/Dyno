import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredProject.addedAt, order: .reverse) private var projects: [StoredProject]
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var allSessions: [StoredSession]
    @Query(sort: \StoredKanbanTask.updatedAt, order: .reverse) private var allTasks: [StoredKanbanTask]
    @StateObject private var vm = ChatViewModel()
    @StateObject private var agent = AgentManager.shared
    @StateObject private var approvals = ToolApprovalCenter.shared
    @EnvironmentObject private var authSession: AuthSession

    private let kanban = KanbanController()

    /// Sessions for the currently-selected project.
    private var projectSessions: [StoredSession] {
        guard let path = vm.selectedProjectPath else { return [] }
        return allSessions.filter { $0.projectPath == path }
    }

    /// Sessions grouped by project path; passed to the sidebar.
    private var sessionsByProjectPath: [String: [StoredSession]] {
        Dictionary(grouping: allSessions, by: { $0.projectPath })
    }

    private var selectedProject: StoredProject? {
        guard let path = vm.selectedProjectPath else { return nil }
        return projects.first(where: { $0.path == path })
    }

    private var selectedSession: StoredSession? {
        guard let id = vm.selectedSessionID else { return nil }
        return allSessions.first(where: { $0.id == id })
    }

    private var kanbanTasks: [StoredKanbanTask] {
        guard let path = vm.selectedProjectPath else { return [] }
        return allTasks
            .filter { $0.projectPath == path }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status.rawValue < rhs.status.rawValue
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// Rows to render in the chat scroll area for the focused session.
    /// Merges messages (user + assistant), tool runs, and compaction summaries
    /// into one chronologically-sorted list, then folds adjacent tool runs
    /// into a single collapsible group.
    private var chatRows: [ChatRow] {
        guard let session = selectedSession else { return [] }
        return Self.buildChatRows(for: session)
    }

    private var focusedSessionAgent: SessionAgent? {
        agent.existingSessionAgent(for: vm.selectedSessionID)
    }

    private func ensureFocusedSessionAgent() {
        guard let sessionID = vm.selectedSessionID,
              let projectPath = vm.selectedProjectPath
        else { return }
        _ = agent.sessionAgent(for: sessionID, projectPath: projectPath)
        agent.focusedSessionID = sessionID
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if !vm.isSidebarCollapsed {
                    sidebar
                    sidebarResizeHandle
                }
                mainColumn
            }
            .background(MetalParticleBackground(isDark: colorScheme == .dark))
            .overlay(alignment: .top) { UserAlertBanner() }
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar { mainToolbar }
            .sheet(isPresented: $vm.showConfigSheet) {
                SettingsContainerView(agent: agent)
            }
            .alert("chat.rename_session", isPresented: $vm.showRenameDialog) {
                renameAlertButtons
            } message: {
                Text("chat.rename_selected_session")
            }
            .alert(item: $approvals.pendingRequest) { request in
                Alert(
                    title: Text(L10n.tr("tool_approval.title")),
                    message: Text("\(request.reason)\n\n\(request.summary)"),
                    primaryButton: .destructive(Text(L10n.tr("tool_approval.run_once"))) {
                        approvals.approve(request)
                    },
                    secondaryButton: .cancel(Text(L10n.tr("tool_approval.reject"))) {
                        approvals.reject(request)
                    }
                )
            }
            .task {
                await agent.refreshServiceStatus()
                autoCreateSessionIfNeeded()
                ensureFocusedSessionAgent()
            }
            .onChange(of: vm.selectedProjectPath) { _, _ in
                autoCreateSessionIfNeeded()
                ensureFocusedSessionAgent()
            }
            .onChange(of: vm.selectedSessionID) { _, _ in
                ensureFocusedSessionAgent()
            }
            .frame(minWidth: 980, minHeight: 760)
            .animation(.easeInOut(duration: 0.2), value: vm.showKanbanPanel)
        }
    }

    // MARK: - Body subviews

    private var sidebar: some View {
        ChatSidebarView(
            projects: projects,
            sessionsByProjectPath: sessionsByProjectPath,
            selectedProjectPath: vm.selectedProjectPath,
            selectedSessionID: vm.selectedSessionID,
            expandedProjectPaths: vm.expandedProjectPaths,
            onAddProject: addProject,
            onCreateSession: createSession,
            onToggleProject: { vm.toggleProjectExpansion($0.path) },
            onSelectProject: { vm.selectProject($0.path, agent: agent) },
            onRemoveProject: { vm.removeProject(path: $0.path, modelContext: modelContext, agent: agent) },
            onSelectSession: { project, session in
                vm.selectSession(projectPath: project.path, sessionID: session.id, agent: agent)
            },
            onRenameSession: vm.requestRename,
            onDeleteSession: { vm.deleteSession($0, modelContext: modelContext) },
            onSettings: { vm.showConfigSheet = true },
            onHelp: openHelp,
            accountName: authSession.user?.displayName ?? L10n.tr("account.google_user"),
            accountSubtitle: authSession.provider.accountTitleKey,
            accountInitial: authSession.user?.avatarInitial ?? "G",
            accountAvatarURL: authSession.user?.avatarURL,
            onLogout: { authSession.signOut() }
        )
        .frame(width: vm.sidebarWidth)
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            if vm.showKanbanPanel {
                KanbanPanelView(
                    project: selectedProject,
                    selectedSession: selectedSession,
                    tasks: kanbanTasks,
                    projectSessions: projectSessions,
                    onCreateTask: { title, priority, status in
                        kanban.createTask(
                            title: title,
                            priority: priority,
                            status: status,
                            projectPath: vm.selectedProjectPath,
                            selectedSessionID: vm.selectedSessionID,
                            modelContext: modelContext
                        )
                    },
                    onMoveTask: { task, status in kanban.moveTask(task, to: status) },
                    onLinkSelectedSession: { task in
                        kanban.linkSession(task, sessionID: vm.selectedSessionID)
                    },
                    onDeleteTask: { task in kanban.deleteTask(task, modelContext: modelContext) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 372)
                .padding(.horizontal, 56)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            chatScrollArea

            InputBar(
                inputText: $vm.inputText,
                projects: projects,
                selectedProjectPath: vm.selectedProjectPath,
                isResponding: focusedSessionAgent?.isResponding ?? false,
                onSelectProject: { vm.selectProject($0.path, agent: agent) },
                onSend: sendMessage,
                sessionAgent: focusedSessionAgent
            )
        }
    }

    private var chatScrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    if selectedSession == nil {
                        emptyState
                    } else {
                        ForEach(chatRows) { row in
                            chatRowView(row)
                        }
                        if let focusedSessionAgent {
                            AgentResponseView(sessionAgent: focusedSessionAgent)
                                .id("agent_response")
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .onChange(of: chatRows.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(chatRows.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: focusedSessionAgent?.isResponding ?? false) { _, responding in
                if responding {
                    proxy.scrollTo("agent_response", anchor: .bottom)
                }
            }
            .onChange(of: vm.selectedSessionID) { _, _ in
                if let lastID = chatRows.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chatRowView(_ row: ChatRow) -> some View {
        switch row {
        case .message(let m):
            MessageView(message: m).id(row.id)
        case .toolGroup(let group):
            ToolExecutionGroupView(group: group).id(group.id)
        case .compactionSummary:
            // Compaction summaries are persisted but not rendered (they
            // exist for the SDK prelude builder, not for the user).
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                vm.toggleSidebar()
            } label: {
                Image(systemName: vm.isSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.toggleKanbanPanel()
            } label: {
                Label(
                    vm.showKanbanPanel ? "kanban.hide_board" : "kanban.show_board",
                    systemImage: vm.showKanbanPanel ? "rectangle.compress.vertical" : "rectangle.3.group"
                )
            }
            .labelStyle(.iconOnly)
            .help("kanban.toggle")
        }
    }

    @ViewBuilder
    private var renameAlertButtons: some View {
        TextField("chat.session_title", text: $vm.renameDraft)
        Button("common.cancel", role: .cancel) {
            vm.renamingSessionID = nil
        }
        Button("common.save") {
            vm.applyRename(modelContext: modelContext)
        }
        .disabled(!vm.renameDraft.isNotBlank)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if !projects.isEmpty {
                Text("chat.select_session_empty")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.88))
            } else {
                Text("chat.no_project_available")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.88))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(.top, 80)
    }

    private var sidebarResizeHandle: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.16))
                .frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if vm.dragSidebarStartWidth == nil {
                        vm.dragSidebarStartWidth = vm.sidebarWidth
                    }
                    guard let start = vm.dragSidebarStartWidth else { return }
                    vm.sidebarWidth = min(max(start + value.translation.width, 240), 520)
                }
                .onEnded { _ in
                    vm.lastExpandedSidebarWidth = vm.sidebarWidth
                    vm.dragSidebarStartWidth = nil
                }
        )
    }

    // MARK: - Actions

    private func autoCreateSessionIfNeeded() {
        guard selectedProject != nil, selectedSession == nil else { return }
        _ = vm.startNewChat(modelContext: modelContext, agent: agent)
    }

    private func addProject() {
        vm.addProject(modelContext: modelContext, agent: agent)
    }

    private func createSession(_ project: StoredProject) {
        vm.selectProject(project.path, agent: agent)
        _ = vm.startNewChat(modelContext: modelContext, agent: agent)
    }

    private func sendMessage() {
        guard let session = selectedSession else { return }
        vm.sendMessage(modelContext: modelContext, agent: agent, session: session)
    }

    private func openHelp() {
        if let url = URL(string: "https://github.com/section9-lab/Impulse/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Row construction

    /// Merge messages, tool runs, and compaction summaries into a single
    /// chronologically-sorted list and fold adjacent tool runs into groups.
    static func buildChatRows(for session: StoredSession) -> [ChatRow] {
        // Each event has a kind so we can sort heterogeneously by timestamp.
        enum Event {
            case message(StoredMessage)
            case toolRun(StoredToolRun)
            case summary(StoredCompactionSummary)

            var timestamp: Date {
                switch self {
                case .message(let m): return m.timestamp
                case .toolRun(let r): return r.timestamp
                case .summary(let s): return s.timestamp
                }
            }
        }

        var events: [Event] = []
        events.reserveCapacity(session.messages.count + session.toolRuns.count + session.compactionSummaries.count)
        events.append(contentsOf: session.messages.map(Event.message))
        events.append(contentsOf: session.toolRuns.map(Event.toolRun))
        events.append(contentsOf: session.compactionSummaries.map(Event.summary))
        events.sort { $0.timestamp < $1.timestamp }

        var rows: [ChatRow] = []
        var pendingRuns: [StoredToolRun] = []
        var groupAnchor: String?

        func flush() {
            guard !pendingRuns.isEmpty, let anchor = groupAnchor else {
                pendingRuns = []
                groupAnchor = nil
                return
            }
            rows.append(.toolGroup(ToolExecutionGroup(id: "group-\(anchor)", runs: pendingRuns)))
            pendingRuns = []
            groupAnchor = nil
        }

        for event in events {
            switch event {
            case .toolRun(let run):
                if groupAnchor == nil { groupAnchor = run.id }
                pendingRuns.append(run)
            case .message(let m):
                flush()
                rows.append(.message(m))
            case .summary(let s):
                flush()
                rows.append(.compactionSummary(s))
            }
        }
        flush()
        return rows
    }
}

struct MetalParticleBackground: View {
    let isDark: Bool

    private static let lightBaseColor = Color(red: 0.95, green: 0.95, blue: 0.96)
    private static let darkBaseColor = Color(red: 0.095, green: 0.098, blue: 0.106)
    private static let particles: [MetalParticle] = {
        var generator = SeededRandomGenerator(seed: 0xA11E2026)
        return (0..<1800).map { _ in
            let intensity = Double.random(in: 0...1, using: &generator)
            return MetalParticle(
                x: Double.random(in: 0...1, using: &generator),
                y: Double.random(in: 0...1, using: &generator),
                size: intensity > 0.88 ? Double.random(in: 1.4...2.6, using: &generator) : Double.random(in: 0.6...1.2, using: &generator),
                alpha: intensity > 0.82 ? Double.random(in: 0.16...0.32, using: &generator) : Double.random(in: 0.05...0.14, using: &generator),
                isBright: intensity > 0.46
            )
        }
    }()

    var body: some View {
        ZStack {
            baseColor

            LinearGradient(
                stops: [
                    .init(color: gradientStartColor, location: 0),
                    .init(color: .clear, location: 0.42),
                    .init(color: gradientEndColor, location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)

            Canvas { context, size in
                for particle in Self.particles {
                    let rect = CGRect(
                        x: particle.x * size.width,
                        y: particle.y * size.height,
                        width: particle.size,
                        height: particle.size
                    )
                    let color = particle.isBright ? Color.white : Color.black
                    context.opacity = particle.alpha
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
            .opacity(isDark ? 0.58 : 0.92)
            .blendMode(.overlay)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var baseColor: Color {
        isDark ? Self.darkBaseColor : Self.lightBaseColor
    }

    private var gradientStartColor: Color {
        isDark ? Color.white.opacity(0.055) : Color.white.opacity(0.12)
    }

    private var gradientEndColor: Color {
        isDark ? Color.black.opacity(0.18) : Color.black.opacity(0.035)
    }
}

private struct MetalParticle {
    let x: Double
    let y: Double
    let size: Double
    let alpha: Double
    let isBright: Bool
}

private struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: StoredSession.self, inMemory: true)
}

enum ChatRow: Identifiable {
    case message(StoredMessage)
    case toolGroup(ToolExecutionGroup)
    case compactionSummary(StoredCompactionSummary)

    var id: String {
        switch self {
        case .message(let m): return "msg-\(m.persistentModelID.hashValue)"
        case .toolGroup(let group): return group.id
        case .compactionSummary(let s): return "sum-\(s.persistentModelID.hashValue)"
        }
    }
}
