import SwiftUI

@main
struct FluxRemoteApp: App {
    @State private var languageManager: AppLanguageManager?
    @State private var apiClient: RemoteAPIClient?
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let lm = languageManager, let api = apiClient {
                    AppContainerView()
                        .environment(api)
                        .environment(lm)
                        .environment(\.locale, lm.selectedLanguage.locale ?? .current)
                        .id(lm.selectedLanguage.rawValue)
                        .tint(nil)
                } else {
                    // This is shown for only a few milliseconds, but it decouples init from launch
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        Image("LaunchLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 128, height: 128)
                    }
                    .onAppear {
                        // Defer everything to a background-priority task to let the UI breathe
                        Task {
                            let lm = AppLanguageManager()
                            let api = RemoteAPIClient()
                            api.languageManager = lm
                            
                            // Return to main thread to update state
                            await MainActor.run {
                                self.languageManager = lm
                                self.apiClient = api
                            }
                        }
                    }
                }
            }
        }
    }
}
