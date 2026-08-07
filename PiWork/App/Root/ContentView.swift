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
                    SidebarPanel {
                        SidebarView(
                            projectStore: projectStore,
                            selectedProject: $selectedProject,
                            onAddFolder: pickFolder
                        )
                    }
                    .transition(.move(edge: .leading))
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
                        SidebarToggleButton {
                            withAnimation(.easeInOut(duration: 0.22)) { sidebarCollapsed.toggle() }
                        }

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

/// Geometry + surface colors for the floating sidebar panel, kept in one
/// place so the inset and the corner radius can be tuned together.
private enum SidebarPanelMetrics {
    /// Gap between the panel and the window edges — the window gradient
    /// shows through here, which is what makes the panel read as floating.
    static let inset: CGFloat = 9
    static let cornerRadius: CGFloat = 16
    static let contentWidth: CGFloat = 236
    static var columnWidth: CGFloat { contentWidth + inset * 2 }

    static let surface = LinearGradient(
        colors: [
            Color(red: 0.972, green: 0.976, blue: 0.980),
            Color(red: 0.870, green: 0.938, blue: 0.984)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// The reference design's sidebar is a rounded card inset from every window
/// edge, hovering above the content gradient rather than being a flush
/// column with a split divider.
///
/// macOS 26 renders `NavigationSplitView` sidebars this way natively, but
/// only for apps linked against the macOS 26 SDK — and on macOS 13-25 there
/// is no system affordance for it at all (the split view always paints an
/// edge-to-edge column plus a divider, and its automatic toolbar toggle
/// cannot be removed before macOS 14). So the panel *chrome* is drawn here
/// while the panel's interior stays a real system `List(.sidebar)`.
///
/// The card deliberately ignores the safe area so it runs the full height of
/// the window, behind the traffic lights, while `content` stays inside the
/// safe area so the tab header clears them.
private struct SidebarPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            adaptiveRoundedShape(cornerRadius: SidebarPanelMetrics.cornerRadius)
                .fill(SidebarPanelMetrics.surface)
                .overlay(
                    adaptiveRoundedShape(cornerRadius: SidebarPanelMetrics.cornerRadius)
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.09), radius: 9, y: 2)
                .padding(SidebarPanelMetrics.inset)
                .ignoresSafeArea()

            content
                .padding(.horizontal, SidebarPanelMetrics.inset)
                .padding(.bottom, SidebarPanelMetrics.inset)
        }
        .frame(width: SidebarPanelMetrics.columnWidth)
    }
}

/// Floating rounded-square button that collapses/expands the sidebar. Drawn
/// by hand rather than using `NavigationSplitView`'s automatic toolbar
/// toggle, which sits in the title bar and can't be restyled or moved.
private struct SidebarToggleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
