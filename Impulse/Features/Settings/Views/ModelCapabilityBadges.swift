import SwiftUI

/// Compact row of capability pills shown next to a model in the picker.
/// Renders, in order:
///   - `推理` if `reasoning`
///   - `工具` if `toolCall`
///   - One pill per non-text input modality (image / audio / video)
///
/// Output modalities aren't surfaced — almost all chat-style models output
/// text only, so the pill would be visual noise. If we ever support
/// image-out / audio-out we'll add them then.
///
/// Each pill is intentionally tiny (font 9) and uses semantic color (not
/// any random palette) so the row reads at a glance without dominating
/// the model name.
struct ModelCapabilityBadges: View {
    let model: ModelInfo

    var body: some View {
        HStack(spacing: 4) {
            if model.reasoning {
                CapabilityPill(
                    text: L10n.tr("settings.model.cap.reasoning"),
                    color: .purple
                )
            }

            if model.toolCall {
                CapabilityPill(
                    text: L10n.tr("settings.model.cap.tools"),
                    color: .blue
                )
            }

            // Non-text input modalities (image/audio/video). Sorted for a
            // stable visual order regardless of Set iteration.
            ForEach(nonTextInputs, id: \.self) { modality in
                CapabilityPill(
                    text: label(for: modality),
                    color: color(for: modality)
                )
            }
        }
    }

    private var nonTextInputs: [Modality] {
        // Stable order: image, audio, video.
        Modality.allCases
            .filter { $0 != .text && model.inputModalities.contains($0) }
    }

    private func label(for modality: Modality) -> String {
        switch modality {
        case .text:  return L10n.tr("settings.model.cap.text")
        case .image: return L10n.tr("settings.model.cap.image")
        case .audio: return L10n.tr("settings.model.cap.audio")
        case .video: return L10n.tr("settings.model.cap.video")
        }
    }

    private func color(for modality: Modality) -> Color {
        switch modality {
        case .text:  return .gray
        case .image: return .green
        case .audio: return .orange
        case .video: return .pink
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
