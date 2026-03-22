import SwiftUI

struct LaunchAgentModuleView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var launchAgents: [LaunchAgentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedAgent: LaunchAgentItem?
    @State private var loadingAction: [String: String] = [:] // [agent.path: action]
    @State private var confirmDeleteAgent: LaunchAgentItem? = nil
    @State private var searchText = ""
    @State private var showingAddAgent = false
    
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
                                    isLoading: loadingAction[agent.path] == "remove"
                                ) {
                                    confirmDeleteAgent = agent
                                }
                                .alert(item: $confirmDeleteAgent) { agent in
                                    Alert(
                                        title: Text(languageManager.t("launchagent.deleteConfirmTitle")),
                                        message: Text(String.localizedStringWithFormat(languageManager.t("launchagent.deleteConfirmMessage"), agent.name)),
                                        primaryButton: .destructive(Text(languageManager.t("launchagent.delete"))) {
                                            loadingAction[agent.path] = "remove"
                                            Task {
                                                await performAction("remove", path: agent.path)
                                                loadingAction[agent.path] = nil
                                            }
                                        },
                                        secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                                    )
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
            await fetchData()
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
                AddAgentNameView { name in
                    let firstPath = launchAgents.first?.path ?? "/Users/chentao/Library/LaunchAgents/placeholder.plist"
                    let basePath = firstPath.components(separatedBy: "/").dropLast().joined(separator: "/") + "/"
                    let fullName = name.hasSuffix(".plist") ? name : name + ".plist"
                    
                    selectedAgent = LaunchAgentItem(
                        name: fullName,
                        label: fullName.replacingOccurrences(of: ".plist", with: ""),
                        path: basePath + fullName,
                        isLoaded: false,
                        size: 0,
                        mtime: Int64(Date().timeIntervalSince1970 * 1000)
                    )
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
    }
    
    func fetchData() async {
        do {
            let response: LaunchAgentResponse = try await apiClient.request("/api/launchagent/list")
            await MainActor.run {
                self.launchAgents = response.data
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func performAction(_ action: String, path: String) async {
        do {
            let _: ActionResponse = try await apiClient.request("/api/launchagent/action", method: "POST", body: ["action": action, "filePath": path])
            await fetchData()
        } catch {
            print("Action failed: \(error)")
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

struct AddAgentNameView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var name: String = ""
    var onAdd: (String) -> Void
    
    var body: some View {
        Form {
            Section {
                TextField(languageManager.t("launchagent.newConfigPrompt"), text: $name)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle(languageManager.t("launchagent.addConfig"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(languageManager.t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(languageManager.t("common.add")) {
                    onAdd(name)
                    dismiss()
                }
                .disabled(name.isEmpty)
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
            }
            Spacer()
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
            let response: ConfigResponse = try await apiClient.request("/api/configs", method: "POST", body: ["action": "read", "id": agent.path])
            await MainActor.run {
                self.content = response.content ?? ""
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
            // Reusing configs API for saving plist
            let _: ActionResponse = try await apiClient.request("/api/configs", method: "POST", body: ["action": "write", "id": agent.path, "content": content])
            await onSave()
            await MainActor.run { 
                self.isSaving = false
                dismiss()
            }
        } catch {
            print("Save agent plist failed: \(error)")
            await MainActor.run { 
                self.errorMessage = error.localizedDescription
                self.showingError = true
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
