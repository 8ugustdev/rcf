import SwiftUI

/// Root gate: loading → onboarding → login → tabs, with app-lock cover on top.
/// Builds the Session environment for the tab tree once authenticated.
struct RootView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppLockManager.self) private var lock

    var body: some View {
        Group {
            switch auth.phase {
            case .loading:
                LoadingView()
            case .onboarding:
                OnboardingView {
                    auth.completeOnboarding()
                }
            case .login:
                LoginView()
            case .authenticated:
                if let session = auth.session {
                    AppShell()
                        .environment(session)
                } else {
                    LoginView()
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { lock.isLocked },
            set: { _ in } // dismiss only via successful unlock
        )) {
            AppLockOverlay()
        }
    }
}
