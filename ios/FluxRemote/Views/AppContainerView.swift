import SwiftUI

struct AppContainerView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var selection: NavigationItem? = .monitor
    @State private var morePath: [NavigationItem] = []
    @State private var modulePaths: [NavigationItem: NavigationPath] = [:]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var showingQuickTerminal = false
    @AppStorage("terminalButtonIsLeft") private var storedIsLeft: Bool = false
    @AppStorage("terminalButtonYOffset") private var storedYOffset: Double = 0
    @State private var terminalButtonOffset: CGSize = .zero
    @State private var lastTerminalButtonOffset: CGSize = .zero
    @State private var isDraggingTerminalButton = false
    
    var body: some View {
        Group {
            if !apiClient.isAuthenticated {
                NavigationStack {
                    ServerListView(selection: $selection)
                }
                .tint(.primary)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .bottomTrailing) {
                        responsiveContent
                            .onAppear {
                                Task { await apiClient.fetchSettings() }
                            }
                    
                        // Floating Terminal Button
                        if horizontalSizeClass != .regular || selection != nil {
                            Button {
                                if !isDraggingTerminalButton {
                                    showingQuickTerminal = true
                                }
                            } label: {
                                Image(systemName: "terminal")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color("AccentColor"))
                                    .clipShape(Circle())
                                    .shadow(radius: isDraggingTerminalButton ? 8 : 4, y: isDraggingTerminalButton ? 4 : 2)
                                    .scaleEffect(isDraggingTerminalButton ? 1.1 : 1.0)
                            }
                            .padding(16)
                            .padding(.bottom, horizontalSizeClass == .regular ? 0 : 50) // Adjust for TabBar
                            .offset(terminalButtonOffset)
                            .highPriorityGesture(
                                DragGesture()
                                    .onChanged { value in
                                        isDraggingTerminalButton = true
                                        terminalButtonOffset = CGSize(
                                            width: lastTerminalButtonOffset.width + value.translation.width,
                                            height: lastTerminalButtonOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { value in
                                        isDraggingTerminalButton = false
                                        let screenWidth = geometry.size.width
                                        let buttonWidth: CGFloat = 56
                                        let horizontalPadding: CGFloat = 16
                                        
                                        let leftSnapX = -(screenWidth - buttonWidth - 2 * horizontalPadding)
                                        
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if terminalButtonOffset.width < leftSnapX / 2 {
                                                terminalButtonOffset.width = leftSnapX
                                                storedIsLeft = true
                                            } else {
                                                terminalButtonOffset.width = 0
                                                storedIsLeft = false
                                            }
                                            
                                            let tabBarPadding: CGFloat = horizontalSizeClass == .regular ? 0 : 50
                                            let availableHeight = geometry.size.height - tabBarPadding - 2 * horizontalPadding - buttonWidth
                                            let minY = -availableHeight
                                            let maxY: CGFloat = 0
                                            
                                            terminalButtonOffset.height = min(maxY, max(minY, terminalButtonOffset.height))
                                            storedYOffset = -Double(terminalButtonOffset.height)
                                        }
                                        lastTerminalButtonOffset = terminalButtonOffset
                                    }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear { recalculatePosition(geometry: geometry) }
                    .onChange(of: geometry.size) { _, _ in recalculatePosition(geometry: geometry) }
                }
            }
        }
        .sheet(isPresented: $showingQuickTerminal) {
            QuickTerminalView()
        }
        .onChange(of: ServerManager.shared.selectedServerId) { checkOfflineStatus() }
        .onChange(of: ServerManager.shared.servers) { checkOfflineStatus() }
    }
    
    private func checkOfflineStatus() {
        if let sid = ServerManager.shared.selectedServerId,
           let server = ServerManager.shared.servers.first(where: { $0.id == sid }),
           server.isOffline {
            selection = .servers
        }
    }

    private func recalculatePosition(geometry: GeometryProxy) {
        let screenWidth = geometry.size.width
        let buttonWidth: CGFloat = 56
        let horizontalPadding: CGFloat = 16
        let leftSnapX = -(screenWidth - buttonWidth - 2 * horizontalPadding)
        
        terminalButtonOffset = CGSize(
            width: storedIsLeft ? leftSnapX : 0,
            height: -CGFloat(storedYOffset)
        )
        lastTerminalButtonOffset = terminalButtonOffset
    }
    
    @ViewBuilder
    private var responsiveContent: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                sidebarContent
                    .navigationTitle(languageManager.t("appTitle"))
            } detail: {
                if let currentItem = selection {
                    NavigationStack(path: pathBinding(for: currentItem)) {
                        contentView(for: currentItem)
                            .id(currentItem)
                            .navigationTitle(languageManager.t(currentItem.title))
                    }
                    .tint(.primary)
                } else {
                    ContentUnavailableView(languageManager.t("appTitle"), systemImage: "monitor.fill")
                }
            }
        } else {
            TabView(selection: $selection) {
                if isFeatureEnabled(for: .monitor) {
                    NavigationStack { 
                        contentView(for: .monitor) 
                            .navigationTitle(languageManager.t(NavigationItem.monitor.title))
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    ServerPickerMenu(selection: $selection)
                                }
                            }
                    }
                    .tint(.primary)
                    .tabItem { Label(languageManager.t(NavigationItem.monitor.title), systemImage: NavigationItem.monitor.icon) }
                    .tag(Optional(NavigationItem.monitor))
                }
                
                if isFeatureEnabled(for: .processes) {
                    NavigationStack { 
                        contentView(for: .processes)
                            .navigationTitle(languageManager.t(NavigationItem.processes.title))
                    }
                    .tint(.primary)
                    .tabItem { Label(languageManager.t(NavigationItem.processes.title), systemImage: NavigationItem.processes.icon) }
                    .tag(Optional(NavigationItem.processes))
                }
                
                if isFeatureEnabled(for: .logs) {
                    NavigationStack { 
                        contentView(for: .logs)
                            .navigationTitle(languageManager.t(NavigationItem.logs.title))
                    }
                    .tint(.primary)
                    .tabItem { Label(languageManager.t(NavigationItem.logs.title), systemImage: NavigationItem.logs.icon) }
                    .tag(Optional(NavigationItem.logs))
                }
                
                if isFeatureEnabled(for: .configs) {
                    NavigationStack { 
                        contentView(for: .configs)
                            .navigationTitle(languageManager.t(NavigationItem.configs.title))
                    }
                    .tint(.primary)
                    .tabItem { Label(languageManager.t(NavigationItem.configs.title), systemImage: NavigationItem.configs.icon) }
                    .tag(Optional(NavigationItem.configs))
                }
                
                NavigationStack(path: $morePath) {
                    moreView
                        .navigationDestination(for: NavigationItem.self) { item in
                            contentView(for: item)
                        }
                }
                .tint(.primary)
                .tabItem { Label(languageManager.t("common.more"), systemImage: "ellipsis.circle.fill") }
                .tag(Optional(NavigationItem.more))
            }
            .onChange(of: selection) { oldValue, newValue in
                guard horizontalSizeClass == .compact else { return }
                guard let newValue = newValue else { return }
                let moreItems: [NavigationItem] = [.launchagent, .docker, .nginx, .settings, .servers]
                if moreItems.contains(newValue) {
                    selection = .more
                    morePath = [newValue]
                }
            }
            .tint(Color("AccentColor"))
        }
    }
    
    private var moreView: some View {
        List {
            Section(languageManager.t("sidebar.serviceManagement")) {
                if isFeatureEnabled(for: .launchagent) { tabRow(for: .launchagent) }
                if isFeatureEnabled(for: .docker) { tabRow(for: .docker) }
                if isFeatureEnabled(for: .nginx) { tabRow(for: .nginx) }
            }
            
            Section(languageManager.t("sidebar.settings")) {
                tabRow(for: .settings)
                tabRow(for: .servers)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(languageManager.t("common.more"))
    }
    
    private var sidebarContent: some View {
        List(selection: $selection) {
            Section {
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
                        selection = .servers
                    } label: {
                        Label(languageManager.t("settings.serverList"), systemImage: "list.bullet.rectangle.portrait")
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ServerManager.shared.selectedServer?.name ?? languageManager.t("common.none"))
                                .font(.headline)
                            Text(ServerManager.shared.selectedServer?.url ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            
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
                tabRow(for: .servers)
            }
        }
        .listStyle(.sidebar)
        .tint(Color("AccentColor"))
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
        case .servers: return true
        case .more: return true
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
        case .monitor: DashboardView(selection: $selection)
        case .processes: ProcessListView(selection: $selection)
        case .logs: LogModuleView(selection: $selection)
        case .configs: ConfigsModuleView(selection: $selection)
        case .launchagent: LaunchAgentModuleView(selection: $selection)
        case .docker: DockerModuleView(selection: $selection)
        case .nginx: NginxModuleView(selection: $selection)
        case .settings: SettingsView(selection: $selection)
        case .servers: ServerListView(selection: $selection)
        case .more: EmptyView()
        }
    }
    
    private func pathBinding(for item: NavigationItem) -> Binding<NavigationPath> {
        Binding(
            get: { modulePaths[item] ?? NavigationPath() },
            set: { modulePaths[item] = $0 }
        )
    }
}

struct QuickTerminalView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var command: String = ""
    @State private var output: String = ""
    @State private var isExecuting = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("terminal_quick_commands_data") private var quickCommandsData: Data = Data()
    @State private var commands: [QuickCommand] = []
    @State private var showingManageCommands = false
    @State private var executionTask: Task<Void, Never>?
    
    // AI states
    @State private var isTranslating = false
    @State private var isAnalyzingOutput = false
    @State private var aiAnalysis: String?
    @State private var showingAIPrompt = false
    @State private var aiPromptText = ""

    @FocusState private var isFieldFocused: Bool

    static let defaultCommands: [QuickCommand] = [
        QuickCommand(name: "monitor.quickCmds.ls", command: "ls -FhG"),
        QuickCommand(name: "monitor.quickCmds.df", command: "df -h"),
        QuickCommand(name: "monitor.quickCmds.memSort", command: "ps -e -o pmem,comm | sort -rn | head -n 10"),
        QuickCommand(name: "monitor.quickCmds.cpuSort", command: "ps -e -o pcpu,comm | sort -rn | head -n 10"),
        QuickCommand(name: "monitor.quickCmds.ip", command: "ifconfig | grep \"inet \" | grep -v 127.0.0.1"),
        QuickCommand(name: "monitor.quickCmds.ports", command: "lsof -i -P | grep LISTEN"),
        QuickCommand(name: "monitor.quickCmds.uptime", command: "uptime"),
        QuickCommand(name: "monitor.quickCmds.brew", command: "brew list --versions"),
        QuickCommand(name: "monitor.quickCmds.vers", command: "sw_vers"),
        QuickCommand(name: "monitor.quickCmds.procCount", command: "ps aux | wc -l"),
        QuickCommand(name: "monitor.quickCmds.space", command: "du -sh ~/* | sort -rh | head -n 5"),
        QuickCommand(name: "monitor.quickCmds.downloads", command: "ls -lt ~/Downloads | head -n 5"),
        QuickCommand(name: "monitor.quickCmds.arch", command: "uname -m"),
        QuickCommand(name: "monitor.quickCmds.who", command: "who"),
        QuickCommand(name: "monitor.quickCmds.dns", command: "cat /etc/resolv.conf")
    ]
    
    @State private var showingAIDisabledAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Common Commands (Top)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button {
                            showingManageCommands = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.leading, 16)
                        
                        ForEach(commands) { cmd in
                            Button {
                                command = cmd.command
                            } label: {
                                Text(languageManager.t(cmd.name))
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.08))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)
                }
                
                // Input Bar
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            if apiClient.aiConfig?.enabled ?? false {
                                showingAIPrompt = true
                            } else {
                                showingAIDisabledAlert = true
                            }
                        } label: {
                            if isTranslating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.sparkles")
                                    .font(.title3)
                                    .foregroundStyle(Color("AccentColor"))
                            }
                        }
                        .disabled(isTranslating)
                        
                            TextField(languageManager.t("terminal.placeholder"), text: $command, axis: .vertical)
                                .focused($isFieldFocused)
                                .lineLimit(1...5)
                                .font(.system(.body, design: .monospaced))
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
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            Button {
                                executionTask = Task { await execute() }
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(command.isEmpty ? Color.secondary : Color.blue)
                            }
                            .disabled(command.isEmpty)
                        }
                    }
                    .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .background(.ultraThinMaterial)
                    Divider()
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if output.isEmpty {
                                Text(languageManager.t("terminal.waiting"))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                                    .background(Color.black.opacity(0.02))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    let lines = output.components(separatedBy: .newlines)
                                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                        Text(line)
                                            .font(.system(.caption2, design: .monospaced))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(index % 2 == 0 ? Color.clear : Color.black.opacity(0.04))
                                            .id(index)
                                    }
                                }
                                .textSelection(.enabled)
                                
                            }
                        }
                    }
                    .onChange(of: output) { oldValue, newValue in
                        let linesCount = newValue.components(separatedBy: .newlines).count
                        if linesCount > 0 {
                            withAnimation {
                                proxy.scrollTo(linesCount - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isAnalyzingOutput || aiAnalysis != nil {
                    AIAnalysisCard(analysis: aiAnalysis, isAnalyzing: isAnalyzingOutput) {
                        withAnimation { aiAnalysis = nil; isAnalyzingOutput = false }
                    }
                    .padding(.bottom, 20)
                } else if !output.isEmpty && !isExecuting {
                    AIActionButton(languageManager.t("common.aiAnalyze"), systemImage: "sparkle.text.clipboard", isLoading: isAnalyzingOutput) {
                        analyzeOutput()
                    }
                    .padding(.bottom, 30)
                }
            }
            .alert(languageManager.t("settings.aiDisabled"), isPresented: $showingAIDisabledAlert) {
                Button(languageManager.t("common.ok"), role: .cancel) { }
            } message: {
                Text(languageManager.t("settings.aiDisabledDesc"))
            }
            .navigationTitle(languageManager.t("terminal.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark") }
                }
            }
            .sheet(isPresented: $showingManageCommands) {
                ManageCommandsView(commands: $commands)
            }
            .overlay {
                if showingAIPrompt {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture { showingAIPrompt = false }
                        
                        TerminalAIPromptView(text: $aiPromptText) {
                            translateAI()
                            showingAIPrompt = false
                        } onCancel: {
                            showingAIPrompt = false
                        }
                        .frame(maxWidth: 400)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(radius: 20)
                        .padding(20)
                    }
                    .transition(.opacity.combined(with: .scale(0.9)))
                }
            }
            .onAppear { loadCommands() }
            .onChange(of: commands) { _, newValue in saveCommands(newValue) }
        }
    }

    private func loadCommands() {
        if let decoded = try? JSONDecoder().decode([QuickCommand].self, from: quickCommandsData) {
            commands = decoded
        } else {
            commands = QuickTerminalView.defaultCommands
            saveCommands(commands)
        }
    }

    private func saveCommands(_ newCommands: [QuickCommand]) {
        if let encoded = try? JSONEncoder().encode(newCommands) {
            quickCommandsData = encoded
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
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 401 {
                    apiClient.logout()
                    throw NSError(domain: "Terminal", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
                }
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

    private func translateAI() {
        guard !aiPromptText.isEmpty else { return }
        isTranslating = true
        let requirement = aiPromptText
        aiPromptText = ""
        
        Task {
            do {
                // Incorporate strict instructions directly into the prompt to ensure they are followed
                let strictPrompt = """
                Task: Convert the following requirement into a single-line macOS bash command.
                Requirement: \(requirement)
                
                Mandatory Rule: Return ONLY the command text. No explanations. No markdown. No intro. No quotes.
                Command:
                """
                
                let response = try await AIService.shared.analyze(
                    prompt: strictPrompt,
                    systemPrompt: "You are a terminal command generator. Output ONLY raw bash commands.",
                    apiClient: apiClient
                )
                await MainActor.run {
                    self.command = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.isTranslating = false
                    self.isFieldFocused = true
                }
            } catch {
                await MainActor.run {
                    self.isTranslating = false
                }
            }
        }
    }

    private func analyzeOutput() {
        guard !output.isEmpty else { return }
        isAnalyzingOutput = true
        aiAnalysis = nil
        Task {
            do {
                let prompt = "Analyze this terminal output and provide explanations or suggestions in Chinese:\n\(output)\nPlease use Markdown formatting."
                let response = try await AIService.shared.analyze(prompt: prompt, systemPrompt: "You are a terminal output analyzer.", apiClient: apiClient)
                await MainActor.run {
                    self.aiAnalysis = response
                    self.isAnalyzingOutput = false
                }
            } catch {
                await MainActor.run {
                    self.aiAnalysis = "Error: \(error.localizedDescription)"
                    self.isAnalyzingOutput = false
                }
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

struct SudoPasswordView: View {
    @Binding var password: String
    @Environment(\.dismiss) var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    var onConfirm: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(languageManager.t("common.sudoPasswordPlaceholder"), text: $password)
                        .textContentType(.password)
                } header: {
                    Text(languageManager.t("common.sudoRequired"))
                }
            }
            .navigationTitle(languageManager.t("common.sudoRequired"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Image(systemName: "checkmark")
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
        .presentationDetents([.height(250)])
    }
}

// MARK: - Quick Command Models & Views

struct QuickCommand: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var command: String
}

struct ManageCommandsView: View {
    @Binding var commands: [QuickCommand]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var commandToEdit: QuickCommand?
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(commands) { cmd in
                    Button {
                        commandToEdit = cmd
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(languageManager.t(cmd.name))
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text(cmd.command)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if let index = commands.firstIndex(where: { $0.id == cmd.id }) {
                                commands.remove(at: index)
                            }
                        } label: {
                            Label(languageManager.t("common.delete"), systemImage: "trash")
                        }
                    }
                }
                .onMove { indices, newOffset in
                    commands.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(languageManager.t("terminal.commonCommands"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            editMode = (editMode == .inactive) ? .active : .inactive
                        }
                    } label: {
                        Image(systemName: editMode == .inactive ? "arrow.up.arrow.down" : "checkmark")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if editMode == .inactive {
                        Button(action: { commandToEdit = QuickCommand(name: "", command: "") }) {
                            Image(systemName: "plus")
                                .font(.title3)
                        }
                    }
                }
            }
            .sheet(item: $commandToEdit) { cmd in
                CommandEditorView(command: cmd) { updatedCmd in
                    if let index = commands.firstIndex(where: { $0.id == updatedCmd.id }) {
                        commands[index] = updatedCmd
                    } else {
                        commands.append(updatedCmd)
                    }
                }
            }
        }
    }
}

struct CommandEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var name: String
    @State private var commandValue: String
    var initialCommand: QuickCommand
    var onSave: (QuickCommand) -> Void
    
    init(command: QuickCommand, onSave: @escaping (QuickCommand) -> Void) {
        self.initialCommand = command
        self.onSave = onSave
        // Use empty strings if it's a new command (empty name and command)
        _name = State(initialValue: command.name)
        _commandValue = State(initialValue: command.command)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(languageManager.t("terminal.commandNamePlaceholder"), text: $name)
                        .onAppear {
                            // If it's a built-in key, resolve it to localized text for editing
                            if name.contains("monitor.quickCmds.") {
                                name = languageManager.t(name)
                            }
                        }
                    TextEditor(text: $commandValue)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                } header: {
                    Text(languageManager.t("terminal.commandName"))
                } footer: {
                    Text(languageManager.t("terminal.commandPrompt"))
                }
            }
            .navigationTitle(name.isEmpty ? languageManager.t("terminal.addCommand") : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        var updated = initialCommand
                        updated.name = name
                        updated.command = commandValue
                        onSave(updated)
                        dismiss()
                    }) {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.isEmpty || commandValue.isEmpty)
                }
            }
        }
    }
}

struct TerminalAIPromptView: View {
    @Binding var text: String
    var onConfirm: @MainActor () -> Void
    var onCancel: () -> Void
    @Environment(AppLanguageManager.self) private var languageManager
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(languageManager.t("common.aiGenerate"))
                    .font(.headline)
                Spacer()
                Button {
                    onConfirm()
                } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.bold)
                }
                .disabled(text.isEmpty)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(languageManager.t("monitor.aiPromptPlaceholder"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $text)
                    .font(.body)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .onAppear {
            isFocused = true
        }
    }
}
