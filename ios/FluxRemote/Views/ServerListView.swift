import SwiftUI

struct ServerListView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var serverManager = ServerManager.shared
    @State private var showingAddServer = false
    @State private var serverToEdit: ServerConfig?
    @State private var showingDeleteAlert = false
    @State private var serverToDelete: ServerConfig?
    @State private var showingLoginForServer: ServerConfig?
    @Binding var selection: NavigationItem?
    
    var body: some View {
        List {
            Section {
                Toggle(languageManager.t("settings.cloudSync"), isOn: Bindable(ServerManager.shared).isCloudSyncEnabled)
            }
            
            Section {
                if ServerManager.shared.servers.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 60))
                            .foregroundStyle(.tertiary)
                        Text(languageManager.t("settings.noServers"))
                            .font(.headline)
                        Button {
                            showingAddServer = true
                        } label: {
                            Text(languageManager.t("common.add"))
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(ServerManager.shared.servers) { server in
                        ServerRow(server: server, isActive: server.id == ServerManager.shared.selectedServerId) {
                            apiClient.switchServer(to: server)
                            selection = .monitor
                            if !ServerManager.shared.isServerAuthenticated(server.id) {
                                showingLoginForServer = server
                            }
                        } onEdit: {
                            serverToEdit = server
                        } onDelete: {
                            serverToDelete = server
                            showingDeleteAlert = true
                        }
                    }
                }
            }
        }
        .tint(Color("AccentColor"))
        .refreshable {
            await ServerManager.shared.manualSync()
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s delay for feedback
        }
        .navigationTitle(languageManager.t("settings.serverList"))
        .onAppear {
            if let server = ServerManager.shared.selectedServer, 
               !ServerManager.shared.isServerAuthenticated(server.id),
               !server.isOffline {
                showingLoginForServer = server
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            FluxLoginView(isAddingServer: true)
                .environment(apiClient)
                .environment(languageManager)
        }
        .sheet(item: $showingLoginForServer) { server in
            FluxLoginView(initialURL: server.url, initialServerName: server.name)
                .environment(apiClient)
                .environment(languageManager)
        }
        .sheet(item: $serverToEdit) { server in
            ServerEditView(server: server) { updatedServer in
                ServerManager.shared.updateServer(updatedServer)
                if updatedServer.id == ServerManager.shared.selectedServer?.id {
                    apiClient.switchServer(to: updatedServer)
                }
            }
        }
        .alert(languageManager.t("settings.deleteServerConfirm"), isPresented: $showingDeleteAlert) {
            Button(languageManager.t("common.delete"), role: .destructive) {
                if let server = serverToDelete {
                    ServerManager.shared.removeServer(server)
                    if let nextServer = ServerManager.shared.selectedServer {
                        apiClient.switchServer(to: nextServer)
                    }
                }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        }
    }
}

struct ServerRow: View {
    let server: ServerConfig
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(AppLanguageManager.self) private var languageManager

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(server.name)
                            .font(.headline)
                            .foregroundStyle(server.isOffline ? .secondary : .primary)
                        
                        if server.isOffline {
                            Text(languageManager.t("common.offline"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                        
                        if server.isLauncher {
                            Text(languageManager.t("common.launcher"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }

                    }
                    
                    Text(server.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if server.isOffline {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else if ServerManager.shared.selectedServerId == server.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color("AccentColor"))
                        .font(.subheadline)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(server.isOffline)
        .swipeActions(edge: .trailing) {
            if !server.isLauncher {
                Button(role: .destructive, action: onDelete) {
                    Label(languageManager.t("common.delete"), systemImage: "trash")
                }
                .tint(.red)
                
                Button(action: onEdit) {
                    Label(languageManager.t("common.edit"), systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
    }
}

struct ServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var name: String
    @State private var url: String
    var server: ServerConfig
    var onSave: (ServerConfig) -> Void
    
    init(server: ServerConfig, onSave: @escaping (ServerConfig) -> Void) {
        self.server = server
        self.onSave = onSave
        _name = State(initialValue: server.name)
        _url = State(initialValue: server.url)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(languageManager.t("common.basicInfo")) {
                    TextField(languageManager.t("settings.serverName"), text: $name)
                    TextField(languageManager.t("settings.serverURL"), text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .tint(Color("AccentColor"))
            .navigationTitle(languageManager.t("settings.editServer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        var updated = server
                        updated.name = name
                        updated.url = url
                        onSave(updated)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                    }
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
        .tint(.primary)
    }
}
