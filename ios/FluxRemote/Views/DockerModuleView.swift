import SwiftUI

struct DockerModuleView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var containers: [DockerContainer] = []
    @State private var images: [DockerImage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: Tab = .containers
    @State private var loadingAction: [String: String] = [:] // [id: action]
    
    @State private var activeAlert: DockerAlertType? = nil
    @State private var activeSheet: DockerSheetType? = nil
    
    enum DockerAlertType: Identifiable {
        case prune
        case actionError(String)
        case delete(DockerContainer)
        case restart(DockerContainer)
        case stop(DockerContainer)
        case deleteImage(DockerImage)
        
        var id: String {
            switch self {
            case .prune: return "prune"
            case .actionError(let e): return "error-\(e)"
            case .delete(let c): return "delete-\(c.id)"
            case .restart(let c): return "restart-\(c.id)"
            case .stop(let c): return "stop-\(c.id)"
            case .deleteImage(let i): return "rmi-\(i.id)"
            }
        }
    }
    
    enum DockerSheetType: Identifiable {
        case logs(DockerContainer)
        case detail(DockerContainer)
        
        var id: String {
            switch self {
            case .logs(let c): return "logs-\(c.id)"
            case .detail(let c): return "detail-\(c.id)"
            }
        }
    }
    
    enum Tab: String, CaseIterable {
        case containers = "docker.containers"
        case images = "docker.images"
    }
    
    var body: some View {
        mainContent
            .navigationTitle(languageManager.t("sidebar.docker"))
            .toolbar { toolbarContent }
            .refreshable { await refreshData() }
            .onAppear { Task { await fetchData() } }
            .onChange(of: selectedTab) { Task { await fetchData() } }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .logs(let container):
                    NavigationStack {
                        DockerLogView(containerId: container.id, containerName: container.name)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button(action: { activeSheet = nil }) { Image(systemName: "xmark") }
                                }
                            }
                    }
                case .detail(let container):
                    NavigationStack {
                        DockerDetailView(
                            container: container,
                            loadingAction: loadingAction,
                            onAction: { await performAction($0, id: container.id) },
                            onViewLogs: { activeSheet = .logs(container) }
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { activeSheet = nil }) { Image(systemName: "xmark") }
                            }
                        }
                    }
                }
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .prune:
                    return Alert(
                        title: Text(languageManager.t("docker.pruneTitle")),
                        message: Text(languageManager.t("docker.pruneMessage")),
                        primaryButton: .destructive(Text(languageManager.t("common.delete"))) {
                            Task { await performAction("prune", id: "") }
                        },
                        secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                    )
                case .actionError(let error):
                    return Alert(
                        title: Text(languageManager.t("common.error")),
                        message: Text(error),
                        dismissButton: .cancel(Text(languageManager.t("common.ok")))
                    )
                case .delete(let container):
                    return Alert(
                        title: Text(languageManager.t("launchagent.deleteConfirmTitle")),
                        message: Text(String.localizedStringWithFormat(languageManager.t("launchagent.deleteConfirmMessage"), container.name)),
                        primaryButton: .destructive(Text(languageManager.t("common.delete"))) {
                            Task { await performAction("rm", id: container.id) }
                        },
                        secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                    )
                case .restart(let container):
                    return Alert(
                        title: Text(languageManager.t("common.confirm")),
                        message: Text(languageManager.t("docker.restartConfirm")),
                        primaryButton: .destructive(Text(languageManager.t("server.restart"))) {
                            Task { await performAction("restart", id: container.id) }
                        },
                        secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                    )
                case .stop(let container):
                    return Alert(
                        title: Text(languageManager.t("common.confirm")),
                        message: Text(languageManager.t("docker.stopConfirm")),
                        primaryButton: .destructive(Text(languageManager.t("common.stop"))) {
                            Task { await performAction("stop", id: container.id) }
                        },
                        secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                    )
                case .deleteImage(let image):
                    return Alert(
                        title: Text(languageManager.t("docker.deleteImageTitle")),
                        message: Text(String.localizedStringWithFormat(languageManager.t("docker.deleteImageMessage"), image.repository)),
                        primaryButton: .destructive(Text(languageManager.t("common.delete"))) {
                            Task { await performAction("rmi", id: image.id) }
                        },
                        secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                    )
                }
            }
    }
    
    private var mainContent: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            
            List {
                Section {
                    if let error = errorMessage {
                        ContentUnavailableView(languageManager.t("common.error"), systemImage: "exclamationmark.triangle.fill", description: Text(error))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        switch selectedTab {
                        case .containers:
                            if containers.isEmpty && !isLoading {
                                ContentUnavailableView(languageManager.t("docker.noContainers"), systemImage: "shippingbox")
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                containerList
                            }
                        case .images:
                            if images.isEmpty && !isLoading {
                                ContentUnavailableView(languageManager.t("docker.noImages"), systemImage: "photo.trianglebadge.exclamationmark")
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                imageList
                            }
                        }
                    }
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            
            if isLoading && (selectedTab == .containers ? containers.isEmpty : images.isEmpty) {
                LoadingView()
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Tabs", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(languageManager.t(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            if selectedTab == .images {
                Button {
                    activeAlert = .prune
                } label: {
                    if loadingAction[""] == "prune" {
                        ProgressView()
                    } else {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(loadingAction[""] != nil)
            }
        }
    }
    
    private func refreshData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await fetchData() }
            group.addTask { try? await Task.sleep(for: .milliseconds(600)) }
            await group.waitForAll()
        }
    }
    
    private var containerRow: some View {
        EmptyView() // Placeholder if used elsewhere, but we have containerList
    }

    private var containerList: some View {
        ForEach(Array(containers.enumerated()), id: \.element.id) { index, container in
            VStack(alignment: .leading, spacing: 12) {
                // Main info row
                HStack(alignment: .top) {
                    StatusBadge(status: container.state, size: 14)
                        .padding(.top, 4)
                    VStack(alignment: .leading) {
                        Text(container.name)
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(container.image)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    
                    // Log button at the top right of the row
                    Button {
                        activeSheet = .logs(container)
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeSheet = .detail(container)
                }
                
                // Status and Buttons row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(container.status)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        if !container.ports.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "network")
                                    .font(.system(size: 10))
                                Text(container.ports)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        let isRunning = container.state == "running"
                        if isRunning {
                            actionButton(icon: "arrow.clockwise", color: .orange, isLoading: loadingAction[container.id] == "restart") {
                                await MainActor.run { activeAlert = .restart(container) }
                            }
                            actionButton(icon: "stop", color: .red, isLoading: loadingAction[container.id] == "stop") {
                                await MainActor.run { activeAlert = .stop(container) }
                            }
                        } else {
                            actionButton(icon: "play", color: .green, isLoading: loadingAction[container.id] == "start") {
                                await performAction("start", id: container.id)
                            }
                            actionButton(icon: "trash", color: .red, isLoading: loadingAction[container.id] == "rm") {
                                await MainActor.run { activeAlert = .delete(container) }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    activeAlert = .delete(container)
                } label: {
                    Label(languageManager.t("common.delete"), systemImage: "trash")
                }
                
                Button {
                    activeSheet = .logs(container)
                } label: {
                    Label(languageManager.t("docker.viewLogs"), systemImage: "doc.text")
                }
                .tint(.blue)
            }
            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        }
    }
    
    private var imageList: some View {
        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        StatusBadge(status: image.inUse == true ? "online" : "offline", size: 14)
                        Text(image.repository)
                            .font(.headline)
                        
                        Text(image.tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 12) {
                        Text("\(languageManager.t("common.id")): \(image.id.prefix(12))")
                        Text(image.size)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if image.inUse != true {
                    actionButton(icon: "trash", color: .red, isLoading: loadingAction[image.id] == "rmi") {
                        await MainActor.run { activeAlert = .deleteImage(image) }
                    }
                } else {
                    // Placeholder to keep spacing consistent if needed, or just let Spacer take it
                    Color.clear.frame(width: 32, height: 32)
                }
            }
            .padding(.vertical, 6)
            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        }
    }
    
    private func actionButton(icon: String, color: Color, isLoading: Bool = false, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    @State private var fetchTask: Task<Void, Never>?
    
    func fetchData() async {
        fetchTask?.cancel()
        
        fetchTask = Task {
            await MainActor.run { 
                isLoading = true
                errorMessage = nil 
            }
            
            do {
                switch selectedTab {
                case .containers:
                    let response: DockerResponse = try await apiClient.request("/api/docker/containers")
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.containers = response.data
                            self.isLoading = false
                        }
                    }
                case .images:
                    let response: DockerImageResponse = try await apiClient.request("/api/docker/images")
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.images = response.data
                            self.isLoading = false
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        if let nsError = error as NSError?, let msg = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                            self.errorMessage = "\(languageManager.t("common.failed")): \(msg)"
                        } else {
                            self.errorMessage = "\(languageManager.t("common.failed")): \(error.localizedDescription)"
                        }
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    func performAction(_ action: String, id: String) async {
        await MainActor.run { loadingAction[id] = action }
        defer { 
            Task { @MainActor in
                loadingAction[id] = nil 
            }
        }
        
        do {
            let response: ActionResponse = try await apiClient.request("/api/docker/action", method: "POST", body: ["action": action, "id": id])
            
            await MainActor.run {
                if response.success {
                    if action == "start" || action == "stop" || action == "restart" {
                        if let index = containers.firstIndex(where: { $0.id == id }) {
                            let old = containers[index]
                            let newState = (action == "start" || action == "restart") ? "running" : "exited"
                            let newStatus = (action == "start" || action == "restart") ? "Up" : "Exited"
                            
                            containers[index] = DockerContainer(
                                id: old.id,
                                names: old.names,
                                image: old.image,
                                state: newState,
                                status: newStatus,
                                ports: old.ports
                            )
                        }
                    } else {
                        // For rm, rmi, prune, or others, refresh all to ensure consistency
                        Task { await fetchData() }
                    }
                } else {
                    self.activeAlert = .actionError(response.details ?? response.error ?? languageManager.t("common.failed"))
                }
            }
        } catch {
            await MainActor.run {
                self.activeAlert = .actionError(error.localizedDescription)
            }
        }
    }
}

// Sub-view for Docker Logs
struct DockerLogView: View {
    let containerId: String
    let containerName: String
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var logs: String = ""
    @State private var isLoading = true
    @State private var timer: Timer?
    @State private var autoScroll = true
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let lines = logs.components(separatedBy: .newlines)
                        let displayLines = lines.suffix(5000)
                        ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index % 2 == 0 ? Color.clear : Color.black.opacity(0.04))
                                .id(index)
                        }
                    }
                    .textSelection(.enabled)
                }
                .background(Color.black.opacity(0.02))
                
                if isLoading && logs.isEmpty {
                    LoadingView()
                }
            }
            .onAppear {
                let linesCount = logs.components(separatedBy: .newlines).suffix(5000).count
                if autoScroll && linesCount > 0 {
                    proxy.scrollTo(linesCount - 1, anchor: .bottom)
                }
            }
            .onChange(of: logs) {
                let linesCount = logs.components(separatedBy: .newlines).suffix(5000).count
                if autoScroll && linesCount > 0 {
                    withAnimation {
                        proxy.scrollTo(linesCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .refreshable {
            await fetchLogs()
        }
        .navigationTitle(String(format: languageManager.t("docker.containerLogs"), containerName))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await fetchLogs() }
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                Task { await fetchLogs(silent: true) }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    func fetchLogs(silent: Bool = false) async {
        if !silent { isLoading = true }
        do {
            let response: GenericLogResponse = try await apiClient.request("/api/docker/logs?id=\(containerId)")
            await MainActor.run {
                self.logs = response.logs
                self.isLoading = false
            }
        } catch {
            print("Fetch Docker logs failed: \(error)")
            if !silent { await MainActor.run { self.isLoading = false } }
        }
    }
    
    func analyzeLogs() {
        // AI Analysis logic using /api/ai
    }
}


#Preview {
    NavigationStack {
        DockerModuleView()
            .environment(RemoteAPIClient())
    }
}

struct DockerDetailView: View {
    let container: DockerContainer
    let loadingAction: [String: String]
    let onAction: (String) async -> Void
    var onViewLogs: () -> Void
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var confirmRestart = false
    @State private var confirmStop = false
    @State private var showingLogs = false
    
    var body: some View {
        List {
            Section(languageManager.t("docker.basicInfo")) {
                detailRow(label: languageManager.t("common.name"), value: container.name)
                detailRow(label: languageManager.t("common.id"), value: container.id.prefix(12).lowercased())
                detailRow(label: languageManager.t("docker.image"), value: container.image)
                if let command = container.command {
                    detailRow(label: languageManager.t("docker.command"), value: command)
                }
                if let created = container.createdAt {
                    detailRow(label: languageManager.t("docker.createdAt"), value: created)
                }
            }
            
            Section(languageManager.t("docker.status")) {
                HStack {
                    Text(languageManager.t("docker.serviceStatus"))
                    Spacer()
                    StatusBadge(status: container.state, showLabel: true, size: 14)
                }
                detailRow(label: languageManager.t("docker.statusDetail"), value: container.status)
            }
            
            if !container.ports.isEmpty {
                Section(languageManager.t("docker.mappings")) {
                    Text(container.ports)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(languageManager.t("common.delete"), systemImage: "trash")
                }
            }
        }
        .navigationTitle(container.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(destination: DockerLogView(containerId: container.id, containerName: container.name)) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                }
                
                let isRunning = container.state == "running"
                if isRunning {
                    toolbarButton(icon: "arrow.clockwise", color: .orange, isLoading: loadingAction[container.id] == "restart") {
                        confirmRestart = true
                    }
                    toolbarButton(icon: "stop", color: .red, isLoading: loadingAction[container.id] == "stop") {
                        confirmStop = true
                    }
                } else {
                    toolbarButton(icon: "play", color: .green, isLoading: loadingAction[container.id] == "start") {
                        await onAction("start")
                    }
                }
            }
        }
        .alert(languageManager.t("launchagent.deleteConfirmTitle"), isPresented: $confirmDelete) {
            Button(languageManager.t("common.delete"), role: .destructive) {
                Task {
                    await onAction("rm")
                    await MainActor.run { dismiss() }
                }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(String.localizedStringWithFormat(languageManager.t("launchagent.deleteConfirmMessage"), container.name))
        }
        .alert(languageManager.t("common.confirm"), isPresented: $confirmRestart) {
            Button(languageManager.t("server.restart"), role: .destructive) {
                Task { await onAction("restart") }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(languageManager.t("docker.restartConfirm"))
        }
        .alert(languageManager.t("common.confirm"), isPresented: $confirmStop) {
            Button(languageManager.t("common.stop"), role: .destructive) {
                Task { await onAction("stop") }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(languageManager.t("docker.stopConfirm"))
        }
    }
    
    private func toolbarButton(icon: String, color: Color, isLoading: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
        }
        .disabled(isLoading)
    }
    
    private func controlButton(icon: String, color: Color, label: String, isLoading: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.headline)
                }
                Text(label)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
