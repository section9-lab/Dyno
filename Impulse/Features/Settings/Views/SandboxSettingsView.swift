import SwiftUI

struct SandboxSettingsView: View {
    @ObservedObject var agent: AgentManager
    @ObservedObject var viewModel: SandboxSettingsViewModel
    @StateObject private var sandbox = SandboxAccessManager.shared

    @State private var expandedFolders: Set<String> = []
    @State private var agentEntries: [SandboxTreeRowEntry] = []
    @State private var selectedTextPreview: SandboxTextPreview?

    private let actionRowWidth: CGFloat = 420

    private var storageDirectoryURL: URL {
        agent.storageDirectoryURL
    }

    var body: some View {
        VStack(spacing: 14) {
            agentStateCard
            sandboxCard
        }
        .sheet(item: $selectedTextPreview) { preview in
            textPreviewSheet(preview)
        }
        .onAppear {
            refreshAgentEntries()
        }
    }
    
    private var agentStateCard: some View {
        SettingsCard(title: "settings.files.data_directory") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Storage Root")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(storageDirectoryURL.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Project")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(agent.activeProjectPath ?? L10n.tr("common.not_selected"))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(agent.activeProjectPath == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(agentEntries) { entry in
                            agentTreeRow(entry)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 400)
                .padding(10)
                .background(Color.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                Text("settings.files.storage_description")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("settings.files.workspace_description")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var sandboxCard: some View {
        SettingsCard(title: "settings.files.authorized_directories") {
            VStack(spacing: 10) {
                if sandbox.entries.isEmpty {
                    Text("settings.files.no_authorized_directories")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sandbox.entries) { entry in
                            let status = sandbox.status(of: entry)
                            HStack {
                                Text(entry.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(statusLabel(for: status))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(statusColor(for: status).opacity(0.15))
                                    .foregroundColor(statusColor(for: status))
                                    .clipShape(Capsule())
                                if status != .active {
                                    Button("settings.files.reauthorize") {
                                        sandbox.reauthorizeEntry(entry)
                                        agent.refreshRuntimeContext()
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Button(role: .destructive) {
                                    sandbox.removeEntry(entry)
                                    agent.refreshRuntimeContext()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                HStack {
                    Button("settings.files.add_directory_authorization") {
                        sandbox.authorizeDirectoryViaOpenPanel()
                        agent.refreshRuntimeContext()
                    }
                    Button("settings.files.refresh_authorization") {
                        sandbox.refreshAccess()
                        agent.refreshRuntimeContext()
                    }
                    Spacer()
                }
                .frame(maxWidth: actionRowWidth, alignment: .leading)
                
                Text("settings.files.authorization_description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func agentTreeRow(_ entry: SandboxTreeRowEntry) -> some View {
        let row = HStack(spacing: 8) {
            if entry.isDirectory && entry.exists {
                Image(systemName: entry.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
            } else {
                Spacer().frame(width: 10)
            }
            
            Image(systemName: entry.icon)
                .font(.system(size: 12))
                .foregroundColor(entry.iconColor)
                .frame(width: 14, height: 14)
            
            Text(entry.name)
                .font(.system(size: 12, weight: entry.isDirectory ? .medium : .regular))
                .foregroundColor(entry.nameColor)
                .lineLimit(1)
            
            Spacer()
            
            if entry.isTextFile {
                Text("settings.files.view")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)
            } else if entry.isMissingDirectory {
                Text("settings.files.not_created")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        
        if entry.isDirectory && entry.exists {
            return AnyView(
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        toggleFolder(entry.url)
                    }
                } label: {
                    row
                }
                .buttonStyle(.plain)
            )
        }
        
        if entry.isTextFile {
            return AnyView(
                Button {
                    openTextPreview(name: entry.name, url: entry.url)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            )
        }
        
        return AnyView(row)
    }
    
    private func textPreviewSheet(_ preview: SandboxTextPreview) -> some View {
        NavigationStack {
            ScrollView {
                Text(preview.content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .navigationTitle(preview.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") {
                        selectedTextPreview = nil
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }
    
    private func appendAgentRows(
        for url: URL,
        name: String,
        depth: Int,
        into result: inout [SandboxTreeRowEntry],
        isRoot: Bool = false
    ) {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let key = url.standardizedFileURL.path
        let isExpanded = exists && expandedFolders.contains(key)
        let children = isExpanded ? agentChildren(of: url) : []
        
        result.append(
            SandboxTreeRowEntry(
                name: name,
                url: url,
                depth: depth,
                isDirectory: true,
                isTextFile: false,
                isRoot: isRoot,
                isExpanded: isExpanded,
                isEmptyDirectory: exists && isExpanded && children.isEmpty,
                exists: exists,
                isMissingDirectory: !exists
            )
        )
        
        guard exists, isExpanded else { return }
        
        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                appendAgentRows(
                    for: child,
                    name: child.lastPathComponent,
                    depth: depth + 1,
                    into: &result
                )
            } else {
                result.append(
                    SandboxTreeRowEntry(
                        name: child.lastPathComponent,
                        url: child,
                        depth: depth + 1,
                        isDirectory: false,
                        isTextFile: isPreviewableTextFile(child),
                        isRoot: false,
                        isExpanded: false,
                        isEmptyDirectory: false,
                        exists: true,
                        isMissingDirectory: false
                    )
                )
            }
        }
        
        if children.isEmpty {
            result.append(
                SandboxTreeRowEntry(
                    name: L10n.tr("settings.files.empty_directory"),
                    url: url,
                    depth: depth + 1,
                    isDirectory: false,
                    isTextFile: false,
                    isRoot: false,
                    isExpanded: false,
                    isEmptyDirectory: true,
                    exists: true,
                    isMissingDirectory: false
                )
            )
        }
    }
    
    private func toggleFolder(_ url: URL) {
        let key = url.standardizedFileURL.path
        if expandedFolders.contains(key) {
            expandedFolders.remove(key)
        } else {
            expandedFolders.insert(key)
        }
        refreshAgentEntries()
    }
    
    private func refreshAgentEntries() {
        var result: [SandboxTreeRowEntry] = []
        let roots = agentChildren(of: storageDirectoryURL)

        for url in roots {
            appendAgentRows(for: url, name: url.lastPathComponent, depth: 0, into: &result, isRoot: true)
        }

        agentEntries = result
    }
    
    private func agentChildren(of url: URL) -> [URL] {
        let rootPath = storageDirectoryURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { return [] }
        
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        return children.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
    }
    
    private func isPreviewableTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let allowed = [
            "txt", "md", "markdown", "json", "jsonl", "yaml", "yml",
            "log", "csv", "tsv", "swift", "py", "js", "ts", "tsx", "jsx",
            "html", "css", "xml", "sh"
        ]
        return allowed.contains(ext)
    }
    
    private func openTextPreview(name: String, url: URL) {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode)
        else {
            selectedTextPreview = SandboxTextPreview(
                title: name,
                content: L10n.tr("settings.files.unable_to_read_file")
            )
            return
        }
        
        let previewText = content.count > 20_000 ? String(content.prefix(20_000)) + "\n\n" + L10n.tr("settings.files.truncated") : content
        selectedTextPreview = SandboxTextPreview(title: name, content: previewText)
    }
    
    private func statusLabel(for status: SandboxAuthorizationStatus) -> String {
        switch status {
        case .active: return L10n.tr("settings.files.status.active")
        case .stale: return L10n.tr("settings.files.status.stale")
        case .invalid: return L10n.tr("settings.files.status.invalid")
        }
    }
    
    private func statusColor(for status: SandboxAuthorizationStatus) -> Color {
        switch status {
        case .active: return .green
        case .stale: return .orange
        case .invalid: return .red
        }
    }
}

private struct SandboxTreeRowEntry: Identifiable {
    let name: String
    let url: URL
    let depth: Int
    let isDirectory: Bool
    let isTextFile: Bool
    let isRoot: Bool
    let isExpanded: Bool
    let isEmptyDirectory: Bool
    let exists: Bool
    let isMissingDirectory: Bool
    
    var id: String {
        [url.standardizedFileURL.path, String(depth), isDirectory ? "dir" : "file", isExpanded ? "expanded" : "collapsed", exists ? "exists" : "missing", isEmptyDirectory ? "empty" : "filled"].joined(separator: "|")
    }
    
    var icon: String {
        if isMissingDirectory { return "folder.badge.questionmark" }
        if isEmptyDirectory { return "questionmark.folder" }
        if isRoot { return "internaldrive" }
        if isDirectory { return isExpanded ? "folder.fill" : "folder" }
        return isTextFile ? "doc.text" : "doc"
    }
    
    var iconColor: Color {
        if isMissingDirectory { return .secondary }
        if isEmptyDirectory { return .secondary.opacity(0.6) }
        if isRoot { return .accentColor }
        return isTextFile ? .accentColor : .secondary
    }
    
    var nameColor: Color {
        if isMissingDirectory { return .secondary }
        return isEmptyDirectory ? .secondary.opacity(0.6) : (isTextFile ? .accentColor : .primary)
    }
}

private struct SandboxTextPreview: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

#Preview {
    SandboxSettingsView(agent: AgentManager.shared, viewModel: SandboxSettingsViewModel())
        .frame(width: 600)
}
