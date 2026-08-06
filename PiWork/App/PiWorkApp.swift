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
    @State private var didRestore = false

    var body: some View {
        Group {
            if authSession.isSignedIn {
                ContentView()
            } else {
                OnboardingLoginView(authSession: authSession)
            }
        }
        .task {
            guard !didRestore else { return }
            didRestore = true
            await authSession.restoreSessionOnLaunch()
        }
    }
}
