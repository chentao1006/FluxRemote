import SwiftUI

struct LogModuleView: View {
        // Add autoRefresh property (always enabled)
        var autoRefresh: Bool { true }

        // Add categoryCount function
        func categoryCount(_ category: String) -> Int {
            if category == "All" { return logs.count }
            return logs.filter { $0.category == category }.count
        }
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var logs: [LogItem] = []
    @State private var selectedCategory: String = "All"
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedLog: LogItem?
    @State private var showingAddLog = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var actionTarget: LogItem?
    @State private var actionType: String?
    @State private var showingActionConfirm = false
    @State private var sudoPassword = ""
    @State private var showingSudoPrompt = false
    @State private var isActioning = false

    
    let categories = ["All", "system", "service", "app", "other"]
    
    var filteredFiles: [LogItem] {
        let categoryFiltered = selectedCategory == "All" ? logs : logs.filter { $0.category == selectedCategory }
        if searchText.isEmpty { return categoryFiltered }
        return categoryFiltered.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.path.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        fileList
            .navigationTitle(languageManager.t("logs.title"))
            .searchable(text: $searchText, prompt: languageManager.t("logs.searchPlaceholder"))
            .sheet(item: $selectedLog) { log in
                NavigationStack {
                    LogDetailView(file: log, onAction: { action in
                        Task { await performAction(file: log, action: action) }
                    })
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { selectedLog = nil }) { Image(systemName: "xmark") }
                            }
                        }
                }
            }
            .confirmationDialog(
                (actionType == "delete" ? languageManager.t("common.delete") : (actionType == "remove" ? languageManager.t("common.remove") : languageManager.t("common.clear"))),
                isPresented: $showingActionConfirm,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    if let file = actionTarget, let action = actionType {
                        Task { await performAction(file: file, action: action) }
                    }
                } label: {
                    Text(actionType == "delete" ? languageManager.t("common.delete") : (actionType == "remove" ? languageManager.t("common.remove") : languageManager.t("common.clear")))
                }
                Button(languageManager.t("common.cancel"), role: .cancel) {}
            } message: {
                if let action = actionType, let file = actionTarget {
                    Text(action == "delete" ? languageManager.t("logs.deleteConfirm") : (action == "remove" ? languageManager.t("logs.removeConfirm") : languageManager.t("logs.clearConfirm")))
                }
            }
            .sheet(isPresented: $showingSudoPrompt) {
                SudoPasswordView(password: $sudoPassword) {
                    if let file = actionTarget, let action = actionType {
                        let pwd = sudoPassword
                        sudoPassword = ""
                        Task { await performAction(file: file, action: action, password: pwd) }
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
                                Text("\(category == "All" ? languageManager.t("common.all") : languageManager.t(categoryDisplay(category))) (\(categoryCount(category)))").tag(category)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                            Text("\(selectedCategory == "All" ? languageManager.t("common.all") : languageManager.t(categoryDisplay(selectedCategory))) (\(categoryCount(selectedCategory)))").lineLimit(1)
                                .font(.caption2)
                        }
                    }
                    
                    Button {
                        showingAddLog = true
                    } label: {
                        Label(languageManager.t("logs.addPath"), systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddLog) {
                NavigationStack {
                    AddPathView(title: languageManager.t("logs.addPath")) { path, name in
                        let _: ActionResponse = try await apiClient.request("/api/logs", method: "POST", body: ["file": path, "action": "add"])
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
                        Text(category == "All" ? languageManager.t("common.all") : languageManager.t(categoryDisplay(category)))
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
    
    var fileList: some View {
        ZStack {
            List {
                Section {
                    if let error = errorMessage {
                        ContentUnavailableView(languageManager.t("logs.syncFailed"), systemImage: "exclamationmark.triangle.fill", description: Text(error))
                    } else if logs.isEmpty && !isLoading {
                        ContentUnavailableView {
                            Label(languageManager.t("logs.noLogs"), systemImage: "doc.text.magnifyingglass")
                        } description: {
                            Text(languageManager.t("logs.noLogsDesc"))
                        }
                    } else {
                        ForEach(filteredFiles) { file in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(file.path)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        HStack {
                                            Text(languageManager.t(categoryDisplay(file.category)))
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundStyle(.blue)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            Text(formatSize(file.size))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                            Spacer(minLength: 0)
                                            Text(formatDate(file.mtime))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedLog = file
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Button {
                                            actionTarget = file
                                            actionType = "clear"
                                            showingActionConfirm = true
                                        } label: {
                                            Image(systemName: "eraser")
                                                .font(.system(size: 14))
                                                .padding(6)
                                                .background(Color.orange.opacity(0.1))
                                                .foregroundStyle(.orange)
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button {
                                            actionTarget = file
                                            actionType = file.isCustom ? "remove" : "delete"
                                            showingActionConfirm = true
                                        } label: {
                                            Image(systemName: file.isCustom ? "minus.circle" : "trash")
                                                .font(.system(size: 14))
                                                .padding(6)
                                                .background(Color.red.opacity(0.1))
                                                .foregroundStyle(.red)
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if file.isCustom {
                                    Button(role: .destructive) {
                                        actionTarget = file
                                        actionType = "remove"
                                        showingActionConfirm = true
                                    } label: {
                                        Label(languageManager.t("common.remove"), systemImage: "minus.circle")
                                    }
                                    .disabled(isActioning)
                                } else {
                                    Button(role: .destructive) {
                                        actionTarget = file
                                        actionType = "delete"
                                        showingActionConfirm = true
                                    } label: {
                                        Label(languageManager.t("common.delete"), systemImage: "trash")
                                    }
                                    .disabled(isActioning)
                                }
                                
                                Button {
                                    actionTarget = file
                                    actionType = "clear"
                                    showingActionConfirm = true
                                } label: {
                                    Label(languageManager.t("common.clear"), systemImage: "eraser")
                                }
                                .tint(.orange)
                                .disabled(isActioning)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.insetGrouped)
            
            if isLoading && logs.isEmpty {
                LoadingView()
            }
        }
    }
    
    private func fileRow(for file: LogItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.name)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(file.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                Text(languageManager.t(categoryDisplay(file.category)))
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                
                Text(formatSize(file.size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    func categoryDisplay(_ cat: String) -> String {
        switch cat {
        case "system": return "common.system"
        case "service": return "common.service"
        case "app": return "common.app"
        case "other": return "common.other"
        default: return cat
        }
    }
    
    func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
    
    func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    func fetchData() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: LogResponse = try await apiClient.request("/api/logs")
            await MainActor.run {
                if case .list(let items) = response.data {
                    self.logs = items
                }
                self.isLoading = false
            }
        } catch {
            print("Fetch logs failed: \(error)")
            await MainActor.run { 
                self.errorMessage = error.localizedDescription
                self.isLoading = false 
            }
        }
    }

    func performAction(file: LogItem, action: String, password: String? = nil) async {
        await MainActor.run { isActioning = true }
        do {
            var body: [String: Any] = ["file": file.path, "action": action]
            if let password = password {
                body["password"] = password
            }
            
            let response: ActionResponse = try await apiClient.request("/api/logs", method: "POST", body: body)
            
            if response.requiresPassword == true {
                await MainActor.run {
                    self.actionTarget = file
                    self.actionType = action
                    self.showingSudoPrompt = true
                    self.isActioning = false
                }
                return
            }
            
            if response.success {
                await fetchData()
                if action == "delete" || action == "remove" {
                    await MainActor.run {
                        if selectedLog?.path == file.path {
                            selectedLog = nil
                        }
                    }
                }
            } else if let error = response.error {
                await MainActor.run { self.errorMessage = error }
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
        await MainActor.run { isActioning = false }
    }
}

struct LogDetailView: View {
        // Add autoRefresh property (always enabled)
        var autoRefresh: Bool { true }
    let file: LogItem
    let onAction: (String) -> Void

    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var logContent: String = ""
    @State private var isReading = false
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var isSilentRefresh = false // 静默刷新标记
    
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if logContent.isEmpty && (isReading || isSilentRefresh) {
                    LoadingView()
                } else if !logContent.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let lines = logContent.components(separatedBy: .newlines)
                            let displayLines = lines.suffix(5000)
                            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(index % 2 == 0 ? Color.clear : Color.black.opacity(0.04))
                                    .id(index) // Add ID for scrolling
                            }
                        }
                        .textSelection(.enabled)
                    }
                } else if !isReading && !isSilentRefresh {
                    ContentUnavailableView(languageManager.t("logs.noContent"), systemImage: "doc.text.fill")
                }
            }
            .onChange(of: logContent) {
                // Scroll to the bottom when content changes
                let lines = logContent.components(separatedBy: .newlines)
                let displayLines = lines.suffix(5000)
                if displayLines.count > 0 {
                    withAnimation {
                        proxy.scrollTo(displayLines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    onAction("clear")
                } label: {
                    Label(languageManager.t("common.clear"), systemImage: "eraser")
                }
                .tint(.orange)
                
                Button(role: .destructive) {
                    onAction(file.isCustom ? "remove" : "delete")
                } label: {
                    Label(file.isCustom ? languageManager.t("common.remove") : languageManager.t("common.delete"), systemImage: file.isCustom ? "minus.circle" : "trash")
                }
                .tint(.red)
            }
        }



        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await readLog(silent: false) }
            refreshTask?.cancel()
            refreshTask = Task {
                while !Task.isCancelled && autoRefresh {
                    try? await Task.sleep(for: .seconds(3))
                    await readLog(silent: true)
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }
    
    func readLog(silent: Bool = false) async {
        await MainActor.run {
            if silent {
                self.isSilentRefresh = true
            } else {
                self.isReading = true
                self.isSilentRefresh = false
            }
        }
        do {
            let path = "/api/logs?file=\(file.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            let response: LogResponse = try await apiClient.request(path)
            if case .content(let content) = response.data {
                await MainActor.run {
                    self.logContent = content
                    self.isReading = false
                    self.isSilentRefresh = false
                }
            }
        } catch {
            print("Read log failed: \(error)")
            await MainActor.run {
                self.isReading = false
                self.isSilentRefresh = false
            }
        }
    }
}

#Preview {
    LogModuleView()
        .environment(RemoteAPIClient())
}

struct AddPathView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var path: String = ""
    @State private var name: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    let title: String
    let onSave: (String, String) async throws -> Void
    
    var body: some View {
        Form {
            Section {
                TextField(languageManager.t("logs.pathPlaceholder"), text: $path)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                TextField(languageManager.t("logs.namePlaceholder"), text: $name)
            } footer: {
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(languageManager.t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(languageManager.t("common.add")) {
                        Task {
                            isSaving = true
                            errorMessage = nil
                            do {
                                try await onSave(path, name)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                isSaving = false
                            }
                        }
                    }
                    .disabled(path.isEmpty)
                }
            }
        }
    }
}

struct SudoPasswordView: View {
    @Binding var password: String
    @Environment(\.dismiss) var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    var onConfirm: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(languageManager.t("logs.sudoPlaceholder"), text: $password)
                        .textContentType(.password)
                } header: {
                    Text(languageManager.t("logs.requireSudo"))
                } footer: {
                    Text(languageManager.t("nginx.sudoRequired"))
                }
            }
            .navigationTitle(languageManager.t("logs.requireSudo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageManager.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(languageManager.t("common.confirm")) {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
        .presentationDetents([.height(250)])
    }
}

