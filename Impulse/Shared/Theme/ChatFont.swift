import SwiftUI

/// Semantic font sizes for the chat surface. All chat-area text should pick
/// one of these instead of hard-coding `.system(size: N)` so the user's
/// "small / medium / large" preference scales every label coherently.
enum ChatFontKind {
    /// Page titles like the welcome heading.
    case title
    /// AI markdown body, user message text, tool row title, tool group summary.
    case body
    /// "Done" footer, secondary labels.
    case label
    /// "Thinking" caption, reasoning expanded body.
    case caption
    /// Timestamps, chip text, panel field labels.
    case footnote

    fileprivate var baseSize: CGFloat {
        switch self {
        case .title:    return 28
        case .body:     return 14
        case .label:    return 13
        case .caption:  return 11
        case .footnote: return 10
        }
    }
}

extension View {
    /// Apply a semantic chat font that scales with the user's text-size
    /// preference (`ThemeManager.textSize`). Prefer this over hand-rolling
    /// `.font(.system(size: N))` inside chat views.
    func chatFont(_ kind: ChatFontKind, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ChatFontModifier(baseSize: kind.baseSize, weight: weight, design: design))
    }

    /// Escape hatch when a non-semantic size is genuinely needed. Still
    /// scales with the text-size preference.
    func chatFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ChatFontModifier(baseSize: size, weight: weight, design: design))
    }
}

private struct ChatFontModifier: ViewModifier {
    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @EnvironmentObject private var themeManager: ThemeManager

    func body(content: Content) -> some View {
        content.font(.system(size: baseSize * themeManager.textSize.multiplier, weight: weight, design: design))
    }
}
