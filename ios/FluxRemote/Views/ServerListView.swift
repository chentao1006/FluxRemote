import SwiftUI
import Aptabase

struct ServerListView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var serverManager = ServerManager.shared
    @State private var showingAddServer = false
    @State private var showingSettings = false
    @State private var serverToEdit: ServerConfig?
    @State private var showingDeleteAlert = false
    @State private var serverToDelete: ServerConfig?
    @State private var serverStats: [UUID: RemoteSystemStats] = [:]
    @State private var unloggedServerIds: Set<UUID> = []
    @Binding var selection: NavigationItem?
    var onServerSelected: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    private var isBackgroundLoading: Bool {
        ServerManager.shared.isSyncingServers || 
        ServerManager.shared.isCheckingReachability ||
        ServerManager.shared.isInitializing
    }
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: Bindable(ServerManager.shared).isCloudSyncEnabled) {
                    HStack {
                        Text(languageManager.t("settings.cloudSync"))
                        if ServerManager.shared.isSyncingServers {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 4)
                        }
                    }
                }
                .tint(Color("AccentColor"))
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
                            
                            Text(languageManager.t("settings.launcherVisitWebsite"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Link(destination: URL(string: "https://flux.ct106.com/")!) {
                                Label("flux.ct106.com", systemImage: "arrow.up.right")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color("AccentColor"))
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
                        ServerRow(
                            server: server,
                            isActive: server.id == ServerManager.shared.selectedServerId,
                            stats: serverStats[server.id],
                            isUnlogged: unloggedServerIds.contains(server.id)
                        ) {
                            apiClient.switchServer(to: server)
                            Aptabase.shared.trackEvent("server_switched")
                            selection = .monitor
                            onServerSelected?()
                        } onEdit: {
                            serverToEdit = server
                        } onDelete: {
                            serverToDelete = server
                            showingDeleteAlert = true
                        }
                    }
                }
            } header: {
                HStack {
                    Text(languageManager.t("settings.serverList"))
                    Spacer()
                    if isBackgroundLoading {
                        ProgressView()
                            .controlSize(.small)
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
        .task {
            while !Task.isCancelled {
                await refreshServerStats()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }

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
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(selection: $selection)
            }
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
    
    private func refreshServerStats() async {
        let connectedServers = ServerManager.shared.servers.filter { server in
            // Green is the server-management screen's connection contract. Metrics
            // must refresh for every reachable server, not only the checked server.
            ServerManager.shared.reachabilityStatuses[server.id] == false
        }

        var refreshedStats: [UUID: RemoteSystemStats] = [:]
        var detectedUnloggedServerIds = unloggedServerIds.intersection(Set(connectedServers.map(\.id)))
        for server in connectedServers {
            if !ServerManager.shared.isServerAuthenticated(server.id),
               !(await apiClient.loginSilently(for: server)) {
                detectedUnloggedServerIds.insert(server.id)
                continue
            }

            detectedUnloggedServerIds.remove(server.id)

            if let stats = await apiClient.fetchStats(for: server) {
                refreshedStats[server.id] = stats
            }
        }

        serverStats = refreshedStats
        unloggedServerIds = detectedUnloggedServerIds
    }
}

struct ServerRow: View {
    let server: ServerConfig
    let isActive: Bool
    let stats: RemoteSystemStats?
    let isUnlogged: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(AppLanguageManager.self) private var languageManager

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                let status = ServerManager.shared.reachabilityStatuses[server.id]
                let isRefreshingStatus = ServerManager.shared.refreshingReachabilityServerIds.contains(server.id)
                
                Group {
                    if isRefreshingStatus || status == nil || ServerManager.shared.isInitializing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Circle()
                            .fill(status == true ? Color.red : Color.green)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 12, height: 12)
                
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

                    if isUnlogged {
                        Text("未登录")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let stats {
                        Text(stats.summaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

private extension RemoteSystemStats {
    var summaryText: String {
        let cpuPercent = cpu.map { max(0, min(100, 100 - $0.idle)) }
        let memoryPercent = totalMemoryPercent
        let cpuText = cpuPercent.map { "CPU \(Int($0.rounded()))%" } ?? "CPU –"
        let memoryText = memoryPercent.map { "RAM \(Int($0.rounded()))%" } ?? "RAM –"
        return "\(cpuText) · \(memoryText) · Disk \(disk.percent) · Load \(loadAvg)"
    }

    var totalMemoryPercent: Double? {
        guard memory.totalMB > 0 else { return nil }
        return Double(memory.usedMB) / Double(memory.totalMB) * 100
    }
}

struct ServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var name: String
    @State private var url: String
    @State private var autoLogin: Bool
    var server: ServerConfig
    var onSave: (ServerConfig) -> Void
    
    init(server: ServerConfig, onSave: @escaping (ServerConfig) -> Void) {
        self.server = server
        self.onSave = onSave
        _name = State(initialValue: server.name)
        _url = State(initialValue: server.url)
        _autoLogin = State(initialValue: server.autoLogin)
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
                
                Section {
                    Toggle(languageManager.t("login.autoLogin"), isOn: $autoLogin)
                        .tint(Color("AccentColor"))
                } footer: {
                    if !autoLogin && ServerManager.shared.getPassword(for: server.id) != nil {
                        Text(languageManager.t("settings.passwordWillBeCleared"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        let urlChanged = url != server.url
                        var updated = server
                        updated.name = name
                        updated.url = url
                        updated.rememberPassword = autoLogin
                        updated.autoLogin = autoLogin
                        // We no longer clear password automatically here to respect user preference
                        // unless they manually logout from settings.
                        
                        if urlChanged {
                            ServerManager.shared.setAuthenticated(false, for: server.id)
                        }
                        
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
