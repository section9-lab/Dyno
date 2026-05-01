import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var storedSessions: [StoredSession]
    @StateObject private var vm = ChatViewModel()
    @StateObject private var agent = AgentManager.shared
    @StateObject private var approvals = ToolApprovalCenter.shared
    @EnvironmentObject private var authSession: AuthSession

    /// All chat rows projected to value-type `Item` for the UI. Computed
    /// from the SwiftData `StoredSession` query above; callers further down
    /// (ChatViewModel, ChatHistoryService) treat this as the source of truth
    /// they used to read from the old single-table `Item` query.
    private var items: [Item] {
        vm.flattenAllItems(from: storedSessions)
    }

    private var projects: [ChatProject] {
        vm.makeProjects(from: items)
    }

    private var selectedSession: ChatSession? {
        vm.makeSelectedSession(from: items)
    }

    private var selectedProject: ChatProject? {
        vm.makeSelectedProject(from: items)
    }

    private var displayedItems: [Item] {
        vm.makeDisplayedItems(from: items)
    }

    private var displayedRows: [ChatRow] {
        vm.makeDisplayedRows(from: items)
    }

    private var kanbanTasks: [KanbanTaskSnapshot] {
        vm.makeKanbanTasks(from: items)
    }

    /// The SessionAgent powering the focused session.
    /// Returns nil if no session is selected or the agent hasn't been
    /// initialized yet — view lifecycle (`.task` / `.onChange`) creates it,
    /// keeping side-effects out of the SwiftUI body.
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
                vm.loadConversationsFromSessionFilesIfNeeded(items: items, modelContext: modelContext, agent: agent)
                await agent.refreshServiceStatus()
                persistProjects()
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
            .onChange(of: items.count) { _, _ in
                if !vm.isImportingSessionFiles {
                    persistProjects()
                }
            }
            .frame(minWidth: 980, minHeight: 760)
            .animation(.easeInOut(duration: 0.2), value: vm.showKanbanPanel)
        }
    }

    // MARK: - Body subviews
    //
    // SwiftUI's type-checker can't handle the original 170-line `body` in
    // reasonable time (Swift 6 compiler limit). Each subview owns one chunk
    // and stays under the threshold individually.

    private var sidebar: some View {
        ChatSidebarView(
            projects: projects,
            selectedProjectPath: vm.selectedProjectPath,
            selectedSessionID: vm.selectedSessionID,
            expandedProjectPaths: vm.expandedProjectPaths,
            onAddProject: addProject,
            onCreateSession: createSession,
            onToggleProject: { vm.toggleProjectExpansion($0.path) },
            onSelectProject: { vm.selectProject($0.path, agent: agent) },
            onRemoveProject: removeProject,
            onSelectSession: { project, session in
                vm.selectSession(projectPath: project.path, sessionID: session.id, agent: agent)
            },
            onRenameSession: requestRename,
            onDeleteSession: deleteSession,
            onSettings: openSettings,
            onHelp: openHelp,
            accountName: authSession.user?.displayName ?? L10n.tr("account.google_user"),
            accountSubtitle: authSession.provider.accountTitleKey,
            accountInitial: authSession.user?.avatarInitial ?? "G",
            accountAvatarURL: authSession.user?.avatarURL,
            onLogout: handleLogout
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
                    onCreateTask: createKanbanTask,
                    onMoveTask: moveKanbanTask,
                    onLinkSelectedSession: linkSelectedSessionToKanbanTask,
                    onDeleteTask: deleteKanbanTask
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
                        ForEach(displayedRows) { row in
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
            .onChange(of: items.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(displayedItems.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: focusedSessionAgent?.isResponding ?? false) { _, responding in
                if responding {
                    proxy.scrollTo("agent_response", anchor: .bottom)
                }
            }
            .onChange(of: vm.selectedSessionID) { _, _ in
                scrollToBottom(proxy: proxy, id: selectedSession?.messages.last?.id)
            }
        }
    }

    @ViewBuilder
    private func chatRowView(_ row: ChatRow) -> some View {
        switch row {
        case .message(let item):
            if item.kindEnum == .compactionSummary {
                EmptyView().id(item.id)
            } else {
                MessageView(item: item).id(item.id)
            }
        case .toolGroup(let group):
            ToolExecutionGroupView(group: group).id(group.id)
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
            applyRename()
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

    private func autoCreateSessionIfNeeded() {
        guard selectedProject != nil, selectedSession == nil else { return }
        guard vm.startNewChat(items: items, agent: agent) else { return }
        persistProjects()
    }

    private func addProject() {
        vm.addProject(agent: agent)
        persistProjects()
    }

    private func createSession(_ project: ChatProject) {
        vm.selectProject(project.path, agent: agent)
        guard vm.startNewChat(items: items, agent: agent) else { return }
        persistProjects()
    }

    private func persistProjects() {
        vm.persistProjects(items: items, agent: agent)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, id: AnyHashable?) {
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func sendMessage() {
        vm.sendMessage(
            modelContext: modelContext,
            agent: agent,
            session: selectedSession,
            conversationItems: displayedItems
        ) {
            persistProjects()
        }
    }

    private func requestRename(_ session: ChatSession) {
        vm.requestRename(session)
    }

    private func applyRename() {
        let didRename = vm.applyRename(items: items, modelContext: modelContext)
        guard didRename else { return }
        persistProjects()
    }

    private func deleteSession(_ session: ChatSession) {
        vm.deleteSession(session, modelContext: modelContext)
        persistProjects()
    }

    private func removeProject(_ project: ChatProject) {
        vm.removeProject(project, items: items, modelContext: modelContext, agent: agent)
        persistProjects()
    }

    private func createKanbanTask(_ title: String, _ priority: KanbanTaskPriority, _ status: KanbanTaskStatus) {
        vm.createKanbanTask(title: title, priority: priority, status: status)
        persistProjects()
    }

    private func moveKanbanTask(_ task: KanbanTaskSnapshot, _ status: KanbanTaskStatus) {
        vm.moveKanbanTask(task, to: status)
        persistProjects()
    }

    private func linkSelectedSessionToKanbanTask(_ task: KanbanTaskSnapshot) {
        vm.linkSelectedSessionToKanbanTask(task)
        persistProjects()
    }

    private func deleteKanbanTask(_ task: KanbanTaskSnapshot) {
        vm.deleteKanbanTask(task)
        persistProjects()
    }

    private func openSettings() {
        vm.showConfigSheet = true
    }

    private func openHelp() {
        if let url = URL(string: "https://github.com/section9-lab/Impulse/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleLogout() {
        authSession.signOut()
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
    case message(Item)
    case toolGroup(ToolExecutionGroup)

    var id: String {
        switch self {
        case .message(let item): return "msg-\(item.id.hashValue)"
        case .toolGroup(let group): return group.id
        }
    }
}
