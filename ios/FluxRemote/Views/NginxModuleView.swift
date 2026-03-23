import SwiftUI

struct NginxModuleView: View {
        @State private var confirmDeleteSite: NginxSite? = nil
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var sites: [NginxSite] = []
    @State private var serviceStatus: NginxResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var showingAddSite = false
    @State private var editingSite: NginxSite?
    @State private var showingErrorLog = false
    @State private var loadingAction: [String: String] = [:] // key: site.name or "service", value: action
    @State private var showingSudoPrompt = false
    @State private var sudoPassword = ""
    @State private var currentAction: String? // "service" or "site"
    @State private var currentSite: NginxSite?
    @State private var currentServiceAction: String? // "start", "stop", etc.
    @State private var showingRestartConfirm = false
    @State private var showingStopConfirm = false
    
    var body: some View {
        List {
            if isLoading && sites.isEmpty {
                LoadingView()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if let error = errorMessage {
                ContentUnavailableView(languageManager.t("common.error"), systemImage: "wifi.exclamationmark.fill", description: Text(error))
                    .listRowBackground(Color.clear)
            } else {
                serviceSection
                siteSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(languageManager.t("sidebar.nginx"))
        .refreshable {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await fetchData() }
                group.addTask { try? await Task.sleep(for: .milliseconds(600)) }
                await group.waitForAll()
            }
        }
        .onAppear {
            Task { await fetchData() }
        }
        .alert(languageManager.t("common.confirm"), isPresented: $showingRestartConfirm) {
            Button(languageManager.t("server.restart"), role: .destructive) {
                Task { await performAction("restart") }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(languageManager.t("nginx.restartConfirm"))
        }
        .alert(languageManager.t("common.confirm"), isPresented: $showingStopConfirm) {
            Button(languageManager.t("server.stop"), role: .destructive) {
                Task { await performAction("stop") }
            }
            Button(languageManager.t("common.cancel"), role: .cancel) { }
        } message: {
            Text(languageManager.t("nginx.stopConfirm"))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddSite = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSite) {
            NavigationStack {
                NginxSiteEditView(site: nil) { await fetchData() }
            }
        }
        .sheet(item: $editingSite) { site in
            NavigationStack {
                NginxSiteEditView(site: site) { await fetchData() }
            }
        }
        .sheet(isPresented: $showingErrorLog) {
            NavigationStack {
                NginxErrorLogView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: { showingErrorLog = false }) { Image(systemName: "xmark") }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSudoPrompt) {
            SudoPasswordView(password: $sudoPassword) {
                Task {
                    if let site = currentSite {
                        if currentAction == "toggle" { await toggleSite(site) }
                        else if currentAction == "delete" { await deleteSite(site) }
                    } else if let action = currentServiceAction {
                        await performAction(action)
                    }
                }
            }
        }
        .alert(languageManager.t("common.error"), isPresented: Binding(
            get: { errorMessage != nil && !showingSudoPrompt },
            set: { _ in errorMessage = nil }
        )) {
            Button(languageManager.t("common.ok"), role: .cancel) { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    func resetCurrentAction() {
        currentAction = nil
        currentSite = nil
        currentServiceAction = nil
    }
    
    private var serviceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    StatusBadge(status: serviceStatus?.running == true ? "running" : "stopped", size: 14)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("nginx.runningStatus"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let pids = serviceStatus?.pids, !pids.isEmpty {
                            Text("\(languageManager.t("common.pids")): \(pids.joined(separator: ", "))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                }
                
                if let binPath = serviceStatus?.binPath {
                    Text(String(format: languageManager.t("nginx.binPath"), binPath))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 20) {
                    let isRunning = serviceStatus?.running == true
                    actionButton(icon: isRunning ? "stop" : "play", color: isRunning ? .red : .green, label: isRunning ? languageManager.t("server.stop") : languageManager.t("server.start"), isLoading: loadingAction["service"] == (isRunning ? "stop" : "start")) {
                        if isRunning {
                            currentServiceAction = "stop"
                            showingStopConfirm = true
                        } else {
                            await performAction("start")
                        }
                    }

                    actionButton(icon: "arrow.clockwise", color: .blue, label: languageManager.t("server.restart"), isLoading: loadingAction["service"] == "restart") {
                        currentServiceAction = "restart"
                        showingRestartConfirm = true
                    }

                    actionButton(icon: "checkmark.shield", color: .orange, label: languageManager.t("common.test"), isLoading: loadingAction["service"] == "test") {
                        await performAction("test")
                    }

                    Spacer()
                }
            }
            .padding(.vertical, 8)
            
            Button {
                showingErrorLog = true
            } label: {
                Label(languageManager.t("nginx.viewErrorLogs"), systemImage: "doc.text")
                    .foregroundStyle(.blue)
            }
        } header: {
            Text(languageManager.t("nginx.serviceControl"))
        }
    }
    
    private var siteSection: some View {
        Section {
            ForEach($sites) { $site in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusBadge(status: site.status == "enabled" ? "running" : "stopped", size: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name)
                                .font(.headline)
                            Text("\(site.serverName):\(site.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 16) {
                        let isEnabled = site.status == "enabled"
                        actionButton(icon: isEnabled ? "stop" : "play", color: isEnabled ? .red : .green, isLoading: loadingAction[site.name] == (isEnabled ? "disable" : "enable")) {
                            await toggleSite(site)
                        }
                        actionButton(icon: "pencil", color: .blue) {
                            editingSite = site
                        }
                        Spacer()
                        actionButton(icon: "trash", color: .red, isLoading: loadingAction[site.name] == "delete") {
                            confirmDeleteSite = site
                        }
                        .alert(item: $confirmDeleteSite) { site in
                            Alert(
                                title: Text(languageManager.t("launchagent.deleteConfirmTitle")),
                                message: Text(String.localizedStringWithFormat(languageManager.t("launchagent.deleteConfirmMessage"), site.name)),
                                primaryButton: .destructive(Text(languageManager.t("launchagent.delete"))) {
                                    Task { await deleteSite(site) }
                                },
                                secondaryButton: .cancel(Text(languageManager.t("common.cancel")))
                            )
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(languageManager.t("nginx.siteManagement"))
        }
    }
    
    private func actionButton(icon: String, color: Color, label: String? = nil, isLoading: Bool = false, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.subheadline)
                }
                if let label = label {
                    Text(label)
                        .font(.subheadline)
                }
            }
            .padding(8)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    func fetchData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let sitesTask: NginxResponse = apiClient.request("/api/nginx/sites")
            async let statusTask: NginxResponse = apiClient.request("/api/nginx/action", method: "POST", body: ["action": "status"])
            
            let (sRes, stRes) = try await (sitesTask, statusTask)
            
            await MainActor.run {
                self.sites = sRes.data ?? []
                self.serviceStatus = stRes
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch {
            print("Fetch nginx failed: \(error)")
            await MainActor.run { 
                self.errorMessage = error.localizedDescription
                self.isLoading = false 
            }
        }
    }
    
    func performAction(_ action: String) async {
        loadingAction["service"] = action
        currentServiceAction = action
        do {
            var body: [String: Any] = ["action": action]
            if !sudoPassword.isEmpty {
                body["password"] = sudoPassword // Note: Nginx action API use "password" instead of "sudoPassword"
            }
            
            let response: ActionResponse = try await apiClient.request("/api/nginx/action", method: "POST", body: body)
            if response.success {
                self.sudoPassword = ""
                resetCurrentAction()
                await fetchData()
            } else if response.requiresPassword == true || response.error == "SUDO_REQUIRED" {
                await MainActor.run {
                    self.showingSudoPrompt = true
                }
            } else if response.error == "SUDO_AUTH_FAILED" || response.error == "SUDO_PASSWORD_INCORRECT" {
                await MainActor.run {
                   self.errorMessage = languageManager.t("common.passwordIncorrect")
                   self.sudoPassword = ""
                   resetCurrentAction()
                }
            } else {
                await MainActor.run {
                    self.errorMessage = response.details ?? response.error ?? languageManager.t("common.failed")
                    resetCurrentAction()
                }
            }
        } catch {
            print("Action failed: \(error)")
            let errorMsg = error.localizedDescription
            await MainActor.run {
                let msg = errorMsg.lowercased()
                let isPermissionError = msg.contains("sudo_required") || msg.contains("requirespassword") || msg.contains("permission_denied") || msg.contains("permission denied") || msg.contains("eacces") || msg.contains("eperm")
                
                if isPermissionError && self.sudoPassword.isEmpty {
                    self.showingSudoPrompt = true
                } else {
                    self.errorMessage = errorMsg
                    resetCurrentAction()
                }
            }
        }
        loadingAction["service"] = nil
    }
    
    func toggleSite(_ site: NginxSite) async {
        let action = site.status == "enabled" ? "disable" : "enable"
        loadingAction[site.name] = action
        currentAction = "toggle"
        currentSite = site
        do {
            var body: [String: Any] = ["action": action, "filename": site.name]
            if !sudoPassword.isEmpty {
                body["sudoPassword"] = sudoPassword
            }
            let _: ActionResponse = try await apiClient.request("/api/nginx/sites", method: "POST", body: body)
            self.sudoPassword = ""
            resetCurrentAction()
            await fetchData()
        } catch {
            print("Toggle site failed: \(error)")
            let errorMsg = error.localizedDescription
            await MainActor.run {
                let msg = errorMsg.lowercased()
                let isPermissionError = msg.contains("sudo_required") || msg.contains("permission_denied") || msg.contains("permission denied") || msg.contains("eacces") || msg.contains("eperm")
                if isPermissionError && self.sudoPassword.isEmpty {
                    self.showingSudoPrompt = true
                } else if msg.contains("sudo_password_incorrect") || msg.contains("incorrect password") || msg.contains("auth failed") {
                    self.errorMessage = languageManager.t("common.passwordIncorrect")
                    self.sudoPassword = ""
                } else {
                    self.errorMessage = errorMsg
                    resetCurrentAction()
                }
            }
        }
        loadingAction[site.name] = nil
    }
    
    func deleteSite(_ site: NginxSite) async {
        loadingAction[site.name] = "delete"
        currentAction = "delete"
        currentSite = site
        do {
            var body: [String: Any] = ["action": "delete", "filename": site.name]
            if !sudoPassword.isEmpty {
                body["sudoPassword"] = sudoPassword
            }
            let _: ActionResponse = try await apiClient.request("/api/nginx/sites", method: "POST", body: body)
            self.sudoPassword = ""
            resetCurrentAction()
            await fetchData()
        } catch {
            print("Delete site failed: \(error)")
            let errorMsg = error.localizedDescription
            await MainActor.run {
                let msg = errorMsg.lowercased()
                let isPermissionError = msg.contains("sudo_required") || msg.contains("permission_denied") || msg.contains("permission denied") || msg.contains("eacces") || msg.contains("eperm")
                if isPermissionError && self.sudoPassword.isEmpty {
                    self.showingSudoPrompt = true
                } else if msg.contains("sudo_password_incorrect") || msg.contains("incorrect password") || msg.contains("auth failed") {
                    self.errorMessage = languageManager.t("common.passwordIncorrect")
                    self.sudoPassword = ""
                } else {
                    self.errorMessage = errorMsg
                    resetCurrentAction()
                }
            }
        }
        loadingAction[site.name] = nil
    }
}

struct NginxSiteEditView: View {
    let site: NginxSite?
    var onSave: () async -> Void
    
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @Environment(\.dismiss) private var dismiss
    @State private var filename: String = ""
    @State private var content: String = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSudoPrompt = false
    @State private var sudoPassword = ""
    
    var body: some View {
        VStack(spacing: 0) {
            if site == nil {
                TextField(languageManager.t("nginx.filenamePlaceholder"), text: $filename)
                    .textFieldStyle(.roundedBorder)
                    .padding()
            }
            
            if isLoading {
                ProgressView().padding()
            }
            
            TextEditor(text: $content)
                .font(.system(.caption2, design: .monospaced))
                .padding(4)
        }
        .navigationTitle(site == nil ? Text(languageManager.t("nginx.addSite")) : Text(site!.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) { Image(systemName: "xmark") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { Task { await save() } }) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .disabled(isSaving || (site == nil && filename.isEmpty))
            }
        }
        .onAppear {
            if let site {
                filename = site.name
                Task { await fetchContent() }
            } else {
                content = """
server {
    listen 80;
    server_name example.com;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
"""
            }
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
                Task { await save() }
            }
        }
    }
    
    func fetchContent() async {
        isLoading = true
        do {
            let response: ConfigResponse = try await apiClient.request("/api/nginx/sites", method: "POST", body: ["action": "read", "filename": filename])
            await MainActor.run {
                self.content = response.content ?? ""
                self.isLoading = false
            }
        } catch {
            print("Fetch nginx site content failed: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func save() async {
        isSaving = true
        errorMessage = nil
        do {
            var body: [String: Any] = [
                "action": "write",
                "filename": filename,
                "content": content
            ]
            if !sudoPassword.isEmpty {
                body["sudoPassword"] = sudoPassword
            }
            
            let _: ActionResponse = try await apiClient.request("/api/nginx/sites", method: "POST", body: body)
            await onSave()
            await MainActor.run { 
                self.isSaving = false
                self.sudoPassword = ""
                dismiss() 
            }
        } catch {
            print("Save nginx site failed: \(error)")
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
    NavigationStack {
        NginxModuleView()
            .environment(RemoteAPIClient())
    }
}

struct NginxErrorLogView: View {
    @Environment(RemoteAPIClient.self) private var apiClient
    @Environment(AppLanguageManager.self) private var languageManager
    @State private var logs: String = ""
    @State private var isLoading = true
    
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
            .onChange(of: logs) {
                let linesCount = logs.components(separatedBy: .newlines).suffix(5000).count
                if linesCount > 0 {
                    withAnimation {
                        proxy.scrollTo(linesCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .refreshable {
            await fetchLogs()
        }
        .navigationTitle(languageManager.t("nginx.errorLogs"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await fetchLogs() }
        }
    }
    
    func fetchLogs() async {
        isLoading = true
        do {
            let response: GenericLogResponse = try await apiClient.request("/api/nginx/action", method: "POST", body: ["action": "logs"])
            await MainActor.run {
                self.logs = response.logs
                self.isLoading = false
            }
        } catch {
            print("Fetch Nginx logs failed: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
}
