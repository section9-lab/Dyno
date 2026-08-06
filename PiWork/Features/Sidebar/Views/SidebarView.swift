import SwiftUI

/// Left sidebar: navigation (mostly placeholder for now — this rewrite's
/// first milestone is wiring up the real `pi` agent, see AGENTS.md), the
/// list of linked project folders (the working feature), and the user
/// footer. Layout follows the reference design (nav list + "linked
/// folders" section + bottom-anchored user row).
struct SidebarView: View {
    @ObservedObject var projectStore: ProjectStore
    @Binding var selectedProject: PiProject?
    var onAddFolder: () -> Void
    var onToggleSidebar: () -> Void

    private let placeholderNavItems: [(icon: String, title: String)] = [
        ("square.and.pencil", "任务"),
        ("clock", "排程"),
        ("doc.text", "技能"),
        ("cloud", "关联的应用")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarTopBar(onToggleSidebar: onToggleSidebar)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 2) {
                Label(placeholderNavItems[0].title, systemImage: placeholderNavItems[0].icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)

                Text("自定义")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .padding(.horizontal, 12)

                ForEach(placeholderNavItems.dropFirst(), id: \.title) { item in
                    Label(item.title, systemImage: item.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.top, 12)

            HStack {
                Text("已关联的文件夹")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 20)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(projectStore.projects) { project in
                        Button {
                            selectedProject = project
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(project.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(
                                selectedProject?.id == project.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }
                }
            }

            Button(action: onAddFolder) {
                Label("添加 Mac 文件夹", systemImage: "plus")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Spacer()

            UserFooterView()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
    }
}

/// Bottom-of-sidebar account row. Placeholder avatar/name until auth is
/// reintroduced in this rewrite (see the auth-login-guide.md notes carried
/// over from the previous implementation).
private struct UserFooterView: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.pink)
                .frame(width: 28, height: 28)
                .overlay(Text("P").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
            Text("pi-work")
                .font(.system(size: 13))
            Spacer()
        }
    }
}

/// Top row of the sidebar: a sidebar-collapse toggle and a segmented
/// "对话 / pi-work Beta 版" tab, matching the reference design's top bar.
/// The tab control is currently decorative (single surface today); it's a
/// placeholder for a future distinction between chat history and the
/// project workspace itself.
private struct SidebarTopBar: View {
    var onToggleSidebar: () -> Void
    @State private var selectedTab = 0

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                tabButton(title: "对话", index: 0)
                tabButton(title: "pi-work", badge: "Beta 版", index: 1)
            }
            .padding(2)
            .background(Color(.controlBackgroundColor))
            .clipShape(Capsule())
        }
    }

    private func tabButton(title: String, badge: String? = nil, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selectedTab == index ? Color(.windowBackgroundColor) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
