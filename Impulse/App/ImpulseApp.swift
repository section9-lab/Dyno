//
// ImpulseApp.swift
// Impulse
//
// Created by jackwang on 2026/3/27.
//

import SwiftUI
import SwiftData

struct OnboardingLoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAcceptedPrivacy = true
    @State private var isPrivacySheetPresented = false
    var isAuthenticating: Bool
    var errorMessage: String?
    var onGoogleSignIn: () -> Void
    var onAlipaySignIn: () -> Void

    var body: some View {
        ZStack {
            Image("OnboardingBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            backgroundOverlay

            VStack(spacing: 34) {
                VStack(spacing: 18) {
                    appMark

                    VStack(spacing: 10) {
                        Text("onboarding.title")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }

                VStack(spacing: 14) {
                    VStack(spacing: 10) {
                        authButton(
                            title: "onboarding.continue_google",
                            accessibilityIdentifier: "googleSignInButton",
                            isLoading: isAuthenticating,
                            action: onGoogleSignIn
                        ) {
                            googleMark
                        }

                        authButton(
                            title: "onboarding.continue_alipay",
                            accessibilityIdentifier: "alipaySignInButton",
                            action: onAlipaySignIn
                        ) {
                            alipayMark
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .frame(width: 360)
                    }

                    privacyAgreementRow
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(minWidth: 980, minHeight: 760)
        .background(LoginWindowConfigurator())
        .sheet(isPresented: $isPrivacySheetPresented) {
            PrivacyAgreementView()
        }
    }

    private var backgroundOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.24 : 0.06)

            LinearGradient(
                stops: [
                    .init(color: overlayBaseColor.opacity(0.42), location: 0),
                    .init(color: overlayBaseColor.opacity(0.34), location: 0.48),
                    .init(color: overlayBaseColor.opacity(0.16), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func authButton<Icon: View>(
        title: LocalizedStringKey,
        accessibilityIdentifier: String,
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    icon()
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(width: 312, height: 48)
            .background(.ultraThinMaterial)
            .background(buttonTint)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(buttonBorderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 12, x: 0, y: 7)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(!hasAcceptedPrivacy || isLoading)
        .opacity(hasAcceptedPrivacy ? 1 : 0.55)
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var privacyAgreementRow: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $hasAcceptedPrivacy) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text("onboarding.privacy_prefix")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Button {
                isPrivacySheetPresented = true
            } label: {
                Text("onboarding.privacy_link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .background(privacyTint)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.10), lineWidth: 1)
        )
    }

    private var appMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(markFill)
                .frame(width: 76, height: 76)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(markBorderColor, lineWidth: 1)
                )

            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.primary.opacity(0.82))
        }
    }

    private var alipayMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.0, green: 0.52, blue: 0.92))
                .frame(width: 24, height: 24)

            Text("支")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var googleMark: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)

            Text("G")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
        }
    }

    private var markFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.68)
    }

    private var markBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var buttonTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.018) : Color.white.opacity(0.035)
    }

    private var buttonBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.12)
    }

    private var privacyTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.016) : Color.white.opacity(0.03)
    }

    private var overlayBaseColor: Color {
        colorScheme == .dark
            ? Color(red: 0.095, green: 0.098, blue: 0.106)
            : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
}

private struct LoginWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
    }
}

private struct PrivacyAgreementView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("onboarding.privacy_sheet_title")
                        .font(.system(size: 20, weight: .semibold))
                    Text("onboarding.privacy_sheet_updated")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("common.close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(22)

            Divider()

            ScrollView {
                Text(privacyAgreementText)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(22)
            }
        }
        .frame(width: 620, height: 560)
    }

    private var privacyAgreementText: String {
        """
        Impulse Privacy Agreement

        This agreement explains how Impulse handles information when you use the macOS app. It is written for a local-first AI workspace that helps with coding, debugging, note-taking, document handling, screenshots, voice input, and multi-step agent workflows.

        1. Account sign-in
        Impulse uses a secure authentication service to complete Google sign-in. Google may share basic account information such as an account identifier, display name, avatar, and email address, depending on the consent screen. Alipay and other sign-in options may be added later.

        2. Local workspace data
        Impulse stores projects, sessions, chat messages, compaction summaries, tool execution records, settings, authorized folders, and agent workspace data on this Mac. App state is stored under Impulse's application support directories unless you explicitly select project folders or authorize additional directories.

        3. Project and file access
        Impulse can access the project folders and additional directories you select. Agent tools may read, write, edit, or run commands within the allowed roots needed to complete your requests. You should only authorize folders that you are comfortable using with an AI-assisted coding agent.

        4. AI provider requests
        When you send messages or ask the agent to work, relevant prompts, conversation context, tool results, OCR text, file snippets, and other selected context may be sent to the model provider configured in Settings. The provider's own terms and privacy policy apply to that processing. Avoid sending secrets or sensitive personal data unless you intend the configured provider to process it.

        5. Screen capture, OCR, microphone, and speech
        If you enable screen capture, OCR, microphone, or speech recognition, Impulse may process screenshots, recognized text, and spoken input to support the app's features. OCR captures are stored locally in the app's data directory. Speech recognition may use Apple's system services depending on macOS behavior and your system settings.

        6. Security-scoped access
        Impulse uses macOS folder authorization and security-scoped bookmarks so it can reopen folders you previously allowed. You can manage authorized folders in Settings. Removing or reauthorizing folders may limit what agent tools can access.

        7. Data sharing
        Impulse does not sell personal data. Data is shared only when needed to provide app features, such as sending selected context to your configured AI model provider, completing Google sign-in, or using operating system services you enable.

        8. Your choices
        You can sign out, change model providers, disable OCR-related behavior, remove authorized folders, delete local sessions, and clear local app data from macOS storage locations. Signing out clears the local sign-in token and cached account profile but does not delete existing project or session data.

        9. Sensitive information
        Because Impulse is designed to work with source code, terminals, files, screenshots, and AI tools, you are responsible for reviewing what you ask the app to process. Do not authorize folders or send content that you do not want the configured model provider or local agent tools to access.

        10. Changes
        This agreement may change as cloud sync, billing, team features, or other hosted services are added. Material changes should be reflected in the app before those features are used.
        """
    }
}

@main
struct ImpulseApp: App {
    var sharedModelContainer: ModelContainer = {
        // Run a rolling daily backup of the SwiftData store BEFORE the
        // container opens it. Once SwiftData has the file open the on-disk
        // bytes can be mid-transaction; copying then risks an inconsistent
        // backup. Best-effort — never blocks startup.
        StoreBackupManager.default()?.runDailyBackupIfNeeded()

        let schema = Schema([
            StoredSession.self,
            StoredMessage.self,
            StoredToolRun.self,
            StoredCompactionSummary.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @StateObject private var agent = AgentManager.shared
    @StateObject private var ocrManager = OCRManager()
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var authSession = AuthSession.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authSession.isSignedIn {
                    ContentView()
                        .background(MainWindowConfigurator())
                } else {
                    OnboardingLoginView(
                        isAuthenticating: authSession.isAuthenticating,
                        errorMessage: authSession.lastErrorMessage
                    ) {
                        Task {
                            await authSession.signInWithGoogle()
                        }
                    } onAlipaySignIn: {
                        authSession.signInWithAlipayPlaceholder()
                    }
                }
            }
                .environmentObject(authSession)
                .environmentObject(localization)
                .environmentObject(themeManager)
                .environment(\.locale, localization.locale)
                .preferredColorScheme(themeManager.theme.colorScheme)
                .onAppear {
                    configureApp()
                    syncOCRCapture()
                }
                .task {
                    await authSession.restoreSessionOnLaunch()
                    syncOCRCapture()
                }
                .onChange(of: authSession.isSignedIn) { _, _ in
                    syncOCRCapture()
                }
        }
        .defaultSize(width: 1180, height: 820)
        .modelContainer(sharedModelContainer)
    }

    private func configureApp() {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let appPath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? "unknown"
        let storageDirectory = agent.storageDirectoryURL

        print("🔧 [APP] Bundle ID: \(bundleId)")
        print("🔧 [APP] App Path: \(appPath)")
        print("🔧 [APP] Executable Path: \(executablePath)")
        print("🔧 [APP] Impulse storage directory: \(storageDirectory.path)")
    }

    private func syncOCRCapture() {
        if authSession.isSignedIn {
            ocrManager.start(storageDirectory: agent.storageDirectoryURL)
        } else {
            ocrManager.stop()
        }
    }
}
