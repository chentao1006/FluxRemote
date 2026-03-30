
import SwiftUI
import Charts

@MainActor
struct DashboardView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var stats: RemoteSystemStats?
    @State private var errorMessage: String?
    @State private var history: [MetricPoint] = []
    @State private var prevNetBytes: RemoteNetBytes?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Binding var selection: NavigationItem?
    
    @State private var terminalCommand: String = ""
    @State private var terminalOutput: String = ""
    @State private var isExecutingCommand = false
    
    // Summary states
    @State private var dockerSummary: (running: Int, total: Int) = (0, 0)
    @State private var nginxSummary: (active: Int, total: Int) = (0, 0)
    @State private var procSummary: (total: Int, topName: String, topCpu: String) = (0, "", "")
    @State private var agentSummary: (loaded: Int, total: Int) = (0, 0)
    @State private var logSummary: (total: Int, lastFile: String) = (0, "")
    @State private var configSummary: (total: Int, sysCount: Int, userCount: Int) = (0, 0, 0)
    @State private var fetchTask: Task<Void, Never>?
    @State private var lastSummaryFetch: Date = .distantPast
    
    private var features: FeatureToggles { apiClient.features }
    
    @AppStorage("hasSeenScreenshotPermission") private var hasSeenScreenshotPermission: Bool = false
    @State private var showingScreenshotPermissionAlert = false

    // 判断是否为 iPhone 横屏
    var isIPhoneLandscape: Bool {
        UIDevice.current.userInterfaceIdiom == .phone &&
        verticalSizeClass == .compact
    }

    // summaryColumns 一行三个
    var summaryColumns: [GridItem] {
        if isIPhoneLandscape || horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible()), count: 3)
        } else {
            return Array(repeating: GridItem(.flexible()), count: 2)
        }
    }

    // detailColumns 一行三个
    var detailColumns: [GridItem] {
        if isIPhoneLandscape {
            return Array(repeating: GridItem(.flexible()), count: 3)
        } else if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible()), count: 4)
        } else {
            return Array(repeating: GridItem(.flexible()), count: 2)
        }
    }

    // Chart 区域的列数
    var chartColumns: [GridItem] {
        if isIPhoneLandscape {
            return Array(repeating: GridItem(.flexible()), count: 3)
        } else if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible()), count: 3)
        } else {
            return [GridItem(.flexible())]
        }
    }
    
    @State private var showingAIDisabledAlert = false
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            mainContent
        }
        .alert(languageManager.t("monitor.screenshotPermissionTitle"), isPresented: $showingScreenshotPermissionAlert) {
            Button(languageManager.t("common.ok"), role: .cancel) { 
                hasSeenScreenshotPermission = true
                takeScreenshot()
            }
        } message: {
            Text(languageManager.t("monitor.screenshotPermissionMessage"))
        }
        .alert(languageManager.t("settings.aiDisabled"), isPresented: $showingAIDisabledAlert) {
            Button(languageManager.t("common.ok"), role: .cancel) { }
        } message: {
            Text(languageManager.t("settings.aiDisabledDesc"))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        if apiClient.aiConfig?.enabled ?? false {
                            analyzeSystem()
                        } else {
                            showingAIDisabledAlert = true
                        }
                    }) {
                        if isAnalyzing {
                            ProgressView().controlSize(.small)
                        } else {
                            HStack {
                                Image(systemName: "sparkle.text.clipboard")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color("AccentColor").opacity(!(apiClient.aiConfig?.enabled ?? false) || isAnalyzing || stats == nil ? 0.5 : 1.0))
                                // Text(languageManager.t("common.aiAnalyze"))
                            }
                        }
                    }
                    .disabled(isAnalyzing || stats == nil)
            }

            ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        if !hasSeenScreenshotPermission {
                            showingScreenshotPermissionAlert = true
                        } else {
                            takeScreenshot()
                        }
                    }) {
                        if isCapturingScreenshot {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .disabled(isCapturingScreenshot)
            }
        }
        .sheet(isPresented: $showScreenshotSheet) {
            if let image = capturedImage {
                ScreenshotPreviewView(image: image)
            }
        }
        .onAppear {
            if stats == nil {
                stats = apiClient.dashboardStats
                history = apiClient.dashboardHistory
            }
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: apiClient.baseURL) { _, _ in
            Task { @MainActor in
                // Clear local states for a clean reset
                stats = nil
                history = []
                dockerSummary = (0, 0)
                nginxSummary = (0, 0)
                procSummary = (0, "", "")
                agentSummary = (0, 0)
                logSummary = (0, "")
                configSummary = (0, 0, 0)
                aiAnalysis = nil
                
                await handleRefresh()
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            Group {
                if let stats {
                    VStack(spacing: 20) {
                        if isAnalyzing || aiAnalysis != nil {
                            AIAnalysisCard(analysis: aiAnalysis, isAnalyzing: isAnalyzing) {
                                withAnimation {
                                    aiAnalysis = nil
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Metric Charts Section
                        VStack(alignment: .leading, spacing: 12) {
                            // ... (rest of stats content remains the same, but without its own ScrollView wrapper)
                            Text(languageManager.t("monitor.metrics"))
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: chartColumns, spacing: 16) {
                                ChartTile(title: languageManager.t("monitor.cpu"), 
                                         value: "\(Int((stats.cpu?.user ?? 0) + (stats.cpu?.sys ?? 0)))%", 
                                         subValue: "\(languageManager.t("monitor.user")): \(Int(stats.cpu?.user ?? 0))% | \(languageManager.t("monitor.sys")): \(Int(stats.cpu?.sys ?? 0))%",
                                         color: .blue, 
                                         data: history, 
                                         keyPath: \.cpu)
                                
                                ChartTile(title: languageManager.t("monitor.memory"), 
                                         value: "\(Int(Double(stats.memory.usedMB) / Double(stats.memory.totalMB) * 100))%", 
                                         subValue: "\(stats.memory.usedMB) MB / \(stats.memory.totalMB) MB",
                                         color: .orange, 
                                         data: history, 
                                         keyPath: \.memory)
                                
                                ChartTile(title: languageManager.t("monitor.network"), 
                                         value: "↓\(Int(history.last?.netIn ?? 0)) ↑\(Int(history.last?.netOut ?? 0))", 
                                         subValue: "\(languageManager.t("monitor.accumulated")): ↓\(formatBytes(stats.netBytes?.in ?? 0)) ↑\(formatBytes(stats.netBytes?.out ?? 0))",
                                         color: .green, 
                                         data: history, 
                                         isNetwork: true)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Summary Modules Section
                        VStack(alignment: .leading, spacing: 12) {
                            // ... (rest of summaries block)
                            Text(languageManager.t("monitor.sections"))
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: summaryColumns, spacing: 12) {
                                if features.processes != false {
                                    SummaryCard(
                                        icon: "square.stack.3d.up.fill",
                                        title: languageManager.t("sidebar.processes"),
                                        value: Text(procSummary.topName.isEmpty ? "\(procSummary.total)" : procSummary.topName).font(.system(size: 18, weight: .bold)),
                                        subtitle: procSummary.topName.isEmpty ? "" : "\(procSummary.total) \(languageManager.t("monitor.processes"))",
                                        rightLabel: procSummary.topCpu,
                                        action: { selection = .processes }
                                    )
                                }
                                
                                if features.logs != false {
                                    SummaryCard(
                                        icon: "doc.text.fill",
                                        title: languageManager.t("sidebar.logs"),
                                        value: Text(logSummary.lastFile.isEmpty ? languageManager.t("common.none") : logSummary.lastFile).font(.system(size: 18, weight: .bold)),
                                        subtitle: "\(logSummary.total) \(languageManager.t("monitor.logs"))",
                                        action: { selection = .logs }
                                    )
                                }
                                
                                if features.configs != false {
                                    SummaryCard(
                                        icon: "gearshape.2.fill",
                                        title: languageManager.t("sidebar.configs"),
                                        value: formattedConfigSummary,
                                        subtitle: "\(configSummary.total) \(languageManager.t("monitor.configs"))",
                                        action: { selection = .configs }
                                    )
                                }
                                
                                if features.launchagent != false {
                                    SummaryCard(
                                        icon: "bolt.fill",
                                        title: languageManager.t("sidebar.launchagent"),
                                        value: Text("\(agentSummary.loaded) / \(agentSummary.total)").font(.system(size: 18, weight: .bold)),
                                        subtitle: languageManager.t("launchagent.totalAgents"),
                                        action: { selection = .launchagent }
                                    )
                                }
                                
                                if features.docker != false {
                                    SummaryCard(
                                        icon: "cube.fill",
                                        title: languageManager.t("sidebar.docker"),
                                        value: Text("\(dockerSummary.running) / \(dockerSummary.total)").font(.system(size: 18, weight: .bold)),
                                        subtitle: languageManager.t("docker.running"),
                                        action: { selection = .docker }
                                    )
                                }
                                
                                if features.nginx != false {
                                    SummaryCard(
                                        icon: "server.rack",
                                        title: languageManager.t("sidebar.nginx"),
                                        value: Text("\(nginxSummary.active) / \(nginxSummary.total)").font(.system(size: 18, weight: .bold)),
                                        subtitle: languageManager.t("nginx.activeSites"),
                                        action: { selection = .nginx }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // System Details Tiles Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text(languageManager.t("monitor.info"))
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: detailColumns, spacing: 12) {
                                SystemDetailTile(icon: "desktopcomputer", title: languageManager.t("monitor.hostname"), value: stats.hostname)
                                SystemDetailTile(icon: "info.circle", title: languageManager.t("monitor.osVersion"), value: stats.osVersion)
                                SystemDetailTile(icon: "clock", title: languageManager.t("monitor.uptime"), value: stats.uptime.components(separatedBy: ",").first ?? "N/A")
                                SystemDetailTile(icon: "cpu", title: languageManager.t("monitor.arch"), value: stats.arch)
                                SystemDetailTile(icon: "internaldrive", title: languageManager.t("monitor.diskSpace"), value: "\(stats.disk.used) / \(stats.disk.total)")
                                SystemDetailTile(icon: "gauge", title: languageManager.t("monitor.loadAvg"), value: stats.loadAvg)
                                
                                if let battery = stats.battery {
                                    SystemDetailTile(icon: "battery.100", title: languageManager.t("monitor.battery"), value: battery)
                                }
                                if let memPressure = stats.memPressure {
                                    SystemDetailTile(icon: "memorychip", title: languageManager.t("monitor.memPressure"), value: memPressure)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label(languageManager.t("common.error"), systemImage: "wifi.exclamationmark.fill")
                    } description: {
                        Text(error)
                    } actions: {
                        Button(languageManager.t("common.retry")) {
                            Task { @MainActor in
                                self.errorMessage = nil
                                await fetchData()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    VStack {
                        Spacer()
                        LoadingView()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                }
            }
        }
        .tint(Color("AccentColor"))
        .refreshable {
            await handleRefresh()
        }
    }

    @MainActor
    private func handleRefresh() async {
        await fetchData()
        await fetchAllSummaries()
        await MainActor.run {
            lastSummaryFetch = Date()
        }
        try? await Task.sleep(for: .milliseconds(400))
    }

    
    @MainActor
    func fetchData() async {
        guard selection == .monitor else { return }
        do {
            let response: RemoteStatsResponse = try await apiClient.request("/api/system/stats")
            self.stats = response.data
            self.apiClient.dashboardStats = response.data
            self.errorMessage = nil
            updateHistory(with: response.data)
            self.apiClient.dashboardHistory = self.history
         } catch {
            print("Fetch stats error: \(error)")
            self.errorMessage = error.localizedDescription
        }
    }
    
    @MainActor
    func fetchAllSummaries() async {
        // Docker
        if let dockerResponse: DockerResponse = try? await apiClient.request("/api/docker/containers") {
            let running = dockerResponse.data.filter { $0.state == "running" }.count
            self.dockerSummary = (running, dockerResponse.data.count)
        }
        
        // Nginx
        if let nginxResponse: NginxResponse = try? await apiClient.request("/api/nginx/sites") {
            let active = nginxResponse.data?.filter { $0.status == "enabled" }.count ?? 0
            self.nginxSummary = (active, nginxResponse.data?.count ?? 0)
        }
        
        // Processes
        if let procResponse: ProcessResponse = try? await apiClient.request("/api/system/processes?sort=cpu") {
            let top = procResponse.data.first
            self.procSummary = (procResponse.data.count, top?.command ?? "", top != nil ? "\(top!.cpu)%" : "")
        }
        
        // LaunchAgents
        if let agentResponse: LaunchAgentResponse = try? await apiClient.request("/api/launchagent/list") {
            let loaded = agentResponse.data.filter { $0.isLoaded }.count
            self.agentSummary = (loaded, agentResponse.data.count)
        }
        
        // Logs
        if let logResponse: LogResponse = try? await apiClient.request("/api/logs") {
            if case .list(let items) = logResponse.data {
                let sorted = items.sorted { $0.mtime > $1.mtime }
                self.logSummary = (items.count, sorted.first?.name ?? "")
            }
        }
        
        // Configs
        if let configResponse: ConfigResponse = try? await apiClient.request("/api/configs") {
            if let items = configResponse.data {
                let sysCount = items.filter { 
                    let cat = $0.category.lowercased()
                    return cat == "system" || cat == "sys"
                }.count
                self.configSummary = (items.count, sysCount, items.count - sysCount)
            }
        }
    }
    
    @MainActor
    private func updateHistory(with stats: RemoteSystemStats) {
        let cpu = (stats.cpu?.user ?? 0) + (stats.cpu?.sys ?? 0)
        let mem = Double(stats.memory.usedMB) / Double(stats.memory.totalMB) * 100
        
        var netIn: Double = 0
        var netOut: Double = 0
        
        if let currentNet = stats.netBytes, let prevNet = prevNetBytes {
            // Updated to 5s interval for speed calculation
            netIn = Double(currentNet.in - prevNet.in) / 1024 / 5.0
            netOut = Double(currentNet.out - prevNet.out) / 1024 / 5.0
        }
        
        self.prevNetBytes = stats.netBytes
        
        let point = MetricPoint(date: Date(), cpu: cpu, memory: mem, netIn: max(0, netIn), netOut: max(0, netOut))
        history.append(point)
        if history.count > 60 { history.removeFirst() }
    }
    
    private var formattedConfigSummary: Text {
        Text("\(configSummary.sysCount)")
            .font(.system(size: 16, weight: .bold))
        + Text(" \(languageManager.t("monitor.sys"))")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        + Text(" | ")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.secondary.opacity(0.5))
        + Text("\(configSummary.userCount)")
            .font(.system(size: 16, weight: .bold))
        + Text(" \(languageManager.t("monitor.user"))")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
    
    @MainActor
    func startTimer() {
        fetchTask?.cancel()
        fetchTask = Task { @MainActor in
            // Initial fetch
            await fetchData()
            await fetchAllSummaries()
            await MainActor.run {
                lastSummaryFetch = Date()
            }
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                
                await fetchData()
                
                // Fetch summaries every 30 seconds
                let shouldFetchSummary = await MainActor.run {
                    Date().timeIntervalSince(lastSummaryFetch) >= 30
                }
                
                if shouldFetchSummary {
                    await fetchAllSummaries()
                    await MainActor.run {
                        lastSummaryFetch = Date()
                    }
                }
            }
        }
    }
    
    @MainActor
    func stopTimer() {
        fetchTask?.cancel()
        fetchTask = nil
    }
    
    @State private var aiAnalysis: String?
    @State private var isAnalyzing = false
    
    @MainActor
    func analyzeSystem() {
        guard let stats = stats else { return }
        isAnalyzing = true
        aiAnalysis = nil
        Task { @MainActor in
            do {
                let prompt = """
Help me analyze this system status output:
Hostname: \(stats.hostname)
OS: \(stats.osVersion)
CPU: \(Int((stats.cpu?.user ?? 0) + (stats.cpu?.sys ?? 0)))% (User: \(Int(stats.cpu?.user ?? 0))%, Sys: \(Int(stats.cpu?.sys ?? 0))%)
Memory: \(stats.memory.usedMB)/\(stats.memory.totalMB)MB
Disk: \(stats.disk.percent)
Load: \(stats.loadAvg)
Processes: \(procSummary.total) Total, Top: \(procSummary.topName) (\(procSummary.topCpu))
Docker: \(dockerSummary.running)/\(dockerSummary.total) Running
Nginx: \(nginxSummary.active)/\(nginxSummary.total) Active
LaunchAgents: \(agentSummary.loaded)/\(agentSummary.total) Loaded

Please provide comments on health, resource usage, and any suggestions in \(languageManager.aiResponseLanguage). Use clean Markdown formatting.
"""
                let response = try await AIService.shared.analyze(prompt: prompt, systemPrompt: "You are a professional system assistant analyzing macOS health and resource usage.", apiClient: apiClient)
                withAnimation {
                    self.aiAnalysis = response
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    let errorMsg = error.localizedDescription
                    if errorMsg.contains("AI_CONFIG_MISSING") {
                        self.aiAnalysis = "\(languageManager.t("common.errors.aiConfigMissing")): \(languageManager.t("common.errors.aiConfigMissingDetail"))"
                    } else {
                        self.aiAnalysis = "\(languageManager.t("monitor.analysisFailed")): \(errorMsg)"
                    }
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    @State private var isCapturingScreenshot = false
    @State private var capturedImage: UIImage?
    @State private var showScreenshotSheet = false
    
    @MainActor
    func takeScreenshot() {
        isCapturingScreenshot = true
        Task { @MainActor in
            do {
                let response: ScreenshotResponse = try await apiClient.request("/api/system/screenshot", method: "POST")
                if let base64 = response.data?.components(separatedBy: ",").last,
                   let data = Data(base64Encoded: base64),
                   let image = UIImage(data: data) {
                    self.capturedImage = image
                    self.showScreenshotSheet = true
                    self.isCapturingScreenshot = false
                } else {
                    throw NSError(domain: "ScreenshotError", code: 0, userInfo: [NSLocalizedDescriptionKey: languageManager.t("monitor.decodeFailed")])
                }
            } catch {
                self.isCapturingScreenshot = false
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1024 / 1024 / 1024
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(bytes) / 1024 / 1024
            return String(format: "%.0f MB", mb)
        }
    }
}

struct ScreenshotPreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageManager.self) private var languageManager
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationStack {
            VStack {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale *= delta
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .clipped()
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .padding()
            }
            .navigationTitle(languageManager.t("monitor.screenshot"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 20) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(languageManager.t("monitor.screenshot"), image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}


struct ChartTile: View {
    @Environment(AppLanguageManager.self) private var languageManager
    let title: String
    let value: String
    let subValue: String
    let color: Color
    let data: [MetricPoint]
    var keyPath: KeyPath<MetricPoint, Double>? = nil
    var isNetwork: Bool = false
    
    var body: some View {
        let now = Date()
        let visibleRange = now.addingTimeInterval(-300)...now
        
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Value Row
            Group {
                if isNetwork {
                    let down = Int(data.last?.netIn ?? 0)
                    let up = Int(data.last?.netOut ?? 0)
                    HStack(spacing: 8) {
                        Label("\(down)", systemImage: "arrow.down")
                            .foregroundStyle(.blue)
                        Label("\(up)", systemImage: "arrow.up")
                            .foregroundStyle(.green)
                        
                        Text("KB/s")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                    .font(.title3)
                    .fontWeight(.bold)
                } else {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                }
            }
            .frame(height: 24)
            
            // SubValue Row
            Text(subValue)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 12)
            
            chartContent(now: now)
                .frame(height: 70)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private func chartContent(now: Date) -> some View {
        let visibleRange = now.addingTimeInterval(-300)...now
        let visibleData = data.filter { visibleRange.contains($0.date) }
        let currentDomain = calculateDomain(for: visibleData)
        
        if isNetwork {
            ZStack {
                // 下载图表
                Chart(data) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value(languageManager.t("monitor.download"), point.netIn)
                    )
                    .foregroundStyle(.blue.opacity(0.18))
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(languageManager.t("monitor.download"), point.netIn)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartXScale(domain: visibleRange)
                .chartYAxis {
                    AxisMarks(position: .trailing)
                }
                .chartYScale(domain: currentDomain)
                
                // 上传图表
                Chart(data) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value(languageManager.t("monitor.upload"), point.netOut)
                    )
                    .foregroundStyle(.green.opacity(0.18))
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(languageManager.t("monitor.upload"), point.netOut)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartXScale(domain: visibleRange)
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisValueLabel().foregroundStyle(.clear)
                    }
                }
                .chartYScale(domain: currentDomain)
            }
        } else if let keyPath = keyPath {
            Chart(data) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point[keyPath: keyPath])
                )
                .foregroundStyle(color.opacity(0.1))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point[keyPath: keyPath])
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: visibleRange)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100])
            }
            .chartYScale(domain: currentDomain)
        }
    }
    
    private func calculateDomain(for visibleData: [MetricPoint]) -> ClosedRange<Double> {
        if isNetwork {
            let maxVal = visibleData.map { max($0.netIn, $0.netOut) }.max() ?? 10
            return 0.0...max(10.0, maxVal * 1.2)
        } else {
            return 0.0...100.0
        }
    }
}

struct SystemDetailTile: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SummaryCard: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    let icon: String
    let title: String
    let value: Text
    let subtitle: String?
    var valueLabel: String? = nil
    var rightLabel: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if let rightLabel = rightLabel {
                        Text(rightLabel)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .fontWeight(.bold)
                    }
                }
                .foregroundStyle(.secondary)
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    value
                    
                    if let valueLabel = valueLabel {
                        Text(valueLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        Divider()
    }
}



#Preview {
    NavigationStack {
        DashboardView(selection: .constant(.monitor))
            .environment(RemoteAPIClient())
    }
}

