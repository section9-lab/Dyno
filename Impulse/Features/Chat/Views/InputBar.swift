import AppKit
import SwiftCodingAgent
import SwiftUI

struct InputBar: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var inputText: String
    let projects: [StoredProject]
    let selectedProjectPath: String?
    let isResponding: Bool
    var onSelectProject: (StoredProject) -> Void
    var onSend: () -> Void
    /// nil when no session is selected. Tracks context usage / compact action
    /// for the focused session only.
    var sessionAgent: SessionAgent?

    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var micPulse = false
    @State private var inputHeight: CGFloat = 38
    @State private var isAttachmentButtonHovered = false
    @State private var optionKeyMonitor: Any?
    @State private var hasMarkedText: Bool = false
    @State private var showContextPopover: Bool = false
    @State private var isCompacting: Bool = false

    private let minimumInputHeight: CGFloat = 38
    private let maximumInputHeight: CGFloat = 114
    private let controlButtonSize: CGFloat = 28
    private let inputCornerRadius: CGFloat = 26
    private let trayCornerRadius: CGFloat = 26

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    private var selectedProjectName: String {
        guard let selectedProjectPath,
            let selectedProject = projects.first(where: { $0.path == selectedProjectPath })
        else {
            return L10n.tr("chat.project")
        }
        return selectedProject.displayName
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty && !hasMarkedText {
                            Text(L10n.tr("chat.send_message_placeholder"))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                                .padding(.top, 1)
                                .allowsHitTesting(false)
                        }

                        MultilineMessageInput(
                            text: $inputText,
                            height: $inputHeight,
                            minimumHeight: minimumInputHeight,
                            maximumHeight: maximumInputHeight,
                            canSubmit: canSend,
                            onSubmit: onSend,
                            hasMarkedText: $hasMarkedText
                        )
                    }
                    .frame(height: inputHeight, alignment: .topLeading)
                }

                HStack(spacing: 8) {
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(controlIconColor)
                            .frame(width: controlButtonSize, height: controlButtonSize)
                    }
                    .buttonStyle(
                        HoverCircleButtonStyle(
                            isHovered: isAttachmentButtonHovered,
                            hoverBackground: controlButtonBackground,
                            pressedBackground: pressedControlButtonBackground
                        )
                    )
                    .onHover { hovering in
                        isAttachmentButtonHovered = hovering
                    }

                    Spacer()

                    micButton

                    Button(action: onSend) {
                        Circle()
                            .fill(sendButtonBackground)
                            .frame(width: controlButtonSize, height: controlButtonSize)
                            .overlay(
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(sendIconColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: inputCornerRadius,
                    bottomLeadingRadius: inputCornerRadius,
                    bottomTrailingRadius: inputCornerRadius,
                    topTrailingRadius: inputCornerRadius,
                    style: .continuous
                )
                    .fill(inputBackgroundColor)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: inputCornerRadius,
                    bottomLeadingRadius: inputCornerRadius,
                    bottomTrailingRadius: inputCornerRadius,
                    topTrailingRadius: inputCornerRadius,
                    style: .continuous
                )
                    .stroke(inputBorderColor, lineWidth: 0.5)
            )
            .zIndex(1)

            projectSelectorTray
                .padding(.top, -28)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 56)
        .padding(.bottom, 12)
        .onChange(of: speechManager.transcript) { _, _ in
            inputText = speechManager.composedText
        }
        .onAppear {
            installOptionKeyMonitor()
        }
        .onDisappear {
            removeOptionKeyMonitor()
        }
    }

    private var projectSelectorTray: some View {
        HStack(spacing: 20) {
            Menu {
                ForEach(projects) { project in
                    Button {
                        onSelectProject(project)
                    } label: {
                        if project.path == selectedProjectPath {
                            Label(project.displayName, systemImage: "checkmark")
                        } else {
                            Text(project.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(selectedProjectName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: 220, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Spacer()

            contextUsageIndicator
        }
        .foregroundColor(trayForegroundColor)
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 6)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: trayCornerRadius,
                bottomTrailingRadius: trayCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(trayBackgroundColor)
        )
    }

    // MARK: - Context Usage Indicator

    @ViewBuilder
    private var contextUsageIndicator: some View {
        if let sessionAgent {
            ContextUsageIndicator(
                sessionAgent: sessionAgent,
                showContextPopover: $showContextPopover,
                isCompacting: $isCompacting
            )
        }
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Circle()
            .fill(speechManager.isListening ? Color.red : controlButtonBackground)
            .frame(width: controlButtonSize, height: controlButtonSize)
            .overlay(
                Image(systemName: speechManager.isListening ? "waveform" : "mic")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(speechManager.isListening ? .white : controlIconColor)
                    .symbolEffect(.variableColor.iterative, isActive: speechManager.isListening)
            )
            .scaleEffect(micPulse ? 1.08 : 1.0)
            .animation(
                speechManager.isListening
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: micPulse
            )
            .onChange(of: speechManager.isListening) { _, listening in
                micPulse = listening
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        startVoiceInput()
                    }
                    .onEnded { _ in
                        stopVoiceInput()
                    }
            )
    }

    // MARK: - Voice Input

    private func startVoiceInput() {
        speechManager.startListening(currentText: inputText)
    }

    private func stopVoiceInput() {
        speechManager.stopListening()
    }

    private var inputBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.153, blue: 0.165)
            : Color(red: 0.89, green: 0.89, blue: 0.90)
    }

    private var trayBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.125, green: 0.132, blue: 0.143)
            : Color(red: 0.86, green: 0.86, blue: 0.87)
    }

    private var controlButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.74)
    }

    private var pressedControlButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.92)
    }

    private var controlIconColor: Color {
        colorScheme == .dark ? Color(red: 0.66, green: 0.68, blue: 0.70) : .gray
    }

    private var sendButtonBackground: Color {
        if canSend {
            return colorScheme == .dark ? Color(red: 0.55, green: 0.66, blue: 0.70) : .black
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.25)
    }

    private var sendIconColor: Color {
        canSend || colorScheme == .light ? .white : Color.white.opacity(0.42)
    }

    private var inputBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)
    }

    private var trayForegroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.56) : Color.gray.opacity(0.9)
    }

    // MARK: - Option Key Monitor

    private func installOptionKeyMonitor() {
        guard optionKeyMonitor == nil else { return }
        optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let optionPressed = event.modifierFlags.contains(.option)
            Task { @MainActor in
                if optionPressed {
                    startVoiceInput()
                } else {
                    stopVoiceInput()
                }
            }
            return event
        }
    }

    private func removeOptionKeyMonitor() {
        if let monitor = optionKeyMonitor {
            NSEvent.removeMonitor(monitor)
            optionKeyMonitor = nil
        }
    }
}

private struct ContextUsageIndicator: View {
    @ObservedObject var sessionAgent: SessionAgent
    @Binding var showContextPopover: Bool
    @Binding var isCompacting: Bool

    var body: some View {
        Button {
            showContextPopover.toggle()
        } label: {
            ContextUsageRing(
                percent: sessionAgent.contextUsage.percent,
                color: contextUsageColor
            )
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showContextPopover, arrowEdge: .top) {
            ContextUsagePopover(
                usage: sessionAgent.contextUsage,
                isCompacting: isCompacting,
                onCompact: triggerCompaction
            )
        }
        .help(contextHelpText)
    }

    private var contextUsageColor: Color {
        let pct = sessionAgent.contextUsage.percent
        if pct >= 0.9 { return .red }
        if pct >= 0.75 { return .orange }
        return .secondary
    }

    private var contextHelpText: String {
        let usage = sessionAgent.contextUsage
        let pctText = String(format: "%.0f%%", usage.percent * 100)
        return "Context: \(pctText) (\(formatTokens(usage.usedTokens)) / \(formatTokens(usage.totalTokens)))"
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000 {
            let k = Double(value) / 1_000.0
            return String(format: "%.1fk", k)
        }
        return "\(value)"
    }

    private func triggerCompaction() {
        guard !isCompacting else { return }
        isCompacting = true
        Task {
            defer { isCompacting = false }
            do {
                _ = try await sessionAgent.compact()
                showContextPopover = false
            } catch {
                // Surface failure passively — the popover stays open so the
                // user can see the unchanged usage.
            }
        }
    }
}

private struct HoverCircleButtonStyle: ButtonStyle {
    let isHovered: Bool
    let hoverBackground: Color
    let pressedBackground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(
                        configuration.isPressed
                            ? pressedBackground : (isHovered ? hoverBackground : Color.clear))
            )
            .contentShape(Circle())
    }
}

private struct MultilineMessageInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat

    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let canSubmit: Bool
    let onSubmit: () -> Void
    @Binding var hasMarkedText: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = MessageTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = {
            if canSubmit {
                onSubmit()
            }
        }
        textView.onMarkedTextChange = { marked in
            DispatchQueue.main.async {
                if hasMarkedText != marked {
                    hasMarkedText = marked
                }
            }
        }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MessageTextView else { return }

        context.coordinator.parent = self
        textView.onSubmit = {
            if canSubmit {
                onSubmit()
            }
        }
        textView.onMarkedTextChange = { marked in
            DispatchQueue.main.async {
                if hasMarkedText != marked {
                    hasMarkedText = marked
                }
            }
        }

        if textView.string != text {
            textView.string = text
        }

        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineMessageInput
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(parent: MultilineMessageInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func updateHeight() {
            guard let textView, let scrollView else { return }

            let fittingWidth = max(scrollView.contentSize.width, 1)
            textView.textContainer?.containerSize = NSSize(
                width: fittingWidth,
                height: .greatestFiniteMagnitude
            )
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
            let measuredHeight = ceil(usedRect.height + textView.textContainerInset.height * 2)
            let nextHeight = min(max(measuredHeight, parent.minimumHeight), parent.maximumHeight)

            scrollView.hasVerticalScroller = measuredHeight > parent.maximumHeight
            textView.frame.size = NSSize(
                width: fittingWidth, height: max(measuredHeight, nextHeight))

            if abs(parent.height - nextHeight) > 0.5 {
                parent.height = nextHeight
            }
        }
    }
}

private final class MessageTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onMarkedTextChange: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            // Don't intercept Enter while an IME composition is active —
            // the input method needs it to commit/select candidates.
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            if event.modifierFlags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(self)
            } else {
                onSubmit?()
            }
            return
        }

        super.keyDown(with: event)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onMarkedTextChange?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChange?(false)
    }
}

// MARK: - Context Usage UI

private struct ContextUsageRing: View {
    let percent: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 2)

            Circle()
                .trim(from: 0, to: max(0.001, min(1.0, percent)))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: percent)
        }
    }
}

private struct ContextUsagePopover: View {
    let usage: ContextUsage
    let isCompacting: Bool
    let onCompact: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ContextUsageRing(percent: usage.percent, color: ringColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(percentLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(L10n.tr("context.window_label"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: L10n.tr("context.used"), value: formatTokens(usage.usedTokens))
                statRow(label: L10n.tr("context.total"), value: formatTokens(usage.totalTokens))
                statRow(label: L10n.tr("context.reserved"), value: formatTokens(usage.reservedTokens))
            }

            Button {
                onCompact()
            } label: {
                HStack(spacing: 6) {
                    if isCompacting {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    }
                    Text(isCompacting ? L10n.tr("context.compacting") : L10n.tr("context.compact"))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(isCompacting ? 0.15 : 0.22))
                )
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isCompacting)
        }
        .padding(14)
        .frame(width: 240)
    }

    private var percentLabel: String {
        String(format: "%.0f%% used", usage.percent * 100)
    }

    private var ringColor: Color {
        if usage.percent >= 0.9 { return .red }
        if usage.percent >= 0.75 { return .orange }
        return .accentColor
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        return "\(value)"
    }
}
