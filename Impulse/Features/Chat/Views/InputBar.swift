import AppKit
import SwiftUI

struct InputBar: View {
    @Binding var inputText: String
    let projects: [ChatProject]
    let selectedProjectPath: String?
    let isResponding: Bool
    var onSelectProject: (ChatProject) -> Void
    var onSend: () -> Void

    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var micPulse = false
    @State private var optionKeyMonitor: Any?

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    private var selectedProjectName: String {
        guard let selectedProjectPath,
              let selectedProject = projects.first(where: { $0.path == selectedProjectPath })
        else {
            return "Project"
        }
        return selectedProject.name
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    TextField("Send a message", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.primary)
                        .onSubmit(onSend)
                }

                HStack(spacing: 12) {
                    Button(action: {}) {
                        Circle()
                            .fill(Color.white.opacity(0.74))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundColor(.gray)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    micButton

                    Button(action: onSend) {
                        Circle()
                            .fill(canSend ? Color.black : Color.gray.opacity(0.25))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.89, green: 0.89, blue: 0.90))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
            )
            .zIndex(1)

            projectSelectorTray
                .padding(.top, -14)
        }
        .padding(.horizontal, 18)
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
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
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
            }
            .menuStyle(.borderlessButton)

            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }

            Image(systemName: "point.3.connected.trianglepath.dotted")

            Spacer()
        }
        .font(.system(size: 18, weight: .regular))
        .foregroundColor(Color.gray.opacity(0.9))
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color(red: 0.86, green: 0.86, blue: 0.87))
        )
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Circle()
            .fill(speechManager.isListening ? Color.red : Color.white.opacity(0.74))
            .frame(width: 42, height: 42)
            .overlay(
                Image(systemName: speechManager.isListening ? "waveform" : "mic")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(speechManager.isListening ? .white : .gray)
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
        guard !speechManager.isListening else { return }
        speechManager.startListening(currentText: inputText)
    }

    private func stopVoiceInput() {
        guard speechManager.isListening else { return }
        speechManager.stopListening()
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
