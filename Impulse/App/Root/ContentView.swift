import AppKit
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
    @StateObject private var askCenter = AskCenter.shared
    @EnvironmentObject private var authSession: AuthSession

    /// Project the kanban scopes to. `nil` means "all projects" — the
    /// default aggregate view. Independent from `vm.selectedProjectPath`
    /// so the chat sidebar's selection doesn't snap the board around.
    @State private var kanbanScopePath: String? = nil

    private let kanban = KanbanController()

    /// Sessions for the currently-selected project.
    private var projectSessions: [StoredSession] {
        guard let path = vm.selectedProjectPath else { return [] }
        return allSessions.filter { $0.projectPath == path }
    }

    /// Sessions grouped by project path; passed to the sidebar.
    private var sessionsByProjectPath: [String: [StoredSession]] {
        Dictionary(grouping: allSessions.filter { !$0.projectPath.isEmpty }, by: { $0.projectPath })
    }

    /// Sessions with no project, surfaced in the sidebar's "Conversations"
    /// section. Sorted by most recent first (matching `@Query` order).
    private var projectlessSessions: [StoredSession] {
        allSessions.filter { $0.projectPath.isEmpty }
    }

    private var selectedProject: StoredProject? {
        guard let path = vm.selectedProjectPath else { return nil }
        return projects.first(where: { $0.path == path })
    }

    private var selectedSession: StoredSession? {
        guard let id = vm.selectedSessionID else { return nil }
        return allSessions.first(where: { $0.id == id })
    }

    /// Tasks visible to the kanban — all projects when in aggregate mode,
    /// scoped to a single project otherwise. Sorted by status, then most
    /// recent first within a status. Filtering by project happens inside
    /// the view to keep the picker UI responsive without re-deriving here.
    private var kanbanTasks: [StoredKanbanTask] {
        allTasks.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status.rawValue < rhs.status.rawValue
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Sessions to surface in kanban cards — all sessions for the scoped
    /// project, or every session in aggregate mode.
    private var kanbanProjectSessions: [StoredSession] {
        guard let path = kanbanScopePath else { return allSessions }
        return allSessions.filter { $0.projectPath == path }
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

    /// Past user messages of the active session, most-recent first. Powers
    /// the ↑/↓ history recall in the input bar. Empty list when no session
    /// is selected — recall is then a no-op.
    private var userInputHistory: [String] {
        guard let session = selectedSession else { return [] }
        return session.messages
            .filter { $0.role == "user" }
            .sorted { $0.timestamp > $1.timestamp }
            .map(\.content)
    }

    private func ensureFocusedSessionAgent() {
        guard let sessionID = vm.selectedSessionID else { return }
        let projectPath = vm.selectedProjectPath ?? ""
        let sessionAgent = agent.sessionAgent(for: sessionID, projectPath: projectPath)
        agent.focusedSessionID = sessionID

        // Seed the live TodoStore from the persisted snapshot the first
        // time we touch this SessionAgent. Idempotent — `seedTodoSnapshotIfNeeded`
        // checks `hasSeededTodos` and bails on a re-call.
        if let session = allSessions.first(where: { $0.id == sessionID }) {
            Task { [vm] in
                await vm.seedTodoSnapshotIfNeeded(sessionAgent: sessionAgent, session: session)
            }
        }
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
                ensureFocusedSessionAgent()
            }
            .onChange(of: vm.selectedProjectPath) { _, _ in
                ensureFocusedSessionAgent()
            }
            .onChange(of: vm.selectedSessionID) { _, _ in
                ensureFocusedSessionAgent()
            }
            .frame(minWidth: 980, minHeight: 760)
            .animation(.easeInOut(duration: 0.2), value: vm.route)
        }
    }

    // MARK: - Body subviews

    private var sidebar: some View {
        ChatSidebarView(
            projects: projects,
            sessionsByProjectPath: sessionsByProjectPath,
            projectlessSessions: projectlessSessions,
            route: vm.route,
            isComposingDraft: vm.isComposingDraft,
            selectedProjectPath: vm.selectedProjectPath,
            selectedSessionID: vm.selectedSessionID,
            expandedProjectPaths: vm.expandedProjectPaths,
            onAddProject: addProject,
            onBeginDraft: { vm.beginDraftSession(projectPath: nil, agent: agent) },
            onAutoIntelligence: { vm.setRoute(.autoIntelligence) },
            onMail: { vm.setRoute(.mail) },
            onKanban: { vm.setRoute(.kanban) },
            onBeginDraftInProject: { project in
                vm.beginDraftSession(projectPath: project.path, agent: agent)
            },
            onToggleProject: { vm.toggleProjectExpansion($0.path) },
            onSelectProject: { vm.selectProject($0.path, agent: agent) },
            onRemoveProject: { vm.removeProject(path: $0.path, modelContext: modelContext, agent: agent) },
            onSelectSession: { project, session in
                vm.selectSession(projectPath: project?.path ?? "", sessionID: session.id, agent: agent)
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

    @ViewBuilder
    private var mainColumn: some View {
        switch vm.route {
        case .chat:
            chatColumn
        case .kanban:
            kanbanColumn
        case .autoIntelligence:
            autoIntelligenceColumn
        case .mail:
            mailColumn
        }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            // Inline banner that appears above the chat when the agent
            // invokes the `ask` tool. Auto-collapses when no prompt is
            // pending. The InputBar is also disabled in that state so the
            // user can't race the submission.
            AskPromptBanner(center: askCenter)
                .animation(.easeInOut(duration: 0.18), value: askCenter.pendingPrompt?.id)

            chatScrollArea

            InputBar(
                inputText: $vm.inputText,
                projects: projects,
                selectedProjectPath: vm.selectedProjectPath,
                isResponding: focusedSessionAgent?.isResponding ?? false,
                onSelectProject: { vm.selectProject($0.path, agent: agent) },
                onSend: sendMessage,
                sessionAgent: focusedSessionAgent,
                agent: agent,
                onOpenSettings: { vm.showConfigSheet = true },
                inputHistory: userInputHistory
            )
            .disabled(askCenter.pendingPrompt != nil)
            .opacity(askCenter.pendingPrompt != nil ? 0.5 : 1)
        }
    }

    private var kanbanColumn: some View {
        KanbanPanelView(
            projects: projects,
            selectedProjectPath: $kanbanScopePath,
            selectedSession: selectedSession,
            tasks: kanbanTasks,
            projectSessions: kanbanProjectSessions,
            onCreateTask: { projectPath, title, priority, status, labels in
                kanban.createTask(
                    title: title,
                    priority: priority,
                    status: status,
                    labels: labels,
                    projectPath: projectPath,
                    selectedSessionID: vm.selectedSessionID,
                    modelContext: modelContext
                )
            },
            onMoveTask: { task, status in kanban.moveTask(task, to: status) },
            onLinkSelectedSession: { task in
                kanban.linkSession(task, sessionID: vm.selectedSessionID)
            },
            onDeleteTask: { task in kanban.deleteTask(task, modelContext: modelContext) },
            onUpdateLabels: { task, labels in kanban.setLabels(task, labels: labels) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 56)
        .padding(.vertical, 24)
    }

    private var autoIntelligenceColumn: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))
            Text("sidebar.auto_intelligence.coming_soon.title")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            Text("sidebar.auto_intelligence.coming_soon.subtitle")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mailColumn: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))
            Text("sidebar.mail.coming_soon.title")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            Text("sidebar.mail.coming_soon.subtitle")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatScrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    if vm.isComposingDraft {
                        draftEmptyState
                    } else if selectedSession == nil {
                        emptyState
                    } else {
                        ForEach(Array(chatRows.enumerated()), id: \.element.id) { index, row in
                            chatRowView(row, at: index, in: chatRows)
                        }
                        if let focusedSessionAgent {
                            AgentResponseView(sessionAgent: focusedSessionAgent)
                                .id("agent_response")
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 20)
                .background(OverlayScrollerHook().frame(width: 0, height: 0))
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
        .overlay(alignment: .topTrailing) {
            if let focusedSessionAgent, selectedSession != nil {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: geometry.size.height / 3)

                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            TodoProgressIndicator(sessionAgent: focusedSessionAgent)
                                .allowsHitTesting(true)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chatRowView(_ row: ChatRow, at index: Int, in rows: [ChatRow]) -> some View {
        switch row {
        case .message(let m):
            MessageView(message: m).id(row.id)
        case .toolRun(let run):
            // The timeline rail draws a connector down to the next row when
            // `isLast == false`. Keep it visible only when the next row is
            // also a tool — that's what gives us a single contiguous rail
            // across back-to-back tools and breaks it cleanly when text
            // (or any other row) interrupts the sequence.
            let nextIsTool = index + 1 < rows.count && rows[index + 1].isToolRun
            PersistedToolExecutionMessageView(run: run, isLast: !nextIsTool).id(row.id)
        case .reasoning(let m):
            if let reasoning = m.reasoning {
                PersistedReasoningRow(text: reasoning).id(row.id)
            }
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

    /// Welcome surface shown while the user is composing a fresh chat
    /// that has not yet been committed to a `StoredSession`. The first
    /// `sendMessage` will create the row in the right sidebar section.
    private var draftEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))
            Text("chat.draft.title")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary.opacity(0.88))
            Text(vm.draft?.projectPath == nil
                 ? "chat.draft.subtitle.no_project"
                 : "chat.draft.subtitle.in_project")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(.top, 80)
    }

    private var sidebarResizeHandle: some View {
        SidebarResizeHandle(
            colorScheme: colorScheme,
            onDragChanged: { translation in
                if vm.dragSidebarStartWidth == nil {
                    vm.dragSidebarStartWidth = vm.sidebarWidth
                }
                guard let start = vm.dragSidebarStartWidth else { return }
                vm.sidebarWidth = min(max(start + translation, 240), 520)
            },
            onDragEnded: {
                vm.lastExpandedSidebarWidth = vm.sidebarWidth
                vm.dragSidebarStartWidth = nil
            }
        )
    }

    // MARK: - Actions

    private func addProject() {
        vm.addProject(modelContext: modelContext, agent: agent)
    }

    private func sendMessage() {
        // selectedSession can be nil when the user is composing a draft;
        // ChatViewModel.sendMessage handles the commit-then-send case.
        vm.sendMessage(modelContext: modelContext, agent: agent, session: selectedSession)
    }

    private func openHelp() {
        if let url = URL(string: "https://github.com/section9-lab/Impulse/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Row construction

    /// Merge messages, tool runs, and compaction summaries into a single
    /// chronologically-sorted list. Each event becomes its own row — there
    /// is no longer any tool-group folding, so interleaved `text → tool
    /// → text → tool` turns reload with the same ordering they had live.
    static func buildChatRows(for session: StoredSession) -> [ChatRow] {
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
        for event in events {
            switch event {
            case .toolRun(let run):
                rows.append(.toolRun(run))
            case .message(let m):
                // Reasoning belongs to the assistant turn — emit it as its
                // own row immediately before the text it preceded.
                if m.role == "assistant",
                   let reasoning = m.reasoning,
                   !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rows.append(.reasoning(m))
                }
                rows.append(.message(m))
            case .summary(let s):
                rows.append(.compactionSummary(s))
            }
        }
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
    case toolRun(StoredToolRun)
    case compactionSummary(StoredCompactionSummary)
    /// Persisted chain-of-thought / reasoning trace tied to an assistant
    /// message. Inserted as a row of its own — visually placed *before* the
    /// assistant text it preceded — so the reading order stays
    /// "thinking → answer" rather than mixing reasoning into the answer bubble.
    case reasoning(StoredMessage)

    var id: String {
        switch self {
        case .message(let m): return "msg-\(m.persistentModelID.hashValue)"
        case .toolRun(let run): return "tool-\(run.id)"
        case .compactionSummary(let s): return "sum-\(s.persistentModelID.hashValue)"
        case .reasoning(let m): return "reasoning-\(m.persistentModelID.hashValue)"
        }
    }

    var isToolRun: Bool {
        if case .toolRun = self { return true } else { return false }
    }
}

/// Thin separator between the sidebar and the main column with a draggable
/// hit area. A pill-shaped indicator fades in while the cursor hovers or a
/// drag is in flight, telegraphing that the column is resizable.
private struct SidebarResizeHandle: View {
    private static let hitWidth: CGFloat = 12

    let colorScheme: ColorScheme
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    private var lineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.16)
    }

    private var handleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.42)
    }

    private var isActive: Bool { isHovering || isDragging }

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(lineColor)
                .frame(width: 1)
            Capsule()
                .fill(handleColor)
                .frame(width: 3, height: 28)
                .opacity(isActive ? 1 : 0)
                .scaleEffect(isActive ? 1 : 0.6, anchor: .center)
        }
        .frame(width: Self.hitWidth)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .overlay {
            SidebarResizeEventLayer(
                onHoverChanged: { hovering in
                    isHovering = hovering
                },
                onDragChanged: { translation in
                    isDragging = true
                    onDragChanged(translation)
                },
                onDragEnded: {
                    isDragging = false
                    onDragEnded()
                }
            )
        }
    }
}

private struct SidebarResizeEventLayer: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onHoverChanged: onHoverChanged,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )
    }

    func makeNSView(context: Context) -> ResizeEventView {
        let view = ResizeEventView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ResizeEventView, context: Context) {
        context.coordinator.onHoverChanged = onHoverChanged
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var onHoverChanged: (Bool) -> Void
        var onDragChanged: (CGFloat) -> Void
        var onDragEnded: () -> Void
        var dragStartX: CGFloat?
        var previousWindowDragState: Bool?

        init(
            onHoverChanged: @escaping (Bool) -> Void,
            onDragChanged: @escaping (CGFloat) -> Void,
            onDragEnded: @escaping () -> Void
        ) {
            self.onHoverChanged = onHoverChanged
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
        }
    }

    final class ResizeEventView: NSView {
        weak var coordinator: Coordinator?
        private var trackingArea: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
            trackingArea = area
            addTrackingArea(area)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.resizeLeftRight.set()
        }

        override func mouseEntered(with event: NSEvent) {
            coordinator?.onHoverChanged(true)
            NSCursor.resizeLeftRight.set()
        }

        override func mouseMoved(with event: NSEvent) {
            coordinator?.onHoverChanged(true)
            NSCursor.resizeLeftRight.set()
        }

        override func mouseExited(with event: NSEvent) {
            coordinator?.onHoverChanged(false)
            if coordinator?.dragStartX == nil {
                NSCursor.arrow.set()
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let coordinator else { return }
            coordinator.dragStartX = event.locationInWindow.x
            coordinator.previousWindowDragState = window?.isMovableByWindowBackground
            window?.isMovableByWindowBackground = false
            coordinator.onHoverChanged(true)
            NSCursor.resizeLeftRight.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let coordinator, let dragStartX = coordinator.dragStartX else { return }
            NSCursor.resizeLeftRight.set()
            coordinator.onDragChanged(event.locationInWindow.x - dragStartX)
        }

        override func mouseUp(with event: NSEvent) {
            guard let coordinator else { return }
            let isStillHovering = bounds.contains(convert(event.locationInWindow, from: nil))
            coordinator.dragStartX = nil
            if let previousWindowDragState = coordinator.previousWindowDragState {
                window?.isMovableByWindowBackground = previousWindowDragState
            }
            coordinator.previousWindowDragState = nil
            coordinator.onHoverChanged(isStillHovering)
            coordinator.onDragEnded()
            if isStillHovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}


/// Walks up to the enclosing NSScrollView and switches it to overlay
/// scrollers. The default "legacy" style paints a solid track background
/// that doesn't blend with the chat surface; overlay scrollers float over
/// content and fade out when idle.
private struct OverlayScrollerHook: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = HookView()
        view.applyOverlayScrollerStyle()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HookView)?.applyOverlayScrollerStyle()
    }

    private final class HookView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyOverlayScrollerStyle()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyOverlayScrollerStyle()
        }

        func applyOverlayScrollerStyle() {
            apply()
            DispatchQueue.main.async { [weak self] in
                self?.apply()
            }
        }

        private func apply() {
            guard let scrollView = enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.drawsBackground = false
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.scrollerStyle = .overlay
            scrollView.horizontalScroller?.scrollerStyle = .overlay
        }
    }
}
