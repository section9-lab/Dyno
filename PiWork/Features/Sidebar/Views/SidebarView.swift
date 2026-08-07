import SwiftUI

/// Left sidebar: a segmented tab header, and — depending on which tab is
/// selected — either the "Chat" conversation-history list or the "Work"
/// folder workspace (nav placeholders + linked project folders), plus a
/// bottom-anchored account row. Layout mirrors the reference design.
///
/// The scrollable/selectable portion is a real system sidebar list
/// (`List(selection:)` + `.listStyle(.sidebar)`), not a hand-rolled
/// `ScrollView`/`VStack` — this gets keyboard navigation, hover states, and
/// accessibility for free from AppKit, while row content still renders our
/// own custom look via `.listRowBackground(Color.clear)` +
/// `.listRowInsets(EdgeInsets())`.

/// Which of the two sidebar surfaces is currently shown below the tab
/// header. `.chat` is conversation history (one row per project you've
/// talked to, framed as a session); `.work` is the folder-management view
/// (nav placeholders + the linked-folder list + "add folder").
enum SidebarTab: Int {
    case chat = 0
    case work = 1
}

struct SidebarView: View {
    @ObservedObject var projectStore: ProjectStore
    @Binding var selectedProject: PiProject?
    var onAddFolder: () -> Void

    @State private var selectedTab: SidebarTab = .work

    var body: some View {
        List(selection: $selectedProject) {
            switch selectedTab {
            case .chat:
                Section {
                    ForEach(projectStore.projects) { project in
                        SessionRow(
                            project: project,
                            isSelected: selectedProject?.id == project.id
                        )
                        .tag(project)
                    }
                } header: {
                    SectionLabel("会话记录")
                }

            case .work:
                Section {
                    NavRow(icon: "square.and.pencil", title: "任务")
                }

                Section {
                    NavRow(icon: "clock", title: "排程")
                    NavRow(icon: "doc.text", title: "技能")
                    NavRow(icon: "puzzlepiece.extension", title: "关联的应用")
                } header: {
                    SectionLabel("自定义")
                }

                Section {
                    ForEach(projectStore.projects) { project in
                        FolderRow(
                            project: project,
                            isSelected: selectedProject?.id == project.id
                        )
                        .tag(project)
                    }

                    AddFolderRow(action: onAddFolder)
                } header: {
                    SectionLabel("已关联的文件夹")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SidebarSelectionFix())
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarTabHeader(selectedTab: $selectedTab)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .compositingGroup()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            UserFooterView()
                .padding(.horizontal, 15)
                .padding(.top, 8)
                .padding(.bottom, 18)
                .compositingGroup()
        }
    }
}

// MARK: - Pieces

/// Full-width segmented control at the top of the sidebar. Switches
/// `selectedTab` between conversation history ("Chat") and the folder
/// workspace ("Work"), which drives what the `List` below shows.
private struct SidebarTabHeader: View {
    @Binding var selectedTab: SidebarTab

    var body: some View {
        HStack(spacing: 0) {
            tab(title: "Chat", tab: .chat)
            tab(title: "Work", badge: "BETA", tab: .work)
        }
        .padding(3)
        .background(AppPalette.segmentedTrack)
        .clipShape(Capsule())
    }

    private func tab(title: String, badge: String? = nil, tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(isSelected ? 0.9 : 0.6))
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium))
                        .kerning(0.4)
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? AppPalette.raisedSurface : Color.clear)
                    .shadow(color: isSelected ? AppPalette.subtleShadow : .clear, radius: 2, y: 1)
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
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.42))
            .compositingGroup()
    }
}

private struct FolderRow: View {
    let project: PiProject
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
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
            adaptiveRoundedShape(cornerRadius: 8)
                .fill(isSelected ? AppPalette.selectedRowFill : (isHovering ? AppPalette.hoverRowFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .padding(.horizontal, 4)
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// A row in the Chat tab's "会话记录" list — same look as `FolderRow`, but
/// framed as a conversation (bubble icon) rather than a folder. Each
/// project has exactly one ongoing chat today, so this reuses the same
/// `PiProject` data and selection binding as the Work tab's folder list.
private struct SessionRow: View {
    let project: PiProject
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "bubble.left.and.bubble.right")
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
            adaptiveRoundedShape(cornerRadius: 8)
                .fill(isSelected ? AppPalette.selectedRowFill : (isHovering ? AppPalette.hoverRowFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .padding(.horizontal, 4)
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// "添加 Mac 文件夹" row. Kept as a plain button (not a taggable/selectable
/// list row) since it triggers the folder picker rather than selecting a
/// project.
private struct AddFolderRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .compositingGroup()
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// Bottom-of-sidebar account row. Shows the signed-in user and opens the
/// account popover (settings / help / sign out).
private struct UserFooterView: View {
    @ObservedObject private var authSession = AuthSession.shared
    @State private var isPopoverPresented = false

    private var displayName: String {
        authSession.user?.displayName ?? "pi-work"
    }

    private var initial: String {
        authSession.user?.avatarInitial ?? "p"
    }

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                AccountAvatarImage(
                    url: authSession.user?.avatarURL,
                    fallbackInitial: initial,
                    fallbackFontSize: 15
                )
                .frame(width: 30, height: 30)
                Text(displayName)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            UserAccountPopover(
                isPresented: $isPopoverPresented,
                accountName: displayName,
                accountSubtitle: authSession.provider.accountSubtitle,
                accountInitial: initial,
                accountAvatarURL: authSession.user?.avatarURL,
                onSettings: { isPopoverPresented = false },
                onHelp: { isPopoverPresented = false },
                onLogout: {
                    isPopoverPresented = false
                    authSession.signOut()
                }
            )
        }
    }
}
