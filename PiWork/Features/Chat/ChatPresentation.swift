import AppKit
import Foundation

enum MessageClipboard {
    static func copy(
        _ text: String,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard !text.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

enum MessageCopyFeedback {
    static let resetDelayNanoseconds: UInt64 = 3_000_000_000

    static func iconName(isCopied: Bool) -> String {
        isCopied ? "checkmark" : "doc.on.doc"
    }
}

struct PiChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant, tool, system }

    let id: String
    let role: Role
    let parts: [SessionTranscriptPart]
    let timestamp: Date?
    var isStreaming: Bool

    var text: String {
        parts.map { part in
            switch part {
            case .text(_, let text):
                return text
            case .skill:
                return ""
            case .thinking:
                return ""
            case .image(_, let mimeType):
                return L10n.format("chat.image_attachment", mimeType)
            case .tool(let tool):
                if tool.state == .completed {
                    return tool.isError == true
                        ? "✗ \(tool.name) failed"
                        : "✓ \(tool.name) done"
                }
                if tool.state == .cancelled {
                    return "− \(tool.name) cancelled"
                }
                return "▶ \(tool.name) \(tool.summary)"
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    var copyableText: String {
        parts.compactMap { part -> String? in
            guard case .text(_, let text) = part,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            if role == .assistant,
               let taggedThinking = AssistantTaggedThinkingContent.parse(text) {
                return taggedThinking.response.isEmpty ? nil : taggedThinking.response
            }
            return text
        }
        .joined(separator: "\n")
    }

    var hasCopyableText: Bool {
        !copyableText.isEmpty
    }

    var usedSkills: [SessionSkillRecord] {
        parts.reduce(into: []) { result, part in
            guard case .skill(let skill) = part,
                  !result.contains(where: { $0.name == skill.name }) else {
                return
            }
            result.append(skill)
        }
    }

    var isVisible: Bool {
        isStreaming || parts.contains { part in
            switch part {
            case .text(_, let text):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .skill:
                return true
            case .thinking(let thinking):
                return thinking.isVisibleInTranscript
            case .image, .tool:
                return true
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        role: Role,
        text: String,
        timestamp: Date? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        parts = [.text(id: "\(id):text:0", text: text)]
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    init(
        id: String,
        role: Role,
        parts: [SessionTranscriptPart],
        timestamp: Date?,
        isStreaming: Bool
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    init(message: AgentHostSessionMessage, isStreaming: Bool = false) {
        id = message.id
        role = switch message.role {
        case .user: .user
        case .assistant: .assistant
        case .tool: .tool
        case .system: .system
        }
        parts = message.content.enumerated().map { index, content in
            let partID = "\(message.id):part:\(index)"
            switch content {
            case .text(let text):
                return .text(id: partID, text: text)
            case .skill(let name):
                return .skill(SessionSkillRecord(id: partID, name: name))
            case .thinking(let text, let redacted):
                return .thinking(
                    SessionThinkingRecord(
                        id: partID,
                        text: text,
                        state: .completed,
                        redacted: redacted
                    )
                )
            case .image(let mimeType):
                return .image(id: partID, mimeType: mimeType)
            case .toolCall(let id, let name, let argumentsSummary):
                return .tool(
                    SessionToolRecord(
                        id: id,
                        name: name,
                        summary: argumentsSummary,
                        state: .running,
                        isError: nil
                    )
                )
            }
        }
        timestamp = Self.parseTimestamp(message.timestamp)
        self.isStreaming = isStreaming
    }

    init(message: SessionTranscriptMessage, isStreaming: Bool = false) {
        id = message.id
        role = switch message.role {
        case .user: .user
        case .assistant: .assistant
        case .tool: .tool
        case .system: .system
        }
        parts = message.parts
        timestamp = Self.parseTimestamp(message.timestamp)
        self.isStreaming = isStreaming
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        return fractionalTimestampFormatter.date(from: value)
            ?? timestampFormatter.date(from: value)
    }

    private static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let timestampFormatter = ISO8601DateFormatter()
}

enum AssistantTranscriptBlock: Equatable, Identifiable {
    case text(id: String, text: String)
    case thinking(SessionThinkingRecord)
    case image(id: String, mimeType: String)
    case tools(AssistantToolGroup)

    var id: String {
        switch self {
        case .text(let id, _), .image(let id, _):
            return id
        case .thinking(let thinking):
            return thinking.id
        case .tools(let group):
            return group.id
        }
    }
}

extension SessionThinkingRecord {
    var isVisibleInTranscript: Bool {
        !redacted
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AssistantToolGroup: Equatable, Identifiable {
    let id: String
    let tools: [SessionToolRecord]

    var status: AssistantToolGroupStatus {
        if tools.contains(where: { $0.state == .awaitingApproval }) {
            return .approvalRequired
        }

        if tools.contains(where: { $0.state == .running }) {
            return .running(
                completed: tools.filter { $0.state.isTerminal }.count,
                total: tools.count
            )
        }

        let failedCount = tools.filter { $0.isError == true }.count
        if failedCount > 0 {
            return .failed(total: tools.count, failed: failedCount)
        }

        if tools.contains(where: { $0.state == .cancelled }) {
            return .cancelled(total: tools.count)
        }

        return .completed(total: tools.count)
    }
}

enum AssistantToolGroupStatus: Equatable {
    case running(completed: Int, total: Int)
    case approvalRequired
    case failed(total: Int, failed: Int)
    case completed(total: Int)
    case cancelled(total: Int)

    var prefersExpanded: Bool {
        switch self {
        case .running, .approvalRequired, .failed:
            return true
        case .completed, .cancelled:
            return false
        }
    }

    func isExpanded(manualSelection: Bool?) -> Bool {
        if self == .approvalRequired {
            return true
        }
        return manualSelection ?? prefersExpanded
    }
}

enum AssistantTranscriptPresentation {
    static func groupAdjacentTools(in messages: [PiChatMessage]) -> [PiChatMessage] {
        var grouped: [PiChatMessage] = []

        for message in messages {
            guard isToolOnly(message),
                  let previous = grouped.last,
                  endsWithTools(previous) else {
                grouped.append(message)
                continue
            }

            grouped[grouped.index(before: grouped.endIndex)] = PiChatMessage(
                id: previous.id,
                role: previous.role,
                parts: previous.parts + message.parts,
                timestamp: previous.timestamp ?? message.timestamp,
                isStreaming: previous.isStreaming || message.isStreaming
            )
        }

        return grouped
    }

    static func blocks(from parts: [SessionTranscriptPart]) -> [AssistantTranscriptBlock] {
        var blocks: [AssistantTranscriptBlock] = []
        var consecutiveTools: [SessionToolRecord] = []

        func appendTools() {
            guard let firstTool = consecutiveTools.first else { return }
            blocks.append(
                .tools(
                    AssistantToolGroup(
                        id: "tool-group:\(firstTool.id)",
                        tools: consecutiveTools
                    )
                )
            )
            consecutiveTools.removeAll(keepingCapacity: true)
        }

        for part in parts {
            switch part {
            case .tool(let tool):
                consecutiveTools.append(tool)
            case .skill:
                appendTools()
            case .thinking(let thinking):
                if thinking.isVisibleInTranscript {
                    appendTools()
                    blocks.append(.thinking(thinking))
                }
            case .text(let id, let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                appendTools()
                if let taggedThinking = AssistantTaggedThinkingContent.parse(text) {
                    let thinking = SessionThinkingRecord(
                        id: "\(id):thinking",
                        text: taggedThinking.thinking,
                        state: taggedThinking.state,
                        redacted: false
                    )
                    if thinking.isVisibleInTranscript {
                        blocks.append(.thinking(thinking))
                    }
                    if !taggedThinking.response.isEmpty {
                        blocks.append(
                            .text(id: "\(id):response", text: taggedThinking.response)
                        )
                    }
                } else {
                    blocks.append(.text(id: id, text: text))
                }
            case .image(let id, let mimeType):
                appendTools()
                blocks.append(.image(id: id, mimeType: mimeType))
            }
        }

        appendTools()
        return blocks
    }

    static func metadataAnchorID(in blocks: [AssistantTranscriptBlock]) -> String? {
        for block in blocks.reversed() {
            if case .text(let id, let text) = block,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return id
            }
        }
        return nil
    }

    private static func isToolOnly(_ message: PiChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        let visibleBlocks = blocks(from: message.parts)
        return !visibleBlocks.isEmpty && visibleBlocks.allSatisfy { block in
            if case .tools = block { return true }
            return false
        }
    }

    private static func endsWithTools(_ message: PiChatMessage) -> Bool {
        guard message.role == .assistant,
              let lastBlock = blocks(from: message.parts).last,
              case .tools = lastBlock else {
            return false
        }
        return true
    }
}

private struct AssistantTaggedThinkingContent {
    let thinking: String
    let response: String
    let state: SessionThinkingRunState

    static func parse(_ text: String) -> AssistantTaggedThinkingContent? {
        let openingTag = "<think>"
        let closingTag = "</think>"
        let trimmed = text.drop(while: { $0.isWhitespace })

        if !trimmed.isEmpty, openingTag.hasPrefix(trimmed) {
            return AssistantTaggedThinkingContent(
                thinking: "",
                response: "",
                state: .running
            )
        }
        guard trimmed.hasPrefix(openingTag) else { return nil }

        let thinkingStart = trimmed.index(trimmed.startIndex, offsetBy: openingTag.count)
        guard let closingRange = trimmed.range(of: closingTag, range: thinkingStart..<trimmed.endIndex) else {
            return AssistantTaggedThinkingContent(
                thinking: String(trimmed[thinkingStart...])
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                response: "",
                state: .running
            )
        }

        return AssistantTaggedThinkingContent(
            thinking: String(trimmed[thinkingStart..<closingRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            response: String(trimmed[closingRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            state: .completed
        )
    }
}

enum TranscriptScrollPresentation {
    static func isNearBottom(
        bottomY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat
    ) -> Bool {
        bottomY <= viewportHeight + threshold
    }
}

struct PiModelOption: Identifiable, Equatable {
    let provider: String
    let modelID: String
    let name: String
    let supportsFastMode: Bool

    var id: String { "\(provider)/\(modelID)" }
    var displayName: String { name.isEmpty ? modelID : name }
    var providerIconAssetName: String {
        let modelIdentity = "\(name) \(modelID)".lowercased()
        let normalizedModelID = modelID.lowercased()
        switch modelIdentity {
        case let value where value.contains("claude") || value.contains("anthropic"):
            return "ModelIconClaude"
        case let value where value.contains("gemma"):
            return "ModelIconGemma"
        case let value where value.contains("gemini"):
            return "ModelIconGemini"
        case let value where value.contains("qwen"):
            return "ModelIconQwen"
        case let value where value.contains("llama")
            || normalizedModelID.contains("meta/")
            || normalizedModelID.contains("meta."):
            return "ModelIconMeta"
        case let value where value.contains("mistral")
            || value.contains("mixtral")
            || value.contains("codestral")
            || value.contains("devstral")
            || value.contains("magistral")
            || value.contains("ministral")
            || value.contains("pixtral")
            || value.contains("voxtral"):
            return "ModelIconMistral"
        case let value where value.contains("minimax"):
            return "ModelIconMiniMax"
        case let value where value.contains("glm")
            || value.contains("z.ai")
            || value.contains("z-ai")
            || value.contains("zhipu"):
            return "ModelIconZAI"
        case let value where value.contains("mimo") || value.contains("xiaomi"):
            return "ModelIconXiaomiMiMo"
        case let value where value.contains("nemotron") || value.contains("nvidia"):
            return "ModelIconNVIDIA"
        case let value where value.contains("nova"):
            return "ModelIconNova"
        case let value where value.contains("cohere")
            || normalizedModelID.hasPrefix("command-"):
            return "ModelIconCohere"
        case let value where value.contains("stepfun")
            || normalizedModelID.hasPrefix("step-"):
            return "ModelIconStepFun"
        case let value where value.contains("microsoft")
            || normalizedModelID.hasPrefix("phi-")
            || normalizedModelID.hasPrefix("mai-"):
            return "ModelIconMicrosoft"
        case let value where value.contains("grok"):
            return "ModelIconGrok"
        case let value where value.contains("deepseek"):
            return "ModelIconDeepSeek"
        case let value where value.contains("kimi") || value.contains("moonshot"):
            return "ModelIconKimi"
        case let value where value.contains("gpt")
            || value.contains("openai")
            || normalizedModelID.hasPrefix("o1")
            || normalizedModelID.hasPrefix("o3")
            || normalizedModelID.hasPrefix("o4"):
            return "ModelIconOpenAI"
        default:
            break
        }

        switch provider.lowercased() {
        case let value where value.contains("anthropic"):
            return "ModelIconClaude"
        case let value where value.contains("google") || value.contains("gemini"):
            return "ModelIconGemini"
        case let value where value.contains("xai"):
            return "ModelIconGrok"
        case let value where value.contains("deepseek"):
            return "ModelIconDeepSeek"
        case let value where value.contains("moonshot") || value.contains("kimi"):
            return "ModelIconKimi"
        case let value where value.contains("openai"):
            return "ModelIconOpenAI"
        case let value where value.contains("alibaba") || value.contains("qwen"):
            return "ModelIconQwen"
        case let value where value.contains("mistral"):
            return "ModelIconMistral"
        case let value where value.contains("minimax"):
            return "ModelIconMiniMax"
        case let value where value.contains("zai") || value.contains("zhipu"):
            return "ModelIconZAI"
        case let value where value.contains("nvidia"):
            return "ModelIconNVIDIA"
        case let value where value.contains("cohere"):
            return "ModelIconCohere"
        case let value where value.contains("stepfun"):
            return "ModelIconStepFun"
        case let value where value.contains("microsoft") || value.contains("azure"):
            return "ModelIconMicrosoft"
        default:
            return "ModelIconLobeHub"
        }
    }

    init(model: AgentHostModel) {
        provider = model.provider
        modelID = model.id
        name = model.name
        supportsFastMode = model.supportsFastMode
    }
}

struct ContextUsagePresentation: Equatable {
    let usage: AgentHostContextUsage

    var progress: Double {
        guard let percentage else { return 0 }
        return min(max(percentage / 100, 0), 1)
    }

    var percentText: String {
        guard let percentage else { return L10n.string("context.recalculating") }
        return L10n.format("context.percent_used", Int(percentage.rounded()))
    }

    var detailText: String {
        guard let tokens = usage.tokens else {
            return L10n.format("context.total", Self.tokenCountText(usage.contextWindow))
        }
        return L10n.format(
            "context.used_total",
            Self.tokenCountText(tokens),
            Self.tokenCountText(usage.contextWindow)
        )
    }

    var accessibilityLabel: String {
        L10n.format("context.accessibility", percentText, detailText)
    }

    private var percentage: Double? {
        if let percent = usage.percent { return percent }
        guard let tokens = usage.tokens, usage.contextWindow > 0 else { return nil }
        return Double(tokens) / Double(usage.contextWindow) * 100
    }

    static func tokenCountText(_ count: Int) -> String {
        let value = max(count, 0)
        if value >= 1_000_000 {
            return compact(Double(value) / 1_000_000, suffix: "M")
        }
        if value >= 1_000 {
            return compact(Double(value) / 1_000, suffix: "k")
        }
        return String(value)
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let format = value < 10 && value.rounded() != value ? "%.1f" : "%.0f"
        return String(
            format: format,
            locale: L10n.currentLanguage.locale,
            value
        ) + suffix
    }
}
