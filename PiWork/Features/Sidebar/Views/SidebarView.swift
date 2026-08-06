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

    private let placeholderNavItems: [(icon: String, title: String)] = [
        ("checklist", "任务"),
        ("clock", "排程"),
        ("puzzlepiece.extension", "技能"),
        ("app.connected.to.app.below.fill", "关联的应用")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(placeholderNavItems, id: \.title) { item in
                    Label(item.title, systemImage: item.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.top, 16)

            Divider().padding(.vertical, 8)

            HStack {
                Text("已关联的文件夹")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)

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

            Divider()

            UserFooterView()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
        .background(
            LinearGradient(
                colors: [Color(.windowBackgroundColor), Color.blue.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
