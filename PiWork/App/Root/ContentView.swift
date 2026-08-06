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
                    // The reference sidebar reads as its own panel: a light
                    // gray at the top washing into a pale blue at the bottom,
                    // lighter than the content area at the same height.
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.957, green: 0.961, blue: 0.965),
                                Color(red: 0.855, green: 0.933, blue: 0.984)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Rectangle()
                        .fill(Color.black.opacity(0.04))
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
                                    adaptiveRoundedShape(cornerRadius: 9)
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

/// Single window-spanning gradient (near-white at the top, deepening to a
/// sky blue toward the bottom-trailing corner) drawn once behind the
/// sidebar + content split, so the two panels share one continuous
/// background instead of each drawing its own — matching the reference
/// design's unified backdrop. The axis is mostly vertical with a slight
/// trailing bias, which keeps both top corners near-white and concentrates
/// the blue in the lower half, as in the reference. Uses fixed
/// (non-dynamic) colors since the design is always light-themed.
struct AppBackgroundGradient: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.965, green: 0.972, blue: 0.980), location: 0.00),
                .init(color: Color(red: 0.930, green: 0.950, blue: 0.980), location: 0.35),
                .init(color: Color(red: 0.790, green: 0.870, blue: 0.960), location: 0.70),
                .init(color: Color(red: 0.490, green: 0.700, blue: 0.910), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.15, y: 0.0),
            endPoint: UnitPoint(x: 0.95, y: 1.0)
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
