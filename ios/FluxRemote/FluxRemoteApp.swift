import SwiftUI

@main
struct FluxRemoteApp: App {
    @State private var apiClient = RemoteAPIClient()
    @State private var languageManager = AppLanguageManager()
    
    var body: some Scene {
        WindowGroup {
            AppContainerView()
                .environment(apiClient)
                .environment(languageManager)
                .environment(\.locale, languageManager.selectedLanguage.locale ?? .current)
                .id(languageManager.selectedLanguage.rawValue) // Force redraw when language changes
        }
    }
}
