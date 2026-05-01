import SwiftUI

/// One pill rendered by `ModelCapabilityBadges`. The view is dumb — it
/// just iterates `ModelInfo.capabilityPills` and renders each entry.
/// Adding a new capability is a one-spot change in `capabilityPills`.
///
/// `color` is intentionally a `Color`, not a Codable token — capabilities
/// are a pure presentation concern and never persisted.
struct Capability: Identifiable, Hashable {
    let id: String          // stable key for ForEach diffing
    let labelKey: String    // L10n key; resolved at render time
    let color: Color
}

extension ModelInfo {
    /// Ordered list of capability pills the UI should render for this
    /// model. Single source of truth for "which pills, in what order, in
    /// what color" — the view layer just iterates this.
    ///
    /// Order: reasoning → tools → non-text input modalities (image,
    /// audio, video). Output modalities are deliberately omitted; almost
    /// every chat-style model emits text only, so a pill there would be
    /// noise.
    var capabilityPills: [Capability] {
        var pills: [Capability] = []
        if reasoning {
            pills.append(Capability(
                id: "reasoning",
                labelKey: "settings.model.cap.reasoning",
                color: .purple
            ))
        }
        if toolCall {
            pills.append(Capability(
                id: "tools",
                labelKey: "settings.model.cap.tools",
                color: .blue
            ))
        }
        for modality in Modality.allCases where modality != .text && inputModalities.contains(modality) {
            pills.append(Capability(
                id: "input.\(modality.rawValue)",
                labelKey: "settings.model.cap.\(modality.rawValue)",
                color: Self.color(for: modality)
            ))
        }
        return pills
    }

    private static func color(for modality: Modality) -> Color {
        switch modality {
        case .text:  return .gray
        case .image: return .green
        case .audio: return .orange
        case .video: return .pink
        }
    }
}

/// Compact row of capability pills shown next to a model in the picker.
/// Each pill is intentionally tiny (font 9) so the row reads at a glance
/// without dominating the model name.
struct ModelCapabilityBadges: View {
    let model: ModelInfo

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.capabilityPills) { pill in
                CapabilityPill(text: L10n.tr(pill.labelKey), color: pill.color)
            }
        }
    }
}

private struct CapabilityPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

#Preview("Variants") {
    VStack(alignment: .leading, spacing: 8) {
        ModelCapabilityBadges(model: ModelInfo(
            id: "text-only",
            name: "Text only",
            toolCall: false,
            reasoning: false
        ))
        ModelCapabilityBadges(model: ModelInfo(
            id: "tools",
            name: "Tools only",
            toolCall: true,
            reasoning: false
        ))
        ModelCapabilityBadges(model: ModelInfo(
            id: "reasoning-tools",
            name: "Reasoning + tools",
            toolCall: true,
            reasoning: true
        ))
        ModelCapabilityBadges(model: ModelInfo(
            id: "vision",
            name: "Vision",
            toolCall: true,
            reasoning: false,
            inputModalities: [.text, .image]
        ))
        ModelCapabilityBadges(model: ModelInfo(
            id: "omni",
            name: "Multimodal omni",
            toolCall: true,
            reasoning: true,
            inputModalities: [.text, .image, .audio, .video]
        ))
    }
    .padding()
}
