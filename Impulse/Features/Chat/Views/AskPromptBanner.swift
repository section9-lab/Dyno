import SwiftHarnessAgent
import SwiftUI

/// Inline banner that renders above the chat scroll area when the agent
/// invokes the `ask` tool. Bound to `AskCenter`; collapses to nothing when
/// no prompt is pending. Supports single-select, multi-select, and an
/// "Other (type your own)" path that reveals a free-form text field.
struct AskPromptBanner: View {
    @ObservedObject var center: AskCenter

    @State private var draftAnswers: [String: AskDraft] = [:]

    var body: some View {
        if let prompt = center.pendingPrompt {
            VStack(alignment: .leading, spacing: 14) {
                header

                ForEach(Array(prompt.questions.enumerated()), id: \.element.id) { _, question in
                    QuestionCard(
                        question: question,
                        draft: bindingForDraft(questionID: question.id, options: question.options)
                    )
                }

                actionRow(prompt: prompt)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 56)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onChange(of: prompt.id) { _, _ in
                draftAnswers.removeAll()
            }
        } else {
            EmptyView()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.accentColor)
            Text("ask.banner.title")
                .chatFont(.body, weight: .semibold)
            Spacer()
        }
    }

    private func actionRow(prompt: AskPrompt) -> some View {
        HStack(spacing: 10) {
            if !canSubmit(prompt: prompt) {
                Text("ask.banner.required_hint")
                    .chatFont(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                center.cancel()
                draftAnswers.removeAll()
            } label: {
                Text("ask.banner.cancel")
                    .chatFont(.body)
            }
            .buttonStyle(.bordered)

            Button {
                submit(prompt: prompt)
            } label: {
                Text("ask.banner.submit")
                    .chatFont(.body, weight: .semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit(prompt: prompt))
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private func bindingForDraft(questionID: String, options: [String]) -> Binding<AskDraft> {
        Binding(
            get: {
                draftAnswers[questionID] ?? AskDraft()
            },
            set: { newValue in
                draftAnswers[questionID] = newValue
            }
        )
    }

    private func canSubmit(prompt: AskPrompt) -> Bool {
        prompt.questions.allSatisfy { question in
            let draft = draftAnswers[question.id] ?? AskDraft()
            if draft.isOtherSelected {
                return !draft.customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !draft.selectedOptions.isEmpty
        }
    }

    private func submit(prompt: AskPrompt) {
        let answers: [AskAnswer] = prompt.questions.map { question in
            let draft = draftAnswers[question.id] ?? AskDraft()
            if draft.isOtherSelected {
                let trimmed = draft.customText.trimmingCharacters(in: .whitespacesAndNewlines)
                return AskAnswer(id: question.id, selections: [], customInput: trimmed)
            }
            // Preserve option order from the question for stable strings.
            let ordered = question.options.filter { draft.selectedOptions.contains($0) }
            return AskAnswer(id: question.id, selections: ordered)
        }
        center.submit(answers)
        draftAnswers.removeAll()
    }
}

/// Per-question scratch state. Tracks selected option labels and the
/// optional "Other" free-text path. Multi-select questions accumulate in
/// `selectedOptions`; single-select keeps it to one element.
struct AskDraft: Equatable {
    var selectedOptions: Set<String> = []
    var isOtherSelected: Bool = false
    var customText: String = ""
}

private struct QuestionCard: View {
    let question: AskQuestion
    @Binding var draft: AskDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.question)
                .chatFont(.body, weight: .semibold)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    OptionRow(
                        label: option,
                        recommended: question.recommended == index,
                        multi: question.multi,
                        isSelected: draft.selectedOptions.contains(option),
                        onTap: {
                            toggle(option: option)
                        }
                    )
                }

                OptionRow(
                    label: NSLocalizedString("ask.banner.other", comment: ""),
                    recommended: false,
                    multi: false,
                    isSelected: draft.isOtherSelected,
                    onTap: {
                        toggleOther()
                    }
                )

                if draft.isOtherSelected {
                    TextField(
                        NSLocalizedString("ask.banner.other_placeholder", comment: ""),
                        text: $draft.customText,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .padding(.leading, 24)
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func toggle(option: String) {
        // Tapping a regular option clears the "Other" branch.
        draft.isOtherSelected = false
        draft.customText = ""
        if question.multi {
            if draft.selectedOptions.contains(option) {
                draft.selectedOptions.remove(option)
            } else {
                draft.selectedOptions.insert(option)
            }
        } else {
            draft.selectedOptions = [option]
        }
    }

    private func toggleOther() {
        // "Other" is mutually exclusive with the option list, regardless of
        // multi flag — picking a custom answer means the model gets only the
        // free-text response.
        if draft.isOtherSelected {
            draft.isOtherSelected = false
            draft.customText = ""
        } else {
            draft.isOtherSelected = true
            draft.selectedOptions = []
        }
    }
}

private struct OptionRow: View {
    let label: String
    let recommended: Bool
    let multi: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.7))
                    .frame(width: 16)
                Text(label)
                    .chatFont(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if recommended {
                    Text("ask.banner.recommended")
                        .chatFont(.caption, weight: .medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.18))
                        )
                        .foregroundColor(.accentColor)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        if multi {
            return isSelected ? "checkmark.square.fill" : "square"
        } else {
            return isSelected ? "largecircle.fill.circle" : "circle"
        }
    }
}
