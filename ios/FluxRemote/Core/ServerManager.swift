import Foundation
import Observation

struct ServerConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var username: String?
    var isOffline: Bool = false
    var isLauncher: Bool = false
    
    var baseURL: URL? {
        var urlStr = url
        if !urlStr.hasSuffix("/") { urlStr += "/" }
        return URL(string: urlStr)
    }
}

@MainActor
@Observable
class ServerManager {
    static let shared = ServerManager()
    
    var servers: [ServerConfig] = []
    var selectedServerId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedServerId?.uuidString, forKey: "selected_server_id_v2")
        }
    }
    var authenticatedServerIds: Set<UUID> = [] {
        didSet {
            let strings = Array(authenticatedServerIds).map { $0.uuidString }
            UserDefaults.standard.set(strings, forKey: "authenticated_server_ids_v2")
        }
    }
    
    var isCloudSyncEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isCloudSyncEnabled, forKey: "is_cloud_sync_enabled")
            if isCloudSyncEnabled {
                CloudSyncManager.shared.upload(servers: servers)
            }
        }
    }
    
    private let serversKey = "flux_remote_servers_v2"
    private var isCloudUpdating = false
    
    init() {
        self.isCloudSyncEnabled = UserDefaults.standard.object(forKey: "is_cloud_sync_enabled") as? Bool ?? true
        
        if let idString = UserDefaults.standard.string(forKey: "selected_server_id_v2") {
            self.selectedServerId = UUID(uuidString: idString)
        }
        if let authStrings = UserDefaults.standard.stringArray(forKey: "authenticated_server_ids_v2") {
            self.authenticatedServerIds = Set(authStrings.compactMap { UUID(uuidString: $0) })
        }
        
        // Load local servers first (fast)
        loadLocalServers()
        
        // Setup cloud sync observers but defer initial sync
        setupCloudSync()
        
        // Asynchronously check cloud for updates after a short delay to allow app to finish launching
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            await manualSync()
        }
    }
    
    private func loadLocalServers() {
        if let data = UserDefaults.standard.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            self.servers = decoded
        } else {
            // Migration for old single server config
            if let oldURL = UserDefaults.standard.string(forKey: "flux_remote_url") {
                let oldUser = UserDefaults.standard.string(forKey: "flux_remote_user")
                let oldServer = ServerConfig(name: "Default Server", url: oldURL, username: oldUser)
                self.servers = [oldServer]
                self.selectedServerId = oldServer.id
                saveLocalOnly() 
            }
        }
    }
    
    private func setupCloudSync() {
        CloudSyncManager.shared.onCloudDataChanged = { [weak self] cloudServers in
            Task { @MainActor in
                guard let self = self, self.isCloudSyncEnabled else { return }
                self.mergeWithCloud(cloudServers)
            }
        }
    }
    
    private func mergeWithCloud(_ cloudServers: [ServerConfig]) {
        var merged: [ServerConfig] = self.servers
        var hasChanges = false
        
        // 1. Add/Update servers from cloud
        for cloudServer in cloudServers {
            if let index = merged.firstIndex(where: { $0.id == cloudServer.id }) {
                // If ID matches, check if content (like isOffline or Name) changed
                if merged[index] != cloudServer {
                    merged[index] = cloudServer
                    hasChanges = true
                }
            } else {
                // New from cloud
                merged.append(cloudServer)
                hasChanges = true
            }
        }
        
        // 2. Check if local has anything not in cloud
        let cloudIds = Set(cloudServers.map { $0.id })
        let localMissingInCloud = self.servers.contains { !cloudIds.contains($0.id) }
        
        isCloudUpdating = true
        self.servers = merged
        saveLocalOnly()
        isCloudUpdating = false
        
        // 3. Force upload if local had extra data to ensure Cloud eventually has EVERYTHING
        if localMissingInCloud || hasChanges {
            CloudSyncManager.shared.upload(servers: self.servers)
        }
    }
    
    var selectedServer: ServerConfig? {
        if let sid = selectedServerId, let server = servers.first(where: { $0.id == sid }) {
            return server
        }
        return servers.first(where: { !$0.isOffline }) ?? servers.first
    }
    
    func selectServer(_ server: ServerConfig) {
        selectedServerId = server.id
        saveServers()
    }
    
    func setAuthenticated(_ authenticated: Bool, for serverId: UUID) {
        if authenticated {
            authenticatedServerIds.insert(serverId)
        } else {
            authenticatedServerIds.remove(serverId)
        }
    }
    
    func isServerAuthenticated(_ serverId: UUID) -> Bool {
        authenticatedServerIds.contains(serverId)
    }
    
    func addServer(_ server: ServerConfig) {
        if servers.isEmpty {
            selectedServerId = server.id
        }
        servers.append(server)
        saveServers()
    }
    
    func updateServer(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }
    
    func removeServer(_ server: ServerConfig) {
        let wasSelected = (selectedServerId == server.id)
        servers.removeAll { $0.id == server.id }
        authenticatedServerIds.remove(server.id)
        if wasSelected {
            selectedServerId = servers.first?.id
        }
        saveServers()
    }
    
    // loadLocalServers replaces the problematic loadServers to avoid blocking launch screen
    
    func manualSync() async {
        print("iCloud: Manual sync requested.")
        
        // 1. Wait for URL initialization if it's still in progress (max 2 seconds)
        var retryCount = 0
        while CloudSyncManager.shared.ubiquityURL == nil && retryCount < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            retryCount += 1
        }
        
        // 2. Force discovery and download
        CloudSyncManager.shared.forceDownload()
        
        // 3. Wait a bit for MetadataQuery to find changes
        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
        
        // 4. Try to download current state
        if let cloudServers = CloudSyncManager.shared.download() {
            print("iCloud: Manual sync found \(cloudServers.count) servers.")
            mergeWithCloud(cloudServers)
        } else {
            print("iCloud: Manual sync found no servers or container not ready.")
        }
    }
    
    private func saveServers() {
        saveLocalOnly()
        if isCloudSyncEnabled && !isCloudUpdating {
            CloudSyncManager.shared.upload(servers: servers)
        }
    }
    
    private func saveLocalOnly() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: serversKey)
        }
    }
}

@MainActor
class CloudSyncManager {
    static let shared = CloudSyncManager()
    
    private let containerIdentifier = "iCloud.com.ct106.flux.shared"
    private let filePrefix = "server_"
    private let fileExtension = "json"
    
    private var cachedUbiquityURL: URL?
    private var isInitializingUbiquity = false
    
    var ubiquityURL: URL? {
        if let cached = cachedUbiquityURL { return cached }
        return nil
    }
    
    private var documentsURL: URL? {
        cachedUbiquityURL?.appendingPathComponent("Documents")
    }
    
    private var metadataQuery: NSMetadataQuery?
    
    var onCloudDataChanged: (([ServerConfig]) -> Void)?
    
    init() {
        // Defer all heavy setup to allow the App to finish launching visually
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s defer
            setupUbiquity()
            setupQuery()
        }
    }
    
    private func setupUbiquity() {
        guard !isInitializingUbiquity else { return }
        isInitializingUbiquity = true
        
        print("iCloud: Starting ubiquity initialization for \(containerIdentifier)...")
        Task.detached(priority: .background) {
            let url = FileManager.default.url(forUbiquityContainerIdentifier: self.containerIdentifier)
            await MainActor.run {
                self.cachedUbiquityURL = url
                self.isInitializingUbiquity = false
                
                if let url = url {
                    print("iCloud: Container ready at \(url.path)")
                    // Once container is ready, we need to restart the query to ensure it searches the newly discovered path
                    self.restartQuery()
                } else {
                    print("iCloud: ERROR - Container NOT available. Check Apple ID, iCloud Drive status, and entitlements.")
                }
            }
        }
    }
    
    func restartQuery() {
        print("iCloud: Restarting metadata query...")
        metadataQuery?.stop()
        setupQuery()
    }
    
    private func setupQuery() {
        let query = NSMetadataQuery()
        query.notificationBatchingInterval = 1
        // Using both Documents and Data scopes to ensure we find files regardless of where the system places them
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryUbiquitousDataScope]
        
        // Match files starting with server_ and ending with .json
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@ AND %K ENDSWITH %@", 
                                    NSMetadataItemFSNameKey, filePrefix,
                                    NSMetadataItemFSNameKey, fileExtension)
        
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidUpdate), name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidUpdate), name: .NSMetadataQueryDidUpdate, object: query)
        
        self.metadataQuery = query
        query.start()
        print("iCloud: Metadata query started.")
    }
    
    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        Task {
            await processCloudChanges()
        }
    }
    
    private func processCloudChanges() async {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        
        let results = query.results as! [NSMetadataItem]
        if results.count > 0 {
            print("iCloud: Query found \(results.count) potential server files.")
        }
        
        // Extract Sendable information from non-sendable NSMetadataItems before passing to detached Task
        struct CloudFileInfo: Sendable {
            let url: URL
            let isCurrent: Bool
        }
        
        let fileInfos = results.compactMap { item -> CloudFileInfo? in
            guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return nil }
            let downloadingStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            return CloudFileInfo(url: fileURL, isCurrent: downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent)
        }
        
        // Offload the heavy NSFileCoordinator and decoding work to a background thread
        let allServers = await Task.detached(priority: .userInitiated) { () -> [ServerConfig] in
            var decodedServers: [ServerConfig] = []
            let coordinator = NSFileCoordinator(filePresenter: nil)
            
            for info in fileInfos {
                let fileURL = info.url
                
                if !info.isCurrent {
                    print("iCloud: File \(fileURL.lastPathComponent) is not local. Starting download...")
                    try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                    continue
                }
                
                var server: ServerConfig?
                var error: NSError?
                // coordinate is blocking; we are safe here since we are in Task.detached
                coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &error) { readURL in
                    do {
                        let data = try Data(contentsOf: readURL)
                        server = try JSONDecoder().decode(ServerConfig.self, from: data)
                    } catch {
                        print("iCloud: Error decoding \(fileURL.lastPathComponent): \(error)")
                    }
                }
                
                if let server = server {
                    decodedServers.append(server)
                }
            }
            return decodedServers
        }.value
        
        if !allServers.isEmpty {
            print("iCloud: Successfully processed \(allServers.count) servers from cloud.")
            onCloudDataChanged?(allServers)
        }
    }
    
    func upload(servers: [ServerConfig]) {
        guard let docURL = documentsURL else { 
            print("iCloud: Upload skipped - Container URL not ready yet.")
            return 
        }
        
        // Capture local copies of constants for Sendable transfer
        let prefix = self.filePrefix
        let ext = self.fileExtension
        
        // Perform file modifications and coordinator work in Background
        Task.detached(priority: .utility) {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            
            if !FileManager.default.fileExists(atPath: docURL.path) {
                try? FileManager.default.createDirectory(at: docURL, withIntermediateDirectories: true)
            }
            
            // 1. Clean up old files
            if let existingFiles = try? FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil) {
                let serverFiles = existingFiles.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == ext }
                let currentFileNames = Set(servers.map { "\(prefix)\($0.id.uuidString).\(ext)" })
                
                for fileURL in serverFiles {
                    if !currentFileNames.contains(fileURL.lastPathComponent) {
                        var error: NSError?
                        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &error) { deleteURL in
                            try? FileManager.default.removeItem(at: deleteURL)
                        }
                    }
                }
            }

            // 2. Upload/Update each server
            for server in servers {
                let fileName = "\(prefix)\(server.id.uuidString).\(ext)"
                let url = docURL.appendingPathComponent(fileName)
                
                do {
                    let data = try JSONEncoder().encode(server)
                    var error: NSError?
                    
                    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writeURL in
                        do {
                            try data.write(to: writeURL, options: .atomic)
                        } catch {
                            print("iCloud: Write error (\(fileName)): \(error)")
                        }
                    }
                } catch {
                    print("iCloud: Encoding error for \(server.name): \(error)")
                }
            }
        }
    }
    
    func download() -> [ServerConfig]? {
        // Since download is used in manualSync (Task-based), it should be fine but ideally it should match the async pattern
        // For debugging purposes, it remains as is but it's called within ServerManager's manualSync which is sync-within-a-Task
        guard let docURL = documentsURL, FileManager.default.fileExists(atPath: docURL.path) else { return nil }
        
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var allServers: [ServerConfig] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil)
            let serverFiles = files.filter { $0.lastPathComponent.hasPrefix(filePrefix) && $0.pathExtension == fileExtension }
            
            for fileURL in serverFiles {
                var server: ServerConfig?
                var error: NSError?
                coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &error) { readURL in
                    if let data = try? Data(contentsOf: readURL),
                       let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data) {
                        server = decoded
                    }
                }
                if let server = server {
                    allServers.append(server)
                }
            }
        } catch {
            print("iCloud: Directory listing error: \(error)")
            return nil
        }
        
        return allServers.isEmpty ? nil : allServers
    }
    
    func forceDownload() {
        guard let docURL = documentsURL else { 
            print("iCloud: forceDownload deferred - Container not ready.")
            setupUbiquity() // Try to re-init
            return 
        }
        
        if let files = try? FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil) {
            let serverFiles = files.filter { $0.lastPathComponent.hasPrefix(filePrefix) && $0.pathExtension == fileExtension }
            for fileURL in serverFiles {
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            }
        }
        
        restartQuery()
    }
}
