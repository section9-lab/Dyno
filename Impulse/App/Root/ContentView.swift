import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp) private var items: [Item]
    @StateObject private var vm = ChatViewModel()
    @StateObject private var agent = AgentManager.shared
    @StateObject private var approvals = ToolApprovalCenter.shared
    @EnvironmentObject private var authSession: AuthSession

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

    private var kanbanTasks: [KanbanTaskSnapshot] {
        vm.makeKanbanTasks(from: items)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if !vm.isSidebarCollapsed {
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
                        onLogout: handleLogout
                    )
                    .frame(width: vm.sidebarWidth)

                    sidebarResizeHandle
                }

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
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))

                        Divider()
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                if selectedSession == nil {
                                    emptyState
                                } else {
                                    ForEach(displayedItems) { item in
                                        if item.kind == "compaction_summary" {
                                            EmptyView()
                                                .id(item.id)
                                        } else if item.kind == "tool_execution",
                                                  let payload = decodePersistedToolExecution(from: item.content)
                                        {
                                            PersistedToolExecutionMessageView(execution: payload)
                                                .id(item.id)
                                        } else {
                                            MessageView(item: item)
                                                .id(item.id)
                                        }
                                    }

                                    AgentResponseView(agent: agent)
                                        .id("agent_response")
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
                        .onChange(of: agent.isResponding) { _, responding in
                            if responding {
                                proxy.scrollTo("agent_response", anchor: .bottom)
                            }
                        }
                        .onChange(of: vm.selectedSessionID) { _, _ in
                            scrollToBottom(proxy: proxy, id: selectedSession?.messages.last?.id)
                        }
                    }

                    InputBar(
                        inputText: $vm.inputText,
                        projects: projects,
                        selectedProjectPath: vm.selectedProjectPath,
                        isResponding: agent.isResponding,
                        onSelectProject: { vm.selectProject($0.path, agent: agent) },
                        onSend: sendMessage
                    )
                }
            }
            .background(MetalParticleBackground(isDark: colorScheme == .dark))
            .navigationTitle("")
            .toolbarBackground(toolbarBackgroundColor, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar {
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
            .sheet(isPresented: $vm.showConfigSheet) {
                SettingsContainerView(agent: agent)
            }
            .alert("chat.rename_session", isPresented: $vm.showRenameDialog) {
                TextField("chat.session_title", text: $vm.renameDraft)
                Button("common.cancel", role: .cancel) {
                    vm.renamingSessionID = nil
                }
                Button("common.save") {
                    applyRename()
                }
                .disabled(!vm.renameDraft.isNotBlank)
            } message: {
                Text("chat.rename_selected_session")
            }
            .alert(item: $approvals.pendingRequest) { request in
                Alert(
                    title: Text("Dangerous Operation"),
                    message: Text("\(request.reason)\n\n\(request.summary)"),
                    primaryButton: .destructive(Text("Run Once")) {
                        approvals.approve(request)
                    },
                    secondaryButton: .cancel(Text("Reject")) {
                        approvals.reject(request)
                    }
                )
            }
            .task {
                vm.loadConversationsFromSessionFilesIfNeeded(items: items, modelContext: modelContext, agent: agent)
                await agent.refreshServiceStatus()
                persistProjects()
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

    private var toolbarBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.095, green: 0.098, blue: 0.106)
            : Color(red: 0.95, green: 0.95, blue: 0.96)
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

    private func decodePersistedToolExecution(from raw: String) -> PersistedToolExecution? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PersistedToolExecution.self, from: data)
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
        let didRename = vm.applyRename(items: items)
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
        .modelContainer(for: Item.self, inMemory: true)
}
