import SwiftUI

struct ChatSidebarView: View {
    let projects: [ChatProject]
    let selectedProjectPath: String?
    let selectedSessionID: String?
    let expandedProjectPaths: Set<String>
    var onAddProject: () -> Void
    var onCreateSession: (ChatProject) -> Void
    var onToggleProject: (ChatProject) -> Void
    var onSelectProject: (ChatProject) -> Void
    var onRemoveProject: (ChatProject) -> Void
    var onSelectSession: (ChatProject, ChatSession) -> Void
    var onRenameSession: (ChatSession) -> Void
    var onDeleteSession: (ChatSession) -> Void
    var onSettings: () -> Void
    var onHelp: () -> Void
    var onLogout: () -> Void

    @State private var hoveredButtonId: String?
    @State private var showUserPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButtons

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(projects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }

            userAvatarSection
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            sidebarActionButton(
                id: "add_project",
                title: "Add Project",
                systemImage: "folder.badge.plus",
                enabled: true,
                action: onAddProject
            )
        }
        .padding(.top, 12)
    }

    private func projectSection(_ project: ChatProject) -> some View {
        let isSelected = project.path == selectedProjectPath && selectedSessionID == nil
        let isHovered = hoveredButtonId == project.path

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    onToggleProject(project)
                    onSelectProject(project)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: expandedProjectPaths.contains(project.path) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 12)

                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .foregroundColor(.primary)

                            Text(project.path)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onCreateSession(project)
                } label: {
                    Label("New Session", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Start session")

                if project.isMissing {
                    Text("Missing")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(projectBackgroundColor(isSelected: isSelected, isHovered: isHovered))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredButtonId = hovering ? project.path : nil
                }
            }
            .contextMenu {
                Button("Remove Project", systemImage: "trash", role: .destructive) {
                    onRemoveProject(project)
                }
            }

            if expandedProjectPaths.contains(project.path) {
                VStack(alignment: .leading, spacing: 4) {
                    if project.sessions.isEmpty {
                        Text("No sessions")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.leading, 42)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(project.sessions) { session in
                            Button {
                                onSelectSession(project, session)
                            } label: {
                                Text(previewText(for: session.title))
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 28)
                            }
                            .buttonStyle(
                                SidebarRowButtonStyle(
                                    isSelected: project.path == selectedProjectPath && session.id == selectedSessionID,
                                    isHovered: hoveredButtonId == "\(project.path)::\(session.id)"
                                )
                            )
                            .onHover { isHovered in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredButtonId = isHovered ? "\(project.path)::\(session.id)" : nil
                                }
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") {
                                    onRenameSession(session)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    onDeleteSession(session)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sidebarActionButton(
        id: String,
        title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(enabled ? .primary : .secondary)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!enabled)
        .buttonStyle(SidebarRowButtonStyle(isSelected: false, isHovered: hoveredButtonId == id))
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredButtonId = isHovered ? id : nil
            }
        }
    }

    private var userAvatarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showUserPopover {
                UserAccountPopover(
                    isPresented: $showUserPopover,
                    onSettings: onSettings,
                    onHelp: onHelp,
                    onLogout: onLogout
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    showUserPopover.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text("G")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }

                    Text("Guest")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hoveredButtonId == "user_avatar" ? Color.white.opacity(0.4) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    hoveredButtonId = hovering ? "user_avatar" : nil
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func previewText(for text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? "(empty)" : singleLine
    }

    private func projectBackgroundColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.white.opacity(0.55)
        } else if isHovered {
            return Color.white.opacity(0.6)
        }
        return Color.clear
    }
}

struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor())
            )
    }

    private func backgroundColor() -> Color {
        if isSelected {
            return Color.white.opacity(0.55)
        } else if isHovered {
            return Color.white.opacity(0.6)
        }
        return Color.clear
    }
}
