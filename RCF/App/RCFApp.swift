import SwiftUI

/// App entry point: wires auth, session, theme, and app lock into the environment.
@main
struct RCFApp: App {
    @State private var theme = ThemeManager.shared
    @State private var auth = AuthViewModel()
    @State private var lock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(theme)
                .environment(auth)
                .environment(lock)
                .preferredColorScheme(theme.preference.colorScheme)
                .tint(.cfAccent)
                .task {
                    lock.refreshAvailability()
                    MonitorScheduler.register()
                    await auth.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    lock.scenePhaseChanged(phase)
                    if phase == .active {
                        Task {
                            await MonitorScheduler().foregroundRefreshIfNeeded(clientProvider: CurrentSessionClient.shared)
                        }
                    }
                }
        }
    }
}
