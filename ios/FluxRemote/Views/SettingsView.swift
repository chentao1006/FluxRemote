import SwiftUI

struct SettingsView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var serverSettings: ServerSettings?
    @State private var isLoading = true
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var lastSavedTime: Date?
    
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(version) (\(languageManager.t("app.build_type")))"
    }
    
    var body: some View {
        Form {
            if isLoading {
                ProgressView(languageManager.t("common.loading"))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                Section(header: Text(languageManager.t("settings.connection"))) {
                    NavigationLink(destination: ServerListView()) {
                        LabeledContent(languageManager.t("settings.server"), value: ServerManager.shared.selectedServer?.name ?? languageManager.t("common.none"))
                    }
                    LabeledContent(languageManager.t("settings.version"), value: serverSettings?.version ?? languageManager.t("common.unknown"))
                }
                
                Section(languageManager.t("settings.account")) {
                    LabeledContent(languageManager.t("settings.currentUser"), value: apiClient.currentUser ?? languageManager.t("common.unknown"))
                    Button(languageManager.t("settings.logout"), role: .destructive) {
                        apiClient.logout()
                    }
                }
                
                Section(header: Text(languageManager.t("settings.featureControl"))) {
                    Toggle(languageManager.t("sidebar.monitor"), isOn: featureBinding(\.monitor))
                    Toggle(languageManager.t("sidebar.processes"), isOn: featureBinding(\.processes))
                    Toggle(languageManager.t("sidebar.logs"), isOn: featureBinding(\.logs))
                    Toggle(languageManager.t("sidebar.configs"), isOn: featureBinding(\.configs))
                    Toggle(languageManager.t("sidebar.launchagent"), isOn: featureBinding(\.launchagent))
                    Toggle(languageManager.t("sidebar.docker"), isOn: featureBinding(\.docker))
                    Toggle(languageManager.t("sidebar.nginx"), isOn: featureBinding(\.nginx))
                }
                
                Section(header: Text(languageManager.t("settings.aiConfig"))) {
                    NavigationLink(destination: AISettingsView(
                        languageManager: languageManager,
                        aiConfig: Binding(
                            get: { serverSettings?.ai },
                            set: { serverSettings?.ai = $0 }
                        ),
                        onSave: { triggerAutoSave() },
                        apiClient: apiClient
                    )) {
                        HStack {
                            Text(languageManager.t("settings.aiConfig"))
                            Spacer()
                            if !(serverSettings?.ai?.enabled ?? false) {
                                Text(languageManager.t("common.off"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(serverSettings?.ai?.usePublicService ?? true ? languageManager.t("settings.publicService") : (serverSettings?.ai?.model ?? languageManager.t("common.none")))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text(languageManager.t("settings.language"))) {
                    Picker(languageManager.t("settings.language"), selection: Bindable(languageManager).selectedLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayNameKey == "common.systemDefault" ? languageManager.t(lang.displayNameKey) : lang.displayNameKey).tag(lang)
                        }
                    }
                }
                
                Section {
                    VStack(spacing: 8) {
                        Text(appVersionString)
                    }
                    .frame(maxWidth: .infinity)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .tint(Color("AccentColor"))
        .refreshable {
            await fetchData()
        }
        .navigationTitle(languageManager.t("sidebar.settings"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else if let _ = lastSavedTime {
                    Text(languageManager.t("common.saveSuccess"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            Task { await fetchData() }
        }
    }
    
    private func featureBinding(_ keyPath: WritableKeyPath<FeatureToggles, Bool?>) -> Binding<Bool> {
        Binding(
            get: { serverSettings?.features?[keyPath: keyPath] ?? true },
            set: { 
                serverSettings?.features?[keyPath: keyPath] = $0
                triggerAutoSave()
            }
        )
    }
    
    private func triggerAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
            guard !Task.isCancelled else { return }
            await saveSettings()
        }
    }
    
    func fetchData() async {
        if serverSettings == nil {
            isLoading = true
        }
        do {
            let response: ServerSettingsResponse = try await apiClient.request("/api/settings")
            await MainActor.run {
                self.serverSettings = response.data
                self.isLoading = false
            }
        } catch {
            print("Fetch settings failed: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func saveSettings() async {
        guard let settings = serverSettings else { return }
        await MainActor.run { isSaving = true }
        do {
            let _: ActionResponse = try await apiClient.request("/api/settings", method: "POST", encodableBody: settings)
            await MainActor.run {
                if let feats = settings.features {
                    apiClient.features = feats
                }
                apiClient.aiConfig = settings.ai
                self.isSaving = false
                self.lastSavedTime = Date()
            }
        } catch {
            print("Auto-save failed: \(error)")
            await MainActor.run {
                self.isSaving = false
            }
        }
    }
}
