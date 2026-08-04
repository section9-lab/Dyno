import SwiftUI
import PiWorkCore

/// Top-anchored banner that observes `UserAlertCenter.shared` and shows the
/// current alert, if any. Drop into a view as `.overlay(alignment: .top) { UserAlertBanner() }`.
struct UserAlertBanner: View {
    @ObservedObject private var center = UserAlertCenter.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let alert = center.current {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: alert.severity))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor(for: alert.severity))

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    if let detail = alert.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    center.dismissCurrent()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 480)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(accentColor(for: alert.severity).opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
            )
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.18), value: alert.id)
        }
    }

    private func iconName(for severity: UserAlert.Severity) -> String {
        switch severity {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func accentColor(for severity: UserAlert.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .accentColor
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.17, blue: 0.18)
            : Color.white
    }
}
