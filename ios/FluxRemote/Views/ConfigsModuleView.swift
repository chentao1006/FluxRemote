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
                await fetchData()
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
                        Label(languageManager.t("configs.addPath"), systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConfig) {
                NavigationStack {
                    AddPathView(title: languageManager.t("configs.addPath")) { path, name in
                        let _: ActionResponse = try await apiClient.request("/api/configs", method: "POST", body: ["path": path, "name": name])
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
        List(selection: $selectedConfig) {
            Section {
                if isLoading && configs.isEmpty {
                    ProgressView(languageManager.t("configs.loading"))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if let error = errorMessage {
                    ContentUnavailableView(languageManager.t("common.error"), systemImage: "exclamationmark.triangle.fill", description: Text(error))
                } else if configs.isEmpty {
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
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
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
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .padding()
            }
            TextEditor(text: $content)
                .font(.system(.caption2, design: .monospaced))
                .padding(4)
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
        .onAppear {
            Task { await fetchContent() }
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
        do {
            let _: ActionResponse = try await apiClient.request("/api/configs", method: "POST", body: ["path": config.path, "content": content])
            await MainActor.run { self.isSaving = false }
        } catch {
            print("Save config failed: \(error)")
            await MainActor.run { self.isSaving = false }
        }
    }
}

#Preview {
    ConfigsModuleView()
        .environment(RemoteAPIClient())
}
