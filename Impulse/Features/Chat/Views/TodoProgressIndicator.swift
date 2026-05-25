import SwiftHarnessAgent
import SwiftUI

/// Side-notch indicator pinned to the trailing edge of the chat surface.
/// When project files are available, the collapsed black dock hosts the todo
/// progress above the file icon so the edge controls read as one unit.
struct TodoProgressIndicator: View {
    @ObservedObject var sessionAgent: SessionAgent

    var body: some View {
        FilesIslandPill(
            projectPath: sessionAgent.projectPath,
            phases: sessionAgent.todoPhases
        )
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Island shell

/// Side-notch shape matching the iPhone side-button reference design.
///
/// Geometry (clockwise from top-right):
/// - Right edge: perfectly straight vertical line, flush with the screen edge
/// - Bottom curve: cubic Bezier from (w, h) sweeping left-up to (0, h-r),
///   with VERTICAL tangents at both ends so the curve flows seamlessly into
///   the right edge below and into the left straight edge above
/// - Left edge: straight vertical line (where the icon sits)
/// - Top curve: cubic Bezier mirror of the bottom curve
///
/// The shape has NO horizontal segments — the right and left edges are
/// vertical, and the two curves taper between them. The vertical-tangent
/// control points create the smooth "embedded in the edge" look.
///
/// Curve height is computed as a fraction of total height (~22%) to match
/// the reference design's proportions, regardless of pill size.
private struct SideNotchShape: Shape {
    /// Fraction of total height taken by each end curve. The reference design
    /// uses ~0.22, leaving ~0.56 for the straight middle section.
    var curveFraction: CGFloat = 0.22

    /// Hard cap so very tall pills don't get curves that are too elongated.
    var maxCurveHeight: CGFloat = 60

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = min(h * curveFraction, h / 2, maxCurveHeight)

        var path = Path()
        path.move(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))

        path.addCurve(
            to: CGPoint(x: 0, y: h - r),
            control1: CGPoint(x: w, y: h - r),
            control2: CGPoint(x: 0, y: h)
        )

        path.addLine(to: CGPoint(x: 0, y: r))

        path.addCurve(
            to: CGPoint(x: w, y: 0),
            control1: CGPoint(x: 0, y: 0),
            control2: CGPoint(x: w, y: r)
        )

        path.closeSubpath()
        return path
    }
}

/// Pill silhouette variants. `.notch` is the tall iPhone side-button shape
/// with full-width S-curve transitions (use for narrow vertical pills).
/// `.card` is a wider panel that keeps the same edge-attached treatment:
/// rounded corners on the exposed left side and SideNotch-style curves on
/// the right where it attaches to the screen edge.
private enum IslandShellStyle {
    case notch
    case card
}

/// Card shape for the expanded files panel. The exposed left side is a
/// conventional rounded card edge; the edge-facing right side is a full
/// straight edge so it can sit flush against the screen boundary like the
/// collapsed iOS-style side key.
private struct NotchCardShape: Shape {
    /// Radius of the exposed left corners.
    var leftCornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let lcr = min(leftCornerRadius, h / 2, w / 4)

        var path = Path()

        path.move(to: CGPoint(x: lcr, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: lcr, y: h))

        path.addCurve(
            to: CGPoint(x: 0, y: h - lcr),
            control1: CGPoint(x: lcr * 0.45, y: h),
            control2: CGPoint(x: 0, y: h - lcr * 0.45)
        )

        path.addLine(to: CGPoint(x: 0, y: lcr))

        path.addCurve(
            to: CGPoint(x: lcr, y: 0),
            control1: CGPoint(x: 0, y: lcr * 0.45),
            control2: CGPoint(x: lcr * 0.45, y: 0)
        )

        path.closeSubpath()
        return path
    }
}

/// Wraps content in a dark pill pinned to the trailing edge. The right side
/// is always flat against the screen edge; the left side rounds either as
/// an iPhone side-notch or as a smooth squircle card depending on `style`.
private struct IslandShell<Content: View>: View {
    let style: IslandShellStyle
    let content: Content

    init(style: IslandShellStyle = .notch, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        Group {
            switch style {
            case .notch:
                content
                    .background(SideNotchShape().fill(Color.black.opacity(0.88)))
                    .clipShape(SideNotchShape())
                    .overlay(
                        SideNotchShape()
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            case .card:
                content
                    .background(NotchCardShape().fill(Color.black.opacity(0.88)))
                    .clipShape(NotchCardShape())
                    .overlay(
                        NotchCardShape()
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            }
        }
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: -2, y: 2)
    }
}

private extension Animation {
    static var islandDock: Animation {
        .spring(response: 0.36, dampingFraction: 0.84, blendDuration: 0.08)
    }
}

private extension AnyTransition {
    static var islandDock: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98, anchor: .trailing)),
            removal: .opacity
                .combined(with: .scale(scale: 0.98, anchor: .trailing))
        )
    }

    static var islandBody: AnyTransition {
        .opacity
            .combined(with: .move(edge: .top))
    }
}

// MARK: - Todo pill

private struct TodoIslandPill: View {
    let phases: [TodoPhase]
    @State private var isExpanded: Bool = false

    private let expandedWidth: CGFloat = 320

    var body: some View {
        IslandShell {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.islandDock) {
                        isExpanded.toggle()
                    }
                } label: {
                    pillHeader
                }
                .buttonStyle(.plain)
                .help(helpText)

                if isExpanded {
                    VStack(spacing: 0) {
                        Divider()
                            .overlay(Color.white.opacity(0.10))
                            .padding(.horizontal, 14)

                        expandedBody
                            .frame(width: expandedWidth, alignment: .leading)
                    }
                    .transition(.islandBody)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .animation(.islandDock, value: isExpanded)
    }

    @ViewBuilder
    private var pillHeader: some View {
        HStack(spacing: 10) {
            TodoProgressRing(percent: completionPercent)
                .frame(width: 16, height: 16)

            Text(progressLabel)
                .chatFont(.footnote, weight: .semibold, design: .monospaced)
                .foregroundColor(.white)

            if !isExpanded, let active = currentInProgressTitle {
                Text(active)
                    .chatFont(.footnote)
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .leading)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
        .frame(width: isExpanded ? expandedWidth : nil, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var expandedBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(allTasks, id: \.id) { entry in
                    IslandTaskRow(task: entry.task)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(maxHeight: 380)
    }

    private var totalTasks: Int {
        phases.reduce(0) { $0 + $1.tasks.count }
    }

    private var completedTasks: Int {
        phases.reduce(0) { acc, phase in
            acc + phase.tasks.filter { $0.status == .completed }.count
        }
    }

    private var completionPercent: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    private var progressLabel: String {
        "\(completedTasks)/\(totalTasks)"
    }

    private var currentInProgressTitle: String? {
        for phase in phases {
            if let task = phase.tasks.first(where: { $0.status == .inProgress }) {
                return task.content
            }
        }
        return nil
    }

    private var helpText: String {
        if let current = currentInProgressTitle {
            return "Todos: \(progressLabel) — \(current)"
        }
        return "Todos: \(progressLabel)"
    }

    private var allTasks: [TaskEntry] {
        var out: [TaskEntry] = []
        for (phaseIndex, phase) in phases.enumerated() {
            for (taskIndex, task) in phase.tasks.enumerated() {
                out.append(TaskEntry(id: "\(phaseIndex)-\(taskIndex)", task: task))
            }
        }
        return out
    }

    private struct TaskEntry {
        let id: String
        let task: TodoItem
    }
}

// MARK: - Files pill

private struct FilesIslandPill: View {
    let projectPath: String
    let phases: [TodoPhase]
    @State private var expandedMode: ExpandedMode? = nil
    @State private var entries: [Entry] = []
    @State private var loadState: LoadState = .loading
    /// Path currently being browsed. Starts at `projectPath` and is updated
    /// when the user drills into / out of subdirectories.
    @State private var currentPath: String = ""

    private let maxEntries = 80
    private let collapsedWidth: CGFloat = 30
    private let collapsedTodoOnlyHeight: CGFloat = 92
    private let collapsedWithTodoHeight: CGFloat = 176
    private let expandedWidth: CGFloat = 220
    private let expandedMaxHeight: CGFloat = 420
    private let cardCornerRadius: CGFloat = 32

    var body: some View {
        ZStack(alignment: .trailing) {
            if let expandedMode {
                IslandShell(style: .card) {
                    switch expandedMode {
                    case .todo:
                        expandedTodoView
                    case .files:
                        expandedFilesView
                    }
                }
                .id(expandedMode)
                .transition(.islandDock)
            }

            if expandedMode == nil {
                IslandShell(style: .notch) { collapsedView }
                    .transition(.islandDock)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .animation(.islandDock, value: expandedMode)
        .task(id: projectPath) {
            // Reset to project root when the project itself changes.
            currentPath = projectPath
            if showsProjectFiles {
                loadEntries()
            } else {
                entries = []
                loadState = .loading
                if expandedMode == .files {
                    expandedMode = nil
                }
            }
        }
        .onChange(of: currentPath) { _, _ in
            if showsProjectFiles {
                loadEntries()
            }
        }
    }

    private var collapsedView: some View {
        VStack(spacing: 0) {
            Button {
                expandTodo()
            } label: {
                Group {
                    if hasTodos {
                        collapsedTodoProgress
                    } else {
                        Image(systemName: "checklist")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))
                    }
                }
                .frame(width: collapsedWidth, height: showsProjectFiles ? 78 : collapsedTodoOnlyHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(todoHelpText)

            if showsProjectFiles {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 16, height: 1)

                Button {
                    expandFiles()
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .frame(width: collapsedWidth, height: 78)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(URL(fileURLWithPath: projectPath).lastPathComponent)
            }
        }
        .frame(width: collapsedWidth, height: collapsedHeight)
    }

    private var collapsedTodoProgress: some View {
        VStack(spacing: 5) {
            TodoProgressRing(percent: completionPercent)
                .frame(width: 18, height: 18)

            Text(progressLabel)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(width: collapsedWidth - 4)
        }
    }

    private var expandedFilesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
                .overlay(Color.white.opacity(0.10))
                .padding(.horizontal, 14)
            bodyContent
        }
        .frame(width: expandedWidth, alignment: .leading)
        .frame(maxHeight: expandedMaxHeight, alignment: .top)
    }

    private var expandedTodoView: some View {
        VStack(alignment: .leading, spacing: 0) {
            todoHeaderRow
            Divider()
                .overlay(Color.white.opacity(0.10))
                .padding(.horizontal, 14)
            todoBodyContent
        }
        .frame(width: expandedWidth, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            if canGoUp {
                Button {
                    goUp()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Go up")
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 18, alignment: .leading)
            }

            Text(currentFolderName)
                .chatFont(.footnote, weight: .semibold)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                collapse()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 30)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    private var todoHeaderRow: some View {
        HStack(spacing: 8) {
            if hasTodos {
                TodoProgressRing(percent: completionPercent)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(width: 16, height: 16)
            }

            Text(progressLabel)
                .chatFont(.footnote, weight: .semibold, design: .monospaced)
                .foregroundColor(.white)

            if let current = currentInProgressTitle {
                Text(current)
                    .chatFont(.footnote)
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 96, alignment: .leading)
            }

            Spacer(minLength: 8)

            Button {
                collapse()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 30)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var todoBodyContent: some View {
        if allTasks.isEmpty {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.bottom, 8)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allTasks, id: \.id) { entry in
                        IslandTaskRow(task: entry.task)
                    }
                }
                .padding(.leading, 30)
                .padding(.trailing, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 380)
        }
    }

    private var hasTodos: Bool {
        !phases.isEmpty
    }

    private var showsProjectFiles: Bool {
        !projectPath.isEmpty
    }

    private var collapsedHeight: CGFloat {
        showsProjectFiles ? collapsedWithTodoHeight : collapsedTodoOnlyHeight
    }

    private var totalTasks: Int {
        phases.reduce(0) { $0 + $1.tasks.count }
    }

    private var completedTasks: Int {
        phases.reduce(0) { acc, phase in
            acc + phase.tasks.filter { $0.status == .completed }.count
        }
    }

    private var completionPercent: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    private var progressLabel: String {
        "\(completedTasks)/\(totalTasks)"
    }

    private var currentInProgressTitle: String? {
        for phase in phases {
            if let task = phase.tasks.first(where: { $0.status == .inProgress }) {
                return task.content
            }
        }
        return nil
    }

    private var todoHelpText: String {
        if let current = currentInProgressTitle {
            return "Todos: \(progressLabel) — \(current)"
        }
        return "Todos: \(progressLabel)"
    }

    private var allTasks: [TaskEntry] {
        var out: [TaskEntry] = []
        for (phaseIndex, phase) in phases.enumerated() {
            for (taskIndex, task) in phase.tasks.enumerated() {
                out.append(TaskEntry(id: "\(phaseIndex)-\(taskIndex)", task: task))
            }
        }
        return out
    }

    private var canGoUp: Bool {
        currentPath != projectPath && !currentPath.isEmpty
    }

    private var currentFolderName: String {
        let path = currentPath.isEmpty ? projectPath : currentPath
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func goUp() {
        let url = URL(fileURLWithPath: currentPath)
        let parent = url.deletingLastPathComponent().path
        // Never navigate above the project root.
        if parent.hasPrefix(projectPath) || parent == projectPath {
            currentPath = parent
        } else {
            currentPath = projectPath
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch loadState {
        case .loading:
            HStack {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        case .error:
            emptyText(key: "todo.popover.project_files.error")
        case .loaded where entries.isEmpty:
            emptyText(key: "todo.popover.project_files.empty")
        case .loaded:
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries, id: \.url) { entry in
                        Button {
                            openEntry(entry)
                        } label: {
                            IslandFileRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, max(12, cardCornerRadius - 12))
            }
            .scrollClipDisabled(false)
        }
    }

    private func emptyText(key: LocalizedStringKey) -> some View {
        Text(key)
            .chatFont(.footnote)
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandTodo() {
        withAnimation(.islandDock) {
            expandedMode = .todo
        }
    }

    private func expandFiles() {
        withAnimation(.islandDock) {
            expandedMode = .files
        }
        if loadState != .loaded {
            loadEntries()
        }
    }

    private func collapse() {
        withAnimation(.islandDock) {
            expandedMode = nil
        }
    }

    private func openEntry(_ entry: Entry) {
        if entry.isDirectory {
            currentPath = entry.url.path
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        }
    }

    private func loadEntries() {
        guard showsProjectFiles else {
            entries = []
            loadState = .loading
            return
        }

        let path = currentPath.isEmpty ? projectPath : currentPath
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        do {
            let raw = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles]
            )
            let filtered = raw.filter { !Self.skippedDirectoryNames.contains($0.lastPathComponent) }
            let sorted = filtered.sorted { lhs, rhs in
                let lDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let rDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if lDir != rDir { return lDir && !rDir }
                return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
            entries = sorted.prefix(maxEntries).map {
                let isDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return Entry(url: $0, isDirectory: isDir)
            }
            loadState = .loaded
        } catch {
            entries = []
            loadState = .error
        }
    }

    fileprivate struct Entry {
        let url: URL
        let isDirectory: Bool
    }

    fileprivate enum LoadState {
        case loading, loaded, error
    }

    private enum ExpandedMode: Equatable {
        case todo, files
    }

    private struct TaskEntry {
        let id: String
        let task: TodoItem
    }

    private static let skippedDirectoryNames: Set<String> = [
        "node_modules", ".git", ".build", "DerivedData", "build",
        ".next", ".turbo", "dist", ".venv", "venv", "__pycache__",
        ".idea", ".vscode"
    ]
}

// MARK: - Shared row views

private struct TodoProgressRing: View {
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.001, min(1.0, percent)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: percent)
        }
    }
}

private struct IslandTaskRow: View {
    let task: TodoItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(iconColor)
                .frame(width: 14)
            Text(task.content)
                .chatFont(.footnote)
                .foregroundColor(textColor)
                .strikethrough(task.status == .completed || task.status == .abandoned, color: .white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var iconName: String {
        switch task.status {
        case .pending: return "circle"
        case .inProgress: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .abandoned: return "minus.circle"
        }
    }

    private var iconColor: Color {
        switch task.status {
        case .pending: return .white.opacity(0.45)
        case .inProgress: return .accentColor
        case .completed: return .green
        case .abandoned: return .white.opacity(0.35)
        }
    }

    private var textColor: Color {
        switch task.status {
        case .pending: return .white.opacity(0.85)
        case .inProgress: return .white
        case .completed: return .white.opacity(0.55)
        case .abandoned: return .white.opacity(0.45)
        }
    }
}

private struct IslandFileRow: View {
    let entry: FilesIslandPill.Entry
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(isHovering ? 0.85 : 0.55))
                .frame(width: 14)
            Text(entry.url.lastPathComponent)
                .chatFont(.footnote)
                .foregroundColor(.white.opacity(isHovering ? 1.0 : 0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
