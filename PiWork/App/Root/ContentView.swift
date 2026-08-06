import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var projectStore = ProjectStore()
    @State private var selectedProject: PiProject?

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                projectStore: projectStore,
                selectedProject: $selectedProject,
                onAddFolder: pickFolder
            )

            Divider()

            Group {
                if let project = selectedProject {
                    ChatView(project: project)
                        .id(project.id)
                } else {
                    WelcomeHeroView(onPickFolder: pickFolder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择项目文件夹"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectStore.addProject(path: url.path)
        selectedProject = projectStore.projects.first { $0.path == url.path }
    }
}

#Preview {
    ContentView()
}
