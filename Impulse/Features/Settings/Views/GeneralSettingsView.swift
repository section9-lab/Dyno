import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    
    var body: some View {
        SettingsCard(title: "通用设置") {
            VStack(alignment: .leading, spacing: 18) {
                languageSection
                themeSection
                ocrSection
                voiceSection
            }
        }
    }
    
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语言")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Picker("", selection: $viewModel.language) {
                Text("简体中文").tag("zh")
                Text("English").tag("en")
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("主题")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Picker("", selection: $viewModel.theme) {
                Text("自动").tag("auto")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var ocrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("屏幕捕获")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Toggle(isOn: $viewModel.ocrEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动 OCR 截屏")
                    Text("在系统空闲时自动捕获屏幕并进行 OCR 识别")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
    
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语音输入快捷键")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Picker("", selection: $viewModel.voiceShortcut) {
                Text("Option (⌥)").tag("Option")
                Text("Command (⌘)").tag("Command")
                Text("Control (⌃)").tag("Control")
                Text("Fn").tag("Fn")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("按住快捷键说话，松开发送")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    GeneralSettingsView(viewModel: GeneralSettingsViewModel())
        .frame(width: 600)
}
