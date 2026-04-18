import SwiftUI

struct UserAccountPopover: View {
    @Binding var isPresented: Bool
    var onSettings: () -> Void
    var onHelp: () -> Void
    var onLogout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text("G")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Guest")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Text("个人账户")
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
                .padding(.horizontal, 16)

            MenuItem(icon: "sparkles", title: "个性化")
            MenuItem(icon: "person.circle", title: "个人资料")

            Divider()
                .padding(.horizontal, 16)

            MenuItem(icon: "gearshape", title: "设置", action: {
                onSettings()
            })

            Divider()
                .padding(.horizontal, 16)

            MenuItem(icon: "questionmark.circle", title: "帮助", hasChevron: true, action: {
                onHelp()
            })

            Divider()
                .padding(.horizontal, 16)

            MenuItem(icon: "arrow.right.square", title: "退出登录", isDestructive: true, action: {
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
    let title: String
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.gray.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
        onSettings: {},
        onHelp: {},
        onLogout: {}
    )
    .padding()
}
