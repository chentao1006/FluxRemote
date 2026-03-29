import SwiftUI

struct ServerPickerMenu: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Binding var selection: NavigationItem?
    var onManageServers: (() -> Void)? = nil
    
    var body: some View {
        Menu {
            ForEach(ServerManager.shared.servers) { server in
                Button {
                    apiClient.switchServer(to: server)
                    selection = .monitor
                } label: {
                    HStack {
                        let status = ServerManager.shared.reachabilityStatuses[server.id]
                        Circle()
                            .fill(status == nil ? Color.gray : (status == true ? Color.red : Color.green))
                            .frame(width: 8, height: 8)
                        
                        Text(server.name)
                        
                        if server.id == ServerManager.shared.selectedServerId {
                            Image(systemName: "checkmark")
                                .font(.body)
                        }
                    }
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
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
