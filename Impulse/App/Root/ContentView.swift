import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp) private var items: [Item]
    @StateObject private var vm = ChatViewModel()
    @StateObject private var agent = AgentManager.shared

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
                            newTaskTitle: $vm.newKanbanTitle,
                            newTaskPriority: $vm.newKanbanPriority,
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
            .background(Color(red: 0.95, green: 0.95, blue: 0.96))
            .navigationTitle("")
            .toolbarBackground(Color(red: 0.95, green: 0.95, blue: 0.96), for: .windowToolbar)
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
                            vm.showKanbanPanel ? "Hide Board" : "Show Board",
                            systemImage: vm.showKanbanPanel ? "rectangle.compress.vertical" : "rectangle.3.group"
                        )
                    }
                    .labelStyle(.iconOnly)
                    .help("Toggle project Kanban")
                }
            }
            .sheet(isPresented: $vm.showConfigSheet) {
                SettingsContainerView(agent: agent)
            }
            .alert("Rename session", isPresented: $vm.showRenameDialog) {
                TextField("Session title", text: $vm.renameDraft)
                Button("Cancel", role: .cancel) {
                    vm.renamingSessionID = nil
                }
                Button("Save") {
                    applyRename()
                }
                .disabled(!vm.renameDraft.isNotBlank)
            } message: {
                Text("Rename selected session")
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
            .animation(.easeInOut(duration: 0.2), value: vm.showKanbanPanel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if !projects.isEmpty {
                Text("Select a session from the sidebar")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.88))
            } else {
                Text("No project available")
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
                .fill(Color.black.opacity(0.16))
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

    private func createKanbanTask() {
        vm.createKanbanTask()
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
