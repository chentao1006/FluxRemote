import SwiftUI

struct StatusBadge: View {
    let status: String
    var showLabel: Bool = false
    var size: CGFloat = 8
    @Environment(AppLanguageManager.self) private var languageManager
    
    var color: Color {
        let s = status.lowercased()
        if s == "running" || s == "enabled" || s == "online" || s == "active" || s == "loaded" {
            return .green
        } else if s == "stopped" || s == "disabled" || s == "offline" || s == "inactive" || s == "unloaded" || s == "exited" {
            return .red
        } else if s == "restarting" || s == "loading" {
            return .orange
        }
        return .gray
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .foregroundStyle(color)
                .font(.system(size: size))
            
            if showLabel {
                Text(languageManager.t("status.\(status.lowercased())"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MarkdownView: View {
    let text: String
    
    var body: some View {
        // iOS 15+ supports Markdown in Text
        Text(text)
            .font(.system(.subheadline, design: .default))
            .lineSpacing(4)
    }
}

struct AIAnalysisCard: View {
    let analysis: String?
    let isAnalyzing: Bool
    var onDismiss: () -> Void
    @Environment(AppLanguageManager.self) private var languageManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(languageManager.t("monitor.aiAnalysisTitle"), systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            if isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(languageManager.t("common.analyzing"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if let analysis = analysis {
                ScrollView {
                    MarkdownView(text: analysis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }
            
            if !isAnalyzing && analysis != nil {
                HStack {
                    Spacer()
                    Text(languageManager.t("monitor.aiAdvice"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}


struct AIAnalyzeView: View {
    let originalContent: String
    let contextInfo: String
    
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var analysisResult: String?
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(header: Text(languageManager.t("monitor.aiAnalysisTitle"))) {
                if let result = analysisResult {
                    ScrollView {
                        MarkdownView(text: result)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 400)
                } else if isProcessing {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(languageManager.t("common.analyzing"))
                            .padding(.leading, 8)
                        Spacer()
                    }
                } else {
                    Text(languageManager.t("monitor.aiAnalysisPrompt"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(languageManager.t("common.aiAnalyze"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) { Image(systemName: "xmark") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: analyze) {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkle.text.clipboard")
                    }
                }
                .disabled(isProcessing)
            }
        }
        .onAppear {
            if analysisResult == nil { analyze() }
        }
    }
    
    func analyze() {
        guard !originalContent.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let prompt = "Explain the following configuration and provide optimization suggestions in \(languageManager.aiResponseLanguage):\n\nContext:\n\(contextInfo)\n\nContent:\n\(originalContent)\n\nUse Markdown formatting for the response."
                let response: AIResponse = try await apiClient.request("/api/ai", method: "POST", body: ["prompt": prompt])
                await MainActor.run {
                    self.analysisResult = response.data
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
}

struct AIAssistView: View {
    let originalContent: String
    let contextInfo: String
    var onApply: (String) -> Void
    
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var prompt: String = ""
    @State private var generatedContent: String?
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(header: Text(languageManager.t("common.aiGenerate"))) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 120)
                    .overlay(
                        Group {
                            if prompt.isEmpty {
                                Text(languageManager.t("monitor.aiPromptPlaceholder"))
                                    .foregroundStyle(.placeholder)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
            }
            
            if isProcessing {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(languageManager.t("common.analyzing"))
                            .padding(.leading, 8)
                        Spacer()
                    }
                }
            }
            
            if let generated = generatedContent {
                Section(header: Text(languageManager.t("monitor.generatedPreview"))) {
                    ScrollView {
                        Text(generated)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.02))
                    }
                    .frame(maxHeight: 300)
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(languageManager.t("common.aiGenerate"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) { Image(systemName: "xmark") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if generatedContent != nil {
                    Button(action: { 
                        onApply(generatedContent!)
                        dismiss()
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                } else {
                    Button(action: generate) {
                        if isProcessing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.sparkles")
                        }
                    }
                    .disabled(isProcessing || prompt.isEmpty)
                }
            }
        }
    }
    
    func generate() {
        guard !prompt.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let systemPrompt = """
                You are a configuration expert. Based on the user's requirements, modify the provided configuration content.
                Return ONLY the full modified content. Do not include any explanations or markdown code blocks like ```nginx.
                The response must be the final text to be saved to the file.
                
                Context:
                \(contextInfo)
                """
                
                let userPrompt = """
                Requirements: \(prompt)
                
                Current Content:
                \(originalContent)
                """
                
                let response: AIResponse = try await apiClient.request("/api/ai", method: "POST", body: [
                    "prompt": userPrompt,
                    "system_prompt": systemPrompt
                ])
                
                await MainActor.run {
                    self.generatedContent = response.data
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
}
