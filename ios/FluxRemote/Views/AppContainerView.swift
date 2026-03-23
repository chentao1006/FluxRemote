import SwiftUI

struct AppContainerView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var selection: NavigationItem? = .monitor
    @State private var morePath: [NavigationItem] = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var showingQuickTerminal = false
    @AppStorage("terminalButtonIsLeft") private var storedIsLeft: Bool = false
    @AppStorage("terminalButtonYOffset") private var storedYOffset: Double = 0
    @State private var terminalButtonOffset: CGSize = .zero
    @State private var lastTerminalButtonOffset: CGSize = .zero
    @State private var isDraggingTerminalButton = false
    
    var body: some View {
        if !apiClient.isAuthenticated {
            FluxLoginView()
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
                                .background(Color.blue)
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
            .sheet(isPresented: $showingQuickTerminal) {
                QuickTerminalView()
            }
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
                if let selection = selection {
                    NavigationStack {
                        contentView(for: selection)
                    }
                } else {
                    LoadingView()
                }
            }
        } else {
            TabView(selection: $selection) {
                if isFeatureEnabled(for: .monitor) {
                    NavigationStack { contentView(for: .monitor) }
                        .tabItem { Label(languageManager.t(NavigationItem.monitor.title), systemImage: NavigationItem.monitor.icon) }
                        .tag(Optional(NavigationItem.monitor))
                }
                
                if isFeatureEnabled(for: .processes) {
                    NavigationStack { contentView(for: .processes) }
                        .tabItem { Label(languageManager.t(NavigationItem.processes.title), systemImage: NavigationItem.processes.icon) }
                        .tag(Optional(NavigationItem.processes))
                }
                
                if isFeatureEnabled(for: .logs) {
                    NavigationStack { contentView(for: .logs) }
                        .tabItem { Label(languageManager.t(NavigationItem.logs.title), systemImage: NavigationItem.logs.icon) }
                        .tag(Optional(NavigationItem.logs))
                }
                
                if isFeatureEnabled(for: .configs) {
                    NavigationStack { contentView(for: .configs) }
                        .tabItem { Label(languageManager.t(NavigationItem.configs.title), systemImage: NavigationItem.configs.icon) }
                        .tag(Optional(NavigationItem.configs))
                }
                
                NavigationStack(path: $morePath) {
                    moreView
                        .navigationDestination(for: NavigationItem.self) { item in
                            contentView(for: item)
                        }
                }
                .tabItem { Label(languageManager.t("common.more"), systemImage: "ellipsis.circle.fill") }
                .tag(Optional(NavigationItem.more))
            }
            .onChange(of: selection) { oldValue, newValue in
                guard let newValue = newValue else { return }
                let moreItems: [NavigationItem] = [.launchagent, .docker, .nginx, .settings]
                if moreItems.contains(newValue) {
                    selection = .more
                    morePath = [newValue]
                }
            }
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
            }
        }
        .listStyle(.insetGrouped)
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
        case .processes: ProcessListView()
        case .logs: LogModuleView()
        case .configs: ConfigsModuleView()
        case .launchagent: LaunchAgentModuleView()
        case .docker: DockerModuleView()
        case .nginx: NginxModuleView()
        case .settings: SettingsView()
        case .more: EmptyView()
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
    @AppStorage("terminal_quick_commands_data") private var quickCommandsData: Data = Data()
    @State private var commands: [QuickCommand] = []
    @State private var showingManageCommands = false
    @State private var executionTask: Task<Void, Never>?
    
    // AI states
    @State private var isTranslating = false
    @State private var isAnalyzingOutput = false
    @State private var aiAnalysis: String?

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
                                .foregroundStyle(.blue)
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
                                    .background(Color.blue.opacity(0.08))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)
                }
                
                // Input Bar
                VStack(spacing: 0) {
                    HStack(spacing: 15) {
                        Image(systemName: "chevron.right.square")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        
                        TextField(languageManager.t("terminal.placeholder"), text: $command, axis: .vertical)
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
                            HStack(spacing: 8) {
                                Button(action: translateAI) {
                                    if isTranslating {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "wand.and.sparkles")
                                            .font(.title2)
                                            .foregroundStyle(.purple)
                                    }
                                }
                                .disabled(command.isEmpty || isTranslating)
                                
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
                    }
                    .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .background(.ultraThinMaterial)
                    Divider()
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeader(title: languageManager.t("terminal.output"))
                                .padding(.top)
                            
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
                                
                                if isAnalyzingOutput || aiAnalysis != nil {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Divider().padding(.vertical, 8)
                                        HStack {
                                            Label(languageManager.t("monitor.aiAnalysisTitle"), systemImage: "sparkles")
                                                .font(.headline)
                                                .foregroundStyle(.purple)
                                            Spacer()
                                            if !isAnalyzingOutput {
                                                Button {
                                                    aiAnalysis = nil
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        
                                        if isAnalyzingOutput {
                                            HStack {
                                                ProgressView().controlSize(.small)
                                                Text(languageManager.t("common.analyzing"))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: CGFloat.infinity, alignment: .center)
                                            .padding()
                                        } else if let analysis = aiAnalysis {
                                            MarkdownView(text: analysis)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal)
                                    .padding(.bottom)
                                } else {
                                    Button(action: analyzeOutput) {
                                        Label(languageManager.t("monitor.aiAnalyzeBtn"), systemImage: "sparkles")
                                            .font(.subheadline)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.purple.opacity(0.1))
                                            .foregroundStyle(.purple)
                                            .clipShape(Capsule())
                                    }
                                    .padding()
                                    .frame(maxWidth: CGFloat.infinity, alignment: .center)
                                }
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
            .navigationTitle(languageManager.t("terminal.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        output = ""
                        command = ""
                    }) {
                        Image(systemName: "eraser")
                    }
                    .disabled(output.isEmpty && command.isEmpty)
                }
            }
            .sheet(isPresented: $showingManageCommands) {
                ManageCommandsView(commands: $commands)
            }
            .onAppear { loadCommands() }
            .onChange(of: commands) { _, newValue in saveCommands(newValue) }
        }
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
        guard !command.isEmpty else { return }
        isTranslating = true
        Task {
            do {
                let prompt = "Translate this natural language command to a macOS bash command: \"\(command)\". Provide ONLY the command, no explanations, no markdown blocks."
                let response: AIResponse = try await apiClient.request("/api/ai", method: "POST", body: ["prompt": prompt])
                await MainActor.run {
                    self.command = response.data.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.isTranslating = false
                }
            } catch {
                await MainActor.run {
                    self.isTranslating = false
                    // Optionally show alert
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
                let response: AIResponse = try await apiClient.request("/api/ai", method: "POST", body: ["prompt": prompt])
                await MainActor.run {
                    self.aiAnalysis = response.data
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
                } footer: {
                    Text(languageManager.t("common.sudoPassword"))
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t(cmd.name))
                            .fontWeight(.medium)
                        Text(cmd.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let index = commands.firstIndex(where: { $0.id == cmd.id }) {
                                commands.remove(at: index)
                            }
                        } label: {
                            Label(languageManager.t("common.delete"), systemImage: "trash")
                        }
                        
                        Button {
                            commandToEdit = cmd
                        } label: {
                            Label(languageManager.t("common.edit"), systemImage: "pencil")
                        }
                        .tint(.orange)
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
                    TextField(languageManager.t("terminal.placeholder"), text: $name)
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
