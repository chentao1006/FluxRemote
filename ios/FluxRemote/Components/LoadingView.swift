import SwiftUI

struct LoadingView: View {
    let message: String?
    @Environment(AppLanguageManager.self) private var languageManager
    
    init(_ message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message ?? languageManager.t("common.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    LoadingView()
        .environment(AppLanguageManager())
}
