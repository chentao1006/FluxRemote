import SwiftUI

@main
struct FluxRemoteApp: App {
    @State private var apiClient: RemoteAPIClient
    @State private var languageManager: AppLanguageManager
    
    init() {
        let lm = AppLanguageManager()
        let api = RemoteAPIClient()
        api.languageManager = lm
        self._apiClient = State(wrappedValue: api)
        self._languageManager = State(wrappedValue: lm)
    }
    
    var body: some Scene {
        WindowGroup {
            AppContainerView()
                .environment(apiClient)
                .environment(languageManager)
                .environment(\.locale, languageManager.selectedLanguage.locale ?? .current)
                .id(languageManager.selectedLanguage.rawValue) // Force redraw when language changes
                .tint(Color.accentColor)
        }
    }
}
