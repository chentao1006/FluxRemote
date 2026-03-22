import SwiftUI

struct AppContainerView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var selection: NavigationItem? = .monitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    enum NavigationItem: String, CaseIterable, Identifiable {
        case monitor, processes, logs, configs, launchagent, docker, nginx, settings
        
        var id: String { self.rawValue }
        
        var title: String {
            switch self {
            case .monitor: return "sidebar.monitor"
            case .processes: return "sidebar.processes"
            case .logs: return "sidebar.logs"
            case .configs: return "sidebar.configs"
            case .launchagent: return "sidebar.launchagent"
            case .docker: return "sidebar.docker"
            case .nginx: return "sidebar.nginx"
            case .settings: return "sidebar.settings"
            }
        }
        
// ... (icon part remains same, omitting for brevity in TargetContent if possible, but I'll replace the whole block to be safe)
        var icon: String {
            switch self {
            case .monitor: return "waveform.path.ecg.rectangle.fill"
            case .processes: return "cpu.fill"
            case .logs: return "long.text.page.and.pencil.fill"
            case .configs: return "document.badge.gearshape.fill"
            case .launchagent: return "paperplane.fill"
            case .docker: return "shippingbox.fill"
            case .nginx: return "server.rack"
            case .settings: return "slider.horizontal.3"
            }
        }
    }
    
    @State private var showingQuickTerminal = false
    
    var body: some View {
        if !apiClient.isAuthenticated {
            FluxLoginView()
        } else {
            ZStack(alignment: .bottomTrailing) {
                responsiveContent
                    .onAppear {
                        Task { await apiClient.fetchSettings() }
                    }
                
                // Floating Terminal Button
                if horizontalSizeClass != .regular || selection != nil {
                    Button {
                        showingQuickTerminal = true
                    } label: {
                        Image(systemName: "terminal")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4, y: 2)
                    }
                    .padding(16)
                    .padding(.bottom, horizontalSizeClass == .regular ? 0 : 50) // Adjust for TabBar
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingQuickTerminal) {
                QuickTerminalView()
            }
        }
    }
    
    @ViewBuilder
    private var responsiveContent: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                sidebarContent
                    .navigationTitle(languageManager.t("appTitle"))
            } detail: {
                if let selection = selection {
                    NavigationStack {
                        contentView(for: selection)
                    }
                } else {
                    Text(languageManager.t("common.loading"))
                }
            }
        } else {
            TabView {
                if isFeatureEnabled(for: .monitor) {
                    NavigationStack { contentView(for: .monitor) }
                        .tabItem { Label(languageManager.t(NavigationItem.monitor.title), systemImage: NavigationItem.monitor.icon) }
                }
                
                if isFeatureEnabled(for: .processes) {
                    NavigationStack { contentView(for: .processes) }
                        .tabItem { Label(languageManager.t(NavigationItem.processes.title), systemImage: NavigationItem.processes.icon) }
                }
                
                if isFeatureEnabled(for: .logs) {
                    NavigationStack { contentView(for: .logs) }
                        .tabItem { Label(languageManager.t(NavigationItem.logs.title), systemImage: NavigationItem.logs.icon) }
                }
                
                if isFeatureEnabled(for: .configs) {
                    NavigationStack { contentView(for: .configs) }
                        .tabItem { Label(languageManager.t(NavigationItem.configs.title), systemImage: NavigationItem.configs.icon) }
                }
                
                NavigationStack {
                    moreView
                        .navigationDestination(for: NavigationItem.self) { item in
                            contentView(for: item)
                        }
                }
                .tabItem { Label(languageManager.t("common.more"), systemImage: "ellipsis.circle.fill") }
            }
        }
    }
    
    private var moreView: some View {
        List {
            Section(languageManager.t("sidebar.launchagent")) {
                if isFeatureEnabled(for: .launchagent) { tabRow(for: .launchagent) }
                if isFeatureEnabled(for: .docker) { tabRow(for: .docker) }
                if isFeatureEnabled(for: .nginx) { tabRow(for: .nginx) }
            }
            
            Section(languageManager.t("sidebar.settings")) {
                tabRow(for: .settings)
            }
        }
        .navigationTitle(languageManager.t("common.more"))
    }
    
    private var sidebarContent: some View {
        List(selection: $selection) {
            Section(languageManager.t("sidebar.home")) {
                if isFeatureEnabled(for: .monitor) { tabRow(for: .monitor) }
            }
            
            Section(languageManager.t("sidebar.systemTools")) {
                if isFeatureEnabled(for: .processes) { tabRow(for: .processes) }
                if isFeatureEnabled(for: .logs) { tabRow(for: .logs) }
                if isFeatureEnabled(for: .configs) { tabRow(for: .configs) }
            }
            
            Section(languageManager.t("sidebar.serviceManagement")) {
                if isFeatureEnabled(for: .launchagent) { tabRow(for: .launchagent) }
                if isFeatureEnabled(for: .docker) { tabRow(for: .docker) }
                if isFeatureEnabled(for: .nginx) { tabRow(for: .nginx) }
            }
            
            Section(languageManager.t("sidebar.system")) {
                tabRow(for: .settings)
            }
        }
        .listStyle(.sidebar)
    }
    
    private func isFeatureEnabled(for item: NavigationItem) -> Bool {
        switch item {
        case .monitor: return apiClient.features.monitor ?? true
        case .processes: return apiClient.features.processes ?? true
        case .logs: return apiClient.features.logs ?? true
        case .configs: return apiClient.features.configs ?? true
        case .launchagent: return apiClient.features.launchagent ?? true
        case .docker: return apiClient.features.docker ?? true
        case .nginx: return apiClient.features.nginx ?? true
        case .settings: return true
        }
    }
    
    private func tabRow(for item: NavigationItem) -> some View {
        NavigationLink(value: item) {
            Label(languageManager.t(item.title), systemImage: item.icon)
        }
        .tag(item)
    }
    
    @ViewBuilder
    private func contentView(for item: NavigationItem) -> some View {
        switch item {
        case .monitor: DashboardView()
        case .processes: ProcessListView()
        case .logs: LogModuleView()
        case .configs: ConfigsModuleView()
        case .launchagent: LaunchAgentModuleView()
        case .docker: DockerModuleView()
        case .nginx: NginxModuleView()
        case .settings: SettingsView()
        }
    }
}

struct QuickTerminalView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var command: String = ""
    @State private var output: String = ""
    @State private var isExecuting = false
    @Environment(\.dismiss) private var dismiss
    @State private var executionTask: Task<Void, Never>?
    
    let commonCommands: [(String, String)] = [
        ("monitor.quickCmds.ls", "ls -FhG"),
        ("monitor.quickCmds.df", "df -h"),
        ("monitor.quickCmds.memSort", "ps -e -o pmem,comm | sort -rn | head -n 10"),
        ("monitor.quickCmds.cpuSort", "ps -e -o pcpu,comm | sort -rn | head -n 10"),
        ("monitor.quickCmds.ip", "ifconfig | grep \"inet \" | grep -v 127.0.0.1"),
        ("monitor.quickCmds.ports", "lsof -i -P | grep LISTEN"),
        ("monitor.quickCmds.uptime", "uptime"),
        ("monitor.quickCmds.brew", "brew list --versions"),
        ("monitor.quickCmds.vers", "sw_vers"),
        ("monitor.quickCmds.procCount", "ps aux | wc -l"),
        ("monitor.quickCmds.space", "du -sh ~/* | sort -rh | head -n 5"),
        ("monitor.quickCmds.downloads", "ls -lt ~/Downloads | head -n 5"),
        ("monitor.quickCmds.arch", "uname -m"),
        ("monitor.quickCmds.who", "who"),
        ("monitor.quickCmds.dns", "cat /etc/resolv.conf")
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Common Commands (Top)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(commonCommands, id: \.1) { label, cmd in
                            Button {
                                command = cmd
                            } label: {
                                Text(languageManager.t(label))
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                
                // Input Bar
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.right.square")
                            .foregroundStyle(.blue)
                        
                        TextField(languageManager.t("terminal.placeholder"), text: $command, axis: .vertical)
                            .lineLimit(1...3)
                            .font(.system(.subheadline, design: .monospaced))
                            .onSubmit { 
                                if !isExecuting {
                                    executionTask = Task { await execute() } 
                                }
                            }
                        
                        if isExecuting {
                            Button {
                                executionTask?.cancel()
                                isExecuting = false
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Button {
                                executionTask = Task { await execute() }
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(command.isEmpty ? Color.secondary : Color.blue)
                            }
                            .disabled(command.isEmpty)
                        }
                    }
                    .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .background(.ultraThinMaterial)
                    Divider()
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: languageManager.t("terminal.output"))
                        
                        if output.isEmpty {
                            Text(languageManager.t("terminal.waiting"))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                                .background(Color.black.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                        } else {
                            Text(output)
                                .font(.system(.caption2, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(languageManager.t("terminal.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { output = "" }) {
                        Image(systemName: "eraser")
                    }
                    .disabled(output.isEmpty)
                }
            }
        }
    }
    
    private func execute() async {
        guard !command.isEmpty else { return }
        isExecuting = true
        output = "\(languageManager.t("terminal.executing")): \(command)...\n\n"
        
        do {
            guard let baseURL = apiClient.baseURL else { throw NSError(domain: "API", code: 400, userInfo: [NSLocalizedDescriptionKey: "No base URL"]) }
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/system/command"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["command": command])
            
            let (result, response) = try await apiClient.session.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorData = try await result.reduce(into: Data(), { @Sendable (data, byte) in data.append(byte) })
                throw NSError(domain: "Terminal", code: 1, userInfo: [NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "Server Error"])
            }
            
            for try await line in result.lines {
                if Task.isCancelled { throw CancellationError() }
                await MainActor.run {
                    self.output += line + "\n"
                }
            }
            
            await MainActor.run {
                self.output += "\n[\(languageManager.t("terminal.finished"))]"
                self.isExecuting = false
            }
        } catch {
            await MainActor.run {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.output += "\n[\(languageManager.t("terminal.stopped"))]"
                } else {
                    self.output += "\n[\(languageManager.t("common.error")): \(error.localizedDescription)]"
                }
                self.isExecuting = false
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .textCase(.uppercase)
    }
}
