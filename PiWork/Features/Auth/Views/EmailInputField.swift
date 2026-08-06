import SwiftUI

/// Onboarding email input — matches the look of the OAuth buttons above
/// (frosted material, soft border) but exposes a SwiftUI `TextField` for
/// typing. Captures Return as a submit signal so the user can keep both
/// hands on the keyboard.
struct EmailInputField: View {
    @Binding var text: String
    var onSubmit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)

            TextField("email.placeholder", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .disableAutocorrection(true)
                // macOS doesn't auto-lowercase the way iOS does, but trimming
                // accidental leading whitespace from autofill avoids a class
                // of "looks valid but isn't" failures downstream.
                .onChange(of: text) { newValue in
                    if newValue.first?.isWhitespace == true {
                        text = String(newValue.drop(while: { $0.isWhitespace }))
                    }
                }
        }
        .padding(.horizontal, 14)
        .frame(width: 312, height: 44)
        .background(.ultraThinMaterial)
        .background(fieldTint)
        .overlay(
            adaptiveRoundedShape(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
        .adaptiveCornerRadius(10)
        .onAppear { isFocused = true }
    }

    private var fieldTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.7)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }
}
