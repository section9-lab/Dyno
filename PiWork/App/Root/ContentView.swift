import AppKit
import CoreData
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \StoredProject.addedAt, ascending: false)])
    private var projects: FetchedResults<StoredProject>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \StoredKanbanTask.updatedAt, ascending: false)])
    private var allTasks: FetchedResults<StoredKanbanTask>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \StoredSession.updatedAt, ascending: false)])
    private var allSessions: FetchedResults<StoredSession>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \StoredSessionEntry.createdAt, ascending: true)])
    private var allSessionEntries: FetchedResults<StoredSessionEntry>
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedProjectPath: String?
    @State private var selectedSessionID: String?
    @State private var expandedProjectPaths: Set<String> = []
    @State private var showSettingsSheet = false
    @State private var showAccountPopover = false
    @State private var showRemoveProjectAlert = false
    @State private var sessionPendingDeletion: StoredSession?

    private let kanban = KanbanController()
    private let sessionController = SessionController()

    private var sortedTasks: [StoredKanbanTask] {
        allTasks.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status.rawValue < rhs.status.rawValue
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private var selectedProject: StoredProject? {
        guard let selectedProjectPath else { return nil }
        return projects.first(where: { $0.path == selectedProjectPath })
    }

    private var selectedSession: StoredSession? {
        guard let selectedSessionID else { return nil }
        return allSessions.first(where: { $0.id == selectedSessionID })
    }

    private func sessions(for project: StoredProject) -> [StoredSession] {
        allSessions.filter { $0.projectPath == project.path }
    }

    private func entries(for session: StoredSession) -> [StoredSessionEntry] {
        allSessionEntries.filter { $0.sessionID == session.id }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .top) { UserAlertBanner() }
        .toolbar { mainToolbar }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsContainerView()
        }
        .alert("project.remove.title", isPresented: $showRemoveProjectAlert) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                removeSelectedProject()
            }
        } message: {
            Text(selectedProject?.displayName ?? "")
        }
        .alert(
            "session.delete",
            isPresented: Binding(
                get: { sessionPendingDeletion != nil },
                set: { if !$0 { sessionPendingDeletion = nil } }
            )
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                if let session = sessionPendingDeletion {
                    deleteSession(session)
                }
            }
        } message: {
            Text("session.delete.confirm_message")
        }
        .task {
            selectDefaultProjectIfNeeded()
        }
        .onChange(of: projects.count) { _ in
            selectDefaultProjectIfNeeded()
        }
        .frame(minWidth: 1040, minHeight: 760)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    projectRow(title: L10n.tr("project.all"), subtitle: L10n.tr("project.all.subtitle"), systemImage: "square.grid.2x2", path: nil)

                    ForEach(projects, id: \.path) { project in
                        VStack(alignment: .leading, spacing: 2) {
                            projectRow(
                                title: project.displayName,
                                subtitle: project.path,
                                systemImage: project.isMissing ? "exclamationmark.triangle" : "folder",
                                path: project.path,
                                isDimmed: project.isMissing,
                                sessionCount: sessions(for: project).count,
                                isExpanded: expandedProjectPaths.contains(project.path),
                                onToggleExpand: { toggleExpanded(project) }
                            )

                            if expandedProjectPaths.contains(project.path) {
                                ForEach(sessions(for: project), id: \.id) { session in
                                    sessionRow(session)
                                }
                                newSessionButton(for: project)
                            }
                        }
                    }
                } header: {
                    Text("project.sidebar")
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                addProject()
            } label: {
                Label("project.add", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Divider()

            userAvatarSection
        }
        .frame(minWidth: 240)
    }

    private func sessionRow(_ session: StoredSession) -> some View {
        Button {
            selectedProjectPath = session.projectPath
            selectedSessionID = session.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11))
                    .foregroundColor(session.id == selectedSessionID ? .accentColor : .secondary)
                    .frame(width: 14)
                Text(session.title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, 30)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                sessionPendingDeletion = session
            } label: {
                Label("session.delete", systemImage: "trash")
            }
        }
    }

    private func newSessionButton(for project: StoredProject) -> some View {
        Button {
            createSession(for: project)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                Text("session.sidebar.new")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.leading, 30)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // User & Settings entry point, restored at the bottom of the sidebar
    // (its original location before the chat/agent sidebar was removed).
    private var userAvatarSection: some View {
        Button {
            showAccountPopover.toggle()
        } label: {
            HStack(spacing: 10) {
                AccountAvatarImage(
                    url: authSession.user?.avatarURL,
                    fallbackInitial: authSession.user?.avatarInitial ?? "U",
                    fallbackFontSize: 13
                )
                .frame(width: 28, height: 28)

                Text(authSession.user?.displayName ?? L10n.tr("account.google_user"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAccountPopover, arrowEdge: .top) {
            UserAccountPopover(
                isPresented: $showAccountPopover,
                accountName: authSession.user?.displayName ?? L10n.tr("account.google_user"),
                accountSubtitle: authSession.provider.accountTitleKey,
                accountInitial: authSession.user?.avatarInitial ?? "U",
                accountAvatarURL: authSession.user?.avatarURL,
                onSettings: { showSettingsSheet = true },
                onHelp: openHelp,
                onLogout: { authSession.signOut() }
            )
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if projects.isEmpty {
            emptyState(
                title: "project.empty.title",
                subtitle: "project.empty.subtitle",
                buttonTitle: "project.add",
                action: addProject
            )
        } else if let session = selectedSession {
            SessionDetailView(
                session: session,
                entries: entries(for: session),
                onSend: { content in
                    sessionController.addEntry(content: content, to: session, modelContext: viewContext)
                },
                onDeleteEntry: { entry in
                    sessionController.deleteEntry(entry, modelContext: viewContext)
                }
            )
        } else {
            KanbanPanelView(
                projects: Array(projects),
                selectedProjectPath: $selectedProjectPath,
                tasks: sortedTasks,
                onCreateTask: { projectPath, title, priority, status, labels in
                    kanban.createTask(
                        title: title,
                        priority: priority,
                        status: status,
                        labels: labels,
                        projectPath: projectPath,
                        modelContext: viewContext
                    )
                },
                onMoveTask: { task, status in
                    kanban.moveTask(task, to: status)
                },
                onDeleteTask: { task in
                    kanban.deleteTask(task, modelContext: viewContext)
                },
                onUpdateLabels: { task, labels in
                    kanban.setLabels(task, labels: labels)
                }
            )
            .padding(24)
        }
    }

    private func projectRow(
        title: String,
        subtitle: String,
        systemImage: String,
        path: String?,
        isDimmed: Bool = false,
        sessionCount: Int? = nil,
        isExpanded: Bool = false,
        onToggleExpand: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                selectedProjectPath = path
                selectedSessionID = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundColor(path == selectedProjectPath && selectedSessionID == nil ? .accentColor : .secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if path == selectedProjectPath && selectedSessionID == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.vertical, 4)
                .opacity(isDimmed ? 0.7 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onToggleExpand, let sessionCount {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(sessionCount > 0 ? "\(sessionCount)" : "")
            }
        }
    }

    private func emptyState(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        buttonTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 24, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Account/Settings now live in the sidebar footer (userAvatarSection);
    // only project actions remain in the top toolbar.
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                addProject()
            } label: {
                Label("project.add", systemImage: "folder.badge.plus")
            }

            Button {
                showRemoveProjectAlert = true
            } label: {
                Label("project.remove", systemImage: "trash")
            }
            .disabled(selectedProject == nil)
        }
    }

    private func selectDefaultProjectIfNeeded() {
        if let selectedProjectPath,
           projects.contains(where: { $0.path == selectedProjectPath }) {
            return
        }
        selectedProjectPath = projects.first?.path
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.tr("project.add")
        panel.message = L10n.tr("project.add.message")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path

        if !projects.contains(where: { $0.path == path }) {
            _ = StoredProject(context: viewContext, path: path)
            try? viewContext.save()
        }
        selectedProjectPath = path
    }

    private func removeSelectedProject() {
        guard let selectedProjectPath else { return }

        for task in allTasks.filter({ $0.projectPath == selectedProjectPath }) {
            viewContext.delete(task)
        }

        let projectSessionIDs = Set(allSessions.filter { $0.projectPath == selectedProjectPath }.map(\.id))
        for entry in allSessionEntries.filter({ projectSessionIDs.contains($0.sessionID) }) {
            viewContext.delete(entry)
        }
        for session in allSessions.filter({ $0.projectPath == selectedProjectPath }) {
            viewContext.delete(session)
        }

        for project in projects.filter({ $0.path == selectedProjectPath }) {
            viewContext.delete(project)
        }
        try? viewContext.save()

        expandedProjectPaths.remove(selectedProjectPath)
        selectedSessionID = nil
        self.selectedProjectPath = projects.first(where: { $0.path != selectedProjectPath })?.path
    }

    private func toggleExpanded(_ project: StoredProject) {
        if expandedProjectPaths.contains(project.path) {
            expandedProjectPaths.remove(project.path)
        } else {
            expandedProjectPaths.insert(project.path)
        }
    }

    private func createSession(for project: StoredProject) {
        let ordinal = sessions(for: project).count + 1
        let title = L10n.tr("session.default_title_format", ordinal)
        let session = sessionController.createSession(title: title, projectPath: project.path, modelContext: viewContext)
        expandedProjectPaths.insert(project.path)
        selectedProjectPath = project.path
        selectedSessionID = session.id
    }

    private func deleteSession(_ session: StoredSession) {
        sessionController.deleteSession(session, entries: entries(for: session), modelContext: viewContext)
        if selectedSessionID == session.id {
            selectedSessionID = nil
        }
        sessionPendingDeletion = nil
    }

    private func openHelp() {
        if let url = URL(string: "https://github.com/section9-lab/pi-work/issues") {
            NSWorkspace.shared.open(url)
        }
    }
}
