import SwiftUI

/// Compact model picker shown inside the chat input bar (right of mic).
/// Lists models the user has favorited in Settings; selecting one swaps the
/// global agent config so the next message goes to that provider+model.
struct ChatModelSwitcher: View {
    @ObservedObject var agent: AgentManager
    @ObservedObject var registry: ModelRegistry
    var onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPopoverShown = false

    init(agent: AgentManager, onOpenSettings: @escaping () -> Void) {
        self.agent = agent
        self.registry = agent.registry
        self.onOpenSettings = onOpenSettings
    }

    private var favorites: [(provider: Provider, model: ModelInfo)] {
        registry.favoriteModels()
    }

    private var currentLabel: String {
        let modelId = agent.config.modelId
        if modelId.isEmpty { return L10n.tr("settings.model.no_favorites") }
        // Prefer the favorite's display name if there's a match.
        if let entry = favorites.first(where: { $0.provider.id == agent.config.providerId && $0.model.id == modelId }) {
            return entry.model.name
        }
        return modelId
    }

    var body: some View {
        Button {
            isPopoverShown.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(currentLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.primary.opacity(0.78))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: 160)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                Capsule(style: .continuous).fill(chipBackground)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverShown, arrowEdge: .top) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if favorites.isEmpty {
                Text("settings.model.no_favorites")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(favorites.enumerated()), id: \.offset) { _, entry in
                            modelRow(provider: entry.provider, model: entry.model)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }

            Divider()

            Button {
                isPopoverShown = false
                onOpenSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                    Text("settings.model.manage_favorites")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: popoverCornerRadius, style: .continuous)
                .fill(popoverBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: popoverCornerRadius, style: .continuous)
                .stroke(popoverBorderColor, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: popoverCornerRadius, style: .continuous))
    }

    private func modelRow(provider: Provider, model: ModelInfo) -> some View {
        let isCurrent = provider.id == agent.config.providerId && model.id == agent.config.modelId
        return Button {
            isPopoverShown = false
            selectModel(provider: provider, model: model)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(provider.name)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                ModelCapabilityBadges(model: model)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectModel(provider: Provider, model: ModelInfo) {
        let newConfig = AgentServiceConfig(
            providerId: provider.id,
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            modelId: model.id,
            apiKind: provider.effectiveApiKind(for: model)
        )
        Task { await agent.applyConfig(newConfig) }
    }

    private var chipBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.74)
    }

    // Mirror InputBar's card so the popover reads as part of the input bar.
    private let popoverCornerRadius: CGFloat = 14

    private var popoverBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.153, blue: 0.165)
            : Color.white
    }

    private var popoverBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.08)
    }
}
