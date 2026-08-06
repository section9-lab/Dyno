import SwiftUI

/// Left sidebar: a segmented tab header, navigation items (placeholders
/// for now — this rewrite's first milestone is wiring up the real `pi`
/// agent), the list of linked project folders (the working feature), and
/// a bottom-anchored account row. Layout mirrors the reference design.
struct SidebarView: View {
    @ObservedObject var projectStore: ProjectStore
    @Binding var selectedProject: PiProject?
    var onAddFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarTabHeader()
                .padding(.horizontal, 10)
                .padding(.top, 14)

            NavRow(icon: "square.and.pencil", title: "任务")
                .padding(.top, 18)

            SectionLabel("自定义")
                .padding(.top, 18)

            NavRow(icon: "clock", title: "排程")
            NavRow(icon: "doc.text", title: "技能")
            NavRow(icon: "puzzlepiece.extension", title: "关联的应用")

            SectionLabel("已关联的文件夹")
                .padding(.top, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(projectStore.projects) { project in
                        FolderRow(
                            project: project,
                            isSelected: selectedProject?.id == project.id
                        ) {
                            selectedProject = project
                        }
                    }

                    Button(action: onAddFolder) {
                        HStack(spacing: 11) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .regular))
                                .frame(width: 18)
                            Text("添加 Mac 文件夹")
                                .font(.system(size: 14))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            UserFooterView()
                .padding(.horizontal, 15)
                .padding(.bottom, 18)
        }
        .frame(width: 232)
    }
}

// MARK: - Pieces

/// Full-width segmented control at the top of the sidebar. Decorative for
/// now: there is only one surface today, so the tabs are a placeholder for
/// a future split between chat history and the project workspace.
private struct SidebarTabHeader: View {
    @State private var selectedTab = 1

    var body: some View {
        HStack(spacing: 0) {
            tab(title: "对话", index: 0)
            tab(title: "pi-work", badge: "Beta 版", index: 1)
        }
        .padding(3)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }

    private func tab(title: String, badge: String? = nil, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            selectedTab = index
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(isSelected ? 0.9 : 0.6))
                if let badge {
                    Text(badge)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white : Color.clear)
                    .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 2, y: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct NavRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 14))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.primary.opacity(0.78))
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.42))
            .padding(.horizontal, 15)
            .padding(.bottom, 4)
    }
}

private struct FolderRow: View {
    let project: PiProject
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(project.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.75) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

/// Bottom-of-sidebar account row. Placeholder avatar/name until auth is
/// reintroduced in this rewrite (see the auth-login-guide.md notes carried
/// over from the previous implementation).
private struct UserFooterView: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0.95, green: 0.23, blue: 0.42))
                .frame(width: 30, height: 30)
                .overlay(
                    Text("p")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                )
            Text("pi-work")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.85))
            Spacer(minLength: 0)
        }
    }
}
