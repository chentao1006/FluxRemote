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
    
    var body: some View {
        List {
            if isLoading && launchAgents.isEmpty {
                HStack {
                    Spacer()
                    ProgressView(languageManager.t("launchagent.loading"))
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if let error = errorMessage {
                ContentUnavailableView(languageManager.t("common.error"), systemImage: "wifi.exclamationmark.fill", description: Text(error))
            } else {
                ForEach(launchAgents) { agent in
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            selectedAgent = agent
                        } label: {
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(agent.isLoaded ? Color.green : Color.red)
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name.replacingOccurrences(of: ".plist", with: ""))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        HStack(spacing: 16) {
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

                            Spacer()

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
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle(languageManager.t("launchagent.title"))
        .refreshable {
            await fetchData()
        }
        .onAppear {
            Task { await fetchData() }
        }
        .sheet(item: $selectedAgent) { agent in
            NavigationStack {
                LaunchAgentDetailView(agent: agent)
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
                        .font(.caption)
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

struct LaunchAgentDetailView: View {
    let agent: LaunchAgentItem
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView().padding()
            } else if let error = errorMessage {
                ContentUnavailableView(languageManager.t("common.error"), systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                TextEditor(text: $content)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(4)
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
    }
    
    func fetchContent() async {
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
        do {
            // Reusing configs API for saving plist
            let _: ActionResponse = try await apiClient.request("/api/configs", method: "POST", body: ["path": agent.path, "content": content])
            await MainActor.run { self.isSaving = false }
        } catch {
            print("Save agent plist failed: \(error)")
            await MainActor.run { self.isSaving = false }
        }
    }
}

#Preview {
    NavigationStack {
        LaunchAgentModuleView()
            .environment(RemoteAPIClient())
    }
}
