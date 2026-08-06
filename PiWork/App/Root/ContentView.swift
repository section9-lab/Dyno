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
                        onAddFolder: pickFolder
                    )
                    .transition(.move(edge: .leading))
                    .background(Color.white.opacity(0.3))

                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 1)
                }

                ZStack(alignment: .top) {
                    Group {
                        if let project = selectedProject {
                            ChatView(project: project)
                                .id(project.id)
                        } else {
                            WelcomeHeroView(onPickFolder: pickFolder)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // The reference puts the sidebar toggle in the content
                    // area's top-left corner (not inside the sidebar), where
                    // it stays put whether the sidebar is open or collapsed.
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) { sidebarCollapsed.toggle() }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        BetaBadge()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        // The design is a fixed light-themed gradient, so pin the color
        // scheme — otherwise system dark mode flips Color.primary to white
        // and the text disappears against the light background.
        .preferredColorScheme(.light)
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
        HStack(spacing: 10) {
            Text("Beta 版")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.85)))

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2, height: 22)
                .clipShape(Capsule())
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
