import SwiftUI
import StoreKit

struct AboutView: View {
    @Environment(AppLanguageManager.self) private var languageManager
    
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(version)"
    }
    
    var body: some View {
        Form {
            Section {
                Button(action: {
                    if let url = URL(string: "itms-apps://itunes.apple.com/app/id6761290185") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Label(languageManager.t("settings.version"), systemImage: "info.circle")
                        Spacer()
                        Text(appVersionString)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://flux.ct106.com")!) {
                    HStack {
                        Label(languageManager.t("settings.serverInstall"), systemImage: "globe")
                        Spacer()
                        Text("flux.ct106.com")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://github.com/chentao1006/FluxMonitor/issues")!) {
                    Label(languageManager.t("settings.feedback"), systemImage: "quote.bubble")
                }
                
                Button(action: {
                    if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                }) {
                    Label(languageManager.t("settings.rateApp"), systemImage: "star")
                }
            }
        }
    }
}
