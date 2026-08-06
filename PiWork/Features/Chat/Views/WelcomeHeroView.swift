import SwiftUI

/// Shown when no project is selected — a centered hero prompt input plus
/// suggested tasks, matching the reference design's welcome screen.
struct WelcomeHeroView: View {
    var onPickFolder: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("让 pi 为你服务")
                .font(.system(size: 34, weight: .medium))

            HeroInputBar(onPickFolder: onPickFolder)
                .frame(maxWidth: 640)

            VStack(alignment: .leading, spacing: 16) {
                Text("热门")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(suggestions, id: \.title) { suggestion in
                    SuggestionRow(title: suggestion.title, subtitle: suggestion.subtitle)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(.windowBackgroundColor), Color.blue.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var suggestions: [(title: String, subtitle: String)] {
        [
            ("整理项目文件", "选择一个文件夹，让 pi 分析结构并整理杂乱的文件"),
            ("跟进未完成的改动", "查看最近的 git 改动，起草提交说明或继续未完成的工作"),
            ("代码审查", "选择一个文件夹，请 pi 审查最近的改动并给出建议")
        ]
    }
}

private struct SuggestionRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The pill-shaped task input used on the welcome screen. Because there's
/// no project selected yet, submitting here first prompts the user to pick
/// a folder (a session always needs a working directory for the agent
/// subprocess).
private struct HeroInputBar: View {
    var onPickFolder: () -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPickFolder) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)

            TextField("描述任务", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onPickFolder)

            Image(systemName: "mic")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.textBackgroundColor))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}
