import SwiftUI

struct ConfigsModuleView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var configs: [ConfigItem] = []
    @State private var selectedCategory: String = "All"
    @State private var isLoading = true
    @State private var selectedConfig: ConfigItem?
    @State private var errorMessage: String?
    @State private var showingAddConfig = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    
    func categoryCount(_ category: String) -> Int {
        if category == "All" { return configs.count }
        return configs.filter { $0.category == category }.count
    }
    
    var categories: [String] {
        ["All"] + Array(Set(configs.map { $0.category })).sorted()
    }
    
    var filteredConfigs: [ConfigItem] {
        let categoryFiltered = selectedCategory == "All" ? configs : configs.filter { $0.category == selectedCategory }
        if searchText.isEmpty { return categoryFiltered }
        return categoryFiltered.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.path.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        fileList
            .navigationTitle(languageManager.t("configs.title"))
            .searchable(text: $searchText, prompt: languageManager.t("configs.searchPlaceholder"))
            .sheet(item: $selectedConfig) { config in
                NavigationStack {
                    ConfigDetailView(config: config)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedConfig = nil }) { Image(systemName: "xmark") }
                            }
                        }
                }
            }
            .onAppear {
                Task { await fetchData() }
            }
            .refreshable {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await fetchData() }
                    group.addTask { try? await Task.sleep(for: .milliseconds(600)) }
                    await group.waitForAll()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker(languageManager.t("common.category"), selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                Text("\(category == "All" ? languageManager.t("common.all") : languageManager.t(category)) (\(categoryCount(category)))").tag(category)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                            Text("\(selectedCategory == "All" ? languageManager.t("common.all") : languageManager.t(selectedCategory)) (\(categoryCount(selectedCategory)))").lineLimit(1)
                                .font(.caption2)
                        }
                    }
                    
                    Button {
                        showingAddConfig = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConfig) {
                NavigationStack {
                    AddPathView(title: languageManager.t("configs.addPath")) { path, name in
                        let _: ActionResponse = try await apiClient.request("/api/configs", method: "POST", body: ["action": "add", "id": path])
                        await fetchData()
                    }
                }
            }
    }
    
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category == "All" ? languageManager.t("common.all") : languageManager.t(category))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == category ? Color.blue : Color.secondary.opacity(0.1))
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
    
    private var fileList: some View {
        ZStack {
            List(selection: $selectedConfig) {
                Section {
                    if let error = errorMessage {
                        ContentUnavailableView(languageManager.t("common.error"), systemImage: "exclamationmark.triangle.fill", description: Text(error))
                    } else if configs.isEmpty && !isLoading {
                        ContentUnavailableView(languageManager.t("configs.noConfigs"), systemImage: "gearshape")
                    } else {
                        ForEach(filteredConfigs) { config in
                            Button {
                                selectedConfig = config
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(config.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(config.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text(languageManager.t(config.category))
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundStyle(.blue)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                        
                                        if let size = config.size {
                                            Text(formatSize(size))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }
                                        
                                        Spacer(minLength: 0)
                                        
                                        if let mtime = config.mtime {
                                            Text(formatDate(mtime))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            
            if isLoading && configs.isEmpty {
                LoadingView()
            }
        }
    }

    
    private func configRow(for config: ConfigItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(config.name)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(config.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
    
    func formatDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }


    func fetchData() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: ConfigResponse = try await apiClient.request("/api/configs")
            await MainActor.run {
                self.configs = response.data ?? []
                self.isLoading = false
            }
        } catch {
            print("Fetch configs failed: \(error)")
            await MainActor.run { 
                self.errorMessage = error.localizedDescription
                self.isLoading = false 
            }
        }
    }
}

struct ConfigDetailView: View {
    let config: ConfigItem
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSudoPrompt = false
    @State private var sudoPassword = ""
    @State private var showingAIAnalyze = false
    @State private var showingAIAssist = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(config.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospaced()
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            if isLoading {
                LoadingView()
            }
            TextEditor(text: $content)
                .font(.system(.caption2, design: .monospaced))
                .padding(4)
            Spacer()
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
        .navigationTitle(config.name)
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
        .sheet(isPresented: $showingAIAnalyze) {
            NavigationStack {
                AIAnalyzeView(originalContent: content, contextInfo: "File Path: \(config.path)")
            }
        }
        .sheet(isPresented: $showingAIAssist) {
            NavigationStack {
                AIAssistView(originalContent: content, contextInfo: "File Path: \(config.path)") { newContent in
                    self.content = newContent
                }
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
        isLoading = true
        do {
            let response: ConfigResponse = try await apiClient.request("/api/configs", method: "POST", body: ["action": "read", "id": config.path])
            await MainActor.run {
                self.content = response.content ?? ""
                self.isLoading = false
            }
        } catch {
            print("Fetch config content failed: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func saveConfig() async {
        isSaving = true
        errorMessage = nil
        do {
            var body: [String: Any] = ["action": "write", "id": config.path, "content": content]
            if !sudoPassword.isEmpty {
                body["sudoPassword"] = sudoPassword
            }
            
            let _: ActionResponse = try await apiClient.request("/api/configs", method: "POST", body: body)
            await MainActor.run { 
                self.isSaving = false
                self.sudoPassword = ""
                dismiss()
            }
        } catch {
            print("Save config failed: \(error)")
            let errorMsg = error.localizedDescription
            
            await MainActor.run { 
                let msg = errorMsg.lowercased()
                let isPermissionError = msg.contains("sudo_required") || msg.contains("permission_denied") || msg.contains("permission denied") || msg.contains("eacces") || msg.contains("eperm")
                
                if isPermissionError && self.sudoPassword.isEmpty {
                    self.showingSudoPrompt = true
                } else if msg.contains("sudo_password_incorrect") || msg.contains("incorrect password") || msg.contains("auth failed") {
                    self.errorMessage = languageManager.t("common.passwordIncorrect")
                    self.showingError = true
                    self.sudoPassword = ""
                } else {
                    self.errorMessage = errorMsg
                    self.showingError = true
                }
                self.isSaving = false 
            }
        }
    }
}

#Preview {
    ConfigsModuleView()
        .environment(RemoteAPIClient())
}
