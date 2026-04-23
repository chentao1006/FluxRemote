import Foundation
import Observation

struct ServerConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var username: String?
    var isLauncher: Bool = false
    var lastUpdatedAt: Date = Date()
    
    // New fields for remember password and auto login
    var rememberPassword: Bool = false
    var autoLogin: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, username, isLauncher, lastUpdatedAt, rememberPassword, autoLogin
    }
    
    init(id: UUID = UUID(), name: String, url: String, username: String? = nil, isLauncher: Bool = false, lastUpdatedAt: Date = Date(), rememberPassword: Bool = false, autoLogin: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.isLauncher = isLauncher
        self.lastUpdatedAt = lastUpdatedAt
        self.rememberPassword = rememberPassword
        self.autoLogin = autoLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        isLauncher = try container.decodeIfPresent(Bool.self, forKey: .isLauncher) ?? false
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt) ?? Date(timeIntervalSince1970: 0)
        
        rememberPassword = try container.decodeIfPresent(Bool.self, forKey: .rememberPassword) ?? false
        autoLogin = try container.decodeIfPresent(Bool.self, forKey: .autoLogin) ?? false
    }
    
    var baseURL: URL? {
        var urlStr = url
        if !urlStr.hasSuffix("/") { urlStr += "/" }
        return URL(string: urlStr)
    }
    
    func isContentEqual(to other: ServerConfig) -> Bool {
        return name == other.name && 
               url == other.url && 
               username == other.username && 
               isLauncher == other.isLauncher &&
               rememberPassword == other.rememberPassword &&
               autoLogin == other.autoLogin
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
    var authenticatedServerIds: Set<UUID> = []
    private var localPasswords: [UUID: String] = [:]
    
    var isCloudSyncEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isCloudSyncEnabled, forKey: "is_cloud_sync_enabled")
            if isCloudSyncEnabled {
                CloudSyncManager.shared.upload(servers: servers)
            }
        }
    }
    
    private let serversKey = "flux_remote_servers_v2"
    private let passwordsKey = "flux_remote_passwords_v1"
    private let aiConfigKey = "flux_remote_shared_ai_config"
    private var isCloudUpdating = false
    private var isInitialCloudSyncDone = false
    private var hasSuccessfullySyncedAtLeastOnce = false
    
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
        
        // Load local passwords
        if let data = UserDefaults.standard.data(forKey: passwordsKey),
           let decoded = try? JSONDecoder().decode([UUID: String].self, from: data) {
            self.localPasswords = decoded
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
                // Use a very old date for migration to ensure cloud data always wins
                let oldServer = ServerConfig(name: "Default Server", url: oldURL, username: oldUser, lastUpdatedAt: Date(timeIntervalSince1970: 0))
                self.servers = [oldServer]
                self.selectedServerId = oldServer.id
                saveLocalOnly() 
            }
        }
    }
    
    private func setupCloudSync() {
        CloudSyncManager.shared.onCloudDataChanged = { [weak self] (cloudServers, isComplete) in
            Task { @MainActor in
                guard let self = self, self.isCloudSyncEnabled else { return }
                self.mergeWithCloud(cloudServers, isComplete: isComplete)
            }
        }
    }
    
    private func mergeWithCloud(_ cloudServers: [ServerConfig], isComplete: Bool) {
        var merged: [ServerConfig] = self.servers
        var hasChangesFromCloud = false
        var serversToUploadBack: [ServerConfig] = []
        
        if isComplete { hasSuccessfullySyncedAtLeastOnce = true }
        
        print("iCloud: Starting merge with \(cloudServers.count) cloud servers. Complete: \(isComplete), InitialSyncDone: \(isInitialCloudSyncDone)")
        
        // 1. Add/Update servers from cloud
        for cloudServer in cloudServers {
            if let index = merged.firstIndex(where: { $0.id == cloudServer.id }) {
                let localServer = merged[index]
                let cloudDate = cloudServer.lastUpdatedAt
                let localDate = localServer.lastUpdatedAt
                
                // Use a small grace period for timestamp comparison to handle precision noise
                let isSameTime = abs(cloudDate.timeIntervalSince(localDate)) < 1.0
                let isContentEqual = cloudServer.isContentEqual(to: localServer)
                
                if isContentEqual {
                    // Content is the same, just unify the timestamp if they differ slightly
                    if !isSameTime && cloudDate > localDate {
                        print("iCloud: Aligning timestamp for '\(cloudServer.name)' to cloud version.")
                        merged[index].lastUpdatedAt = cloudDate
                        hasChangesFromCloud = true
                    }
                } else {
                    // Content is DIFFERENT.
                    let timeDiff = localDate.timeIntervalSince(cloudDate)
                    let fsDate = CloudSyncManager.shared.getFileModificationDate(for: cloudServer.id) ?? Date(timeIntervalSince1970: 0)
                    
                    if cloudDate > localDate || fsDate.timeIntervalSince(localDate) > 60 {
                        print("iCloud: Updating '\(cloudServer.name)' because Cloud is newer.")
                        merged[index] = cloudServer
                        hasChangesFromCloud = true
                    } else if timeDiff > 120 { // ONLY upload back if local is SIGNIFICANTLY newer (real intentional edit)
                        print("iCloud: Local version of '\(localServer.name)' is MUCH newer (>2m). Considering it a local edit. Uploading back.")
                        serversToUploadBack.append(localServer)
                    } else {
                        // Conflict with close timestamps: Prefer the cloud as it's the more likely source of truth across devices
                        print("iCloud: Conflict for '\(cloudServer.name)' with close timestamps (\(Int(timeDiff))s). Preferring Cloud.")
                        merged[index] = cloudServer
                        hasChangesFromCloud = true
                    }
                }
            } else {
                // New from cloud
                print("iCloud: Found new server '\(cloudServer.name)' in cloud. Adding.")
                merged.append(cloudServer)
                hasChangesFromCloud = true
            }
        }
        
        // Only upload back "missing" servers if we have a reasonably high confidence the cloud isn't just lagging.
        // For now, only upload if it's explicitly NOT a launcher and NOT just seen in the merged list.
        let cloudIdList = Set(cloudServers.map { $0.id })
        let localNotYetInCloud = self.servers.filter { !cloudIdList.contains($0.id) && !$0.isLauncher }
        
        // Only consider 'missing' servers if we are doing a COMPLETE sync and definitely found some servers
        if isComplete && cloudServers.count > 0 {
            serversToUploadBack.append(contentsOf: localNotYetInCloud)
        }
        
        if hasChangesFromCloud {
            isCloudUpdating = true
            self.servers = merged
            sortServers()
            saveLocalOnly()
            isCloudUpdating = false
            print("iCloud: Server list updated from cloud merge.")
        }
        
        // IMPORTANT: Only upload if we've already performed at least one valid cloud discovery 
        // AND the current discovery is complete.
        if (isInitialCloudSyncDone || hasSuccessfullySyncedAtLeastOnce) && isCloudSyncEnabled && isComplete {
            if !serversToUploadBack.isEmpty {
                print("iCloud: Uploading \(serversToUploadBack.count) strictly newer/missing local changes to cloud...")
                CloudSyncManager.shared.upload(servers: serversToUploadBack)
            }
        } else {
            print("iCloud: Skipping upload back - Sync incomplete or not yet initialized.")
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
        // selectedServerId didSet already saves to UserDefaults. 
        // Cloud upload is NOT needed just for selecting a server.
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
    
    func getPassword(for serverId: UUID) -> String? {
        localPasswords[serverId]
    }
    
    func setPassword(_ password: String?, for serverId: UUID) {
        if let password = password {
            localPasswords[serverId] = password
        } else {
            localPasswords.removeValue(forKey: serverId)
        }
        savePasswords()
    }
    
    func addServer(_ server: ServerConfig) {
        if servers.isEmpty {
            selectedServerId = server.id
        }
        var newServer = server
        newServer.lastUpdatedAt = Date()
        servers.append(newServer)
        sortServers()
        saveLocalOnly()
        if isCloudSyncEnabled && !isCloudUpdating {
            CloudSyncManager.shared.upload(servers: [newServer])
        }
    }
    
    func updateServer(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            var updated = server
            updated.lastUpdatedAt = Date()
            servers[index] = updated
            sortServers()
            saveLocalOnly()
            if isCloudSyncEnabled && !isCloudUpdating {
                CloudSyncManager.shared.upload(servers: [updated])
            }
        }
    }
    
    func removeServer(_ server: ServerConfig) {
        let wasSelected = (selectedServerId == server.id)
        servers.removeAll { $0.id == server.id }
        authenticatedServerIds.remove(server.id)
        localPasswords.removeValue(forKey: server.id)
        savePasswords()
        
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
        for i in 0..<12 { // 6s max wait (12 * 0.5s)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            let status = CloudSyncManager.shared.getDownloadStatus()
            
            // If we found servers and they are ALL current, break
            if status.totalCount > 0 && status.pendingCount == 0 {
                cloudServers = status.servers
                print("iCloud: Manual sync discovery complete. All \(status.totalCount) servers current.")
                break 
            }
            
            // Log progress
            if status.totalCount > 0 {
                print("iCloud: Manual sync progress iter \(i): \(status.totalCount - status.pendingCount)/\(status.totalCount) current")
            } else {
                print("iCloud: Manual sync waiting for query discovery iter \(i)...")
            }
            
            // If it's the last iteration, we take what we have
            if i == 11 {
                cloudServers = status.servers
                print("iCloud: Manual sync timeout reached. Merging partial data (\(status.servers.count) servers).")
            }
        }
        
        // 5. Final results and merge
        if let servers = cloudServers {
            let status = CloudSyncManager.shared.getDownloadStatus()
            let isComplete = (status.totalCount > 0 && status.pendingCount == 0)
            
            self.isInitialCloudSyncDone = true
            mergeWithCloud(servers, isComplete: isComplete)
        }
    }
    
    private func saveServers() {
        saveLocalOnly()
        // Removed batch upload from here to prevent redundant/risky syncs
    }
    
    private func saveLocalOnly() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: serversKey)
        }
    }
    
    private func savePasswords() {
        if let encoded = try? JSONEncoder().encode(localPasswords) {
            UserDefaults.standard.set(encoded, forKey: passwordsKey)
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
    
    var onCloudDataChanged: (([ServerConfig], Bool) -> Void)?
    
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
        
        let allServers = await Task.detached(priority: .userInitiated) { () -> ([ServerConfig], Bool) in
            var decodedServers: [ServerConfig] = []
            var pendingCount = 0
            let coordinator = NSFileCoordinator(filePresenter: nil)
            
            for info in fileInfos {
                let fileURL = info.url
                
                if !info.isCurrent {
                    print("iCloud: Metadata updated but Bytes not Current for \(fileURL.lastPathComponent). Downloading...")
                    try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                    pendingCount += 1
                    continue
                }
                
                var server: ServerConfig?
                var error: NSError?
                coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error) { readURL in
                    do {
                        let data = try Data(contentsOf: readURL, options: .mappedIfSafe)
                        server = try JSONDecoder().decode(ServerConfig.self, from: data)
                    } catch {
                        print("iCloud: Read/Decode failed for \(fileURL.lastPathComponent): \(error)")
                    }
                }
                
                if let server = server {
                    decodedServers.append(server)
                }
            }
            return (decodedServers, pendingCount == 0)
        }.value
        
        if !allServers.0.isEmpty || results.isEmpty {
            onCloudDataChanged?(allServers.0, allServers.1)
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
    
    struct DownloadStatus {
        var servers: [ServerConfig]
        var totalCount: Int
        var pendingCount: Int
    }
    
    func getDownloadStatus() -> DownloadStatus {
        var allServers: [ServerConfig] = []
        var totalFound = 0
        var pending = 0
        
        if let query = metadataQuery {
            let results = query.results as! [NSMetadataItem]
            totalFound = results.count
            
            let coordinator = NSFileCoordinator(filePresenter: nil)
            for item in results {
                let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                    pending += 1
                    
                    // Trigger download if it's not already downloading
                    if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    }
                    continue
                }
                
                if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                    var error: NSError?
                    coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readURL in
                        if let data = try? Data(contentsOf: readURL, options: .mappedIfSafe),
                           let server = try? JSONDecoder().decode(ServerConfig.self, from: data) {
                            allServers.append(server)
                        }
                    }
                }
            }
        }
        
        return DownloadStatus(servers: allServers, totalCount: totalFound, pendingCount: pending)
    }
    
    // Obsolete - use getDownloadStatus
    func download() -> [ServerConfig]? {
        let status = getDownloadStatus()
        return status.servers.isEmpty ? nil : status.servers
    }
    
    func forceDownload() {
        guard let docURL = documentsURL else { 
            setupUbiquity()
            return 
        }
        
        // 1. Trigger download for everything in directory listing including stubs
        if let files = try? FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil) {
            for fileURL in files {
                // Just trigger download without eviction, to avoid disappearing files
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            }
        }
        
        // 2. Also trigger for items mentioned in query but not yet in directory (or known to it)
        if let query = metadataQuery {
            let results = query.results as! [NSMetadataItem]
            for item in results {
                if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
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
