import SwiftUI
import AppKit

/// Diagnostics page in Settings: lists daily store backups and lets the user
/// restore one. Restore requires a relaunch; the page makes that explicit.
///
/// Each backup carries a schema-version stamp. Mismatched backups can't be
/// restored (would corrupt the store on next launch); legacy stamp-less
/// backups warn but allow override.
struct DiagnosticsSettingsView: View {
    @State private var backups: [StoreBackupManager.BackupEntry] = []
    @State private var pendingRestore: StoreBackupManager.BackupEntry?
    @State private var restoreState: RestoreState = .idle

    private enum RestoreState: Equatable {
        case idle
        case running
        case succeeded(date: String)
        case failed(message: String)
    }

    private enum Compatibility {
        case compatible
        case unknownSchema      // legacy backup, no stamp
        case mismatch(backup: Int)
    }

    private var manager: StoreBackupManager? {
        StoreBackupManager.default()
    }

    private var currentSchemaVersion: Int {
        SchemaVersion.current
    }

    var body: some View {
        SettingsCard(title: "settings.diagnostics.backups") {
            VStack(alignment: .leading, spacing: 14) {
                Text("settings.diagnostics.backups.description")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                schemaInfoRow

                if backups.isEmpty {
                    emptyState
                } else {
                    backupList
                }

                statusFooter
            }
        }
        .task {
            reload()
        }
        .alert(item: $pendingRestore) { entry in
            Alert(
                title: Text(L10n.tr("settings.diagnostics.confirm_restore.title")),
                message: Text(confirmMessage(for: entry)),
                primaryButton: .destructive(Text(L10n.tr("settings.diagnostics.restore"))) {
                    performRestore(entry)
                },
                secondaryButton: .cancel(Text("common.cancel"))
            )
        }
    }

    // MARK: - Subviews

    private var schemaInfoRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(L10n.tr("settings.diagnostics.current_schema", currentSchemaVersion))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var emptyState: some View {
        Text("settings.diagnostics.no_backups")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
    }

    private var backupList: some View {
        VStack(spacing: 0) {
            ForEach(backups) { entry in
                backupRow(entry)
            }
        }
    }

    private func backupRow(_ entry: StoreBackupManager.BackupEntry) -> some View {
        let compat = compatibility(of: entry)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.id)
                        .font(.system(size: 13, weight: .medium))
                    schemaBadge(for: compat, version: entry.schemaVersion)
                }
                Text(formatSize(entry.sizeBytes))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                revealInFinder(entry.url)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("settings.diagnostics.reveal_in_finder")

            Button("settings.diagnostics.restore") {
                pendingRestore = entry
            }
            .controlSize(.small)
            .disabled(restoreState == .running || isMismatch(compat))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func schemaBadge(for compat: Compatibility, version: Int?) -> some View {
        switch compat {
        case .compatible:
            Text(L10n.tr("settings.diagnostics.schema_label", version ?? -1))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.black.opacity(0.06)))
        case .unknownSchema:
            Text("settings.diagnostics.schema_unknown")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
        case .mismatch(let v):
            Text(L10n.tr("settings.diagnostics.schema_mismatch", v))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.red.opacity(0.12)))
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch restoreState {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("settings.diagnostics.restoring")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        case .succeeded(let date):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("settings.diagnostics.restore_succeeded", date))
                        .font(.system(size: 12, weight: .medium))
                    Text("settings.diagnostics.restart_required")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Logic

    private func compatibility(of entry: StoreBackupManager.BackupEntry) -> Compatibility {
        switch entry.schemaVersion {
        case .none:
            return .unknownSchema
        case .some(let v) where v == currentSchemaVersion:
            return .compatible
        case .some(let v):
            return .mismatch(backup: v)
        }
    }

    private func isMismatch(_ compat: Compatibility) -> Bool {
        if case .mismatch = compat { return true }
        return false
    }

    private func confirmMessage(for entry: StoreBackupManager.BackupEntry) -> String {
        switch compatibility(of: entry) {
        case .unknownSchema:
            return L10n.tr("settings.diagnostics.confirm_restore.message_unknown_schema", entry.id)
        case .compatible, .mismatch:
            return L10n.tr("settings.diagnostics.confirm_restore.message", entry.id)
        }
    }

    // MARK: - Actions

    private func reload() {
        backups = manager?.listBackups() ?? []
    }

    private func performRestore(_ entry: StoreBackupManager.BackupEntry) {
        guard let manager else { return }
        let allowUnknown = entry.schemaVersion == nil
        restoreState = .running
        Task.detached(priority: .userInitiated) {
            do {
                try manager.restore(from: entry, allowUnknownSchema: allowUnknown)
                await MainActor.run {
                    restoreState = .succeeded(date: entry.id)
                }
            } catch {
                await MainActor.run {
                    restoreState = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
