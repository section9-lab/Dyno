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
        customApiKey: String = ""
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
    }

    func getConfig() -> (providerId: String, baseURL: String, apiKey: String, modelId: String)? {
        guard !draftBaseURL.isEmpty && !draftModelId.isEmpty else { return nil }
        return (selectedProviderId, draftBaseURL, draftApiKey, draftModelId)
    }
}
