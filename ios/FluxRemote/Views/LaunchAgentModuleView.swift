import SwiftUI

struct LaunchAgentModuleView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var launchAgents: [LaunchAgentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedAgent: LaunchAgentItem?
    @State private var loadingAction: [String: String] = [:] // [agent.path: action]
    @State private var searchText = ""
    @State private var showingAddAgent = false
    @State private var showingSudoPrompt = false
    @State private var sudoPassword = ""
    @State private var pendingAction: (String, String)? // (action, path)
    @State private var activeAlert: LaunchAgentAlert?
    
    enum LaunchAgentAlert: Identifiable {
        case delete(LaunchAgentItem)
        case error(String)
        
        var id: String {
            switch self {
            case .delete(let item): return "delete-\(item.path)"
            case .error(let msg): return "error-\(msg)"
            }
        }
    }
    
    var filteredAgents: [LaunchAgentItem] {
        if searchText.isEmpty { return launchAgents }
        return launchAgents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ZStack {
            List {
                if let error = errorMessage {
                    ContentUnavailableView(languageManager.t("common.error"), systemImage: "wifi.exclamationmark.fill", description: Text(error))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if launchAgents.isEmpty && !isLoading {
                    ContentUnavailableView(languageManager.t("launchagent.noAgents"), systemImage: "circle.grid.3x3")
                } else {
                    ForEach(filteredAgents) { agent in
                        HStack {
                            Button {
                                selectedAgent = agent
                            } label: {
                                HStack(spacing: 12) {
                                    StatusBadge(status: agent.isLoaded ? "running" : "stopped", size: 14)
                                    
                                    Text(agent.name.replacingOccurrences(of: ".plist", with: ""))
                                        .font(.headline)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            HStack(spacing: 10) {
                                actionButton(
                                    icon: agent.isLoaded ? "stop" : "play",
                                    color: agent.isLoaded ? .orange : .green,
                                    isLoading: loadingAction[agent.path] == (agent.isLoaded ? "unload" : "load")
                                ) {
                                    loadingAction[agent.path] = agent.isLoaded ? "unload" : "load"
                                    await performAction(agent.isLoaded ? "unload" : "load", path: agent.path)
                                    loadingAction[agent.path] = nil
                                }

                                actionButton(
                                    icon: "arrow.clockwise",
                                    color: .blue,
                                    isLoading: loadingAction[agent.path] == "reload"
                                ) {
                                    loadingAction[agent.path] = "reload"
                                    await performAction("reload", path: agent.path)
                                    loadingAction[agent.path] = nil
                                }

                                actionButton(
                                    icon: "trash",
                                    color: .red,
                                    isLoading: loadingAction[agent.path] == "delete"
                                ) {
                                    activeAlert = .delete(agent)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            
            if isLoading && launchAgents.isEmpty {
                LoadingView()
            }
        }
        .navigationTitle(languageManager.t("launchagent.title"))
        .searchable(text: $searchText, prompt: languageManager.t("configs.searchPlaceholder"))
        .refreshable {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await fetchData() }
                group.addTask { try? await Task.sleep(for: .milliseconds(600)) }
                await group.waitForAll()
            }
        }
        .onAppear {
            Task { await fetchData() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddAgent = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAgent) {
            NavigationStack {
                AddAgentView { name, content in
                    Task {
                        await createAgent(name: name, content: content)
                    }
                }
            }
        }
        .sheet(item: $selectedAgent) { agent in
            NavigationStack {
                LaunchAgentDetailView(agent: agent, isNew: !launchAgents.contains(where: { $0.path == agent.path })) {
                    await fetchData()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { selectedAgent = nil }) { Image(systemName: "xmark") }
                    }
                }
            }
        }
        .sheet(isPresented: $showingSudoPrompt) {
            SudoPasswordView(password: $sudoPassword) {
                Task {
                    if let pending = pendingAction {
                        await performAction(pending.0, path: pending.1)
                    }
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .delete(let agent):
                return Alert(
                    title: Text(languageManager.t("launchagent.deleteConfirmTitle")),
                    message: Text(String.localizedStringWithFormat(languageManager.t("launchagent.deleteConfirmMessage"), agent.name)),
                    primaryButton: .destructive(Text(languageManager.t("launchagent.delete"))) {
                        loadingAction[agent.path] = "delete"
                        Task {
                            await performAction("delete", path: agent.path)
                            loadingAction[agent.path] = nil
                        }
                    },
                    secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                )
            case .error(let message):
                return Alert(
                    title: Text(languageManager.t("common.error")),
                    message: Text(message),
                    dismissButton: .default(Text(languageManager.t("common.ok")))
                )
            }
        }
    }
    
    func fetchData() async {
        do {
            let response: LaunchAgentResponse = try await apiClient.request("/api/launchagent/list")
            await MainActor.run {
                self.launchAgents = response.data
                self.errorMessage = nil
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func createAgent(name: String, content: String) async {
        let firstPath = launchAgents.first?.path ?? "/Users/chentao/Library/LaunchAgents/placeholder.plist"
        let basePath = firstPath.components(separatedBy: "/").dropLast().joined(separator: "/") + "/"
        let fullName = name.hasSuffix(".plist") ? name : name + ".plist"
        let path = basePath + fullName
        
        do {
            let body: [String: Any] = ["action": "write", "filePath": path, "content": content]
            let _: ActionResponse = try await apiClient.request("/api/launchagent/action", method: "POST", body: body)
            await fetchData()
            await MainActor.run {
                self.showingAddAgent = false
                // Select the new one to show details
                self.selectedAgent = LaunchAgentItem(
                    name: fullName,
                    label: fullName.replacingOccurrences(of: ".plist", with: ""),
                    path: path,
                    isLoaded: false,
                    size: Int64(content.utf8.count),
                    mtime: Int64(Date().timeIntervalSince1970 * 1000)
                )
            }
        } catch {
            print("Create agent failed: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func performAction(_ action: String, path: String) async {
        do {
            var body: [String: Any] = ["action": action, "filePath": path]
            if !sudoPassword.isEmpty {
                body["sudoPassword"] = sudoPassword
            }
            let _: ActionResponse = try await apiClient.request("/api/launchagent/action", method: "POST", body: body)
            await MainActor.run {
                self.sudoPassword = ""
                self.pendingAction = nil
            }
            await fetchData()
        } catch {
            print("Action failed: \(error)")
            let errorMsg = error.localizedDescription
            await MainActor.run {
                let msg = errorMsg.lowercased()
                let isPermissionError = msg.contains("sudo_required") || msg.contains("permission_denied") || msg.contains("permission denied") || msg.contains("eacces") || msg.contains("eperm")
                
                if isPermissionError && self.sudoPassword.isEmpty {
                    self.pendingAction = (action, path)
                    self.showingSudoPrompt = true
                } else if msg.contains("sudo_password_incorrect") || msg.contains("incorrect password") || msg.contains("auth failed") {
                    self.activeAlert = .error(languageManager.t("common.passwordIncorrect"))
                    self.sudoPassword = ""
                    self.pendingAction = nil
                } else {
                    self.activeAlert = .error(errorMsg)
                    self.pendingAction = nil
                }
            }
        }
    }
    
    private func actionButton(icon: String, color: Color, isLoading: Bool = false, action: @escaping () async -> Void) -> some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(width: 32, height: 32)
            } else {
                Button {
                    Task { await action() }
                } label: {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(color)
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AddAgentView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var name: String = ""
    @State private var content: String = ""
    var onAdd: (String, String) -> Void
    
    @State private var showingAIAnalyze = false
    @State private var showingAIAssist = false
    
    init(onAdd: @escaping (String, String) -> Void) {
        self.onAdd = onAdd
        _content = State(initialValue: """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/executable</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
""")
    }
    
    var body: some View {
        Form {
            Section(header: Text(languageManager.t("launchagent.newConfigPrompt"))) {
                TextField("com.example.app.plist", text: $name)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: name) { oldValue, newValue in
                        let newLabel = newValue.replacingOccurrences(of: ".plist", with: "")
                        if let range = content.range(of: "<key>Label</key>\\s*<string>.*?</string>", options: .regularExpression) {
                            let oldPart = content[range]
                            if let stringRange = oldPart.range(of: "<string>.*?</string>", options: .regularExpression) {
                                let newPart = oldPart.replacingCharacters(in: stringRange, with: "<string>\(newLabel)</string>")
                                content.replaceSubrange(range, with: newPart)
                            }
                        }
                    }
            }
            
            Section(header: Text(languageManager.t("launchagent.configContent"))) {
                TextEditor(text: $content)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(minHeight: 300)
            }
        }
        .navigationTitle(languageManager.t("launchagent.addConfig"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { dismiss() }) { Image(systemName: "xmark") }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(action: { showingAIAnalyze = true }) {
                    Image(systemName: "sparkle.text.clipboard")
                        .foregroundStyle(.purple)
                }
                
                Button(action: { showingAIAssist = true }) {
                    Image(systemName: "wand.and.sparkles")
                        .foregroundStyle(.purple)
                }
                
                Button(action: {
                    onAdd(name, content)
                    dismiss()
                }) {
                    Image(systemName: "checkmark")
                }
                .disabled(name.isEmpty)
            }
        }
        .sheet(isPresented: $showingAIAnalyze) {
            NavigationStack {
                AIAnalyzeView(originalContent: content, contextInfo: "Action: Creating New macOS LaunchAgent Plist")
            }
        }
        .sheet(isPresented: $showingAIAssist) {
            NavigationStack {
                AIAssistView(originalContent: content, contextInfo: "Action: Creating New macOS LaunchAgent Plist") { newContent in
                    self.content = newContent
                }
            }
        }
    }
}

struct LaunchAgentDetailView: View {
    let agent: LaunchAgentItem
    let isNew: Bool
    var onSave: () async -> Void = {}
    
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showingError = false
    @State private var showingSudoPrompt = false
    @State private var sudoPassword = ""
    @State private var showingAIAnalyze = false
    @State private var showingAIAssist = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(agent.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospaced()
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.05))
            
            if isLoading {
                LoadingView()
            } else if let error = errorMessage {
                ContentUnavailableView(languageManager.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
            TextEditor(text: $content)
                .font(.system(.caption2, design: .monospaced))
                .padding(4)
                Spacer()
            }
        }
        .overlay(alignment: .bottom) {
            if !isLoading && !content.isEmpty {
                HStack(spacing: 12) {
                    Button(action: { showingAIAnalyze = true }) {
                        Label(languageManager.t("common.aiAnalyze"), systemImage: "sparkle.text.clipboard")
                            .font(.system(.subheadline, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                            .shadow(color: Color.purple.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    
                    Button(action: { showingAIAssist = true }) {
                        Label(languageManager.t("common.aiGenerate"), systemImage: "wand.and.sparkles")
                            .font(.system(.subheadline, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                            .shadow(color: Color.purple.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showingAIAnalyze) {
            NavigationStack {
                AIAnalyzeView(originalContent: content, contextInfo: "File Path: \(agent.path)\nType: macOS LaunchAgent Plist")
            }
        }
        .sheet(isPresented: $showingAIAssist) {
            NavigationStack {
                AIAssistView(originalContent: content, contextInfo: "File Path: \(agent.path)\nType: macOS LaunchAgent Plist") { newContent in
                    self.content = newContent
                }
            }
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { Task { await saveConfig() } }) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .disabled(isSaving || isLoading)
            }
        }
        .onAppear {
            Task { await fetchContent() }
        }
        .alert(languageManager.t("common.error"), isPresented: $showingError) {
            Button(languageManager.t("common.ok"), role: .cancel) { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showingSudoPrompt) {
            SudoPasswordView(password: $sudoPassword) {
                Task { await saveConfig() }
            }
        }
    }
    
    func fetchContent() async {
        if isNew {
            let label = agent.name.replacingOccurrences(of: ".plist", with: "")
            self.content = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(label)</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/executable</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
"""
            self.isLoading = false
            return
        }
        
        isLoading = true
        do {
            let response: ActionResponse = try await apiClient.request("/api/launchagent/action", method: "POST", body: ["action": "read", "filePath": agent.path])
            await MainActor.run {
                self.content = response.data ?? ""
                self.isLoading = false
            }
        } catch {
            print("Fetch agent plist failed: \(error)")
            await MainActor.run { 
                self.errorMessage = error.localizedDescription
                self.isLoading = false 
            }
        }
    }
    
    func saveConfig() async {
        isSaving = true
        errorMessage = nil
        do {
            var body: [String: Any] = ["action": "write", "filePath": agent.path, "content": content]
            if !sudoPassword.isEmpty {
                body["sudoPassword"] = sudoPassword
            }
            let _: ActionResponse = try await apiClient.request("/api/launchagent/action", method: "POST", body: body)
            await onSave()
            await MainActor.run { 
                self.isSaving = false
                self.sudoPassword = ""
                dismiss()
            }
        } catch {
            print("Save agent plist failed: \(error)")
            let errorMsg = error.localizedDescription
            await MainActor.run { 
                self.isSaving = false 
            }
        }
    }
}

#Preview {
    NavigationStack {
        LaunchAgentModuleView()
            .environment(RemoteAPIClient())
    }
}

