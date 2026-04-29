import SwiftUI

struct UserAccountPopover: View {
    @Binding var isPresented: Bool
    let accountName: String
    let accountSubtitle: LocalizedStringKey
    let accountInitial: String
    var onSettings: () -> Void
    var onHelp: () -> Void
    var onLogout: () -> Void

    private let contentInset: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            Button {
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text(accountInitial)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(accountSubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Divider()
                .padding(.horizontal, contentInset)

            MenuItem(icon: "gearshape", title: "settings.title", action: {
                isPresented = false
                onSettings()
            })

            Divider()
                .padding(.horizontal, contentInset)

            MenuItem(icon: "questionmark.circle", title: "common.help", hasChevron: true, action: {
                isPresented = false
                onHelp()
            })

            Divider()
                .padding(.horizontal, contentInset)

            MenuItem(icon: "arrow.right.square", title: "account.logout", isDestructive: true, action: {
                isPresented = false
                onLogout()
            })
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .frame(width: 240)
    }
}

private struct MenuItem: View {
    let icon: String
    let title: LocalizedStringKey
    var hasChevron: Bool = false
    var isDestructive: Bool = false
    var action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 20)
                    .foregroundColor(isDestructive ? .red : .primary)

                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(isDestructive ? .red : .primary)

                Spacer()

                if hasChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.055) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview {
    UserAccountPopover(
        isPresented: .constant(true),
        accountName: "Google User",
        accountSubtitle: "account.google_user",
        accountInitial: "G",
        onSettings: {},
        onHelp: {},
        onLogout: {}
    )
    .padding()
}
