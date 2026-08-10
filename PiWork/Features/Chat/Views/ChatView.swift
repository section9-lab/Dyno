import AppKit
import MarkdownUI
import SwiftUI

/// One conversation surface shared by Chat and Work. Chat owns an isolated
/// application-support working directory; Work only creates an agent after
/// the user has selected a linked project.
struct ChatView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject private var sessionStore: SessionStore
    @Binding private var selectedProject: PiProject?

    let mode: SidebarTab
    let projects: [PiProject]
    let hostError: String?
    let onSelectProject: (PiProject) -> Void
    let onAddFolder: () -> Void

    @State private var draft = ""
    @State private var selectedSlashCommand: AgentHostSlashCommand?
    @State private var slashCommands: [AgentHostSlashCommand] = []
    @State private var actionError: String?
    @State private var gitBranches = AgentHostGitBranchesResult.unavailable
    @State private var isFollowingTranscriptTail = true
    @State private var isAdjustingTranscriptScroll = false
    @State private var transcriptScrollRequest = 0

    init(
        mode: SidebarTab,
        projects: [PiProject],
        selectedProject: Binding<PiProject?>,
        sessionStore: SessionStore,
        hostError: String? = nil,
        onSelectProject: @escaping (PiProject) -> Void = { _ in },
        onAddFolder: @escaping () -> Void
    ) {
        self.mode = mode
        self.projects = projects
        self._selectedProject = selectedProject
        self._sessionStore = ObservedObject(wrappedValue: sessionStore)
        self.hostError = hostError
        self.onSelectProject = onSelectProject
        self.onAddFolder = onAddFolder
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)

            if messages.isEmpty {
                emptySession
            } else {
                transcript
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
            }

            SessionComposer(
                mode: mode,
                projects: projects,
                selectedProject: $selectedProject,
                draft: $draft,
                selectedSlashCommand: $selectedSlashCommand,
                slashCommands: slashCommands,
                promptHistory: promptHistory,
                isExecuting: isExecuting,
                canSend: canSend,
                availableModels: availableModels,
                selectedModel: selectedModel,
                selectedModelName: selectedModelName,
                contextUsage: activeRecord?.contextUsage,
                selectedThinkingLevel: activeRecord?.thinkingLevel,
                availableThinkingLevels: activeRecord?.availableThinkingLevels ?? [],
                modelOptions: activeRecord?.modelOptions ?? .unsupported,
                selectedAccessMode: activeRecord?.accessMode,
                gitBranches: gitBranches.branches,
                isGitAvailable: gitBranches.available,
                selectedGitBranch: activeRecord?.gitBranch,
                canSelectGitBranch: activeRecord?.messages.isEmpty == true,
                onAddFolder: onAddFolder,
                onSelectProject: onSelectProject,
                onSelectGitBranch: selectGitBranch,
                onSelectModel: selectModel,
                onToggleFastMode: toggleFastMode,
                onSelectThinkingLevel: selectThinkingLevel,
                onSelectModelOption: selectModelOption,
                onSelectAccessMode: selectAccessMode,
                onSend: send,
                onStop: stopGeneration
            )
            .frame(maxWidth: 900)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .task(id: activeSessionId) {
            await loadSlashCommands()
        }
        .task(id: gitBranchLoadID) {
            await loadGitBranches()
        }
        .onChange(of: activeSessionId) { _ in
            isFollowingTranscriptTail = true
            transcriptScrollRequest &+= 1
        }
    }

    private var transcript: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(messages) { message in
                            ChatMessageRow(message: message) { approval, decision in
                                resolve(approval: approval, decision: decision)
                            }
                            .id(message.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(TranscriptLayout.tailID)
                            .background(
                                GeometryReader { tail in
                                    Color.clear.preference(
                                        key: TranscriptBottomPreferenceKey.self,
                                        value: tail.frame(
                                            in: .named(TranscriptLayout.coordinateSpace)
                                        ).maxY
                                    )
                                }
                            )
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .coordinateSpace(name: TranscriptLayout.coordinateSpace)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 16)
                        .opacity(0.32)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottom) {
                    if !isFollowingTranscriptTail {
                        Button {
                            scrollToTranscriptTail(using: proxy)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .background(.regularMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                        .shadow(color: AppPalette.subtleShadow, radius: 7, y: 2)
                        .padding(.bottom, 12)
                        .help(L10n.string("chat.scroll_to_latest"))
                        .accessibilityLabel(L10n.string("chat.scroll_to_latest"))
                        .transition(
                            accessibilityReduceMotion
                                ? .opacity
                                : .scale(scale: 0.92).combined(with: .opacity)
                        )
                    }
                }
                .animation(
                    accessibilityReduceMotion ? nil : .easeOut(duration: 0.16),
                    value: isFollowingTranscriptTail
                )
                .onPreferenceChange(TranscriptBottomPreferenceKey.self) { bottomY in
                    guard !isAdjustingTranscriptScroll else { return }
                    isFollowingTranscriptTail = TranscriptScrollPresentation.isNearBottom(
                        bottomY: bottomY,
                        viewportHeight: viewport.size.height,
                        threshold: TranscriptLayout.followThreshold
                    )
                }
                .onChange(of: transcriptScrollToken) { _ in
                    guard isFollowingTranscriptTail else { return }
                    scrollToTranscriptTail(using: proxy)
                }
                .onChange(of: transcriptScrollRequest) { _ in
                    scrollToTranscriptTail(using: proxy)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        scrollToTranscriptTail(using: proxy)
                    }
                }
            }
        }
    }

    private func scrollToTranscriptTail(using proxy: ScrollViewProxy) {
        isAdjustingTranscriptScroll = true
        proxy.scrollTo(TranscriptLayout.tailID, anchor: .bottom)
        DispatchQueue.main.async {
            isFollowingTranscriptTail = true
            isAdjustingTranscriptScroll = false
        }
    }

    private var emptySession: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text(L10n.string("chat.welcome"))
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.86))

                    Text(mode == .work
                        ? L10n.string("chat.work_subtitle")
                        : L10n.string("chat.chat_subtitle"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.48))
                }

                HStack(spacing: 12) {
                    ForEach(SessionSuggestion.defaults) { suggestion in
                        Button {
                            draft = suggestion.prompt
                        } label: {
                            SessionSuggestionCard(suggestion: suggestion)
                        }
                        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 20))
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 820)
            }
            .padding(.horizontal, 28)
            .padding(.top, 54)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func send() {
        let text = SessionComposerState.submissionText(
            draft: draft,
            selectedCommand: selectedSlashCommand
        )
        guard
            SessionComposerState.primaryAction(
                draft: text,
                isExecuting: isExecuting
            ) == .send,
            canSend
        else { return }

        draft = ""
        selectedSlashCommand = nil
        guard let sessionId = activeSessionId else { return }
        isFollowingTranscriptTail = true
        transcriptScrollRequest &+= 1
        actionError = nil
        Task {
            do {
                try await sessionStore.submitPrompt(sessionId: sessionId, text: text)
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func loadSlashCommands() async {
        guard mode == .work, let sessionId = activeSessionId else {
            slashCommands = []
            return
        }
        do {
            slashCommands = try await sessionStore.slashCommands(sessionId: sessionId)
            actionError = nil
        } catch {
            slashCommands = []
            actionError = String(describing: error)
        }
    }

    private func loadGitBranches() async {
        guard mode == .work, let project = selectedProject else {
            gitBranches = .unavailable
            return
        }
        let sessionId = activeSessionId
        do {
            let result = try await sessionStore.gitBranches(cwd: project.path)
            guard selectedProject?.id == project.id, activeSessionId == sessionId else { return }
            gitBranches = result
            guard
                result.available,
                let sessionId,
                activeRecord?.messages.isEmpty == true,
                activeRecord?.gitBranch == nil,
                let currentBranch = result.currentBranch,
                result.branches.contains(currentBranch)
            else { return }
            try? await sessionStore.setGitBranch(currentBranch, sessionId: sessionId)
        } catch {
            guard selectedProject?.id == project.id, activeSessionId == sessionId else { return }
            gitBranches = .unavailable
        }
    }

    private func selectGitBranch(_ branch: String) {
        guard let sessionId = activeSessionId, activeRecord?.messages.isEmpty == true else {
            return
        }
        actionError = nil
        Task {
            do {
                try await sessionStore.setGitBranch(branch, sessionId: sessionId)
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func selectModel(_ model: PiModelOption) {
        guard let sessionId = activeSessionId else { return }
        guard let hostModel = sessionStore.availableModels.first(where: {
            $0.provider == model.provider && $0.id == model.modelID
        }) else { return }
        actionError = nil
        Task {
            do {
                try await sessionStore.selectModel(hostModel, sessionId: sessionId)
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func toggleFastMode(_ model: PiModelOption) {
        guard model.supportsFastMode, let sessionId = activeSessionId else { return }
        guard let hostModel = sessionStore.availableModels.first(where: {
            $0.provider == model.provider && $0.id == model.modelID
        }) else { return }
        let isSelected = selectedModel == model
        let shouldEnable = !isSelected || activeRecord?.modelOptions.fastMode.enabled != true
        actionError = nil
        Task {
            do {
                if !isSelected {
                    try await sessionStore.selectModel(hostModel, sessionId: sessionId)
                }
                try await sessionStore.selectModelOption(
                    .fastMode,
                    enabled: shouldEnable,
                    sessionId: sessionId
                )
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func selectThinkingLevel(_ thinkingLevel: AgentHostThinkingLevel) {
        guard let sessionId = activeSessionId else { return }
        actionError = nil
        Task {
            do {
                try await sessionStore.selectThinkingLevel(
                    thinkingLevel,
                    sessionId: sessionId
                )
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func selectModelOption(
        _ option: AgentHostModelOption,
        enabled: Bool
    ) {
        guard let sessionId = activeSessionId else { return }
        actionError = nil
        Task {
            do {
                try await sessionStore.selectModelOption(
                    option,
                    enabled: enabled,
                    sessionId: sessionId
                )
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func selectAccessMode(_ accessMode: AgentHostAccessMode) {
        guard let sessionId = activeSessionId else { return }
        actionError = nil
        Task {
            do {
                try await sessionStore.selectAccessMode(accessMode, sessionId: sessionId)
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func resolve(
        approval: AgentHostApprovalRequest,
        decision: AgentHostApprovalDecision
    ) {
        guard let sessionId = activeSessionId else { return }
        actionError = nil
        Task {
            do {
                try await sessionStore.resolveApproval(
                    sessionId: sessionId,
                    requestId: approval.id,
                    decision: decision
                )
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func stopGeneration() {
        guard let sessionId = activeSessionId else { return }
        actionError = nil
        Task {
            do {
                try await sessionStore.abortSession(sessionId: sessionId)
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private var activeSessionId: String? {
        switch mode {
        case .chat:
            return sessionStore.selectedChatSessionId
        case .work:
            guard let project = selectedProject else { return nil }
            return sessionStore.selectedWorkSessionIdByProjectPath[project.path]
        }
    }

    private var activeRecord: SessionRecord? {
        guard let sessionId = activeSessionId else { return nil }
        return sessionStore.records[sessionId]
    }

    private var gitBranchLoadID: String {
        "\(mode):\(selectedProject?.path ?? ""):\(activeSessionId ?? "")"
    }

    private var messages: [PiChatMessage] {
        guard let record = activeRecord else { return [] }
        let streamingMessageID = record.activeTurnId.flatMap { turnId in
            let messageID = "turn:\(turnId):assistant"
            return record.transcript.last { message in
                message.role == .assistant
                    && (
                        message.id == messageID
                            || message.id.hasPrefix("\(messageID):")
                    )
            }?.id
        }
        let visibleMessages = record.transcript.map { message in
            PiChatMessage(
                message: message,
                isStreaming: message.id == streamingMessageID && isExecuting
            )
        }
        .filter(\.isVisible)
        return AssistantTranscriptPresentation.groupAdjacentTools(in: visibleMessages)
    }

    private var transcriptTailID: String? {
        return messages.last?.id
    }

    private var transcriptScrollToken: String {
        "\(transcriptTailID ?? ""):\(activeRecord?.lastSequence ?? 0)"
    }

    private var promptHistory: [String] {
        messages.compactMap { message in
            guard message.role == .user else { return nil }
            return message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : message.text
        }
    }

    private var isExecuting: Bool {
        switch activeRecord?.runState {
        case .submitting, .running, .stopping: return true
        default: return false
        }
    }

    private var canSend: Bool {
        guard let model = activeRecord?.model else { return false }
        return sessionStore.availableModels.contains {
            $0.provider == model.provider && $0.id == model.id
        }
    }

    private var availableModels: [PiModelOption] {
        guard activeRecord != nil else { return [] }
        return sessionStore.availableModels.map(PiModelOption.init(model:))
    }

    private var selectedModel: PiModelOption? {
        return activeRecord?.model.map(PiModelOption.init(model:))
    }

    private var selectedModelName: String {
        selectedModel?.displayName ?? L10n.string("chat.select_model")
    }

    private var errorMessage: String? {
        actionError ?? activeRecord?.errorMessage ?? hostError
    }
}

private enum TranscriptLayout {
    static let coordinateSpace = "transcript-scroll"
    static let tailID = "transcript-tail"
    static let followThreshold: CGFloat = 72
}

private struct TranscriptBottomPreferenceKey: PreferenceKey {
    static var defaultValue = CGFloat.infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SessionComposer: View {
    let mode: SidebarTab
    let projects: [PiProject]
    @Binding var selectedProject: PiProject?
    @Binding var draft: String
    @Binding var selectedSlashCommand: AgentHostSlashCommand?
    let slashCommands: [AgentHostSlashCommand]
    let promptHistory: [String]
    let isExecuting: Bool
    let canSend: Bool
    let availableModels: [PiModelOption]
    let selectedModel: PiModelOption?
    let selectedModelName: String
    let contextUsage: AgentHostContextUsage?
    let selectedThinkingLevel: AgentHostThinkingLevel?
    let availableThinkingLevels: [AgentHostThinkingLevel]
    let modelOptions: AgentHostModelOptions
    let selectedAccessMode: AgentHostAccessMode?
    let gitBranches: [String]
    let isGitAvailable: Bool
    let selectedGitBranch: String?
    let canSelectGitBranch: Bool
    let onAddFolder: () -> Void
    let onSelectProject: (PiProject) -> Void
    let onSelectGitBranch: (String) -> Void
    let onSelectModel: (PiModelOption) -> Void
    let onToggleFastMode: (PiModelOption) -> Void
    let onSelectThinkingLevel: (AgentHostThinkingLevel) -> Void
    let onSelectModelOption: (AgentHostModelOption, Bool) -> Void
    let onSelectAccessMode: (AgentHostAccessMode) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    private let outerRadius: CGFloat = 28
    private let innerRadius: CGFloat = 27

    @State private var editorHeight = SessionComposerState.minimumEditorHeight
    @State private var isComposerHovering = false
    @State private var isProjectPickerPresented = false
    @State private var isGitBranchPickerPresented = false
    @State private var gitBranchSearchQuery = ""
    @FocusState private var isGitBranchSearchFocused: Bool
    @State private var isModelPickerPresented = false
    @State private var modelSearchQuery = ""
    @FocusState private var isModelSearchFocused: Bool
    @State private var isThinkingPickerPresented = false
    @State private var thinkingSliderValue = 0.0
    @State private var isThinkingMenuHovering = false
    @State private var isAccessMenuHovering = false
    @State private var highlightedSlashCommandIndex = 0
    @State private var isSlashCommandPanelDismissed = false
    @State private var editorFocusRequest = 0
    @State private var promptHistoryNavigation = SessionComposerPromptHistoryNavigation()

    var body: some View {
        VStack(spacing: 9) {
            if isSlashCommandPanelPresented {
                slashCommandPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composerSurface
        }
        .animation(.easeOut(duration: 0.16), value: isSlashCommandPanelPresented)
        .onChange(of: draft) { _ in
            highlightedSlashCommandIndex = 0
            isSlashCommandPanelDismissed = false
        }
        .onChange(of: slashCommands.map(\.id)) { _ in
            highlightedSlashCommandIndex = 0
        }
    }

    @ViewBuilder
    private var composerSurface: some View {
        Group {
            if mode.showsProjectSelection {
                VStack(spacing: 0) {
                    projectBar
                    editor
                        .background(AppPalette.raisedSurface)
                        .adaptiveCornerRadius(innerRadius)
                }
                .background(Color.primary.opacity(0.045))
                .adaptiveCornerRadius(outerRadius)
                .overlay(
                    adaptiveRoundedShape(cornerRadius: outerRadius)
                        .stroke(composerBorderColor, lineWidth: composerBorderWidth)
                )
                .shadow(color: AppPalette.raisedShadow, radius: 16, y: 5)
            } else {
                editor
                    .background(AppPalette.raisedSurface)
                    .adaptiveCornerRadius(outerRadius)
                    .overlay(
                        adaptiveRoundedShape(cornerRadius: outerRadius)
                            .stroke(composerBorderColor, lineWidth: composerBorderWidth)
                    )
                    .shadow(color: AppPalette.raisedShadow, radius: 16, y: 5)
            }
        }
        .onHover { isComposerHovering = $0 }
    }

    private var slashCommandQuery: String? {
        guard selectedSlashCommand == nil, !isSlashCommandPanelDismissed else { return nil }
        return SessionComposerState.slashQuery(in: draft, mode: mode)
    }

    private var filteredSlashCommands: [AgentHostSlashCommand] {
        guard let slashCommandQuery else { return [] }
        return SessionComposerState.filteredSlashCommands(
            slashCommands,
            query: slashCommandQuery
        )
    }

    private var isSlashCommandPanelPresented: Bool {
        slashCommandQuery != nil
    }

    private var slashCommandPanelHeight: CGFloat {
        guard !filteredSlashCommands.isEmpty else { return 58 }
        return CGFloat(min(filteredSlashCommands.count, 5) * 44 + 14)
    }

    private var slashCommandPanel: some View {
        Group {
            if filteredSlashCommands.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(L10n.string("chat.slash.no_matches"))
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.48))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredSlashCommands.indices, id: \.self) { index in
                            slashCommandRow(filteredSlashCommands[index], index: index)
                        }
                    }
                    .padding(7)
                }
            }
        }
        .frame(height: slashCommandPanelHeight)
        .background(AppPalette.raisedSurface)
        .adaptiveCornerRadius(18)
        .overlay(
            adaptiveRoundedShape(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: AppPalette.raisedShadow, radius: 14, y: 5)
        .accessibilityIdentifier("slash-command-menu")
    }

    private func slashCommandRow(
        _ command: AgentHostSlashCommand,
        index: Int
    ) -> some View {
        Button {
            selectSlashCommand(command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: command.source.composerIcon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)

                Text(command.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 12)

                if let description = command.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.46))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(command.source.composerKindTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .fixedSize()
            }
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        }
        .buttonStyle(
            RoundedInteractionButtonStyle(
                cornerRadius: 10,
                isSelected: highlightedSlashCommandIndex == index
            )
        )
        .onHover { hovering in
            if hovering { highlightedSlashCommandIndex = index }
        }
        .accessibilityLabel(
            "\(command.displayName), \(command.source.composerKindTitle)"
        )
        .accessibilityIdentifier("slash-command-\(command.id)")
    }

    private func selectSlashCommand(_ command: AgentHostSlashCommand) {
        draft = SessionComposerState.draftAfterSelectingSlashCommand(from: draft)
        selectedSlashCommand = command
        isSlashCommandPanelDismissed = true
        editorFocusRequest += 1
    }

    private func removeSelectedSlashCommand() {
        guard selectedSlashCommand != nil else { return }
        selectedSlashCommand = nil
        draft = draft.isEmpty ? "/" : "/ \(draft)"
        editorFocusRequest += 1
    }

    private func handleEditorCommand(_ command: SessionComposerEditorCommand) -> Bool {
        switch command {
        case .confirmSuggestion:
            guard isSlashCommandPanelPresented,
                  filteredSlashCommands.indices.contains(highlightedSlashCommandIndex)
            else { return false }
            selectSlashCommand(filteredSlashCommands[highlightedSlashCommandIndex])
            return true
        case .selectPreviousSuggestion:
            guard isSlashCommandPanelPresented, !filteredSlashCommands.isEmpty else {
                return false
            }
            highlightedSlashCommandIndex = (
                highlightedSlashCommandIndex - 1 + filteredSlashCommands.count
            ) % filteredSlashCommands.count
            return true
        case .selectNextSuggestion:
            guard isSlashCommandPanelPresented, !filteredSlashCommands.isEmpty else {
                return false
            }
            highlightedSlashCommandIndex = (
                highlightedSlashCommandIndex + 1
            ) % filteredSlashCommands.count
            return true
        case .dismissSuggestions:
            guard isSlashCommandPanelPresented else { return false }
            isSlashCommandPanelDismissed = true
            return true
        case .deleteSelectedCommand:
            guard selectedSlashCommand != nil else { return false }
            removeSelectedSlashCommand()
            return true
        case .recallPreviousPrompt:
            let currentDraft = SessionComposerState.submissionText(
                draft: draft,
                selectedCommand: selectedSlashCommand
            )
            guard let prompt = promptHistoryNavigation.previous(
                in: promptHistory,
                currentDraft: currentDraft
            ) else { return false }
            applyRecalledPrompt(prompt)
            return true
        case .recallNextPrompt:
            guard let prompt = promptHistoryNavigation.next(in: promptHistory) else {
                return false
            }
            applyRecalledPrompt(prompt)
            return true
        }
    }

    private func applyRecalledPrompt(_ prompt: String) {
        let recalled = SessionComposerState.recalledPrompt(prompt, commands: slashCommands)
        selectedSlashCommand = recalled.selectedCommand
        draft = recalled.draft
    }

    private func submitPrompt() {
        promptHistoryNavigation.reset()
        onSend()
    }

    private var projectBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                projectPicker

                if selectedProject != nil {
                    gitBranchControl
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: geometry.size.width, height: 44)
            .popover(
                isPresented: $isProjectPickerPresented,
                attachmentAnchor: .point(
                    UnitPoint(
                        x: SessionComposerState.projectPickerPopoverAnchorX(
                            composerWidth: geometry.size.width
                        ),
                        y: 0
                    )
                ),
                arrowEdge: .top
            ) {
                projectPickerContent
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var gitBranchControl: some View {
        if canSelectGitBranch {
            Button {
                gitBranchSearchQuery = ""
                isGitBranchPickerPresented.toggle()
            } label: {
                gitBranchLabel(opacity: isGitBranchPickerEnabled ? 0.82 : 0.28)
            }
            .buttonStyle(
                RoundedInteractionButtonStyle(
                    cornerRadius: 9,
                    isSelected: isGitBranchPickerPresented
                )
            )
            .disabled(!isGitBranchPickerEnabled)
            .accessibilityLabel(L10n.string("chat.select_branch"))
            .accessibilityIdentifier("git-branch-picker")
            .popover(isPresented: $isGitBranchPickerPresented, arrowEdge: .top) {
                gitBranchPickerContent
            }
        } else {
            gitBranchLabel(opacity: selectedGitBranch == nil ? 0.28 : 0.72)
                .help(L10n.string("chat.branch_read_only"))
                .accessibilityLabel(selectedGitBranch ?? L10n.string("chat.select_branch"))
                .accessibilityIdentifier("git-branch-picker")
        }
    }

    private func gitBranchLabel(opacity: Double) -> some View {
        HStack(spacing: 7) {
            GitBranchIcon()
            Text(selectedGitBranch ?? L10n.string("chat.select_branch"))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 14))
        .foregroundStyle(Color.primary)
        .opacity(opacity)
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(
            adaptiveRoundedShape(cornerRadius: 9)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var gitBranchPickerContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.primary.opacity(0.42))
                TextField(L10n.string("chat.search_branches"), text: $gitBranchSearchQuery)
                    .textFieldStyle(.plain)
                    .focused($isGitBranchSearchFocused)
                    .accessibilityIdentifier("branch-picker-search")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 42)

            Divider()

            ScrollView(.vertical) {
                if filteredGitBranches.isEmpty {
                    Text(L10n.string("chat.no_branches"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.46))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(6)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredGitBranches, id: \.self) { branch in
                            gitBranchPickerRow(branch)
                        }
                    }
                    .padding(6)
                }
            }
            .frame(height: gitBranchPickerListHeight)
            .accessibilityIdentifier("branch-picker-scroll-view")
        }
        .frame(width: 310)
        .onAppear {
            DispatchQueue.main.async {
                isGitBranchSearchFocused = true
            }
        }
    }

    private func gitBranchPickerRow(_ branch: String) -> some View {
        Button {
            onSelectGitBranch(branch)
            isGitBranchPickerPresented = false
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(branch == selectedGitBranch ? 1 : 0)
                    .frame(width: 14)
                GitBranchIcon()
                    .opacity(0.68)
                Text(branch)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.84))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }
        .buttonStyle(
            RoundedInteractionButtonStyle(
                cornerRadius: 8,
                isSelected: branch == selectedGitBranch
            )
        )
        .accessibilityIdentifier("git-branch-\(branch)")
    }

    private var filteredGitBranches: [String] {
        SessionComposerState.filteredGitBranches(
            gitBranches,
            query: gitBranchSearchQuery
        )
    }

    private var gitBranchPickerListHeight: CGFloat {
        let rowCount = max(
            SessionComposerState.visibleGitBranchRowCount(
                resultCount: filteredGitBranches.count
            ),
            1
        )
        return CGFloat(rowCount * 42 + 10)
    }

    private var isGitBranchPickerEnabled: Bool {
        isGitAvailable && !gitBranches.isEmpty
    }

    private var projectPicker: some View {
        Button {
            isProjectPickerPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(selectedProject?.name ?? L10n.string("chat.select_project"))
                    .lineLimit(1)
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.42))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.primary.opacity(selectedProject == nil ? 0.48 : 0.82))
            .padding(.horizontal, 8)
            .frame(height: 32)
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 9))
        .fixedSize()
        .accessibilityLabel(L10n.string("chat.select_project"))
    }

    private var projectPickerContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(projects) { project in
                Button {
                    onSelectProject(project)
                    isProjectPickerPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Label(project.name, systemImage: "folder")
                            .lineLimit(1)
                        Spacer(minLength: 16)
                        if selectedProject?.id == project.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                }
                .buttonStyle(
                    RoundedInteractionButtonStyle(
                        cornerRadius: 8,
                        isSelected: selectedProject?.id == project.id
                    )
                )
            }

            if !projects.isEmpty {
                Divider()
                    .padding(.vertical, 4)
            }

            Button {
                isProjectPickerPresented = false
                DispatchQueue.main.async {
                    onAddFolder()
                }
            } label: {
                Label(L10n.string("chat.add_project"), systemImage: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
            .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 8))
        }
        .padding(8)
        .frame(width: SessionComposerState.projectPickerPopoverWidth)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                GrowingTextEditor(
                    text: $draft,
                    height: $editorHeight,
                    leadingExclusionWidth: selectedSlashCommandTokenWidth,
                    focusRequest: editorFocusRequest,
                    onEditorCommand: handleEditorCommand,
                    onSubmit: submitPrompt
                )
                .frame(height: editorHeight)
                .accessibilityIdentifier("session-composer-input")

                selectedSlashCommandToken

                if draft.isEmpty, selectedSlashCommand == nil {
                    Text(L10n.string("chat.input_placeholder"))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .padding(.leading, 1)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: editorHeight)

            HStack(spacing: 10) {
                if mode == .work, let selectedAccessMode {
                    accessModeMenu(selectedAccessMode)
                }

                Spacer(minLength: 0)
                if let contextUsage {
                    ContextUsageIndicator(usage: contextUsage)
                }
                modelPicker

                if let selectedThinkingLevel {
                    thinkingLevelMenu(selectedThinkingLevel)
                }

                primaryActionButton
            }
            .frame(height: 42)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var selectedSlashCommandTokenWidth: CGFloat {
        guard let command = selectedSlashCommand else { return 0 }
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let textWidth = (command.displayName as NSString).size(
            withAttributes: [.font: font]
        ).width
        return ceil(17 + 5 + textWidth)
    }

    @ViewBuilder
    private var selectedSlashCommandToken: some View {
        if let command = selectedSlashCommand {
            Button {
                removeSelectedSlashCommand()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: command.source.composerIcon)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 17)
                    Text(command.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.accentColor)
                .frame(height: 18)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .help(L10n.format("chat.slash.remove", command.displayName))
            .accessibilityLabel(L10n.format("chat.slash.remove", command.displayName))
        }
    }

    private var modelPicker: some View {
        Button {
            modelSearchQuery = ""
            isModelPickerPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(selectedModelName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.42))
            }
            .font(.system(size: 14))
            .foregroundStyle(Color.primary.opacity(0.82))
            .padding(.horizontal, 8)
            .frame(height: 32)
        }
        .buttonStyle(
            RoundedInteractionButtonStyle(
                cornerRadius: 9,
                isSelected: isModelPickerPresented
            )
        )
        .fixedSize()
        .disabled(availableModels.isEmpty)
        .accessibilityLabel(L10n.string("chat.select_model"))
        .popover(isPresented: $isModelPickerPresented, arrowEdge: .top) {
            modelPickerContent
        }
    }

    private var modelPickerContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.primary.opacity(0.42))
                TextField(L10n.string("chat.search_models"), text: $modelSearchQuery)
                    .textFieldStyle(.plain)
                    .focused($isModelSearchFocused)
                    .accessibilityIdentifier("model-picker-search")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 40)

            Divider()

            ScrollView(.vertical) {
                if filteredModels.isEmpty {
                    Text(L10n.string("chat.no_models"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.46))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .padding(6)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredModels) { model in
                            modelPickerRow(model)
                        }
                    }
                    .padding(6)
                }
            }
            .frame(height: modelPickerListHeight)
            .accessibilityIdentifier("model-picker-scroll-view")
        }
        .frame(width: 272)
        .onAppear {
            DispatchQueue.main.async {
                isModelSearchFocused = true
            }
        }
    }

    private func modelPickerRow(_ model: PiModelOption) -> some View {
        HStack(spacing: 4) {
            Button {
                onSelectModel(model)
                isModelPickerPresented = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(model == selectedModel ? 1 : 0)
                        .frame(width: 14)
                    ModelProviderIcon(model: model)
                    Text(model.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.84))
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
            .buttonStyle(
                RoundedInteractionButtonStyle(
                    cornerRadius: 8,
                    isSelected: model == selectedModel
                )
            )

            fastModeButton(for: model)
        }
        .frame(maxWidth: .infinity)
    }

    private func fastModeButton(for model: PiModelOption) -> some View {
        let isEnabled = model == selectedModel && modelOptions.fastMode.enabled

        return Button {
            onToggleFastMode(model)
        } label: {
            FastModeCapsuleSwitch(
                isOn: isEnabled,
                isAvailable: model.supportsFastMode
            )
            .frame(width: 38, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.supportsFastMode)
        .help(model.supportsFastMode
            ? L10n.string("chat.fast_mode")
            : L10n.string("chat.fast_unsupported"))
        .accessibilityLabel(L10n.format("chat.fast_accessibility", model.displayName))
        .accessibilityValue(
            isEnabled
                ? L10n.string("chat.enabled")
                : (model.supportsFastMode
                    ? L10n.string("chat.disabled")
                    : L10n.string("chat.unsupported"))
        )
        .accessibilityIdentifier("fast-mode-\(model.id)")
    }

    private var filteredModels: [PiModelOption] {
        SessionComposerState.filteredModels(
            availableModels,
            query: modelSearchQuery
        )
    }

    private var modelPickerListHeight: CGFloat {
        let rowCount = max(
            SessionComposerState.visibleModelRowCount(
                resultCount: filteredModels.count
            ),
            1
        )
        return CGFloat(rowCount * 38 + 10)
    }

    private func thinkingLevelMenu(
        _ selectedThinkingLevel: AgentHostThinkingLevel
    ) -> some View {
        Button {
            thinkingSliderValue = Double(
                availableThinkingLevels.firstIndex(of: selectedThinkingLevel) ?? 0
            )
            isThinkingPickerPresented.toggle()
        } label: {
            Text(selectedThinkingLevel.composerTitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.72))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    adaptiveRoundedShape(cornerRadius: 9)
                        .fill(
                            isThinkingMenuHovering
                                ? AppPalette.hoverRowFill
                                : Color.primary.opacity(0.045)
                        )
                )
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 9))
        .fixedSize()
        .help(L10n.format("chat.thinking_help", selectedThinkingLevel.composerTitle))
        .accessibilityLabel(L10n.format("chat.thinking_help", selectedThinkingLevel.composerTitle))
        .accessibilityIdentifier("session-thinking-level")
        .onHover { isThinkingMenuHovering = $0 }
        .popover(isPresented: $isThinkingPickerPresented, arrowEdge: .bottom) {
            thinkingLevelPickerContent(selectedThinkingLevel)
        }
    }

    private func thinkingLevelPickerContent(
        _ selectedThinkingLevel: AgentHostThinkingLevel
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if availableThinkingLevels.count > 1 {
                HStack(spacing: 5) {
                    Text(L10n.string("chat.effort"))
                        .foregroundStyle(Color.primary.opacity(0.48))
                    Text(pendingThinkingLevel?.composerTitle ?? selectedThinkingLevel.composerTitle)
                        .foregroundStyle(Color.primary.opacity(0.82))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 14, weight: .medium))

                HStack {
                    Text(L10n.string("chat.faster"))
                    Spacer(minLength: 0)
                    Text(L10n.string("chat.smarter"))
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.48))

                ZStack {
                    HStack(spacing: 0) {
                        ForEach(availableThinkingLevels.indices, id: \.self) { index in
                            Circle()
                                .fill(Color.primary.opacity(0.25))
                                .frame(width: 4, height: 4)
                            if index < availableThinkingLevels.count - 1 {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .allowsHitTesting(false)

                    Slider(
                        value: $thinkingSliderValue,
                        in: 0...Double(max(availableThinkingLevels.count - 1, 1)),
                        step: 1,
                        onEditingChanged: { isEditing in
                            guard !isEditing,
                                  let level = pendingThinkingLevel,
                                  level != selectedThinkingLevel else { return }
                            onSelectThinkingLevel(level)
                        }
                    )
                    .tint(Color.primary.opacity(0.20))
                    .accessibilityLabel(L10n.string("chat.thinking_accessibility"))
                    .accessibilityValue(
                        pendingThinkingLevel?.composerTitle ?? selectedThinkingLevel.composerTitle
                    )
                    .accessibilityIdentifier("thinking-level-slider")
                }
                .padding(.horizontal, 8)
                .frame(height: 38)
                .background(
                    adaptiveRoundedShape(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.07))
                )

                Divider()
            }

            modelOptionToggle(
                Text(L10n.string("chat.one_million_context")),
                option: .oneMillionContext,
                state: modelOptions.oneMillionContext,
                accessibilityIdentifier: "one-million-context-toggle"
            )
        }
        .padding(16)
        .frame(width: 300)
    }

    private func modelOptionToggle(
        _ title: Text,
        option: AgentHostModelOption,
        state: AgentHostModelOptionState,
        accessibilityIdentifier: String
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { state.enabled },
                set: { onSelectModelOption(option, $0) }
            )
        ) {
            title
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(state.supported ? 0.82 : 0.34))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!state.supported)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var pendingThinkingLevel: AgentHostThinkingLevel? {
        SessionComposerState.thinkingLevel(
            forSliderValue: thinkingSliderValue,
            availableLevels: availableThinkingLevels
        )
    }

    private func accessModeMenu(_ selectedAccessMode: AgentHostAccessMode) -> some View {
        Menu {
            ForEach(AgentHostAccessMode.workChoices) { accessMode in
                Button {
                    onSelectAccessMode(accessMode)
                } label: {
                    HStack {
                        Label(accessMode.composerTitle, systemImage: accessMode.composerIcon)
                        if accessMode == selectedAccessMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedAccessMode.composerIcon)
                    .font(.system(size: 13))
                Text(selectedAccessMode.composerTitle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(isAccessMenuHovering ? 0.68 : 0.42))
            }
            .font(.system(size: 14))
            .foregroundStyle(
                selectedAccessMode == .full
                    ? Color.orange
                    : Color.primary.opacity(isAccessMenuHovering ? 0.92 : 0.82)
            )
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                adaptiveRoundedShape(cornerRadius: 9)
                    .fill(Color.primary.opacity(isAccessMenuHovering ? 0.08 : 0))
            )
            .overlay(
                adaptiveRoundedShape(cornerRadius: 9)
                    .stroke(Color.primary.opacity(isAccessMenuHovering ? 0.10 : 0), lineWidth: 1)
            )
            .contentShape(adaptiveRoundedShape(cornerRadius: 9))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(selectedAccessMode.composerDescription)
        .accessibilityLabel(L10n.format("chat.access_help", selectedAccessMode.composerTitle))
        .accessibilityIdentifier("session-access-mode")
        .onHover { isAccessMenuHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isAccessMenuHovering)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch primaryAction {
        case .none:
            EmptyView()
        case .send:
            primaryButton(
                icon: "arrow.up",
                accessibilityLabel: L10n.string("chat.send"),
                action: submitPrompt
            )
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.35)
                .accessibilityIdentifier("send-session")
        case .stop:
            primaryButton(
                icon: "stop.fill",
                accessibilityLabel: L10n.string("chat.stop"),
                action: onStop
            )
                .accessibilityIdentifier("stop-session")
        }
    }

    private var primaryAction: SessionComposerPrimaryAction {
        SessionComposerState.primaryAction(
            draft: SessionComposerState.submissionText(
                draft: draft,
                selectedCommand: selectedSlashCommand
            ),
            isExecuting: isExecuting
        )
    }

    private func primaryButton(
        icon: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: icon == "stop.fill" ? 11 : 17, weight: .medium))
                .foregroundStyle(AppPalette.raisedSurface)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.primary.opacity(0.92)))
        }
        .buttonStyle(RoundedInteractionButtonStyle(cornerRadius: 21))
        .accessibilityLabel(accessibilityLabel)
    }

    private var composerBorderColor: Color {
        Color.primary.opacity(
            SessionComposerState.borderOpacity(isHovering: isComposerHovering)
        )
    }

    private var composerBorderWidth: CGFloat {
        SessionComposerState.borderWidth
    }
}

private struct ContextUsageIndicator: View {
    let usage: AgentHostContextUsage
    @State private var isContextUsagePresented = false

    private var presentation: ContextUsagePresentation {
        ContextUsagePresentation(usage: usage)
    }

    var body: some View {
        Button {
            isContextUsagePresented.toggle()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: presentation.progress)
                    .stroke(
                        Color.primary.opacity(0.58),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 17, height: 17)
            .frame(width: 28, height: 32)
        }
        .buttonStyle(
            RoundedInteractionButtonStyle(
                cornerRadius: 9,
                isSelected: isContextUsagePresented
            )
        )
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("context-usage-indicator")
        .onHover { isContextUsagePresented = $0 }
        .popover(isPresented: $isContextUsagePresented, arrowEdge: .top) {
            VStack(spacing: 7) {
                Text(L10n.string("chat.context_window"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.48))

                Text(presentation.percentText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.68))

                Text(presentation.detailText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.88))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 220)
        }
    }
}

private struct FastModeCapsuleSwitch: View {
    let isOn: Bool
    let isAvailable: Bool

    private var trackOpacity: Double {
        guard isAvailable else { return 0.07 }
        return isOn ? 0.72 : 0.16
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.primary.opacity(trackOpacity))

            Circle()
                .fill(AppPalette.raisedSurface)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(isAvailable ? 0.10 : 0.05), lineWidth: 0.5)
                )
                .shadow(color: AppPalette.subtleShadow, radius: 1.5, y: 0.5)
                .frame(width: 14, height: 14)
                .offset(x: isOn ? 7 : -7)
        }
        .frame(width: 32, height: 18)
        .opacity(isAvailable ? 1 : 0.55)
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

private struct ModelProviderIcon: View {
    let model: PiModelOption

    var body: some View {
        Image(model.providerIconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.primary)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

private struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let leadingExclusionWidth: CGFloat
    let focusRequest: Int
    let onEditorCommand: (SessionComposerEditorCommand) -> Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView(frame: NSRect(
            x: 0,
            y: 0,
            width: 1,
            height: SessionComposerState.minimumEditorHeight
        ))
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: SessionComposerState.minimumEditorHeight)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        context.coordinator.updateExclusionPath(in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        }

        context.coordinator.updateExclusionPath(in: textView)

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        DispatchQueue.main.async {
            context.coordinator.updateLayout(in: scrollView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        var lastFocusRequest = 0

        init(parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard
                let textView = notification.object as? NSTextView,
                let scrollView = textView.enclosingScrollView
            else { return }

            parent.text = textView.string
            updateLayout(in: scrollView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                guard !textView.hasMarkedText() else { return false }
                if parent.onEditorCommand(.selectPreviousSuggestion) { return true }
                guard SessionComposerState.shouldNavigatePromptHistory(
                    .previous,
                    in: textView.string,
                    selection: textView.selectedRange(),
                    hasMarkedText: textView.hasMarkedText()
                ) else { return false }
                return parent.onEditorCommand(.recallPreviousPrompt)
            case #selector(NSResponder.moveDown(_:)):
                guard !textView.hasMarkedText() else { return false }
                if parent.onEditorCommand(.selectNextSuggestion) { return true }
                guard SessionComposerState.shouldNavigatePromptHistory(
                    .next,
                    in: textView.string,
                    selection: textView.selectedRange(),
                    hasMarkedText: textView.hasMarkedText()
                ) else { return false }
                return parent.onEditorCommand(.recallNextPrompt)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onEditorCommand(.dismissSuggestions)
            case #selector(NSResponder.deleteBackward(_:)):
                let selection = textView.selectedRange()
                guard selection.location == 0, selection.length == 0 else { return false }
                return parent.onEditorCommand(.deleteSelectedCommand)
            case #selector(NSResponder.insertNewline(_:)):
                break
            default:
                return false
            }

            let action = SessionComposerState.returnKeyAction(
                isShiftPressed: NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
                hasMarkedText: textView.hasMarkedText()
            )

            switch action {
            case .submit:
                if parent.onEditorCommand(.confirmSuggestion) { return true }
                parent.onSubmit()
                return true
            case .insertNewline:
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            case .deferToInputMethod:
                return false
            }
        }

        func updateExclusionPath(in textView: NSTextView) {
            guard
                let textContainer = textView.textContainer,
                let layoutManager = textView.layoutManager,
                let font = textView.font
            else { return }

            let rect = SessionComposerState.slashTokenExclusionRect(
                tokenWidth: parent.leadingExclusionWidth,
                lineHeight: layoutManager.defaultLineHeight(for: font)
            )
            let currentRect = textContainer.exclusionPaths.first?.bounds ?? .zero
            guard currentRect != rect else { return }
            textContainer.exclusionPaths = rect.isEmpty ? [] : [NSBezierPath(rect: rect)]
        }

        func updateLayout(in scrollView: NSScrollView) {
            guard
                let textView = scrollView.documentView as? NSTextView,
                let textContainer = textView.textContainer,
                let layoutManager = textView.layoutManager
            else { return }

            let availableWidth = max(scrollView.contentSize.width, 1)
            textContainer.containerSize = NSSize(
                width: availableWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.setFrameSize(NSSize(width: availableWidth, height: max(parent.height, 1)))
            layoutManager.ensureLayout(for: textContainer)

            let contentHeight = ceil(
                layoutManager.usedRect(for: textContainer).height
                    + textView.textContainerInset.height * 2
            )
            let targetHeight = SessionComposerState.editorHeight(for: contentHeight)
            let documentHeight = max(targetHeight, contentHeight)

            textView.setFrameSize(NSSize(width: availableWidth, height: documentHeight))
            scrollView.hasVerticalScroller = SessionComposerState.editorShouldScroll(
                contentHeight: contentHeight
            )

            if abs(parent.height - targetHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.height = targetHeight
                }
            }
        }
    }
}

private struct SessionSuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let prompt: String
    let color: Color

    static var defaults: [SessionSuggestion] {
        [
            SessionSuggestion(
                icon: "binoculars",
                title: L10n.string("chat.suggestion.explore.title"),
                prompt: L10n.string("chat.suggestion.explore.prompt"),
                color: .blue
            ),
            SessionSuggestion(
                icon: "hammer",
                title: L10n.string("chat.suggestion.build.title"),
                prompt: L10n.string("chat.suggestion.build.prompt"),
                color: .purple
            ),
            SessionSuggestion(
                icon: "arrow.triangle.2.circlepath",
                title: L10n.string("chat.suggestion.review.title"),
                prompt: L10n.string("chat.suggestion.review.prompt"),
                color: .green
            ),
            SessionSuggestion(
                icon: "ladybug",
                title: L10n.string("chat.suggestion.fix.title"),
                prompt: L10n.string("chat.suggestion.fix.prompt"),
                color: .orange
            )
        ]
    }
}

private struct SessionSuggestionCard: View {
    let suggestion: SessionSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(suggestion.color)

            Spacer(minLength: 0)

            Text(suggestion.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.88))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(16)
        .frame(height: 104)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.translucentSurface)
        .adaptiveCornerRadius(20)
        .overlay(
            adaptiveRoundedShape(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.11), lineWidth: 0.5)
        )
        .contentShape(adaptiveRoundedShape(cornerRadius: 20))
    }
}

private struct GitBranchIcon: View {
    var body: some View {
        GitBranchIconShape()
            .stroke(
                Color.primary,
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

private struct GitBranchIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 16
        let scaleY = rect.height / 16
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scaleX, y: y * scaleY)
        }

        var path = Path()
        path.addEllipse(
            in: CGRect(x: 2.5 * scaleX, y: scaleY, width: 3 * scaleX, height: 3 * scaleY)
        )
        path.addEllipse(
            in: CGRect(
                x: 10.5 * scaleX,
                y: 3.5 * scaleY,
                width: 3 * scaleX,
                height: 3 * scaleY
            )
        )
        path.addEllipse(
            in: CGRect(x: 2.5 * scaleX, y: 12 * scaleY, width: 3 * scaleX, height: 3 * scaleY)
        )
        path.move(to: point(4, 4))
        path.addLine(to: point(4, 12))
        path.move(to: point(12, 6.5))
        path.addCurve(
            to: point(5.5, 13.5),
            control1: point(12, 10.5),
            control2: point(9.5, 13.5)
        )
        return path
    }
}

private let assistantMarkdownTheme = Theme.gitHub
    .text {
        ForegroundColor(.primary)
        BackgroundColor(nil)
        FontSize(14)
    }

private struct ChatMessageRow: View {
    let message: PiChatMessage
    let onResolve: (AgentHostApprovalRequest, AgentHostApprovalDecision) -> Void

    @State private var isMessageCopied = false
    @State private var copyFeedbackResetTask: Task<Void, Never>?

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .top) {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 7) {
                    if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(message.text)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppPalette.translucentSurface)
                            .adaptiveCornerRadius(14)
                            .shadow(color: AppPalette.subtleShadow, radius: 4, y: 1)
                    }

                    ForEach(message.usedSkills) { skill in
                        SkillUsageRow(skill: skill)
                    }
                }
            }
        case .assistant:
            HStack(alignment: .top) {
                assistantTimeline
                Spacer(minLength: 60)
            }
        case .tool:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(assistantBlocks) { block in
                    assistantBlock(block)
                }
            }
        case .system:
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.5))
        }
    }

    private var assistantTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(assistantBlocks) { block in
                    assistantBlock(block)
                }
                if assistantBlocks.isEmpty, message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .onDisappear {
            copyFeedbackResetTask?.cancel()
        }
    }

    private var assistantBlocks: [AssistantTranscriptBlock] {
        AssistantTranscriptPresentation.blocks(from: message.parts)
    }

    private var assistantMetadataAnchorID: String? {
        guard message.hasCopyableText else { return nil }
        return AssistantTranscriptPresentation.metadataAnchorID(in: assistantBlocks)
    }

    private var assistantMetadata: some View {
        HStack(spacing: 8) {
            Button(action: copyMessage) {
                Image(systemName: MessageCopyFeedback.iconName(isCopied: isMessageCopied))
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary)
            .help(copyMessageLabel)
            .accessibilityLabel(copyMessageLabel)

            if let timestamp = message.timestamp {
                Text(timestamp, style: .time)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)
        }
    }

    private var copyMessageLabel: String {
        if isMessageCopied {
            return L10n.string("chat.message.copied")
        }
        return L10n.string("chat.message.copy")
    }

    private func copyMessage() {
        guard MessageClipboard.copy(message.copyableText) else { return }
        copyFeedbackResetTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            isMessageCopied = true
        }
        copyFeedbackResetTask = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: MessageCopyFeedback.resetDelayNanoseconds
                )
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.12)) {
                isMessageCopied = false
            }
        }
    }

    @ViewBuilder
    private func assistantBlock(_ block: AssistantTranscriptBlock) -> some View {
        switch block {
        case .text(let id, let text):
            VStack(alignment: .leading, spacing: 4) {
                Markdown(text)
                    .markdownTheme(assistantMarkdownTheme)
                    .textSelection(.enabled)
                if id == assistantMetadataAnchorID {
                    assistantMetadata
                }
            }
        case .thinking(let thinking):
            AssistantThinkingView(thinking: thinking)
        case .image(_, let mimeType):
            Label(L10n.format("chat.image_attachment", mimeType), systemImage: "photo")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
        case .tools(let group):
            AssistantToolGroupView(
                group: group,
                onResolve: onResolve
            )
        }
    }
}

private struct SkillUsageRow: View {
    let skill: SessionSkillRecord

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11.5, weight: .medium))

            Text(L10n.format("chat.skill.used", skill.name))
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.primary.opacity(0.5))
        .accessibilityElement(children: .combine)
    }
}

private struct AssistantThinkingView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let thinking: SessionThinkingRecord

    @State private var isExpanded: Bool
    @State private var isHeaderHovered = false

    init(thinking: SessionThinkingRecord) {
        self.thinking = thinking
        _isExpanded = State(initialValue: thinking.state == .running)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpansion) {
                HStack(spacing: 8) {
                    statusIcon

                    Text(L10n.string("chat.thinking.title"))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.62))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.36))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(
                            accessibilityReduceMotion ? nil : .easeOut(duration: 0.16),
                            value: isExpanded
                        )
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(isHeaderHovered ? 0.045 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }
            .accessibilityLabel(L10n.string("chat.thinking.title"))
            .accessibilityValue(
                thinking.state == .running
                    ? L10n.string("chat.thinking.running")
                    : ""
            )
            .accessibilityHint(
                L10n.string(
                    isExpanded
                        ? "chat.thinking.collapse"
                        : "chat.thinking.expand"
                )
            )

            if isExpanded,
               !thinking.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: thinking.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
                    .padding(.top, 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if thinking.state == .running {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.32))
                .frame(width: 16, height: 16)
        }
    }

    private func toggleExpansion() {
        isExpanded.toggle()
    }
}

private struct AssistantToolGroupView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let group: AssistantToolGroup
    let onResolve: (AgentHostApprovalRequest, AgentHostApprovalDecision) -> Void

    @State private var manualExpansion: Bool?
    @State private var isHeaderHovered = false
    @FocusState private var isHeaderFocused: Bool

    init(
        group: AssistantToolGroup,
        onResolve: @escaping (AgentHostApprovalRequest, AgentHostApprovalDecision) -> Void
    ) {
        self.group = group
        self.onResolve = onResolve
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard canToggleExpansion else { return }
                manualExpansion = !isExpanded
            } label: {
                HStack(spacing: 8) {
                    statusIcon

                    Text(statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.58))

                    if canToggleExpansion {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.36))
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .animation(
                                accessibilityReduceMotion ? nil : .easeOut(duration: 0.14),
                                value: isExpanded
                            )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            Color.primary.opacity(
                                isHeaderHovered || isHeaderFocused ? 0.045 : 0
                            )
                        )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isHeaderFocused)
            .onHover { isHeaderHovered = $0 }
            .accessibilityLabel(statusText)
            .accessibilityHint(
                canToggleExpansion
                    ? L10n.string(isExpanded ? "chat.steps.collapse" : "chat.steps.expand")
                    : ""
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group.tools) { tool in
                        AssistantToolStepRow(
                            tool: tool,
                            onResolve: onResolve
                        )
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                }
                .padding(.leading, 13)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isExpanded: Bool {
        group.status.isExpanded(manualSelection: manualExpansion)
    }

    private var canToggleExpansion: Bool {
        group.status != .approvalRequired
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch group.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
        case .approvalRequired:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.orange)
                .frame(width: 16, height: 16)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.red)
                .frame(width: 16, height: 16)
        case .completed:
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.075))
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.36))
            }
            .frame(width: 16, height: 16)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.32))
                .frame(width: 16, height: 16)
        }
    }

    private var statusText: String {
        switch group.status {
        case .running(let completed, let total):
            return L10n.format("chat.steps.running", completed, total)
        case .approvalRequired:
            return L10n.string("chat.steps.approval_required")
        case .failed(let total, let failed):
            return L10n.format("chat.steps.failed", total, failed)
        case .completed(let total):
            return L10n.format("chat.steps.completed", total)
        case .cancelled(let total):
            return L10n.format("chat.steps.cancelled", total)
        }
    }
}

private struct AssistantToolStepRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let tool: SessionToolRecord
    let onResolve: (AgentHostApprovalRequest, AgentHostApprovalDecision) -> Void

    @State private var isDetailExpanded = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                guard hasDetails else { return }
                isDetailExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    statusIcon

                    Text(presentation.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.68))

                    if !presentation.summary.isEmpty {
                        Text(presentation.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.38))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    if showsExceptionalStatus {
                        Text(statusText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(statusColor)
                    }

                    if hasDetails {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.28))
                            .rotationEffect(.degrees(showsDetails ? 90 : 0))
                            .animation(
                                accessibilityReduceMotion ? nil : .easeOut(duration: 0.14),
                                value: showsDetails
                            )
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isHovered || isFocused ? 0.04 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .onHover { isHovered = $0 }
            .accessibilityLabel("\(presentation.title), \(statusText)")
            .accessibilityHint(
                hasDetails
                    ? L10n.string(showsDetails ? "chat.steps.collapse" : "chat.steps.expand")
                    : ""
            )

            if showsDetails {
                VStack(alignment: .leading, spacing: 10) {
                    if !tool.summary.isEmpty {
                        ToolDetailBlock(
                            title: L10n.string("chat.tool.input"),
                            text: presentation.formattedInput
                        )
                    }
                    if !tool.output.isEmpty {
                        ToolDetailBlock(
                            title: L10n.string("chat.tool.output"),
                            text: tool.output
                        )
                    }
                    if let approval = tool.approval {
                        InlineApprovalActions(approval: approval) { decision in
                            onResolve(approval, decision)
                        }
                    }
                }
                .padding(.leading, 23)
                .padding(.trailing, 4)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsDetails: Bool {
        tool.state == .awaitingApproval || isDetailExpanded
    }

    private var hasDetails: Bool {
        !tool.summary.isEmpty || !tool.output.isEmpty || tool.approval != nil
    }

    private var showsExceptionalStatus: Bool {
        tool.state == .awaitingApproval || tool.isError == true
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.state {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        case .awaitingApproval:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.orange)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: tool.isError == true ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
                .frame(width: 14, height: 14)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.3))
                .frame(width: 14, height: 14)
        }
    }

    private var statusText: String {
        switch tool.state {
        case .running:
            return L10n.string("chat.tool.running")
        case .awaitingApproval:
            return L10n.string("chat.tool.awaiting_approval")
        case .completed:
            return L10n.string(tool.isError == true ? "chat.tool.failed" : "chat.tool.completed")
        case .cancelled:
            return L10n.string("chat.tool.cancelled")
        }
    }

    private var statusColor: Color {
        if tool.state == .awaitingApproval { return .orange }
        if tool.isError == true { return .red }
        return Color.primary.opacity(0.34)
    }

    private var presentation: ToolCallPresentation {
        ToolCallPresentation(tool: tool)
    }
}

private struct ToolDetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .textCase(.uppercase)

                Spacer(minLength: 8)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .accessibilityLabel(L10n.string("chat.tool.copy"))
            }

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(9)
            }
            .frame(maxHeight: 220)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045))
            .adaptiveCornerRadius(8)
        }
    }
}

private struct InlineApprovalActions: View {
    let approval: AgentHostApprovalRequest
    let onResolve: (AgentHostApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("chat.approval.title"), systemImage: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)

            HStack {
                Spacer(minLength: 0)

                Button(L10n.string("chat.approval.deny")) {
                    onResolve(.deny)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("deny-approval")

                Button(L10n.string("chat.approval.allow_once")) {
                    onResolve(.allowOnce)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("allow-approval-once")
            }
        }
    }
}

private struct ToolCallPresentation {
    let tool: SessionToolRecord

    var title: String {
        tool.name.replacingOccurrences(of: "_", with: " ")
    }

    var summary: String {
        guard let data = tool.summary.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return tool.summary
        }
        for key in ["path", "command", "query", "url", "pattern"] {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return tool.summary
    }

    var formattedInput: String {
        guard let data = tool.summary.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formatted = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: formatted, encoding: .utf8) else {
            return tool.summary
        }
        return string
    }

}
