import AppKit
import SwiftUI

struct ModelOption: Identifiable {
    let id: String
    let displayName: String
    let isInstalled: Bool
}

struct InputBar: View {
    @Binding var inputText: String
    let modelName: String
    let modelOptions: [ModelOption]
    let isResponding: Bool
    var onSelectModel: (String) -> Void
    var onSend: () -> Void

    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var isModelPickerVisible = false
    @State private var modelQuery = ""
    @State private var micPulse = false
    @State private var optionKeyMonitor: Any?

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    private var filteredModelOptions: [ModelOption] {
        let query = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return modelOptions }
        return modelOptions.filter {
            $0.displayName.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
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

                    modelPickerButton

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

    // MARK: - Model Picker

    private var modelPickerButton: some View {
        Button {
            isModelPickerVisible.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(modelName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(Color.white.opacity(0.74))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isModelPickerVisible,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            modelPickerPanel
                .onAppear { modelQuery = "" }
        }
    }

    private var modelPickerPanel: some View {
        VStack(spacing: 0) {
            TextField("Find model...", text: $modelQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.98))

            Divider().opacity(0.5)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredModelOptions.enumerated()), id: \.offset) { _, option in
                        Button {
                            onSelectModel(option.id)
                            withAnimation(.easeOut(duration: 0.12)) {
                                isModelPickerVisible = false
                            }
                        } label: {
                            HStack {
                                Text(option.displayName)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(
                                option.id == modelName ? Color.black.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 200)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
    }
}
