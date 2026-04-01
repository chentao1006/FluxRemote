import SwiftUI

struct ProcessListView: View {
        @State private var refreshTask: Task<Void, Never>? = nil
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var processes: [RemoteProcess] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var sortOrder: SortOrder = .cpu
    @State private var selectedUser: String = "All"
    @State private var users: [String] = ["All"]
    @State private var selectedProcess: RemoteProcess?
    @State private var errorMessage: String?
    @State private var loadingAction: [String: String] = [:] // pid: action
    @State private var processToActOn: RemoteProcess?
    @State private var showingStopConfirmation = false
    @State private var showingKillConfirmation = false
    @Binding var selection: NavigationItem?
    
    enum SortOrder: String, CaseIterable {
        case cpu = "CPU"
        case mem = "MEM"
        case pid = "PID"
        case command = "process.command"
    }
    
    var filteredAndSortedProcesses: [RemoteProcess] {
        var result = processes
        
        if selectedUser != "All" {
            result = result.filter { $0.user == selectedUser }
        }
        
        if !searchText.isEmpty {
            result = result.filter { $0.command.localizedCaseInsensitiveContains(searchText) || $0.pid.contains(searchText) }
        }
        
        switch sortOrder {
        case .cpu:
            result.sort { Double($0.cpu) ?? 0 > Double($1.cpu) ?? 0 }
        case .mem:
            result.sort { Double($0.mem) ?? 0 > Double($1.mem) ?? 0 }
        case .pid:
            result.sort { Int($0.pid) ?? 0 > Int($1.pid) ?? 0 }
        case .command:
            result.sort { $0.command.lowercased() < $1.command.lowercased() }
        }
        
        return result
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    if let error = errorMessage, processes.isEmpty {
                        ContentUnavailableView(languageManager.t("processes.fetchFailed"), systemImage: "exclamationmark.triangle", description: Text(error))
                    } else if processes.isEmpty && !isLoading {
                        ContentUnavailableView(languageManager.t("processes.noData"), systemImage: "cpu.fill")
                    } else {
                        ForEach(filteredAndSortedProcesses) { process in
                            Group {
                                if horizontalSizeClass == .compact {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Button {
                                            selectedProcess = process
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(process.command)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                Text("\(languageManager.t("processes.pid")): \(process.pid) · \(languageManager.t("processes.user")): \(process.user)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.top, 8)
                                            .padding(.bottom, 4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        
                                        HStack {
                                            HStack(spacing: 8) {
                                                Text("\(process.cpu)% \(languageManager.t("processes.cpu"))")
                                                    .foregroundStyle(.blue)
                                                Text("\(process.mem)% \(languageManager.t("processes.mem"))")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .font(.caption2)
                                            .monospacedDigit()
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 8) {
                                                actionButton(icon: "stop", color: .orange, isLoading: loadingAction[process.pid] == "stop") {
                                                    processToActOn = process
                                                    showingStopConfirmation = true
                                                }
                                                .disabled(loadingAction[process.pid] != nil)
                                                
                                                actionButton(icon: "trash", color: .red, isLoading: loadingAction[process.pid] == "kill") {
                                                    processToActOn = process
                                                    showingKillConfirmation = true
                                                }
                                                .disabled(loadingAction[process.pid] != nil)
                                            }
                                        }
                                        .padding(.bottom, 8)
                                    }
                                } else {
                                    HStack(alignment: .top) {
                                        Button {
                                            selectedProcess = process
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(process.command)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                Text("\(languageManager.t("processes.pid")): \(process.pid) · \(languageManager.t("processes.user")): \(process.user)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        
                                        HStack(spacing: 8) {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("\(process.cpu)% \(languageManager.t("processes.cpu"))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.blue)
                                                    .lineLimit(1)
                                                    .monospacedDigit()
                                                    .minimumScaleFactor(0.8)
                                                Text("\(process.mem)% \(languageManager.t("processes.mem"))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .monospacedDigit()
                                                    .minimumScaleFactor(0.8)
                                            }
                                            .frame(width: 80, alignment: .trailing)

                                            HStack(spacing: 8) {
                                                actionButton(icon: "stop", color: .orange, isLoading: loadingAction[process.pid] == "stop") {
                                                    processToActOn = process
                                                    showingStopConfirmation = true
                                                }
                                                .disabled(loadingAction[process.pid] != nil)
                                                
                                                actionButton(icon: "trash", color: .red, isLoading: loadingAction[process.pid] == "kill") {
                                                    processToActOn = process
                                                    showingKillConfirmation = true
                                                }
                                                .disabled(loadingAction[process.pid] != nil)
                                            }
                                            .frame(width: 80)
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            
            if isLoading && processes.isEmpty {
                LoadingView()
            }
        }
        .tint(Color("AccentColor"))
        .navigationTitle(languageManager.t("processes.title"))
        .searchable(text: $searchText, prompt: languageManager.t("processes.searchPlaceholder"))
        .refreshable {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await fetchData() }
                group.addTask { try? await Task.sleep(for: .milliseconds(600)) }
                await group.waitForAll()
            }
        }
        // 自动静默刷新
        .onAppear {
            if processes.isEmpty && !apiClient.processItems.isEmpty {
                self.processes = apiClient.processItems
                self.isLoading = false
            }
            Task { await fetchData() }
            refreshTask?.cancel()
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await fetchData(silent: true)
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker(languageManager.t("processes.sort"), selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(languageManager.t(order.rawValue)).tag(order)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(languageManager.t(sortOrder.rawValue))
                            .font(.caption2)
                    }
                }
                
                Menu {
                    Picker(languageManager.t("processes.user"), selection: $selectedUser) {
                        ForEach(users, id: \.self) { user in
                            Text(user == "All" ? languageManager.t("common.all") : user).tag(user)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person")
                        Text(selectedUser == "All" ? languageManager.t("common.all") : selectedUser)
                            .font(.caption2)
                    }
                }
            }
        }
        .sheet(item: $selectedProcess) { process in
            NavigationStack {
                ProcessDetailView(process: process)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: { selectedProcess = nil }) { Image(systemName: "xmark") }
                        }
                    }
            }
        }
        .alert(languageManager.t("processes.terminateConfirm"), isPresented: $showingStopConfirmation) {
            Button(languageManager.t("processes.terminate"), role: .destructive) {
                if let pid = processToActOn?.pid {
                    Task { await stopProcess(pid: pid) }
                }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(processToActOn?.command ?? "")
        }
        .alert(languageManager.t("processes.forceKillConfirm"), isPresented: $showingKillConfirmation) {
            Button(languageManager.t("processes.forceKill"), role: .destructive) {
                if let pid = processToActOn?.pid {
                    Task { await killProcess(pid: pid) }
                }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(processToActOn?.command ?? "")
        }
    }
    
    func fetchData(silent: Bool = false) async {
        guard selection == .processes else { return }
        if !silent { isLoading = processes.isEmpty }
        errorMessage = nil
        do {
            let response: ProcessResponse = try await apiClient.request("/api/system/processes")
            await MainActor.run {
                self.processes = response.data
                self.apiClient.processItems = response.data
                self.users = ["All"] + Array(Set(response.data.map { $0.user })).sorted()
                self.isLoading = false
            }
        } catch {
            print("Fetch processes error: \(error)")
            await MainActor.run { 
                self.errorMessage = error.localizedDescription
                self.isLoading = false 
            }
        }
    }
    
    func killProcess(pid: String) async {
        loadingAction[pid] = "kill"
        do {
            let _: ActionResponse = try await apiClient.request("/api/system/processes", method: "POST", body: ["action": "kill", "pid": pid])
            await fetchData()
        } catch {
            print("Kill process error: \(error)")
        }
        loadingAction[pid] = nil
    }

    func stopProcess(pid: String) async {
        loadingAction[pid] = "stop"
        do {
            let _: ActionResponse = try await apiClient.request("/api/system/processes", method: "POST", body: ["action": "stop", "pid": pid])
            await fetchData()
        } catch {
            print("Stop process error: \(error)")
        }
        loadingAction[pid] = nil
    }
    
    private func actionButton(icon: String, color: Color, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(width: 32, height: 32)
            } else {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
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
struct ProcessDetailView: View {
    let process: RemoteProcess
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var detailedProcess: DetailedProcess?
    @State private var isLoading = true
    @State private var isExecutingAction = false
    @State private var showingStopConfirmation = false
    @State private var showingKillConfirmation = false
    @State private var isAnalyzing = false
    @State private var aiAnalysis: String?
    @State private var aiTask: Task<Void, Never>?
    
    struct DetailedProcess: Codable {
        let pid: String
        let ppid: String
        let ppidName: String
        let cpu: String
        let mem: String
        let state: String
        let start: String
        let time: String
        let user: String
        let command: String
        let fullCommand: String
        let openFiles: [String]
    }
    
    struct DetailedProcessResponse: Codable {
        let success: Bool
        let data: DetailedProcess
    }
    
    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if let dp = detailedProcess {
                Section(languageManager.t("common.basicInfo")) {
                    LabeledContent(languageManager.t("processes.pid"), value: dp.pid)
                    LabeledContent(languageManager.t("processes.parentPid"), value: "\(dp.ppidName) (\(dp.ppid))")
                    LabeledContent(languageManager.t("processes.state"), value: dp.state)
                    LabeledContent(languageManager.t("processes.user"), value: dp.user)
                    LabeledContent(languageManager.t("processes.startTime"), value: dp.start)
                    LabeledContent(languageManager.t("processes.cpuTime"), value: dp.time)
                }
                
                Section(languageManager.t("common.resourceUsage")) {
                    LabeledContent(languageManager.t("processes.cpu"), value: "\(dp.cpu)%")
                    LabeledContent(languageManager.t("processes.mem"), value: "\(dp.mem)%")
                }
                
                Section(languageManager.t("processes.fullCommand")) {
                    Text(dp.fullCommand)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                if !dp.openFiles.isEmpty {
                    Section(languageManager.t("processes.openFiles")) {
                        ForEach(dp.openFiles, id: \.self) { file in
                            Text(file)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
            }
        }
        .overlay(alignment: .bottom) {
            if isAnalyzing || aiAnalysis != nil {
                AIAnalysisCard(analysis: aiAnalysis, isAnalyzing: isAnalyzing) {
                    withAnimation {
                        aiTask?.cancel()
                        aiTask = nil
                        aiAnalysis = nil
                        isAnalyzing = false
                    }
                }
                .padding(.bottom, 20)
            } else if !isLoading {
                AIActionButton(languageManager.t("common.aiAnalyze"), systemImage: "sparkles", isLoading: isAnalyzing) {
                    analyzeProcess()
                }
                .padding(.bottom, 30)
            }
        }
        .navigationTitle(process.command)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isExecutingAction {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        showingStopConfirmation = true
                    } label: {
                        Image(systemName: "stop")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    
                    Button(role: .destructive) {
                        showingKillConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .alert(languageManager.t("processes.terminateConfirm"), isPresented: $showingStopConfirmation) {
            Button(languageManager.t("processes.terminate"), role: .destructive) {
                Task { await stopProcess() }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(process.command)
        }
        .alert(languageManager.t("processes.forceKillConfirm"), isPresented: $showingKillConfirmation) {
            Button(languageManager.t("processes.forceKill"), role: .destructive) {
                Task { await killProcess() }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(process.command)
        }
        .onAppear {
            Task { await fetchDetails() }
        }
    }
    
    func killProcess() async {
        isExecutingAction = true
        do {
            let _: ActionResponse = try await apiClient.request("/api/system/processes", method: "POST", body: ["action": "kill", "pid": process.pid])
            dismiss()
        } catch {
            print("Kill process error: \(error)")
            isExecutingAction = false
        }
    }
    
    func stopProcess() async {
        isExecutingAction = true
        do {
            let _: ActionResponse = try await apiClient.request("/api/system/processes", method: "POST", body: ["action": "stop", "pid": process.pid])
            dismiss()
        } catch {
            print("Stop process error: \(error)")
            isExecutingAction = false
        }
    }
    
    func fetchDetails() async {
        isLoading = true
        do {
            let response: DetailedProcessResponse = try await apiClient.request("/api/system/processes?pid=\(process.pid)")
            await MainActor.run {
                self.detailedProcess = response.data
                self.isLoading = false
            }
        } catch {
            print("Fetch process details error: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func analyzeProcess() {
        guard let dp = detailedProcess else { return }
        isAnalyzing = true
        aiAnalysis = nil
        
        aiTask = Task {
            do {
                let info = "PID: \(dp.pid), PPID: \(dp.ppid) (\(dp.ppidName)), Command: \(dp.command), Full Command: \(dp.fullCommand), CPU: \(dp.cpu)%, MEM: \(dp.mem)%, State: \(dp.state), Start: \(dp.start), User: \(dp.user), Open Files: \(dp.openFiles.joined(separator: ", "))"
                let prompt = "Analyze this macOS process and provide diagnosis or suggestions in \(languageManager.aiResponseLanguage):\n\(info)\nUse Markdown formatting."
                
                let stream = AIService.shared.analyzeStream(prompt: prompt, systemPrompt: "You are a macOS systems expert.", apiClient: apiClient)
                
                for try await chunk in stream {
                    try Task.checkCancellation()
                    await MainActor.run {
                        withAnimation {
                            if self.aiAnalysis == nil {
                                self.aiAnalysis = ""
                                self.isAnalyzing = false
                            }
                            self.aiAnalysis! += chunk
                        }
                    }
                }
                
                await MainActor.run {
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.aiAnalysis = "Error: \(error.localizedDescription)"
                    self.isAnalyzing = false
                }
            }
        }
    }
}


#Preview {
    NavigationStack {
        ProcessListView(selection: .constant(.processes))
            .environment(RemoteAPIClient())
    }
}
