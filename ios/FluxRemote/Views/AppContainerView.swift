import SwiftUI

struct AppContainerView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var selection: NavigationItem? = .monitor
    @State private var morePath: [NavigationItem] = []
    @State private var modulePaths: [NavigationItem: NavigationPath] = [:]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingQuickTerminal = false
    @State private var showingPrimaryTabsCustomization = false
    @State private var primaryNavigationItems: [NavigationItem] = [.processes, .logs, .configs]
    @AppStorage("primaryNavigationItems") private var primaryNavigationItemsData: Data = Data()
    @AppStorage("terminalButtonIsLeft") private var storedIsLeft: Bool = false
    @AppStorage("terminalButtonYOffset") private var storedYOffset: Double = 0
    @State private var terminalButtonOffset: CGSize = .zero
    @State private var lastTerminalButtonOffset: CGSize = .zero
    @State private var isDraggingTerminalButton = false
    @State private var showingServerManagement = false
    @State private var initialServerEntryAttempted = false

    var body: some View {
        Group {
            if !apiClient.isAuthenticated {
                Group {
                    if shouldShowStartupProgress {
                        ZStack {
                            Color(.systemBackground).ignoresSafeArea()
                            VStack(spacing: 20) {
                                Image("LaunchLogo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 128, height: 128)

                                if let serverName = ServerManager.shared.selectedServer?.name, !serverName.isEmpty {
                                    Text("\(languageManager.t("startup.connecting")) \(serverName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .transition(.opacity)
                                }

                                ProgressView()
                                    .tint(Color("AccentColor"))
                                    .padding(.bottom, 20)

                                Button {
                                    // Cancel any active login/auto-login tasks and show server manager
                                    apiClient.logout()
                                    initialServerEntryAttempted = true
                                    showingServerManagement = true
                                } label: {
                                    Text(languageManager.t("startup.switchServer"))
                                        .font(.footnote)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color("AccentColor"))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    } else {
                        NavigationStack {
                            ServerListView(selection: $selection)
                        }
                    }
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
        .sheet(isPresented: $showingPrimaryTabsCustomization) {
            PrimaryTabsCustomizationView(
                selectedItems: $primaryNavigationItems,
                enabledItems: primaryTabCandidates.filter { isFeatureEnabled(for: $0) }
            )
        }
        .sheet(isPresented: $showingServerManagement) {
            NavigationStack {
                ServerListView(selection: $selection)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showingServerManagement = false } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
            }
        }
        .onChange(of: ServerManager.shared.selectedServerId) { checkOfflineStatus() }
        .onChange(of: ServerManager.shared.servers) { checkOfflineStatus() }
        .onChange(of: ServerManager.shared.isInitializing) { attemptInitialServerEntryIfReady() }
        .onChange(of: ServerManager.shared.isCheckingReachability) { attemptInitialServerEntryIfReady() }
        .onChange(of: ServerManager.shared.reachabilityStatuses) { _, _ in attemptInitialServerEntryIfReady() }
        .onAppear {
            attemptInitialServerEntryIfReady()
        }
    }

    private var shouldShowStartupProgress: Bool {
        apiClient.isAutoLoggingIn ||
        (apiClient.isLoading && ServerManager.shared.selectedServer?.autoLogin == true) ||
        shouldWaitForInitialServerStatus
    }

    private var shouldWaitForInitialServerStatus: Bool {
        guard !initialServerEntryAttempted,
              selectedConfiguredServer != nil,
              !ServerManager.shared.servers.isEmpty
        else { return false }

        return ServerManager.shared.isInitializing ||
        ServerManager.shared.isCheckingReachability ||
        selectedServerReachability == nil
    }

    private var selectedServerReachability: Bool? {
        guard let server = selectedConfiguredServer else { return nil }
        return ServerManager.shared.reachabilityStatuses[server.id] ?? nil
    }

    private var selectedConfiguredServer: ServerConfig? {
        guard let sid = ServerManager.shared.selectedServerId else { return nil }
        return ServerManager.shared.servers.first { $0.id == sid }
    }

    private func attemptInitialServerEntryIfReady() {
        guard !initialServerEntryAttempted,
              !apiClient.isAuthenticated,
              !apiClient.isAutoLoggingIn,
              !ServerManager.shared.isInitializing,
              !ServerManager.shared.isCheckingReachability,
              let server = selectedConfiguredServer,
              let isOffline = selectedServerReachability
        else { return }

        initialServerEntryAttempted = true

        if isOffline {
            showingServerManagement = true
        } else {
            apiClient.switchServer(to: server)
        }
    }

    private func checkOfflineStatus() {
        if let sid = ServerManager.shared.selectedServerId,
           ServerManager.shared.reachabilityStatuses[sid] == true {
            showingServerManagement = true
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
                            .toolbar {
                                if shouldShowServerPicker(for: currentItem) {
                                    ToolbarItem(placement: .topBarLeading) {
                                        ServerPickerMenu(selection: $selection, onManageServers: { showingServerManagement = true })
                                    }
                                }
                            }
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
                                    ServerPickerMenu(selection: $selection, onManageServers: { showingServerManagement = true })
                                }
                            }
                    }
                    .tint(.primary)
                    .tabItem { Label(languageManager.t(NavigationItem.monitor.title), systemImage: NavigationItem.monitor.icon) }
                    .tag(Optional(NavigationItem.monitor))
                }

                ForEach(visiblePrimaryTabs) { item in
                    NavigationStack {
                        contentView(for: item)
                            .navigationTitle(languageManager.t(item.title))
                            .toolbar {
                                if shouldShowServerPicker(for: item) {
                                    ToolbarItem(placement: .topBarLeading) {
                                        ServerPickerMenu(selection: $selection, onManageServers: { showingServerManagement = true })
                                    }
                                }
                            }
                    }
                    .tint(.primary)
                    .tabItem { Label(languageManager.t(item.title), systemImage: item.icon) }
                    .tag(Optional(item))
                }

                NavigationStack(path: $morePath) {
                    moreView
                        .navigationDestination(for: NavigationItem.self) { item in
                            contentView(for: item)
                                .navigationTitle(languageManager.t(item.title))
                                .toolbar {
                                    if shouldShowServerPicker(for: item) {
                                        ToolbarItem(placement: .topBarLeading) {
                                            ServerPickerMenu(selection: $selection, onManageServers: { showingServerManagement = true })
                                        }
                                    }
                                }
                        }
                }
                .tint(.primary)
                .tabItem { Label(languageManager.t("common.more"), systemImage: "ellipsis.circle.fill") }
                .tag(Optional(NavigationItem.more))
            }
            .onChange(of: selection) { oldValue, newValue in
                guard horizontalSizeClass == .compact else { return }
                guard let newValue = newValue else { return }
                let moreItems = primaryTabCandidates + [.settings, .servers]
                if moreItems.contains(newValue), !visiblePrimaryTabs.contains(newValue) {
                    selection = .more
                    morePath = [newValue]
                }
            }
            .onAppear {
                loadPrimaryNavigationItems()
            }
            .onChange(of: primaryNavigationItems) { _, newValue in
                savePrimaryNavigationItems(newValue)
            }
            .tint(Color("AccentColor"))
        }
    }

    private var moreView: some View {
        let visibleItems = visiblePrimaryTabs
        let systemItems = [NavigationItem.processes, .ports, .logs, .configs].filter { isFeatureEnabled(for: $0) && !visibleItems.contains($0) }
        let serviceItems = [NavigationItem.launchagent, .docker, .nginx].filter { isFeatureEnabled(for: $0) && !visibleItems.contains($0) }

        return List {
            if !systemItems.isEmpty {
                Section(languageManager.t("sidebar.systemTools")) {
                    ForEach(systemItems) { item in
                        tabRow(for: item)
                    }
                }
            }

            if !serviceItems.isEmpty {
                Section(languageManager.t("sidebar.serviceManagement")) {
                    ForEach(serviceItems) { item in
                        tabRow(for: item)
                    }
                }
            }

            Section(languageManager.t("sidebar.settings")) {
                tabRow(for: .settings)
                tabRow(for: .servers)
                Button {
                    showingPrimaryTabsCustomization = true
                } label: {
                    Label(languageManager.t("navigation.customizeTabs"), systemImage: "square.grid.2x2")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(languageManager.t("common.more"))
    }

    private var primaryTabCandidates: [NavigationItem] {
        [.processes, .ports, .logs, .configs, .launchagent, .docker, .nginx]
    }

    private var visiblePrimaryTabs: [NavigationItem] {
        normalizedPrimaryTabs(primaryNavigationItems, using: primaryTabCandidates.filter { isFeatureEnabled(for: $0) })
    }

    private func normalizedPrimaryTabs(_ items: [NavigationItem], using enabledItems: [NavigationItem]) -> [NavigationItem] {
        var result: [NavigationItem] = []

        for item in items where enabledItems.contains(item) && !result.contains(item) {
            result.append(item)
        }

        for item in enabledItems where result.count < 3 && !result.contains(item) {
            result.append(item)
        }

        return Array(result.prefix(3))
    }

    private func loadPrimaryNavigationItems() {
        guard !primaryNavigationItemsData.isEmpty,
              let rawValues = try? JSONDecoder().decode([String].self, from: primaryNavigationItemsData)
        else { return }

        let decodedItems = rawValues.compactMap(NavigationItem.init(rawValue:)).filter { primaryTabCandidates.contains($0) }
        if !decodedItems.isEmpty {
            primaryNavigationItems = normalizedPrimaryTabs(decodedItems, using: primaryTabCandidates)
        }
    }

    private func savePrimaryNavigationItems(_ items: [NavigationItem]) {
        let normalizedItems = normalizedPrimaryTabs(items, using: primaryTabCandidates)
        if let data = try? JSONEncoder().encode(normalizedItems.map(\.rawValue)) {
            primaryNavigationItemsData = data
        }
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
                                let status = ServerManager.shared.reachabilityStatuses[server.id]
                                Circle()
                                    .fill(status == nil ? Color.gray : (status == true ? Color.red : Color.green))
                                    .frame(width: 8, height: 8)

                                Text(server.name)
                                    .foregroundStyle(status == true ? .secondary : .primary)

                                if server.id == ServerManager.shared.selectedServerId {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .font(.body)
                                }
                            }
                        }
                        .disabled(ServerManager.shared.reachabilityStatuses[server.id] == true)
                    }

                    Divider()

                    Button {
                        showingServerManagement = true
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
                if isFeatureEnabled(for: .ports) { tabRow(for: .ports) }
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
        case .ports: return apiClient.features.ports ?? true
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

    private func shouldShowServerPicker(for item: NavigationItem) -> Bool {
        switch item {
        case .monitor, .processes, .ports, .logs, .configs, .launchagent, .docker, .nginx:
            return true
        case .settings, .servers, .more:
            return false
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
        case .ports: PortModuleView(selection: $selection)
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

struct PrimaryTabsCustomizationView: View {
    @Binding var selectedItems: [NavigationItem]
    let enabledItems: [NavigationItem]

    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(0..<3, id: \.self) { index in
                        Picker(slotTitle(for: index), selection: binding(for: index)) {
                            ForEach(availableItems(for: index)) { item in
                                Label(languageManager.t(item.title), systemImage: item.icon)
                                    .tag(item)
                            }
                        }
                    }
                } footer: {
                    Text(languageManager.t("navigation.customizeTabsFooter"))
                }
            }
            .navigationTitle(languageManager.t("navigation.customizeTabs"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .onAppear {
                selectedItems = normalizedItems(selectedItems)
            }
            .onChange(of: enabledItems) { _, _ in
                selectedItems = normalizedItems(selectedItems)
            }
        }
    }

    private func slotTitle(for index: Int) -> String {
        String(format: languageManager.t("navigation.tabSlot"), index + 2)
    }

    private func binding(for index: Int) -> Binding<NavigationItem> {
        Binding(
            get: {
                normalizedItems(selectedItems)[safe: index] ?? enabledItems.first ?? .processes
            },
            set: { newValue in
                var items = normalizedItems(selectedItems)
                guard items.indices.contains(index) else { return }
                if let existingIndex = items.firstIndex(of: newValue), existingIndex != index {
                    items[existingIndex] = items[index]
                }
                items[index] = newValue
                selectedItems = normalizedItems(items)
            }
        )
    }

    private func availableItems(for index: Int) -> [NavigationItem] {
        let currentItem = normalizedItems(selectedItems)[safe: index]
        return enabledItems.filter { item in
            item == currentItem || !selectedItems.contains(item)
        }
    }

    private func normalizedItems(_ items: [NavigationItem]) -> [NavigationItem] {
        var result: [NavigationItem] = []

        for item in items where enabledItems.contains(item) && !result.contains(item) {
            result.append(item)
        }

        for item in enabledItems where result.count < 3 && !result.contains(item) {
            result.append(item)
        }

        if result.isEmpty {
            return [.processes, .logs, .configs]
        }

        return Array(result.prefix(3))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
    @State private var showingAIHint = false
    @State private var hintTask: Task<Void, Never>? = nil

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

                // Input Bar (Redesigned)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        // Input Field
                        TextField(languageManager.t("terminal.placeholder"), text: $command, axis: .vertical)
                            .focused($isFieldFocused)
                            .lineLimit(1...5)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit {
                                if !isExecuting {
                                    executionTask = Task { await execute() }
                                }
                            }

                        // Action Buttons (Right Side)
                        HStack(spacing: 12) {
                            // AI Wand Button
                            Button {
                                if apiClient.aiConfig?.enabled ?? false {
                                    if command.isEmpty {
                                        showAIUsageHint()
                                    } else {
                                        translateAIContent()
                                    }
                                } else {
                                    showingAIDisabledAlert = true
                                }
                            } label: {
                                Image(systemName: "wand.and.sparkles")
                                    .font(.title3)
                                    .foregroundStyle(Color("AccentColor"))
                            }
                            .disabled(isTranslating)

                            // Execution Button
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
                    }
                    .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .background(.ultraThinMaterial)
                    Divider()
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if output.isEmpty {
                                VStack(spacing: 8) {
                                    if isTranslating {
                                        ProgressView().controlSize(.small)
                                        Text(languageManager.t("terminal.aiTranslating"))
                                    } else if showingAIHint {
                                        Image(systemName: "sparkles")
                                            .font(.title)
                                            .foregroundStyle(Color("AccentColor"))
                                        Text(languageManager.t("terminal.aiHint"))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                    } else {
                                        Text(languageManager.t("terminal.waiting"))
                                    }
                                }
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

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { clearTerminal() }) {
                        Image(systemName: "eraser")
                    }
                    .disabled(isExecuting)
                }
            }
            .sheet(isPresented: $showingManageCommands) {
                ManageCommandsView(commands: $commands)
            }
            .onAppear {
                loadCommands()
                // Auto focus the input field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFieldFocused = true
                }
            }
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
        isFieldFocused = false // Dismiss keyboard
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

    private func translateAIContent() {
        guard !command.isEmpty else { return }
        showingAIHint = false
        isTranslating = true
        let userInput = command

        Task {
            do {
                let strictPrompt = """
                Task: Convert the following natural language requirement into a single-line macOS bash command.
                Requirement: \(userInput)

                Mandatory Rule: Return ONLY the command text. No explanations. No markdown. No intro. No quotes.
                Command:
                """

                let stream = AIService.shared.analyzeStream(
                    prompt: strictPrompt,
                    systemPrompt: "You are a terminal command generator. Output ONLY raw bash commands.",
                    apiClient: apiClient
                )

                var fullCommand = ""
                for try await chunk in stream {
                    fullCommand += chunk
                    let currentCommand = fullCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        self.command = currentCommand
                    }
                }

                await MainActor.run {
                    withAnimation {
                        self.isTranslating = false
                        self.isFieldFocused = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.command = "Error: \(error.localizedDescription)"
                    withAnimation { self.isTranslating = false }
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
                let prompt = "Analyze this terminal output and provide explanations or suggestions in \(languageManager.aiResponseLanguage):\n\(output)\nPlease use Markdown formatting."
                let stream = AIService.shared.analyzeStream(prompt: prompt, systemPrompt: "You are a terminal output analyzer.", apiClient: apiClient)

                for try await chunk in stream {
                    await MainActor.run {
                        if self.aiAnalysis == nil {
                            self.aiAnalysis = ""
                            self.isAnalyzingOutput = false
                        }
                        self.aiAnalysis! += chunk
                    }
                }

                await MainActor.run {
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

    private func clearTerminal() {
        withAnimation {
            command = ""
            output = ""
            aiAnalysis = nil
            showingAIHint = false
        }
        isFieldFocused = true
    }

    private func showAIUsageHint() {
        hintTask?.cancel()
        withAnimation { showingAIHint = true }
        hintTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { showingAIHint = false }
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
                        .submitLabel(.done)
                        .onSubmit {
                            onConfirm()
                        }
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
