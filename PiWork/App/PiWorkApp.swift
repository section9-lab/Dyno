import SwiftUI

@main
struct PiWorkApp: App {
    @StateObject private var authSession = AuthSession.shared

    var body: some Scene {
        WindowGroup {
            RootView(authSession: authSession)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

/// Gates the app on a valid session: onboarding until signed in, the project
/// shell afterwards. `restoreSessionOnLaunch` runs once on cold start and
/// silently refreshes an expired access token when it can.
private struct RootView: View {
    @ObservedObject var authSession: AuthSession
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var didRestore = false

    var body: some View {
        Group {
            if authSession.isSignedIn {
                ContentView()
            } else {
                OnboardingLoginView(authSession: authSession)
            }
        }
        // Applied at the root so onboarding follows the choice too. `nil`
        // means "follow the system", which is the default.
        .preferredColorScheme(themeStore.theme.colorScheme)
        .task {
            guard !didRestore else { return }
            didRestore = true
            await authSession.restoreSessionOnLaunch()
        }
    }
}
