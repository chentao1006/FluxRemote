import SwiftUI

struct AISettingsView: View {
    @Bindable var languageManager: AppLanguageManager
    let initialAIConfig: AIConfig?
    var onSave: (AIConfig?) -> Void
    var apiClient: RemoteAPIClient

    @State private var localAIConfig: AIConfig
    @State private var isTesting = false
    @State private var testResult: String?

    init(
        languageManager: AppLanguageManager,
        initialAIConfig: AIConfig?,
        onSave: @escaping (AIConfig?) -> Void,
        apiClient: RemoteAPIClient
    ) {
        self.languageManager = languageManager
        self.initialAIConfig = initialAIConfig
        self.onSave = onSave
        self.apiClient = apiClient
        _localAIConfig = State(initialValue: initialAIConfig ?? AIConfig(
            enabled: false,
            url: "https://api.openai.com/v1",
            key: "",
            model: "gpt-4o",
            usePublicService: true,
            stream: true
        ))
    }
    
    var body: some View {
        Form {
            Section {
                Toggle(languageManager.t("settings.aiEnabled"), isOn: Binding(
                    get: { localAIConfig.enabled ?? false },
                    set: { localAIConfig.enabled = $0 }
                ))
                .tint(Color("AccentColor"))
                
                if localAIConfig.enabled ?? false {
                    Toggle(languageManager.t("settings.streamOutput"), isOn: Binding(
                        get: { localAIConfig.stream ?? true },
                        set: { localAIConfig.stream = $0 }
                    ))
                    .tint(Color("AccentColor"))
                }
            }
            
            if localAIConfig.enabled ?? false {
                Section {
                    Picker("", selection: Binding(
                        get: { localAIConfig.usePublicService ?? true },
                        set: { localAIConfig.usePublicService = $0 }
                    )) {
                        Text(languageManager.t("settings.publicService")).tag(true)
                        Text(languageManager.t("settings.customService")).tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(languageManager.t("settings.serviceMode"))
                }

                if localAIConfig.usePublicService ?? true {
                    Section {
                        Text(languageManager.t("settings.publicServiceDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField(languageManager.t("settings.url"), text: Binding(
                            get: { localAIConfig.url ?? "" },
                            set: { localAIConfig.url = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        SecureField(languageManager.t("settings.apiKey"), text: Binding(
                            get: { localAIConfig.key ?? "" },
                            set: { localAIConfig.key = $0 }
                        ))
                        #if os(iOS)
                        .textContentType(.password)
                        #endif
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        TextField(languageManager.t("settings.model"), text: Binding(
                            get: { localAIConfig.model ?? "" },
                            set: { localAIConfig.model = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    } header: {
                        Text(languageManager.t("settings.customServiceConfig"))
                    }
                }
                
                Section {
                    Button(action: testConnection) {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(languageManager.t("settings.testConnection"))
                                .foregroundStyle(Color("AccentColor"))
                        }
                    }
                    .disabled(isTesting)
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("✅") ? .green : .red)
                    }
                }
            }
        }
        .navigationTitle(languageManager.t("settings.aiConfig"))
        .onDisappear {
            persistLocalConfig()
        }
    }
    
    private func testConnection() {
        persistLocalConfig()
        isTesting = true
        testResult = nil
        
        Task {
            do {
                apiClient.aiConfig = localAIConfig
                
                let stream = AIService.shared.analyzeStream(
                    prompt: "Ping",
                    systemPrompt: "Respond with 'Pong'",
                    apiClient: apiClient
                )
                
                for try await _ in stream {
                    break
                }
                
                await MainActor.run {
                    testResult = "✅ " + languageManager.t("settings.connectionSuccess")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ " + error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    private func persistLocalConfig() {
        onSave(localAIConfig)
    }
}
