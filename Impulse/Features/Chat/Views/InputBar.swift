import AppKit
import SwiftHarnessAgent
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
    @ObservedObject var agent: AgentManager
    var onOpenSettings: () -> Void

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
                        // Placeholder is always in the tree, hidden by opacity,
                        // so the ZStack's child list stays stable. A conditional
                        // (`if inputText.isEmpty { Text }`) would invalidate the
                        // structure on the first keystroke and force the
                        // NSTextView through a layout pass that eats the first
                        // character.
                        Text(L10n.tr("chat.send_message_placeholder"))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding(.top, 1)
                            .opacity(inputText.isEmpty && !hasMarkedText ? 1 : 0)
                            .allowsHitTesting(false)

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

                    ChatModelSwitcher(agent: agent, onOpenSettings: onOpenSettings)

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

