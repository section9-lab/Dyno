import Foundation

private let agentHostProtocolVersion = 1

struct AgentHostEvent<Payload: Decodable>: Decodable {
    let version: Int
    let kind: String
    let event: String
    let payload: Payload
}

struct AgentHostWireHeader: Decodable {
    let version: Int
    let kind: String
    let id: String?
    let event: String?
}

struct AgentHostHelloPayload: Decodable, Equatable {
    let hostVersion: String
    let piVersion: String
    let capabilities: [String]
}

enum AgentHostSessionRunState: String, Decodable, Equatable {
    case running
    case idle
}

struct AgentHostContextUsage: Decodable, Equatable {
    let tokens: Int?
    let contextWindow: Int
    let percent: Double?
}

struct AgentHostSessionStateChangedPayload: Decodable, Equatable {
    let sessionId: String
    let sequence: Int
    let turnId: String
    let state: AgentHostSessionRunState
    let contextUsage: AgentHostContextUsage?

    init(
        sessionId: String,
        sequence: Int,
        turnId: String,
        state: AgentHostSessionRunState,
        contextUsage: AgentHostContextUsage? = nil
    ) {
        self.sessionId = sessionId
        self.sequence = sequence
        self.turnId = turnId
        self.state = state
        self.contextUsage = contextUsage
    }
}

struct AgentHostSessionMessageDeltaPayload: Decodable, Equatable {
    let sessionId: String
    let sequence: Int
    let turnId: String
    let delta: String
}

struct AgentHostSessionToolStartedPayload: Decodable, Equatable {
    let sessionId: String
    let sequence: Int
    let turnId: String
    let toolCallId: String
    let toolName: String
    let summary: String
}

struct AgentHostSessionToolUpdatedPayload: Decodable, Equatable {
    let sessionId: String
    let sequence: Int
    let turnId: String
    let toolCallId: String
    let toolName: String
    let output: String
}

struct AgentHostSessionToolCompletedPayload: Decodable, Equatable {
    let sessionId: String
    let sequence: Int
    let turnId: String
    let toolCallId: String
    let toolName: String
    let output: String
    let isError: Bool

    private enum CodingKeys: String, CodingKey {
        case sessionId
        case sequence
        case turnId
        case toolCallId
        case toolName
        case output
        case isError
    }

    init(
        sessionId: String,
        sequence: Int,
        turnId: String,
        toolCallId: String,
        toolName: String,
        output: String = "",
        isError: Bool
    ) {
        self.sessionId = sessionId
        self.sequence = sequence
        self.turnId = turnId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.output = output
        self.isError = isError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionId: try container.decode(String.self, forKey: .sessionId),
            sequence: try container.decode(Int.self, forKey: .sequence),
            turnId: try container.decode(String.self, forKey: .turnId),
            toolCallId: try container.decode(String.self, forKey: .toolCallId),
            toolName: try container.decode(String.self, forKey: .toolName),
            output: try container.decodeIfPresent(String.self, forKey: .output) ?? "",
            isError: try container.decode(Bool.self, forKey: .isError)
        )
    }
}

enum AgentHostAccessMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case none
    case readOnly
    case ask
    case full

    var id: String { rawValue }
}

enum AgentHostThinkingLevel: String, Codable, Equatable, CaseIterable, Identifiable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }
}

enum AgentHostApprovalDecision: String, Codable, Equatable {
    case allowOnce
    case deny
}

struct AgentHostApprovalRequest: Decodable, Equatable, Identifiable {
    let id: String
    let toolCallId: String
    let toolName: String
    let summary: String
}

struct AgentHostSessionApprovalRequestedPayload: Decodable, Equatable {
    let sessionId: String
    let sequence: Int
    let turnId: String
    let requestId: String
    let toolCallId: String
    let toolName: String
    let summary: String

    var approval: AgentHostApprovalRequest {
        AgentHostApprovalRequest(
            id: requestId,
            toolCallId: toolCallId,
            toolName: toolName,
            summary: summary
        )
    }
}

struct AgentHostSessionErrorPayload: Decodable, Equatable {
    let sessionId: String
    let sequence: Int
    let turnId: String
    let code: String
    let message: String
}

enum AgentHostAuthPromptType: String, Decodable, Equatable {
    case text
    case secret
    case select
    case manualCode = "manual_code"
}

struct AgentHostAuthPromptOption: Decodable, Equatable, Identifiable {
    let id: String
    let label: String
    let description: String?
}

struct AgentHostAuthPromptPayload: Decodable, Equatable {
    let flowId: String
    let providerId: String
    let sequence: Int
    let promptId: String
    let type: AgentHostAuthPromptType
    let message: String
    let placeholder: String?
    let options: [AgentHostAuthPromptOption]?
}

enum AgentHostAuthMethod: String, Codable, Equatable, CaseIterable, Identifiable {
    case oauth
    case apiKey = "api_key"

    var id: String { rawValue }
}

struct AgentHostProviderAuthMethod: Decodable, Equatable, Identifiable {
    let type: AgentHostAuthMethod
    let name: String
    let loginLabel: String?

    var id: AgentHostAuthMethod { type }
}

enum AgentHostProviderAuthSource: String, Decodable, Equatable {
    case stored
    case runtime
    case environment
    case fallback
    case modelsJSONKey = "models_json_key"
    case modelsJSONCommand = "models_json_command"
}

struct AgentHostProviderAuthStatus: Decodable, Equatable {
    let configured: Bool
    let source: AgentHostProviderAuthSource?
    let credentialType: AgentHostAuthMethod?
    let canDisconnect: Bool
    let label: String?
}

struct AgentHostProviderModelCounts: Decodable, Equatable {
    let total: Int
    let available: Int
}

struct AgentHostProvider: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let methods: [AgentHostProviderAuthMethod]
    let status: AgentHostProviderAuthStatus
    let models: AgentHostProviderModelCounts
}

struct AgentHostProviderListResult: Decodable, Equatable {
    let providers: [AgentHostProvider]
}

struct AgentHostAuthPromptCancelledPayload: Decodable, Equatable {
    let flowId: String
    let providerId: String
    let sequence: Int
    let promptId: String
}

struct AgentHostAuthInfoLink: Decodable, Equatable, Identifiable {
    let url: String
    let label: String?

    var id: String { url }
}

enum AgentHostAuthNotice: Decodable, Equatable {
    case info(message: String, links: [AgentHostAuthInfoLink])
    case authURL(url: String, instructions: String?)
    case deviceCode(
        userCode: String,
        verificationURI: String,
        intervalSeconds: Int?,
        expiresInSeconds: Int?
    )
    case progress(message: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case links
        case url
        case instructions
        case userCode
        case verificationURI = "verificationUri"
        case intervalSeconds
        case expiresInSeconds
    }

    private enum NoticeType: String, Decodable {
        case info
        case authURL = "auth_url"
        case deviceCode = "device_code"
        case progress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(NoticeType.self, forKey: .type) {
        case .info:
            self = .info(
                message: try container.decode(String.self, forKey: .message),
                links: try container.decodeIfPresent(
                    [AgentHostAuthInfoLink].self,
                    forKey: .links
                ) ?? []
            )
        case .authURL:
            self = .authURL(
                url: try container.decode(String.self, forKey: .url),
                instructions: try container.decodeIfPresent(String.self, forKey: .instructions)
            )
        case .deviceCode:
            self = .deviceCode(
                userCode: try container.decode(String.self, forKey: .userCode),
                verificationURI: try container.decode(String.self, forKey: .verificationURI),
                intervalSeconds: try container.decodeIfPresent(Int.self, forKey: .intervalSeconds),
                expiresInSeconds: try container.decodeIfPresent(Int.self, forKey: .expiresInSeconds)
            )
        case .progress:
            self = .progress(message: try container.decode(String.self, forKey: .message))
        }
    }
}

struct AgentHostAuthNoticePayload: Decodable, Equatable {
    let flowId: String
    let providerId: String
    let sequence: Int
    let notice: AgentHostAuthNotice
}

enum AgentHostAuthOutcome: String, Decodable, Equatable {
    case succeeded
    case cancelled
    case failed
}

struct AgentHostAuthFinishedPayload: Decodable, Equatable {
    let flowId: String
    let providerId: String
    let sequence: Int
    let outcome: AgentHostAuthOutcome
    let error: AgentHostResponseError?
}

enum AgentHostModelsChangeReason: String, Decodable, Equatable {
    case authentication
}

struct AgentHostModelsChangedPayload: Decodable, Equatable {
    let reason: AgentHostModelsChangeReason
    let providerId: String
}

enum AgentHostServerEvent: Equatable {
    case hostHello(AgentHostHelloPayload)
    case sessionStateChanged(AgentHostSessionStateChangedPayload)
    case sessionMessageDelta(AgentHostSessionMessageDeltaPayload)
    case sessionToolStarted(AgentHostSessionToolStartedPayload)
    case sessionToolUpdated(AgentHostSessionToolUpdatedPayload)
    case sessionToolCompleted(AgentHostSessionToolCompletedPayload)
    case sessionApprovalRequested(AgentHostSessionApprovalRequestedPayload)
    case sessionError(AgentHostSessionErrorPayload)
    case authPrompt(AgentHostAuthPromptPayload)
    case authPromptCancelled(AgentHostAuthPromptCancelledPayload)
    case authNotice(AgentHostAuthNoticePayload)
    case authFinished(AgentHostAuthFinishedPayload)
    case modelsChanged(AgentHostModelsChangedPayload)
    case unknown(name: String)

    static func decode(from data: Data) throws -> AgentHostServerEvent {
        let decoder = JSONDecoder()
        let header = try decoder.decode(AgentHostWireHeader.self, from: data)
        guard header.version == agentHostProtocolVersion,
              header.kind == "event" else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported Agent Host event"
                )
            )
        }

        switch header.event {
        case "host.hello":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostHelloPayload>.self,
                from: data
            )
            return .hostHello(event.payload)
        case "session.stateChanged":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostSessionStateChangedPayload>.self,
                from: data
            )
            return .sessionStateChanged(event.payload)
        case "session.messageDelta":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostSessionMessageDeltaPayload>.self,
                from: data
            )
            return .sessionMessageDelta(event.payload)
        case "session.toolStarted":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostSessionToolStartedPayload>.self,
                from: data
            )
            return .sessionToolStarted(event.payload)
        case "session.toolUpdated":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostSessionToolUpdatedPayload>.self,
                from: data
            )
            return .sessionToolUpdated(event.payload)
        case "session.toolCompleted":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostSessionToolCompletedPayload>.self,
                from: data
            )
            return .sessionToolCompleted(event.payload)
        case "session.approvalRequested":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostSessionApprovalRequestedPayload>.self,
                from: data
            )
            return .sessionApprovalRequested(event.payload)
        case "session.error":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostSessionErrorPayload>.self,
                from: data
            )
            return .sessionError(event.payload)
        case "auth.prompt":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostAuthPromptPayload>.self,
                from: data
            )
            return .authPrompt(event.payload)
        case "auth.promptCancelled":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostAuthPromptCancelledPayload>.self,
                from: data
            )
            return .authPromptCancelled(event.payload)
        case "auth.notice":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostAuthNoticePayload>.self,
                from: data
            )
            return .authNotice(event.payload)
        case "auth.finished":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostAuthFinishedPayload>.self,
                from: data
            )
            return .authFinished(event.payload)
        case "models.changed":
            let event = try decoder.decode(
                AgentHostEvent<AgentHostModelsChangedPayload>.self,
                from: data
            )
            return .modelsChanged(event.payload)
        default:
            if let eventName = header.event {
                return .unknown(name: eventName)
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported Agent Host event"
                )
            )
        }
    }
}

struct AgentHostRequest<Parameters: Encodable>: Encodable {
    let version: Int
    let kind: String
    let id: String
    let method: String
    let params: Parameters

    init(id: String, method: String, params: Parameters) {
        self.version = agentHostProtocolVersion
        self.kind = "request"
        self.id = id
        self.method = method
        self.params = params
    }

    func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }
}

struct AgentHostSessionListParameters: Codable, Equatable {
    let cwd: String
    let sessionDirectory: String?
}

struct AgentHostAuthStartParameters: Encodable, Equatable {
    let flowId: String
    let providerId: String
    let method: AgentHostAuthMethod
}

struct AgentHostAuthStartResult: Decodable, Equatable {
    let accepted: Bool
    let flowId: String
}

struct AgentHostAuthRespondParameters: Encodable, Equatable {
    let flowId: String
    let promptId: String
    let value: String
}

struct AgentHostAuthAcceptedResult: Decodable, Equatable {
    let accepted: Bool
}

struct AgentHostAuthCancelParameters: Encodable, Equatable {
    let flowId: String
}

struct AgentHostAuthCancelResult: Decodable, Equatable {
    let cancelRequested: Bool
}

struct AgentHostAuthLogoutParameters: Encodable, Equatable {
    let providerId: String
}

struct AgentHostAuthLogoutResult: Decodable, Equatable {
    let removed: Bool
    let provider: AgentHostProvider
}

struct AgentHostEmptyParameters: Encodable, Equatable {}

struct AgentHostDefaultModel: Codable, Equatable, Hashable {
    let provider: String
    let modelId: String
}

enum AgentHostTransport: String, Codable, Equatable, CaseIterable, Identifiable {
    case auto
    case sse
    case websocket
    case websocketCached = "websocket-cached"

    var id: String { rawValue }
}

struct AgentHostSettings: Codable, Equatable {
    let defaultModel: AgentHostDefaultModel?
    let defaultThinkingLevel: AgentHostThinkingLevel
    let transport: AgentHostTransport
    let compactionEnabled: Bool
    let retryEnabled: Bool
}

struct AgentHostSettingsPatch: Encodable, Equatable {
    let defaultModel: AgentHostDefaultModel?
    let defaultThinkingLevel: AgentHostThinkingLevel?
    let transport: AgentHostTransport?
    let compactionEnabled: Bool?
    let retryEnabled: Bool?

    init(
        defaultModel: AgentHostDefaultModel? = nil,
        defaultThinkingLevel: AgentHostThinkingLevel? = nil,
        transport: AgentHostTransport? = nil,
        compactionEnabled: Bool? = nil,
        retryEnabled: Bool? = nil
    ) {
        self.defaultModel = defaultModel
        self.defaultThinkingLevel = defaultThinkingLevel
        self.transport = transport
        self.compactionEnabled = compactionEnabled
        self.retryEnabled = retryEnabled
    }
}

struct AgentHostSettingsUpdateParameters: Encodable, Equatable {
    let patch: AgentHostSettingsPatch
}

enum AgentHostExtensionPackageScope: String, Codable, Equatable {
    case user
    case project
}

struct AgentHostInstalledExtensionPackage: Decodable, Equatable, Identifiable {
    let source: String
    let scope: AgentHostExtensionPackageScope
    let filtered: Bool
    let installedPath: String?
    let enabled: Bool

    var id: String { "\(scope.rawValue):\(source)" }
}

struct AgentHostInstalledExtensionsResult: Decodable, Equatable {
    let packages: [AgentHostInstalledExtensionPackage]
}

enum AgentHostSlashCommandSource: String, Decodable, Equatable {
    case extensionCommand = "extension"
    case skill
}

struct AgentHostSlashCommand: Decodable, Equatable, Identifiable {
    let name: String
    let description: String?
    let source: AgentHostSlashCommandSource

    var id: String { "\(source.rawValue):\(name)" }
}

struct AgentHostSlashCommandsResult: Decodable, Equatable {
    let commands: [AgentHostSlashCommand]
}

struct AgentHostExtensionPackageParameters: Encodable, Equatable {
    let source: String
    let scope: AgentHostExtensionPackageScope
}

struct AgentHostExtensionInstallParameters: Encodable, Equatable {
    let source: String
}

struct AgentHostExtensionEnabledParameters: Encodable, Equatable {
    let source: String
    let scope: AgentHostExtensionPackageScope
    let enabled: Bool
}

enum AgentHostSessionProfile: String, Codable, Equatable {
    case chat
    case work
}

struct AgentHostSessionCreateDraftParameters: Encodable, Equatable {
    let cwd: String
    let sessionDirectory: String?
    let profile: AgentHostSessionProfile
    let accessMode: AgentHostAccessMode?

    init(
        cwd: String,
        sessionDirectory: String?,
        profile: AgentHostSessionProfile,
        accessMode: AgentHostAccessMode? = nil
    ) {
        self.cwd = cwd
        self.sessionDirectory = sessionDirectory
        self.profile = profile
        self.accessMode = accessMode
    }
}

struct AgentHostSessionOpenParameters: Encodable, Equatable {
    let path: String
    let sessionDirectory: String?
    let profile: AgentHostSessionProfile
    let accessMode: AgentHostAccessMode?

    init(
        path: String,
        sessionDirectory: String?,
        profile: AgentHostSessionProfile,
        accessMode: AgentHostAccessMode? = nil
    ) {
        self.path = path
        self.sessionDirectory = sessionDirectory
        self.profile = profile
        self.accessMode = accessMode
    }
}

struct AgentHostSessionIdentifierParameters: Encodable, Equatable {
    let sessionId: String
}

struct AgentHostGitBranchesParameters: Encodable, Equatable {
    let cwd: String
}

struct AgentHostGitBranchesResult: Decodable, Equatable {
    let available: Bool
    let currentBranch: String?
    let branches: [String]

    static let unavailable = AgentHostGitBranchesResult(
        available: false,
        currentBranch: nil,
        branches: []
    )
}

struct AgentHostSessionSetGitBranchParameters: Encodable, Equatable {
    let sessionId: String
    let branch: String
}

struct AgentHostSessionSetGitBranchResult: Decodable, Equatable {
    let sessionId: String
    let branch: String
}

struct AgentHostSessionDeleteParameters: Encodable, Equatable {
    let sessionId: String
    let cwd: String
    let sessionDirectory: String?
}

struct AgentHostSessionRenameParameters: Encodable, Equatable {
    let sessionId: String
    let title: String
}

struct AgentHostSessionPromptParameters: Encodable, Equatable {
    let sessionId: String
    let turnId: String
    let text: String
}

struct AgentHostResponseError: Decodable, Equatable {
    let code: String
    let message: String
}

struct AgentHostResponse<Result: Decodable>: Decodable {
    let version: Int
    let kind: String
    let id: String
    let ok: Bool
    let result: Result?
    let error: AgentHostResponseError?
}

struct AgentHostSessionSummary: Decodable, Equatable, Identifiable {
    let id: String
    let path: String
    let cwd: String
    let title: String
    let firstMessage: String
    let messageCount: Int
    let createdAt: String
    let modifiedAt: String
}

struct AgentHostSessionListResult: Decodable, Equatable {
    let sessions: [AgentHostSessionSummary]
}

struct AgentHostSessionCreateDraftResult: Decodable, Equatable {
    let session: AgentHostSessionSummary
}

struct AgentHostSessionOpenResult: Decodable, Equatable {
    let sessionId: String
    let path: String
    let cwd: String
}

struct AgentHostSessionRenameResult: Decodable, Equatable {
    let sessionId: String
    let title: String
}

struct AgentHostSessionPromptResult: Decodable, Equatable {
    let accepted: Bool
    let sessionId: String
    let turnId: String
}

struct AgentHostSessionAbortResult: Decodable, Equatable {
    let aborted: Bool
    let sessionId: String
}

struct AgentHostSessionCloseResult: Decodable, Equatable {
    let closed: Bool
    let sessionId: String
}

struct AgentHostSessionDeleteResult: Decodable, Equatable {
    let deleted: Bool
    let sessionId: String
}

struct AgentHostModel: Decodable, Equatable, Identifiable {
    let provider: String
    let id: String
    let name: String
    let contextWindow: Int
    let maxTokens: Int
    let reasoning: Bool
    let supportsImages: Bool
    let supportsFastMode: Bool

    init(
        provider: String,
        id: String,
        name: String,
        contextWindow: Int,
        maxTokens: Int,
        reasoning: Bool,
        supportsImages: Bool,
        supportsFastMode: Bool = false
    ) {
        self.provider = provider
        self.id = id
        self.name = name
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
        self.reasoning = reasoning
        self.supportsImages = supportsImages
        self.supportsFastMode = supportsFastMode
    }
}

struct AgentHostModelListResult: Decodable, Equatable {
    let models: [AgentHostModel]
}

enum AgentHostModelOption: String, Codable, Equatable {
    case fastMode
    case oneMillionContext
}

struct AgentHostModelOptionState: Codable, Equatable {
    let supported: Bool
    let enabled: Bool
}

struct AgentHostModelOptions: Codable, Equatable {
    let fastMode: AgentHostModelOptionState
    let oneMillionContext: AgentHostModelOptionState

    static let unsupported = AgentHostModelOptions(
        fastMode: AgentHostModelOptionState(supported: false, enabled: false),
        oneMillionContext: AgentHostModelOptionState(supported: false, enabled: false)
    )
}

struct AgentHostSessionSetModelParameters: Encodable, Equatable {
    let sessionId: String
    let provider: String
    let modelId: String
}

struct AgentHostSessionSetModelResult: Decodable, Equatable {
    let sessionId: String
    let model: AgentHostModel
    let contextUsage: AgentHostContextUsage?
    let thinkingLevel: AgentHostThinkingLevel
    let availableThinkingLevels: [AgentHostThinkingLevel]
    let modelOptions: AgentHostModelOptions

    init(
        sessionId: String,
        model: AgentHostModel,
        contextUsage: AgentHostContextUsage? = nil,
        thinkingLevel: AgentHostThinkingLevel,
        availableThinkingLevels: [AgentHostThinkingLevel],
        modelOptions: AgentHostModelOptions = .unsupported
    ) {
        self.sessionId = sessionId
        self.model = model
        self.contextUsage = contextUsage
        self.thinkingLevel = thinkingLevel
        self.availableThinkingLevels = availableThinkingLevels
        self.modelOptions = modelOptions
    }
}

struct AgentHostSessionSetThinkingLevelParameters: Encodable, Equatable {
    let sessionId: String
    let thinkingLevel: AgentHostThinkingLevel
}

struct AgentHostSessionSetThinkingLevelResult: Decodable, Equatable {
    let sessionId: String
    let thinkingLevel: AgentHostThinkingLevel
    let availableThinkingLevels: [AgentHostThinkingLevel]
}

struct AgentHostSessionSetModelOptionParameters: Encodable, Equatable {
    let sessionId: String
    let option: AgentHostModelOption
    let enabled: Bool
}

struct AgentHostSessionSetModelOptionResult: Decodable, Equatable {
    let sessionId: String
    let model: AgentHostModel
    let contextUsage: AgentHostContextUsage?
    let modelOptions: AgentHostModelOptions
}

struct AgentHostSessionSetAccessModeParameters: Encodable, Equatable {
    let sessionId: String
    let accessMode: AgentHostAccessMode
}

struct AgentHostSessionSetAccessModeResult: Decodable, Equatable {
    let sessionId: String
    let accessMode: AgentHostAccessMode
}

struct AgentHostSessionResolveApprovalParameters: Encodable, Equatable {
    let sessionId: String
    let requestId: String
    let decision: AgentHostApprovalDecision
}

struct AgentHostSessionResolveApprovalResult: Decodable, Equatable {
    let sessionId: String
    let requestId: String
    let decision: AgentHostApprovalDecision
}

struct AgentHostSessionDescriptor: Decodable, Equatable, Identifiable {
    let id: String
    let path: String
    let cwd: String
    let title: String
}

enum AgentHostSessionMessageRole: String, Decodable, Equatable {
    case user
    case assistant
    case tool
    case system
}

enum AgentHostSessionMessageContent: Decodable, Equatable {
    case text(String)
    case image(mimeType: String)
    case toolCall(id: String, name: String, argumentsSummary: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case mimeType
        case id
        case name
        case argumentsSummary
    }

    private enum ContentType: String, Decodable {
        case text
        case image
        case toolCall
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ContentType.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(
                mimeType: try container.decode(String.self, forKey: .mimeType)
            )
        case .toolCall:
            self = .toolCall(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                argumentsSummary: try container.decode(String.self, forKey: .argumentsSummary)
            )
        }
    }
}

struct AgentHostSessionMessage: Decodable, Equatable, Identifiable {
    let id: String
    let role: AgentHostSessionMessageRole
    let content: [AgentHostSessionMessageContent]
    let timestamp: String
    let provider: String?
    let model: String?
    let stopReason: String?
    let errorMessage: String?
    let toolCallId: String?
    let toolName: String?
    let isError: Bool?
}

struct AgentHostSessionSnapshotResult: Decodable, Equatable {
    let session: AgentHostSessionDescriptor
    let messages: [AgentHostSessionMessage]
    let state: AgentHostSessionRunState
    let sequence: Int
    let turnId: String?
    let gitBranch: String?
    let model: AgentHostModel?
    let contextUsage: AgentHostContextUsage?
    let thinkingLevel: AgentHostThinkingLevel
    let availableThinkingLevels: [AgentHostThinkingLevel]
    let modelOptions: AgentHostModelOptions
    let accessMode: AgentHostAccessMode
    let pendingApprovals: [AgentHostApprovalRequest]

    init(
        session: AgentHostSessionDescriptor,
        messages: [AgentHostSessionMessage],
        state: AgentHostSessionRunState,
        sequence: Int,
        turnId: String?,
        gitBranch: String? = nil,
        model: AgentHostModel?,
        contextUsage: AgentHostContextUsage? = nil,
        thinkingLevel: AgentHostThinkingLevel,
        availableThinkingLevels: [AgentHostThinkingLevel],
        modelOptions: AgentHostModelOptions = .unsupported,
        accessMode: AgentHostAccessMode,
        pendingApprovals: [AgentHostApprovalRequest]
    ) {
        self.session = session
        self.messages = messages
        self.state = state
        self.sequence = sequence
        self.turnId = turnId
        self.gitBranch = gitBranch
        self.model = model
        self.contextUsage = contextUsage
        self.thinkingLevel = thinkingLevel
        self.availableThinkingLevels = availableThinkingLevels
        self.modelOptions = modelOptions
        self.accessMode = accessMode
        self.pendingApprovals = pendingApprovals
    }
}
