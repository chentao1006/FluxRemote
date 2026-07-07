import SwiftUI
import Aptabase

struct ServerPickerMenu: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Binding var selection: NavigationItem?
    var onManageServers: (() -> Void)? = nil
    
    var body: some View {
        Menu {
            ForEach(ServerManager.shared.servers) { server in
                let isSelected = server.id == ServerManager.shared.selectedServerId
                Toggle(isOn: Binding(
                    get: { isSelected },
                    set: { newValue in
                        if newValue && !isSelected {
                            apiClient.switchServer(to: server)
                            Aptabase.shared.trackEvent("server_switched")
                            selection = .monitor
                        }
                    }
                )) {
                    Text(server.name)
                }
                .disabled(ServerManager.shared.reachabilityStatuses[server.id] == true)
            }
            
            Divider()
            
            Button {
                if let onManageServers = onManageServers {
                    onManageServers()
                } else {
                    selection = NavigationItem.servers
                }
            } label: {
                Label(languageManager.t("settings.serverList"), systemImage: "list.bullet.rectangle.portrait")
            }
        } label: {
            HStack(spacing: 4) {
                Text(ServerManager.shared.selectedServer?.name ?? languageManager.t("common.none"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
