import SwiftUI

struct ProcessListView: View {
        @State private var refreshTask: Task<Void, Never>? = nil
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var processes: [RemoteProcess] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var sortOrder: SortOrder = .cpu
    @State private var selectedUser: String = "All"
    @State private var users: [String] = ["All"]
    @State private var selectedProcess: RemoteProcess?
    @State private var errorMessage: String?
    @State private var loadingAction: [String: String] = [:] // pid: action
    
    enum SortOrder: String, CaseIterable {
        case cpu = "CPU"
        case mem = "MEM"
        case pid = "PID"
        case command = "common.command"
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
        List {
            Section {
                    if isLoading && processes.isEmpty {
                        ProgressView(languageManager.t("common.loading"))
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else if let error = errorMessage {
                        ContentUnavailableView(languageManager.t("processes.fetchFailed"), systemImage: "exclamationmark.triangle", description: Text(error))
                    } else if processes.isEmpty && !isLoading {
                        ContentUnavailableView(languageManager.t("processes.noData"), systemImage: "cpu.fill")
                    } else {
                        ForEach(filteredAndSortedProcesses) { process in
                            Button {
                                selectedProcess = process
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                        .padding(.trailing, 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(process.command)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Text("\(languageManager.t("processes.pid")): \(process.pid) · \(languageManager.t("processes.user")): \(process.user)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(process.cpu)% \(languageManager.t("processes.cpu"))")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                            .monospacedDigit()
                                        Text("\(process.mem)% \(languageManager.t("processes.mem"))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await killProcess(pid: process.pid) }
                                } label: {
                                    Label(languageManager.t("processes.kill"), systemImage: "xmark.circle")
                                }
                            }
                        }
                    }
                }
            }
        .listStyle(.plain)
        .navigationTitle(languageManager.t("processes.title"))
        .searchable(text: $searchText, prompt: languageManager.t("processes.searchPlaceholder"))
        // 自动静默刷新
        .onAppear {
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
                        Text(selectedUser == "All" ? languageManager.t("common.all") : selectedUser).lineLimit(1)
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
    }
    
    // ...existing code...
    func fetchData(silent: Bool = false) async {
        if !silent { isLoading = processes.isEmpty }
        errorMessage = nil
        do {
            let response: ProcessResponse = try await apiClient.request("/api/system/processes")
            await MainActor.run {
                self.processes = response.data
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
}
struct ProcessDetailView: View {
    let process: RemoteProcess
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var detailedProcess: DetailedProcess?
    @State private var isLoading = true
    @State private var isExecutingAction = false
    
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
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .confirmationDialog(languageManager.t("processes.terminateConfirm"), isPresented: $showingStopConfirmation, titleVisibility: .visible) {
            Button(languageManager.t("processes.terminate"), role: .destructive) {
                Task { await stopProcess() }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(languageManager.t("processes.forceKillConfirm"), isPresented: $showingKillConfirmation, titleVisibility: .visible) {
            Button(languageManager.t("processes.forceKill"), role: .destructive) {
                Task { await killProcess() }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) {}
        }
        .onAppear {
            Task { await fetchDetails() }
        }
    }
    
    @State private var showingKillConfirmation = false
    @State private var showingStopConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
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
}


#Preview {
    NavigationStack {
        ProcessListView()
            .environment(RemoteAPIClient())
    }
}
