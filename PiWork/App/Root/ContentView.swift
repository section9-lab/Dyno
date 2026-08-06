import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var projectStore = ProjectStore()
    @State private var selectedProject: PiProject?
    @State private var sidebarCollapsed = false

    var body: some View {
        ZStack {
            AppBackgroundGradient()

            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    SidebarView(
                        projectStore: projectStore,
                        selectedProject: $selectedProject,
                        onAddFolder: pickFolder,
                        onToggleSidebar: { withAnimation(.easeInOut(duration: 0.2)) { sidebarCollapsed = true } }
                    )
                    .transition(.move(edge: .leading))

                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 1)
                }

                ZStack(alignment: .topTrailing) {
                    Group {
                        if let project = selectedProject {
                            ChatView(project: project)
                                .id(project.id)
                        } else {
                            WelcomeHeroView(onPickFolder: pickFolder)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if sidebarCollapsed {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { sidebarCollapsed = false }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 28, height: 28)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    BetaBadge()
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }
            }
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

/// Small "Beta 版" pill shown in the top-right corner, matching the
/// reference design. Purely decorative for now.
private struct BetaBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Beta 版")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.controlBackgroundColor))
                .clipShape(Capsule())

            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 16)
        }
    }
}

/// Single window-spanning diagonal gradient (near-white top-leading to a
/// vivid sky blue bottom-trailing) drawn once behind the sidebar + content
/// split, so the two panels share one continuous background instead of each
/// drawing its own — matching the reference design's unified backdrop.
/// Uses fixed (non-dynamic) colors since the reference is always light-
/// themed regardless of system appearance.
struct AppBackgroundGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.97, blue: 0.98),
                Color(red: 0.90, green: 0.93, blue: 0.99),
                Color(red: 0.62, green: 0.79, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
