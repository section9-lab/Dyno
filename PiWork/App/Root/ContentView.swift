import AppKit
import CoreData
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \StoredProject.addedAt, ascending: false)])
    private var projects: FetchedResults<StoredProject>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \StoredKanbanTask.updatedAt, ascending: false)])
    private var allTasks: FetchedResults<StoredKanbanTask>
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedProjectPath: String?
    @State private var showSettingsSheet = false
    @State private var showAccountPopover = false
    @State private var showRemoveProjectAlert = false

    private let kanban = KanbanController()

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
                        projectRow(
                            title: project.displayName,
                            subtitle: project.path,
                            systemImage: project.isMissing ? "exclamationmark.triangle" : "folder",
                            path: project.path,
                            isDimmed: project.isMissing
                        )
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
        }
        .frame(minWidth: 240)
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
        isDimmed: Bool = false
    ) -> some View {
        Button {
            selectedProjectPath = path
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundColor(path == selectedProjectPath ? .accentColor : .secondary)
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
                if path == selectedProjectPath {
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

            Button {
                showSettingsSheet = true
            } label: {
                Label("settings.title", systemImage: "gearshape")
            }

            Button {
                openHelp()
            } label: {
                Label("common.help", systemImage: "questionmark.circle")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                showAccountPopover.toggle()
            } label: {
                AccountAvatarImage(
                    url: authSession.user?.avatarURL,
                    fallbackInitial: authSession.user?.avatarInitial ?? "U",
                    fallbackFontSize: 13
                )
                .frame(width: 28, height: 28)
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
        for project in projects.filter({ $0.path == selectedProjectPath }) {
            viewContext.delete(project)
        }
        try? viewContext.save()

        self.selectedProjectPath = projects.first(where: { $0.path != selectedProjectPath })?.path
    }

    private func openHelp() {
        if let url = URL(string: "https://github.com/section9-lab/pi-work/issues") {
            NSWorkspace.shared.open(url)
        }
    }
}
