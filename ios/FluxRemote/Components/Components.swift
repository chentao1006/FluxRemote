import SwiftUI

struct LoadingView: View {
    let message: String?
    @Environment(AppLanguageManager.self) private var languageManager
    
    init(_ message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message ?? languageManager.t("common.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    LoadingView()
        .environment(AppLanguageManager())
}

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
    @Environment(AppLanguageManager.self) private var languageManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private struct MarkdownBlock: Identifiable, Equatable {
        let id: Int
        let type: BlockType
        
        static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
            lhs.id == rhs.id
        }

        enum BlockType {
            case header(Int, String)
            case list(String)
            case table([[String]])
            case code(String)
            case paragraph(String)
        }
    }
    
    private var blocks: [MarkdownBlock] {
        var parsedBlocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        var lineIndex = 0
        
        while lineIndex < lines.count {
            let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { 
                lineIndex += 1
                continue 
            }
            
            // 1. Code Block
            if line.hasPrefix("```") {
                var content = ""
                lineIndex += 1
                while lineIndex < lines.count {
                    let nextLine = lines[lineIndex]
                    if nextLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        lineIndex += 1
                        break
                    }
                    content += lines[lineIndex] + "\n"
                    lineIndex += 1
                }
                parsedBlocks.append(MarkdownBlock(id: i, type: .code(content.trimmingCharacters(in: .newlines))))
                i += 1
            } else if (line.starts(with: "|") || line.contains("|")) && (lineIndex + 1 < lines.count) && lines[lineIndex+1].contains("-") && lines[lineIndex+1].contains("|") {
                var rows: [[String]] = []
                func parseRow(_ r: String) -> [String] {
                    r.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                rows.append(parseRow(line))
                lineIndex += 2 // skip header and separator
                while lineIndex < lines.count && (lines[lineIndex].starts(with: "|") || lines[lineIndex].contains("|")) {
                    rows.append(parseRow(lines[lineIndex]))
                    lineIndex += 1
                }
                parsedBlocks.append(MarkdownBlock(id: i, type: .table(rows)))
                i += 1
            } else if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let content = line.drop { $0 == "#" || $0 == " " }
                parsedBlocks.append(MarkdownBlock(id: i, type: .header(level, String(content))))
                i += 1
                lineIndex += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                parsedBlocks.append(MarkdownBlock(id: i, type: .list(String(line.dropFirst(2)))))
                i += 1
                lineIndex += 1
            } else {
                parsedBlocks.append(MarkdownBlock(id: i, type: .paragraph(line)))
                i += 1
                lineIndex += 1
            }
        }
        return parsedBlocks
    }
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.type {
        case .header(let level, let content):
            Text(LocalizedStringKey(content))
                .font(.system(size: level == 1 ? 22 : level == 2 ? 18 : 16, weight: .bold))
                .padding(.top, 4)
        case .list(let content):
            HStack(alignment: .top, spacing: 8) {
                Text("•").fontWeight(.bold).foregroundColor(.secondary)
                Text(LocalizedStringKey(content)).font(.subheadline)
            }
        case .code(let content):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
            }
        case .table(let rows):
            if #available(iOS 16.0, *) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(0..<rows.count, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(0..<rows[rowIndex].count, id: \.self) { colIndex in
                                Text(LocalizedStringKey(rows[rowIndex][colIndex]))
                                    .font(.system(size: 13, weight: rowIndex == 0 ? .bold : .regular))
                                    .padding(.vertical, 4)
                            }
                        }
                        if rowIndex == 0 { Divider() }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
            }
        case .paragraph(let content):
            Text(LocalizedStringKey(content))
                .font(.subheadline)
                .lineSpacing(4)
        }
    }
}

struct AIAnalysisCard: View {
    let analysis: String?
    let isAnalyzing: Bool
    var onDismiss: () -> Void
    @Environment(AppLanguageManager.self) private var languageManager
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label(languageManager.t("monitor.aiAnalysisTitle"), systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color("AccentColor"))
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
                    VStack(spacing: 12) {
                        Image(systemName: originalContent.isEmpty ? "hourglass" : "sparkles")
                            .font(.system(size: 32))
                            .foregroundStyle(Color("AccentColor").opacity(0.5))
                            .padding(.bottom, 8)
                        
                        Text(originalContent.isEmpty 
                             ? languageManager.t("common.loading") 
                             : languageManager.t("monitor.aiAnalysisReady"))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
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
        analysisResult = nil
        
        Task {
            do {
                let isLog = contextInfo.lowercased().contains("log")
                let systemPrompt = isLog 
                    ? "You are a systems expert. Analyze the provided logs to diagnose issues and provide solutions."
                    : "You are a configuration expert. Explain segments and suggest optimizations."
                
                let prompt = isLog
                    ? "Analyze the following logs and provide diagnosis or suggestions in \(languageManager.aiResponseLanguage):\n\nContext:\n\(contextInfo)\n\nContent:\n\(originalContent)\n\nUse Markdown formatting for the response."
                    : "Explain the following configuration and provide optimization suggestions in \(languageManager.aiResponseLanguage):\n\nContext:\n\(contextInfo)\n\nContent:\n\(originalContent)\n\nUse Markdown formatting for the response."
                
                let stream = AIService.shared.analyzeStream(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    apiClient: apiClient
                )
                
                for try await chunk in stream {
                    await MainActor.run {
                        if self.analysisResult == nil {
                            self.analysisResult = ""
                            self.isProcessing = false
                        }
                        self.analysisResult! += chunk
                    }
                }
                
                await MainActor.run {
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
    @State private var showingApplyConfirmation = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Form {
            Section(header: Text(languageManager.t("common.aiGenerate"))) {
                TextEditor(text: $prompt)
                    .focused($isFieldFocused)
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
                        Text(languageManager.t("common.generating"))
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
                    Button(action: { showingApplyConfirmation = true }) {
                        Text(languageManager.t("common.apply"))
                            .fontWeight(.bold)
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
        .alert(languageManager.t("common.confirmApply"), isPresented: $showingApplyConfirmation) {
            Button(languageManager.t("common.apply"), role: .destructive) {
                if let generated = generatedContent {
                    onApply(generated)
                    dismiss()
                }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(languageManager.t("common.confirmApplyDesc"))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isFieldFocused = true
            }
        }
    }
    
    func generate() {
        guard !prompt.isEmpty else { return }
        isFieldFocused = false
        isProcessing = true
        errorMessage = nil
        generatedContent = nil
        
        Task {
            do {
                let systemPrompt = """
                You are a professional system configuration assistant. Based on the user's requirements, modify the provided configuration content.
                CRITICAL: Return ONLY the full modified content, which will be saved directly to a file.
                NO explanations, NO greetings, NO introductory/concluding text.
                Do NOT use any Markdown code block delimiters (e.g., ```nginx or ```).
                The response should be 100% ready-to-use raw file content.
                
                Context:
                \(contextInfo)
                """
                
                let userPrompt = """
                Requirements: \(prompt)
                
                Current Content:
                \(originalContent)
                """
                
                let stream = AIService.shared.analyzeStream(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    apiClient: apiClient
                )
                
                for try await chunk in stream {
                    await MainActor.run {
                        if self.generatedContent == nil {
                            self.generatedContent = ""
                            self.isProcessing = false
                        }
                        self.generatedContent! += chunk
                    }
                }
                
                await MainActor.run {
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

struct AIActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void
    
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showDisabledAlert = false
    
    init(_ title: String, systemImage: String, color: Color = Color("AccentColor"), isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            if apiClient.aiConfig?.enabled ?? false {
                action()
            } else {
                showDisabledAlert = true
            }
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .font(.system(horizontalSizeClass == .compact ? .footnote : .subheadline))
            .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 24)
            .frame(height: horizontalSizeClass == .compact ? 40 : 44)
            .background(.ultraThinMaterial)
            .background(apiClient.aiConfig?.enabled ?? false ? color.opacity(0.6) : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .disabled(isLoading)
        .buttonStyle(.plain)
        .alert(languageManager.t("settings.aiDisabled"), isPresented: $showDisabledAlert) {
            Button(languageManager.t("common.ok"), role: .cancel) { }
        } message: {
            Text(languageManager.t("settings.aiDisabledDesc"))
        }
    }
}
