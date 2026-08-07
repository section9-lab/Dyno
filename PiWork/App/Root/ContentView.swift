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
        .background(TrafficLightPositioner(offset: SidebarPanelMetrics.trafficLightOffset))
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

    /// The traffic lights belong to the window, so AppKit parks them in the
    /// window's own corner — which lands them on the panel's rounded corner
    /// once the panel is inset. The downward nudge is capped by the title
    /// bar's own height (see `TrafficLightPositioner`), so the horizontal
    /// nudge is kept modest too, to stay visually balanced.
    static let trafficLightOffset = CGSize(width: 10, height: 6)

    /// Clearance the sidebar's own content keeps below the traffic lights so
    /// the tab header doesn't crowd them.
    static let contentTopInset: CGFloat = 6

    static let surface = AppPalette.sidebarSurface
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
                        .stroke(AppPalette.panelBorder, lineWidth: 0.5)
                )
                .shadow(color: AppPalette.raisedShadow, radius: 9, y: 2)
                .padding(SidebarPanelMetrics.inset)
                .ignoresSafeArea()

            content
                .padding(.horizontal, SidebarPanelMetrics.inset)
                .padding(.top, SidebarPanelMetrics.contentTopInset)
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
                        .fill(AppPalette.raisedSurface)
                        .shadow(color: AppPalette.subtleShadow, radius: 3, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Small "BETA" pill shown in the top-right corner, matching the reference
/// design. Shares the tab header badge's type so the two never drift apart.
/// Purely decorative for now.
private struct BetaBadge: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("BETA")
                .font(.system(size: 9, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(AppPalette.translucentSurface))

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2, height: 22)
                .clipShape(Capsule())
        }
    }
}

/// Single window-spanning gradient drawn once behind the sidebar + content
/// split, so the two panels share one continuous background instead of each
/// drawing its own — matching the reference design's unified backdrop.
/// See `AppPalette.windowGradient` for the light/dark stops.
struct AppBackgroundGradient: View {
    var body: some View {
        AppPalette.windowGradient
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
