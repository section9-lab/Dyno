import SwiftUI

@MainActor
class ModelSettingsViewModel: ObservableObject {
    @Published var selectedProviderId: String
    @Published var draftApiKey: String
    @Published var draftBaseURL: String
    @Published var draftModelId: String
    @Published var showAPIKey: Bool
    @Published var isDiscovering: Bool
    @Published var showCustomSheet: Bool
    @Published var customName: String
    @Published var customBaseURL: String
    @Published var customApiKey: String
    @Published var customModelId: String
    /// `nil` means "auto" — `ApiKind.sniff` decides from the URL at save
    /// time. Users can pin a specific protocol when sniff would guess
    /// wrong (e.g. an Anthropic-compatible proxy hosted on a non-Anthropic
    /// domain that would otherwise default to OpenAI completions).
    @Published var customApiKindOverride: ApiKind?
    /// `nil` while the unified custom-provider sheet is in "add" mode;
    /// holds the provider id while editing an existing custom provider.
    /// The sheet uses this to decide whether Save calls `addCustomProvider`
    /// or `updateCustomProvider`.
    @Published var editingCustomProviderId: String?
    @Published var visibleProviderCount: Int

    init(
        selectedProviderId: String = "",
        draftApiKey: String = "",
        draftBaseURL: String = "",
        draftModelId: String = "",
        showAPIKey: Bool = false,
        isDiscovering: Bool = false,
        showCustomSheet: Bool = false,
        customName: String = "",
        customBaseURL: String = "",
        customApiKey: String = "",
        customModelId: String = "",
        customApiKindOverride: ApiKind? = nil,
        editingCustomProviderId: String? = nil,
        visibleProviderCount: Int = 5
    ) {
        self.selectedProviderId = selectedProviderId
        self.draftApiKey = draftApiKey
        self.draftBaseURL = draftBaseURL
        self.draftModelId = draftModelId
        self.showAPIKey = showAPIKey
        self.isDiscovering = isDiscovering
        self.showCustomSheet = showCustomSheet
        self.customName = customName
        self.customBaseURL = customBaseURL
        self.customApiKey = customApiKey
        self.customModelId = customModelId
        self.customApiKindOverride = customApiKindOverride
        self.editingCustomProviderId = editingCustomProviderId
        self.visibleProviderCount = visibleProviderCount
    }

    /// Reset every field that backs the custom-provider editor sheet to its
    /// empty state. Called both when closing the sheet and before opening
    /// it in "add" mode so stale draft values from a previous session don't
    /// leak into a fresh add.
    func resetCustomProviderDraft() {
        customName = ""
        customBaseURL = ""
        customApiKey = ""
        customModelId = ""
        customApiKindOverride = nil
        editingCustomProviderId = nil
    }

    func getConfig() -> (providerId: String, baseURL: String, apiKey: String, modelId: String)? {
        guard !draftBaseURL.isEmpty && !draftModelId.isEmpty else { return nil }
        return (selectedProviderId, draftBaseURL, draftApiKey, draftModelId)
    }

    func loadMoreProviders(totalCount: Int, pageSize: Int = 5) {
        guard visibleProviderCount < totalCount else { return }
        visibleProviderCount = min(visibleProviderCount + pageSize, totalCount)
    }
}
