import Foundation
import Observation

struct ServerConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var username: String?
    var isLauncher: Bool = false
    var lastUpdatedAt: Date = Date()
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, username, isLauncher, lastUpdatedAt
    }
    
    init(id: UUID = UUID(), name: String, url: String, username: String? = nil, isLauncher: Bool = false, lastUpdatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.isLauncher = isLauncher
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        isLauncher = try container.decodeIfPresent(Bool.self, forKey: .isLauncher) ?? false
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt) ?? Date(timeIntervalSince1970: 0)
    }
    
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
    private let aiConfigKey = "flux_remote_shared_ai_config"
    private var isCloudUpdating = false
    private var isInitialCloudSyncDone = false
    
    var sharedAIConfig: AIConfig? {
        didSet {
            if let encoded = try? JSONEncoder().encode(sharedAIConfig) {
                UserDefaults.standard.set(encoded, forKey: aiConfigKey)
            }
        }
    }
    
    private var reachabilityTimer: Timer?
    var reachabilityStatuses: [UUID: Bool?] = [:] // nil = unknown, false = online, true = offline
    
    init() {
        if let data = UserDefaults.standard.data(forKey: aiConfigKey),
           let decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            self.sharedAIConfig = decoded
        }
        
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
        
        startReachabilityTimer()
    }
    
    private func loadLocalServers() {
        if let data = UserDefaults.standard.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            self.servers = decoded
            sortServers()
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
        var hasChangesFromCloud = false
        var hasLocalChangesToUpload = false
        
        print("iCloud: Starting merge with \(cloudServers.count) cloud servers. InitialSyncDone: \(isInitialCloudSyncDone)")
        
        // 1. Add/Update servers from cloud
        for cloudServer in cloudServers {
            if let index = merged.firstIndex(where: { $0.id == cloudServer.id }) {
                // Determine which one is newer. 
                // We trust BOTH the internal timestamp and the actual file system date.
                let cloudDate = cloudServer.lastUpdatedAt
                let localDate = merged[index].lastUpdatedAt
                
                // Also get the FS date we saw during download
                let fsDate = CloudSyncManager.shared.getFileModificationDate(for: cloudServer.id) ?? Date(timeIntervalSince1970: 0)
                
                // If cloud JSON is newer, OR if FS is significantly newer than our current JSON date (indicating manual edit)
                if cloudDate > localDate || fsDate.timeIntervalSince(localDate) > 60 {
                    let reason = cloudDate > localDate ? "JSON newer" : "FS newer (\(fsDate))"
                    print("iCloud: Updating '\(cloudServer.name)' because \(reason).")
                    merged[index] = cloudServer
                    hasChangesFromCloud = true
                } else if cloudDate < localDate {
                    print("iCloud: Local version of '\(merged[index].name)' is still newer (\(localDate) > \(cloudDate)).")
                    hasLocalChangesToUpload = true
                }
            } else {
                // New from cloud
                print("iCloud: Found new server '\(cloudServer.name)' in cloud. Adding.")
                merged.append(cloudServer)
                hasChangesFromCloud = true
            }
        }
        
        let cloudIds = Set(cloudServers.map { $0.id })
        let localNotYetInCloud = self.servers.filter { !cloudIds.contains($0.id) }
        
        if hasChangesFromCloud {
            isCloudUpdating = true
            self.servers = merged
            sortServers()
            saveLocalOnly()
            isCloudUpdating = false
            print("iCloud: Server list updated from cloud merge.")
        }
        
        // IMPORTANT: Only upload if we've already performed at least one valid cloud discovery.
        // This prevents overwriting newer cloud data with stale local data on first launch.
        if isInitialCloudSyncDone && isCloudSyncEnabled {
            if hasLocalChangesToUpload || !localNotYetInCloud.isEmpty {
                print("iCloud: Uploading local changes to cloud...")
                CloudSyncManager.shared.upload(servers: self.servers)
            }
        } else {
            print("iCloud: Skipping upload - Initial sync not yet confirmed.")
        }
    }
    
    var selectedServer: ServerConfig? {
        if let sid = selectedServerId, let server = servers.first(where: { $0.id == sid }) {
            return server
        }
        return servers.first { reachabilityStatuses[$0.id] == false } ?? servers.first
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
        var newServer = server
        newServer.lastUpdatedAt = Date()
        servers.append(newServer)
        sortServers()
        saveServers()
    }
    
    func updateServer(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            var updated = server
            updated.lastUpdatedAt = Date()
            servers[index] = updated
            sortServers()
            saveServers()
        }
    }
    
    func removeServer(_ server: ServerConfig) {
        let wasSelected = (selectedServerId == server.id)
        servers.removeAll { $0.id == server.id }
        authenticatedServerIds.remove(server.id)
        
        // Propagate deletion to cloud
        if isCloudSyncEnabled {
            CloudSyncManager.shared.deleteFile(for: server.id)
        }
        
        if wasSelected {
            selectedServerId = servers.first?.id
        }
        saveServers()
    }
    
    // loadLocalServers replaces the problematic loadServers to avoid blocking launch screen
    
    func manualSync() async {
        print("iCloud: FORCED Manual sync requested.")
        
        // 1. Try to re-initialize ubiquity container if not ready
        if CloudSyncManager.shared.ubiquityURL == nil {
            CloudSyncManager.shared.setupUbiquity()
        }
        
        // 2. Wait for URL initialization if it's still in progress (max 2 seconds)
        var retryCount = 0
        while CloudSyncManager.shared.ubiquityURL == nil && retryCount < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            retryCount += 1
        }
        
        guard let _ = CloudSyncManager.shared.ubiquityURL else {
            return
        }
        
        // 3. Force discovery and download
        CloudSyncManager.shared.forceDownload()
        
        // 4. Wait for query results
        var cloudServers: [ServerConfig]?
        for i in 0..<6 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s x 6 = 3s total
            cloudServers = CloudSyncManager.shared.download()
            if cloudServers != nil && !cloudServers!.isEmpty { 
                print("iCloud: Found \(cloudServers!.count) servers after wait iter \(i)")
                break 
            }
        }
        
        // 5. Final results and merge
        self.isInitialCloudSyncDone = true
        if let servers = cloudServers {
            mergeWithCloud(servers)
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
    
    private func sortServers() {
        servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Reachability
    
    private func startReachabilityTimer() {
        reachabilityTimer?.invalidate()
        reachabilityTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAllServersReachability()
            }
        }
        
        // Initial check
        Task {
            await checkAllServersReachability()
        }
    }
    
    func checkAllServersReachability() async {
        for server in servers {
            let baseURL = server.baseURL
            let isOffline = baseURL != nil ? await checkServerStatus(baseURL!) : true
            
            if reachabilityStatuses[server.id] != isOffline {
                reachabilityStatuses[server.id] = isOffline
            }
        }
    }
    
    private func checkServerStatus(_ url: URL) async -> Bool {
        // We target the login endpoint to verify the Flux application is actually responding.
        // This avoids false greens from tunnel relays (like InstaTunnel) that return 404 for 'tunnel not found'.
        var request = URLRequest(url: url.appendingPathComponent("api/auth/login"))
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                // 200 (OK), 401 (Unauthorized - common if session is expired), 
                // and 405 (Method Not Allowed) all prove the Flux app is reachable.
                if statusCode == 200 || statusCode == 401 || statusCode == 405 {
                    return false // online
                }
                // Any other status (404, 503, etc.) indicates the app is not truly reachable.
                return true
            }
            return true
        } catch {
            return true
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
    private var isSyncing = false
    
    var onCloudDataChanged: (([ServerConfig]) -> Void)?
    
    init() {
        // Defer setup briefly to ensure app finish launching visually
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s defer
            setupUbiquity()
            setupQuery()
        }
    }
    
    func setupUbiquity() {
        guard !isInitializingUbiquity else { return }
        isInitializingUbiquity = true
        
        let targetID = containerIdentifier
        print("iCloud: Starting ubiquity initialization for \(targetID)...")
        
        Task.detached(priority: .userInitiated) {
            // Try specific container first
            var url = FileManager.default.url(forUbiquityContainerIdentifier: targetID)
            
            // Fallback to default (nil) if specific fails
            if url == nil {
                print("iCloud: Specific container \(targetID) failed, trying default container...")
                url = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            }
            
            await MainActor.run {
                self.cachedUbiquityURL = url
                self.isInitializingUbiquity = false
                
                if let url = url {
                    print("iCloud: Container ready at \(url.path)")
                    self.restartQuery()
                } else {
                    print("iCloud: ERROR - Container NOT available. Please verify entitlements and iCloud settings.")
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
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryUbiquitousDataScope]
        
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
        guard let query = metadataQuery, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        query.disableUpdates()
        let results = query.results as! [NSMetadataItem]
        query.enableUpdates()
        
        if results.isEmpty { return }
        
        print("iCloud: Query found \(results.count) potential server files.")
        
        struct CloudFileInfo: Sendable {
            let url: URL
            let isCurrent: Bool
        }
        
        let fileInfos = results.compactMap { item -> CloudFileInfo? in
            guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return nil }
            let downloadingStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            return CloudFileInfo(url: fileURL, isCurrent: downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent)
        }
        
        let allServers = await Task.detached(priority: .userInitiated) { () -> [ServerConfig] in
            var decodedServers: [ServerConfig] = []
            let coordinator = NSFileCoordinator(filePresenter: nil)
            
            for info in fileInfos {
                let fileURL = info.url
                
                if !info.isCurrent {
                    print("iCloud: Metadata updated but Bytes not Current for \(fileURL.lastPathComponent). Downloading...")
                    try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                    // We also want to skip reading it now to avoid stale reads, 
                    // and rely on the next metadata update when it becomes current.
                    continue
                }
                
                var server: ServerConfig?
                var error: NSError?
                // Using empty options but we check for 'Current' status above
                coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error) { readURL in
                    do {
                        // Use .mappedIfSafe to avoid some caching issues
                        let data = try Data(contentsOf: readURL, options: .mappedIfSafe)
                        server = try JSONDecoder().decode(ServerConfig.self, from: data)
                        
                        // SANITY CHECK: If FS date is significantly newer than the internal JSON date, 
                        // it might mean the file content is still being streamed/synced.
                        if let server = server {
                            let attrs = try? FileManager.default.attributesOfItem(atPath: readURL.path)
                            if let fsDate = attrs?[.modificationDate] as? Date {
                                if fsDate.timeIntervalSince(server.lastUpdatedAt) > 60 {
                                    print("iCloud: WARNING - '\(server.name)' FS date (\(fsDate)) is much newer than internal JSON date (\(server.lastUpdatedAt)). Results might be stale.")
                                }
                            }
                        }
                    } catch {
                        print("iCloud: Read/Decode failed for \(fileURL.lastPathComponent): \(error)")
                    }
                }
                
                if let server = server {
                    decodedServers.append(server)
                }
            }
            return decodedServers
        }.value
        
        if !allServers.isEmpty {
            onCloudDataChanged?(allServers)
        }
    }
    
    func upload(servers: [ServerConfig]) {
        guard let docURL = documentsURL else { return }
        let prefix = self.filePrefix
        let ext = self.fileExtension
        let serversToUpload = servers.filter { !$0.isLauncher }
        
        Task.detached(priority: .utility) {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            if !FileManager.default.fileExists(atPath: docURL.path) {
                try? FileManager.default.createDirectory(at: docURL, withIntermediateDirectories: true)
            }
            
            for server in serversToUpload {
                // Skip uninitialized/migration data
                guard server.lastUpdatedAt.timeIntervalSince1970 > 10000 else { continue }
                
                let fileName = "\(prefix)\(server.id.uuidString).\(ext)"
                let url = docURL.appendingPathComponent(fileName)
                
                do {
                    let data = try JSONEncoder().encode(server)
                    var error: NSError?
                    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writeURL in
                        try? data.write(to: writeURL, options: .atomic)
                    }
                } catch {
                    print("iCloud: Upload encoding error for \(server.name)")
                }
            }
        }
    }
    
    func deleteFile(for serverId: UUID) {
        guard let docURL = documentsURL else { return }
        let fileName = "\(filePrefix)\(serverId.uuidString).\(fileExtension)"
        let url = docURL.appendingPathComponent(fileName)
        
        Task.detached(priority: .utility) {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var error: NSError?
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &error) { deleteURL in
                try? FileManager.default.removeItem(at: deleteURL)
            }
        }
    }
    
    func download() -> [ServerConfig]? {
        // Preferred way is now via processCloudChanges, but we keep this for manualSync fallback
        // Improved to use Query results if available
        if let query = metadataQuery {
            let results = query.results as! [NSMetadataItem]
            if !results.isEmpty {
                var cached: [ServerConfig] = []
                let coordinator = NSFileCoordinator(filePresenter: nil)
                for item in results {
                    // Check if actually current/downloaded
                    let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                    guard status == NSMetadataUbiquitousItemDownloadingStatusCurrent else { continue }
                    
                    if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                        var error: NSError?
                        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readURL in
                            if let data = try? Data(contentsOf: readURL, options: .mappedIfSafe),
                               let server = try? JSONDecoder().decode(ServerConfig.self, from: data) {
                                cached.append(server)
                            }
                        }
                    }
                }
                if !cached.isEmpty { return cached }
            }
        }
        
        // Final fallback: direct directory listing (can be stale, handle with care)
        guard let docURL = documentsURL, FileManager.default.fileExists(atPath: docURL.path) else { return nil }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var allServers: [ServerConfig] = []
        
        let files = (try? FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])) ?? []
        let serverFiles = files.filter { 
            ($0.lastPathComponent.hasPrefix(filePrefix) || $0.lastPathComponent.hasPrefix(".\(filePrefix)")) && 
            ($0.pathExtension == fileExtension || $0.absoluteString.contains(".icloud"))
        }
        
        for fileURL in serverFiles {
            // Filter out non-current files from manual poll
            let values = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values?.ubiquitousItemDownloadingStatus != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                continue
            }
            
            var error: NSError?
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error) { readURL in
                if let data = try? Data(contentsOf: readURL, options: .mappedIfSafe),
                   let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data) {
                    allServers.append(decoded)
                }
            }
        }
        return allServers.isEmpty ? nil : allServers
    }
    
    func forceDownload() {
        guard let docURL = documentsURL else { 
            setupUbiquity()
            return 
        }
        
        // Trigger download for everything in directory including stubs
        if let files = try? FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil) {
            for fileURL in files {
                // Just trigger download without eviction, to avoid disappearing files
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            }
        }
        restartQuery()
    }
    
    func getFileModificationDate(for serverId: UUID) -> Date? {
        guard let docURL = documentsURL else { return nil }
        let fileName = "\(filePrefix)\(serverId.uuidString).\(fileExtension)"
        let url = docURL.appendingPathComponent(fileName)
        
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}
