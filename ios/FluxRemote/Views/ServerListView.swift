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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                Toggle(languageManager.t("settings.cloudSync"), isOn: Bindable(ServerManager.shared).isCloudSyncEnabled)
            }
            
            Section {
                if ServerManager.shared.servers.isEmpty {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Color("AccentColor").opacity(0.1))
                                .frame(width: 80, height: 80)
                                .overlay {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 40))
                                        .foregroundStyle(Color("AccentColor"))
                                }
                                .padding(.bottom, 8)
                            
                            Text(languageManager.t("settings.noServersTitle"))
                                .font(.title2.bold())
                            
                            Text(languageManager.t("settings.noServers"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            StepItem(icon: "1.circle.fill", text: languageManager.t("settings.launcherStep1"))
                            StepItem(icon: "2.circle.fill", text: languageManager.t("settings.launcherStep2"))
                            
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "safari.fill")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 20))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(languageManager.t("settings.launcherVisitWebsite"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Link("https://flux.ct106.com/", destination: URL(string: "https://flux.ct106.com/")!)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color("AccentColor"))
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        Button {
                            showingAddServer = true
                        } label: {
                            Label(languageManager.t("common.add"), systemImage: "plus")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("AccentColor"))
                        .padding(.horizontal, 24)
                    }
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(ServerManager.shared.servers) { server in
                        ServerRow(server: server, isActive: server.id == ServerManager.shared.selectedServerId) {
                            apiClient.switchServer(to: server)
                            selection = .monitor
                            if !ServerManager.shared.isServerAuthenticated(server.id) {
                                showingLoginForServer = server
                            } else {
                                // Close the modal if we're authenticated
                                dismiss()
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
            try? await Task.sleep(nanoseconds: 500_000_000) 
        }
        .navigationTitle(languageManager.t("settings.serverList"))
        .onAppear {
            let status = ServerManager.shared.reachabilityStatuses[ServerManager.shared.selectedServerId ?? UUID()]
            if let server = ServerManager.shared.selectedServer, 
               !ServerManager.shared.isServerAuthenticated(server.id),
               status == false {
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
            HStack(spacing: 12) {
                // Reachability dot
                let status = ServerManager.shared.reachabilityStatuses[server.id]
                Circle()
                    .fill(status == nil ? Color.gray : (status == true ? Color.red : Color.green))
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(server.name)
                            .font(.headline)
                        
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
                
                if ServerManager.shared.selectedServerId == server.id {
                    Image(systemName: "checkmark")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ServerManager.shared.reachabilityStatuses[server.id] == true)
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

struct StepItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color("AccentColor"))
                .font(.system(size: 20))
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
