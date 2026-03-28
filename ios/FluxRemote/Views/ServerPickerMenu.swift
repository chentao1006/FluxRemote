import SwiftUI

struct ServerPickerMenu: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Binding var selection: NavigationItem?
    
    var body: some View {
        Menu {
            ForEach(ServerManager.shared.servers) { server in
                Button {
                    apiClient.switchServer(to: server)
                } label: {
                    HStack {
                        if server.isOffline {
                            Label("\(server.name) (\(languageManager.t("common.offline")))", systemImage: "wifi.slash")
                        } else {
                            Text(server.name)
                        }
                        
                        if server.id == ServerManager.shared.selectedServerId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(server.isOffline)
            }
            
            Divider()
            
            Button {
                selection = NavigationItem.servers
            } label: {
                Label(languageManager.t("settings.serverList"), systemImage: "list.bullet.rectangle.portrait")
            }
        } label: {
            HStack(spacing: 4) {
                Text(ServerManager.shared.selectedServer?.name ?? languageManager.t("common.none"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
