import Foundation
import SwiftUI

@main
struct PiWorkApp: App {
    @StateObject private var authSession = AuthSession.shared
    @StateObject private var agentRuntime = AppAgentRuntime()
    @StateObject private var updateController = AppUpdateController()
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var languageStore = LanguageStore.shared

    var body: some Scene {
        WindowGroup {
            RootView(
                authSession: authSession,
                agentRuntime: agentRuntime,
                languageStore: languageStore
            )
                .environment(\.locale, languageStore.language.locale)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 680)
        .commands {
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                Button(L10n.string("update.check")) {
                    Task { await updateController.checkForUpdatesAndPresent() }
                }
                .disabled(updateController.isChecking)
            }
        }

        Settings {
            if let agentSettingsStore = agentRuntime.agentSettingsStore,
               let providerAuthStore = agentRuntime.providerAuthStore {
                AppSettingsView(
                    agentSettingsStore: agentSettingsStore,
                    providerAuthStore: providerAuthStore,
                    languageStore: languageStore,
                    updateController: updateController
                )
                    .preferredColorScheme(themeStore.theme.colorScheme)
                    .environment(\.locale, languageStore.language.locale)
            } else {
                AgentRuntimeUnavailableView(
                    message: agentRuntime.errorMessage ?? L10n.string("agent.host_unavailable")
                )
                .frame(width: 620, height: 440)
                .environment(\.locale, languageStore.language.locale)
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Gates the app on a valid session: onboarding until signed in, the project
/// shell afterwards. `restoreSessionOnLaunch` runs once on cold start and
/// silently refreshes an expired access token when it can.
private struct RootView: View {
    @ObservedObject var authSession: AuthSession
    @ObservedObject var agentRuntime: AppAgentRuntime
    @ObservedObject var languageStore: LanguageStore
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var didRestore = false

    var body: some View {
        Group {
            if authSession.isSignedIn {
                if let sessionStore = agentRuntime.sessionStore,
                   let installedExtensionsStore = agentRuntime.installedExtensionsStore,
                   let scheduleRunner = agentRuntime.scheduleRunner {
                    ContentView(
                        sessionStore: sessionStore,
                        installedExtensionsStore: installedExtensionsStore,
                        scheduleStore: agentRuntime.scheduleStore,
                        scheduleRunner: scheduleRunner
                    )
                } else {
                    AgentRuntimeUnavailableView(
                        message: agentRuntime.errorMessage ?? L10n.string("agent.host_unavailable")
                    )
                }
            } else {
                OnboardingLoginView(authSession: authSession)
            }
        }
        // Applied at the root so onboarding follows the choice too. `nil`
        // means "follow the system", which is the default.
        .preferredColorScheme(themeStore.theme.colorScheme)
        .task {
#if DEBUG
            let environment = ProcessInfo.processInfo.environment
            guard environment["XCTestConfigurationFilePath"] == nil,
                  !CommandLine.arguments.contains("--pi-work-skip-auth-restore") else {
                return
            }
#endif
            guard !didRestore else { return }
            didRestore = true
            await authSession.restoreSessionOnLaunch()
        }
        .task(id: authSession.isSignedIn) {
            if authSession.isSignedIn {
                agentRuntime.scheduleRunner?.start()
            } else {
                agentRuntime.scheduleRunner?.stop()
            }
        }
    }
}

@MainActor
final class AppAgentRuntime: ObservableObject {
    let service: AgentHostService?
    let sessionStore: SessionStore?
    let agentSettingsStore: AgentSettingsStore?
    let providerAuthStore: ProviderAuthStore?
    let installedExtensionsStore: InstalledExtensionsStore?
    let scheduleStore: ScheduleStore
    let scheduleRunner: ScheduleRunner?
    let errorMessage: String?

    init() {
        let scheduleStore = ScheduleStore()
        self.scheduleStore = scheduleStore
        do {
            let service = try AgentHostService.bundled()
            let sessionStore = SessionStore(service: service)
            self.service = service
            self.sessionStore = sessionStore
            agentSettingsStore = AgentSettingsStore(service: service)
            providerAuthStore = ProviderAuthStore(service: service)
            installedExtensionsStore = InstalledExtensionsStore(service: service)
            scheduleRunner = ScheduleRunner(
                store: scheduleStore,
                executor: ScheduleAgentExecutor(sessionClient: sessionStore)
            )
            errorMessage = nil
        } catch {
            service = nil
            sessionStore = nil
            agentSettingsStore = nil
            providerAuthStore = nil
            installedExtensionsStore = nil
            scheduleRunner = nil
            errorMessage = String(describing: error)
        }
    }
}

private struct AgentRuntimeUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
            Text(L10n.string("agent.unavailable"))
                .font(.headline)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
