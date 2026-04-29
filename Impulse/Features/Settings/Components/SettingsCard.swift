import SwiftUI

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(14)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 0.5)
        )
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.153, blue: 0.165).opacity(0.86)
            : Color(red: 0.89, green: 0.89, blue: 0.90).opacity(0.8)
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)
    }
}
