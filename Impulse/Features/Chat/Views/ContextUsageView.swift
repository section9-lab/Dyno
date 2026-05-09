import SwiftHarnessAgent
import SwiftUI

/// Compact ring + popover that shows the focused session's context-window
/// usage, with a "Compact now" trigger. Bound to a single `SessionAgent`
/// so it observes the right one in a parallel-session world.
///
/// Pulled out of `InputBar` to keep that file under 700 lines and to give
/// the context-usage UI its own discoverable surface.
struct ContextUsageIndicator: View {
    @ObservedObject var sessionAgent: SessionAgent
    @Binding var showContextPopover: Bool
    @Binding var isCompacting: Bool

    var body: some View {
        Button {
            showContextPopover.toggle()
        } label: {
            ContextUsageRing(
                percent: sessionAgent.contextUsage.percent,
                color: contextUsageColor
            )
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showContextPopover, arrowEdge: .top) {
            ContextUsagePopover(
                usage: sessionAgent.contextUsage,
                isCompacting: isCompacting,
                onCompact: triggerCompaction
            )
        }
        .help(contextHelpText)
    }

    private var contextUsageColor: Color {
        let pct = sessionAgent.contextUsage.percent
        if pct >= 0.9 { return .red }
        if pct >= 0.75 { return .orange }
        // `.secondary` reads almost invisible against the light tray
        // background; use a fixed mid-tone grey so the ring stays legible
        // before usage warnings kick in.
        return Color.primary.opacity(0.45)
    }

    private var contextHelpText: String {
        let usage = sessionAgent.contextUsage
        let pctText = String(format: "%.0f%%", usage.percent * 100)
        return "Context: \(pctText) (\(formatTokens(usage.usedTokens)) / \(formatTokens(usage.totalTokens)))"
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000 {
            let k = Double(value) / 1_000.0
            return String(format: "%.1fk", k)
        }
        return "\(value)"
    }

    private func triggerCompaction() {
        guard !isCompacting else { return }
        isCompacting = true
        Task {
            defer { isCompacting = false }
            do {
                _ = try await sessionAgent.compact()
                showContextPopover = false
            } catch {
                // Surface failure passively — the popover stays open so the
                // user can see the unchanged usage.
            }
        }
    }
}

// MARK: - Internals (file-private)

private struct ContextUsageRing: View {
    let percent: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 2)

            Circle()
                .trim(from: 0, to: max(0.001, min(1.0, percent)))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: percent)
        }
    }
}

private struct ContextUsagePopover: View {
    let usage: ContextUsage
    let isCompacting: Bool
    let onCompact: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ContextUsageRing(percent: usage.percent, color: ringColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(percentLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(L10n.tr("context.window_label"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: L10n.tr("context.used"), value: formatTokens(usage.usedTokens))
                statRow(label: L10n.tr("context.total"), value: formatTokens(usage.totalTokens))
                statRow(label: L10n.tr("context.reserved"), value: formatTokens(usage.reservedTokens))
            }

            Button {
                onCompact()
            } label: {
                HStack(spacing: 6) {
                    if isCompacting {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    }
                    Text(isCompacting ? L10n.tr("context.compacting") : L10n.tr("context.compact"))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(isCompacting ? 0.15 : 0.22))
                )
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isCompacting)
        }
        .padding(14)
        .frame(width: 240)
    }

    private var percentLabel: String {
        String(format: "%.0f%% used", usage.percent * 100)
    }

    private var ringColor: Color {
        if usage.percent >= 0.9 { return .red }
        if usage.percent >= 0.75 { return .orange }
        return .accentColor
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        return "\(value)"
    }
}
