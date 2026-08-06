//
// PiWorkApp.swift
// pi-work
//
// Created by jackwang on 2026/3/27.
//

import SwiftUI
import AppKit
import PiWorkCore
import SwiftData
import Combine
struct OnboardingLoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var authSession: AuthSession

    @State private var hasAcceptedPrivacy = true
    @State private var isPrivacySheetPresented = false
    /// Tracks which sign-in button the user actually pressed so we can show
    /// the spinner on the right row. `isAuthenticating` alone can't tell us
    /// which provider is in flight.
    @State private var pendingProvider: PendingProvider?
    @State private var step: Step = .picker
    @State private var emailDraft: String = ""
    @State private var codeDraft: String = ""
    @State private var resendCooldown: Int = 0
    @State private var resendTimerTask: Task<Void, Never>?

    private static let resendCooldownSeconds = 120

    private enum PendingProvider {
        case google
        case email
    }

    private enum Step: Equatable {
        case picker
        case emailInput
        case emailCode
    }

    var body: some View {
        ZStack {
            Image("OnboardingBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            backgroundOverlay

            VStack(spacing: 34) {
                VStack(spacing: 10) {
                    Text(stepTitleKey)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.primary)
                }

                VStack(spacing: 14) {
                    Group {
                        switch step {
                        case .picker:
                            pickerStep
                                .transition(stepTransition(forward: false))
                        case .emailInput:
                            emailInputStep
                                .transition(stepTransition(forward: true))
                        case .emailCode:
                            emailCodeStep
                                .transition(stepTransition(forward: true))
                        }
                    }

                    if let errorMessage = authSession.lastErrorMessage {
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
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(LoginWindowConfigurator())
        .onChange(of: authSession.isAuthenticating) { newValue in
            if !newValue { pendingProvider = nil }
        }
        .onDisappear {
            resendTimerTask?.cancel()
        }
        .sheet(isPresented: $isPrivacySheetPresented) {
            PrivacyAgreementView()
        }
    }

    private var stepTitleKey: LocalizedStringKey {
        switch step {
        case .picker:        return "onboarding.title"
        case .emailInput:    return "email.title"
        case .emailCode:     return "email.code_title"
        }
    }

    @ViewBuilder
    private var pickerStep: some View {
        VStack(spacing: 10) {
            authButton(
                title: "onboarding.continue_google",
                accessibilityIdentifier: "googleSignInButton",
                isLoading: authSession.isAuthenticating && pendingProvider == .google,
                action: {
                    pendingProvider = .google
                    Task { await authSession.signInWithGoogle() }
                }
            ) {
                googleMark
            }

            authButton(
                title: "onboarding.continue_email",
                accessibilityIdentifier: "emailSignInButton",
                isLoading: false,
                action: {
                    authSession.clearLastError()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        step = .emailInput
                    }
                }
            ) {
                emailMark
            }
        }
    }

    @ViewBuilder
    private var emailInputStep: some View {
        VStack(spacing: 14) {
            stepHeader(backAction: {
                authSession.clearLastError()
                withAnimation(.easeInOut(duration: 0.22)) { step = .picker }
            })

            EmailInputField(text: $emailDraft, onSubmit: requestEmailCode)
                .frame(width: 312)

            primaryButton(
                title: "email.send_code",
                isLoading: authSession.isAuthenticating && pendingProvider == .email,
                isEnabled: !emailDraft.trimmingCharacters(in: .whitespaces).isEmpty,
                action: requestEmailCode
            )
        }
    }

    @ViewBuilder
    private var emailCodeStep: some View {
        VStack(spacing: 14) {
            stepHeader(backAction: {
                authSession.cancelEmailLogin()
                authSession.clearLastError()
                resendTimerTask?.cancel()
                resendCooldown = 0
                codeDraft = ""
                withAnimation(.easeInOut(duration: 0.22)) { step = .emailInput }
            })

            if let pendingEmail = authSession.pendingEmail {
                Text(L10n.tr("email.code_sent_to", pendingEmail))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 360)
            }

            OTPInputView(code: $codeDraft, length: 6) { _ in
                verifyEmailCode()
            }

            primaryButton(
                title: "email.verify",
                isLoading: authSession.isAuthenticating && pendingProvider == .email,
                isEnabled: codeDraft.count == 6,
                action: verifyEmailCode
            )

            resendRow
        }
    }

    @ViewBuilder
    private var resendRow: some View {
        HStack(spacing: 6) {
            if resendCooldown > 0 {
                Text(L10n.tr("email.resend_in", resendCooldown))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Button {
                    resendEmailCode()
                } label: {
                    Text("email.resend")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(authSession.isAuthenticating)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func stepHeader(backAction: @escaping () -> Void) -> some View {
        HStack {
            Button {
                backAction()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(width: 312)
    }

    @ViewBuilder
    private func primaryButton(
        title: LocalizedStringKey,
        isLoading: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 312, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color.gray.opacity(0.45))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading || !hasAcceptedPrivacy)
        .opacity(hasAcceptedPrivacy ? 1 : 0.55)
    }

    private func stepTransition(forward: Bool) -> AnyTransition {
        let edge: Edge = forward ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func requestEmailCode() {
        let trimmed = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingProvider = .email
        Task {
            do {
                try await authSession.requestEmailCode(trimmed)
                codeDraft = ""
                startResendCooldown()
                withAnimation(.easeInOut(duration: 0.22)) {
                    step = .emailCode
                }
            } catch {
                // Error message already surfaced via authSession.lastErrorMessage
            }
        }
    }

    private func resendEmailCode() {
        Task {
            do {
                try await authSession.resendEmailCode()
                codeDraft = ""
                startResendCooldown()
            } catch {
                // Error surfaced via lastErrorMessage
            }
        }
    }

    private func verifyEmailCode() {
        guard codeDraft.count == 6 else { return }
        pendingProvider = .email
        Task {
            do {
                try await authSession.verifyEmailCode(codeDraft)
                // Successful login flips authSession.isSignedIn → window swap
            } catch {
                codeDraft = ""
            }
        }
    }

    private func startResendCooldown() {
        resendTimerTask?.cancel()
        resendCooldown = Self.resendCooldownSeconds
        resendTimerTask = Task {
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    if resendCooldown > 0 { resendCooldown -= 1 }
                }
            }
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
            // Override the system accent so the checkbox tick reads as a
            // neutral confirmation, not a primary call-to-action — the real
            // CTAs are the two sign-in buttons above.
            .tint(.secondary)

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

    private var emailMark: some View {
        // Neutral envelope glyph in a soft chip — visually parallel to the
        // Google G mark above so the row alignment stays even.
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                .frame(width: 22, height: 22)

            Image(systemName: "envelope.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.78))
        }
    }

    private var googleMark: some View {
        // Google's G mark: white disc with a multi-color G glyph. Reference:
        // developers.google.com/identity/branding-guidelines. We don't ship
        // the official asset so this is an approximation — white disc plus
        // a "G" letter rendered with the four brand colors via an angular
        // gradient. If/when an official PNG is bundled, swap to Image("google_g").
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)

            Text("G")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96), // blue
                            Color(red: 0.20, green: 0.66, blue: 0.33), // green
                            Color(red: 0.99, green: 0.74, blue: 0.02), // yellow
                            Color(red: 0.96, green: 0.26, blue: 0.21), // red
                            Color(red: 0.26, green: 0.52, blue: 0.96)
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    )
                )
        }
        .frame(width: 22, height: 22)
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

    @MainActor
    private func configure(window: NSWindow?) {
        guard let window else { return }
        applyNativeWindowChrome(to: window)
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

    @MainActor
    private func configure(window: NSWindow?) {
        guard let window else { return }
        applyNativeWindowChrome(to: window)
    }
}

@MainActor
private func applyNativeWindowChrome(to window: NSWindow) {
    window.styleMask.remove(.borderless)
    window.styleMask.insert(.titled)
    window.styleMask.insert(.closable)
    window.styleMask.insert(.miniaturizable)
    window.styleMask.insert(.resizable)
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.titlebarSeparatorStyle = .none
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
        pi-work Privacy Agreement

        This agreement explains how pi-work handles information when you use the macOS app. It is written for a local-first project workspace focused on project boards, settings, and account access.

        1. Account sign-in
        pi-work uses a secure authentication service to complete sign-in. Google may share basic account information such as an account identifier, display name, avatar, and email address, depending on the consent screen. If you sign in with email, pi-work only stores the email address you provide and a verification code that expires within minutes.

        2. Local workspace data
        pi-work stores projects, kanban tasks, settings, and sign-in state on this Mac. App state is stored under pi-work's application support directories.

        3. Project folders
        pi-work can access the project folders you select so it can organize your boards around them. You control which folders are added to the app.

        4. Authentication requests
        When you sign in, relevant authentication details are exchanged with the configured authentication service. The provider's own terms and privacy policy apply to that processing.

        5. Local backups
        pi-work maintains local backups of its data store so you can restore project and task data if something goes wrong. Backups stay on this Mac unless you move them yourself.

        6. Data sharing
        pi-work does not sell personal data. Data is shared only when needed to provide app features, such as completing sign-in or using operating system services you enable.

        7. Your choices
        You can sign out, remove projects, delete tasks, and restore local backups. Signing out clears the local sign-in token and cached account profile but does not delete existing project or task data.

        8. Sensitive information
        Because pi-work is designed to work with local project folders, you are responsible for reviewing what you choose to store in the app and which folders you add.

        9. Changes
        This agreement may change as hosted services, sync features, or other integrations are added. Material changes should be reflected in the app before those features are used.

        
        """
    }
}


@main
struct PiWorkApp: App {
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var authSession = AuthSession.shared

    var body: some Scene {
        WindowGroup {
            rootView
            .environmentObject(authSession)
            .environmentObject(localization)
            .environmentObject(themeManager)
            .environment(\.locale, localization.locale)
            .preferredColorScheme(themeManager.theme.colorScheme)
            .onAppear {
                configureApp()
            }
            .task {
                await authSession.restoreSessionOnLaunch()
            }
        }
        .defaultSize(width: 1180, height: 820)
    }

    private func configureApp() {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let appPath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? "unknown"

        print("🔧 [APP] Bundle ID: \(bundleId)")
        print("🔧 [APP] App Path: \(appPath)")
        print("🔧 [APP] Executable Path: \(executablePath)")
    }

    @ViewBuilder
    private var rootView: some View {
        if #available(macOS 14.0, *) {
            PiWorkSupportedRootView()
        } else {
            UnsupportedSystemView()
        }
    }
}

@available(macOS 14.0, *)
private enum PiWorkModelContainerProvider {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StoredProject.self,
            StoredKanbanTask.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

@available(macOS 14.0, *)
private struct PiWorkSupportedRootView: View {
    @EnvironmentObject private var authSession: AuthSession

    var body: some View {
        Group {
            if authSession.isSignedIn {
                ContentView()
                    .background(MainWindowConfigurator())
            } else {
                OnboardingLoginView(authSession: authSession)
            }
        }
        .modelContainer(PiWorkModelContainerProvider.sharedModelContainer)
    }
}

private struct UnsupportedSystemView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            Text("pi-work requires macOS 14 or later")
                .font(.system(size: 24, weight: .semibold))
            Text("This build now has a macOS 13 deployment target so it can launch and run tests on older systems, but the SwiftData-backed board UI still requires macOS 14 at runtime.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainWindowConfigurator())
    }
}
