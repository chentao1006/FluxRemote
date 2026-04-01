import SwiftUI

struct AISettingsView: View {
    @Bindable var languageManager: AppLanguageManager
    @Binding var aiConfig: AIConfig?
    var onSave: () -> Void
    
    var apiClient: RemoteAPIClient
    @State private var isTesting = false
    @State private var testResult: String?
    
    var body: some View {
        Form {
            Section {
                Toggle(languageManager.t("settings.aiEnabled"), isOn: Binding(
                    get: { aiConfig?.enabled ?? false },
                    set: { 
                        if aiConfig == nil {
                            aiConfig = AIConfig(enabled: $0, url: "https://api.openai.com/v1", key: "", model: "gpt-4o", usePublicService: true, stream: true)
                        } else {
                            aiConfig?.enabled = $0
                        }
                        onSave()
                    }
                ))
                .tint(Color("AccentColor"))
                
                if aiConfig?.enabled ?? false {
                    Toggle(languageManager.t("settings.streamOutput"), isOn: Binding(
                        get: { aiConfig?.stream ?? true },
                        set: { 
                            if aiConfig == nil {
                                aiConfig = AIConfig(enabled: true, url: "https://api.openai.com/v1", key: "", model: "gpt-4o", usePublicService: true, stream: $0)
                            } else {
                                aiConfig?.stream = $0
                            }
                            onSave()
                        }
                    ))
                    .tint(Color("AccentColor"))
                }
            }
            
            if aiConfig?.enabled ?? false {
                Section {
                    Picker("", selection: Binding(
                        get: { aiConfig?.usePublicService ?? true },
                        set: { aiConfig?.usePublicService = $0; onSave() }
                    )) {
                        Text(languageManager.t("settings.publicService")).tag(true)
                        Text(languageManager.t("settings.customService")).tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(languageManager.t("settings.serviceMode"))
                }

                if aiConfig?.usePublicService ?? true {
                    Section {
                        Text(languageManager.t("settings.publicServiceDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField(languageManager.t("settings.url"), text: Binding(
                            get: { aiConfig?.url ?? "" },
                            set: { aiConfig?.url = $0; onSave() }
                        ))
                        SecureField(languageManager.t("settings.apiKey"), text: Binding(
                            get: { aiConfig?.key ?? "" },
                            set: { aiConfig?.key = $0; onSave() }
                        ))
                        #if os(iOS)
                        .textContentType(.password)
                        #endif
                        TextField(languageManager.t("settings.model"), text: Binding(
                            get: { aiConfig?.model ?? "" },
                            set: { aiConfig?.model = $0; onSave() }
                        ))
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
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                // Temporarily update RemoteAPIClient's aiConfig for testing custom service
                // and then restore it if necessary, but actually AIService.shared uses the one in RemoteAPIClient.
                // Since this view updates the Binding<AIConfig?> (which references serverSettings in parent),
                // we should make sure RemoteAPIClient has the latest config for testing.
                apiClient.aiConfig = aiConfig
                
                let stream = AIService.shared.analyzeStream(
                    prompt: "Ping",
                    systemPrompt: "Respond with 'Pong'",
                    apiClient: apiClient
                )
                
                for try await _ in stream {
                    // Just need one chunk to verify connection
                    break
                }
                
                await MainActor.run {
                    testResult = "✅ " + languageManager.t("settings.connectionSuccess")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ " + (error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}
