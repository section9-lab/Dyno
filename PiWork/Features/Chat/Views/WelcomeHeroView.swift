import SwiftUI

/// Shown when no project is selected — the hero prompt input plus suggested
/// tasks. Content is anchored toward the top of the pane (not vertically
/// centered) and constrained to a fixed-width column, matching the
/// reference design.
struct WelcomeHeroView: View {
    var onPickFolder: () -> Void

    private let columnWidth: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: 92)

            Text("让 pi 为你服务")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.85))

            HeroInputBar(onPickFolder: onPickFolder)
                .frame(maxWidth: columnWidth)
                .padding(.top, 46)

            VStack(alignment: .leading, spacing: 26) {
                Text("热门")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .padding(.bottom, 2)

                ForEach(suggestions, id: \.title) { suggestion in
                    SuggestionRow(title: suggestion.title, subtitle: suggestion.subtitle)
                }
            }
            .frame(maxWidth: columnWidth, alignment: .leading)
            .padding(.top, 52)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
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
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: 0.56, green: 0.69, blue: 0.92))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.primary.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
        // Without this the leading bar is greedy and stretches to fill all
        // the height the parent offers instead of hugging the two text lines.
        .fixedSize(horizontal: false, vertical: true)
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
        HStack(spacing: 0) {
            Button(action: onPickFolder) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)

            TextField("描述任务", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit(onPickFolder)

            Image(systemName: "mic")
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.7))
                .padding(.leading, 16)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
    }
}
