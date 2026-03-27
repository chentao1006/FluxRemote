import Foundation
import Observation

struct ServerConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var username: String?
    var isOffline: Bool = false
    
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
        
        loadServers()
        setupCloudSync()
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
    
    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            self.servers = decoded
        } else {
            if let oldURL = UserDefaults.standard.string(forKey: "flux_remote_url") {
                let oldUser = UserDefaults.standard.string(forKey: "flux_remote_user")
                let oldServer = ServerConfig(name: "Default Server", url: oldURL, username: oldUser)
                self.servers = [oldServer]
                self.selectedServerId = oldServer.id
                saveServers()
            }
        }
        
        if isCloudSyncEnabled, let cloudServers = CloudSyncManager.shared.download() {
            mergeWithCloud(cloudServers)
        }
    }
    
    func manualSync() async {
        CloudSyncManager.shared.forceDownload()
        // Wait briefly for metadata query or just pull directly
        if let cloudServers = CloudSyncManager.shared.download() {
            mergeWithCloud(cloudServers)
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
    private let fileName = "servers_v2.json"
    
    private var ubiquityURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
    }
    
    private var cloudFileURL: URL? {
        ubiquityURL?.appendingPathComponent("Documents").appendingPathComponent(fileName)
    }
    
    private var metadataQuery: NSMetadataQuery?
    
    var onCloudDataChanged: (([ServerConfig]) -> Void)?
    
    init() {
        setupQuery()
    }
    
    private func setupQuery() {
        let query = NSMetadataQuery()
        query.notificationBatchingInterval = 1
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
        
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidUpdate), name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidUpdate), name: .NSMetadataQueryDidUpdate, object: query)
        
        self.metadataQuery = query
        query.start()
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
        
        for item in query.results as! [NSMetadataItem] {
            guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            
            let downloadingStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if downloadingStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                continue
            }
            
            if let data = try? Data(contentsOf: fileURL),
               let servers = try? JSONDecoder().decode([ServerConfig].self, from: data) {
                onCloudDataChanged?(servers)
            }
        }
    }
    
    func upload(servers: [ServerConfig]) {
        guard let url = cloudFileURL else { return }
        
        let documentsURL = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
        
        do {
            let data = try JSONEncoder().encode(servers)
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var error: NSError?
            
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writeURL in
                do {
                    try data.write(to: writeURL, options: .atomic)
                } catch {
                    print("Failed to write to iCloud: \(error)")
                }
            }
        } catch {
            print("Failed to encode servers: \(error)")
        }
    }
    
    func download() -> [ServerConfig]? {
        guard let url = cloudFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        // Ensure we read latest from iCloud by coordinating
        var result: [ServerConfig]?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { readURL in
            if let data = try? Data(contentsOf: readURL),
               let servers = try? JSONDecoder().decode([ServerConfig].self, from: data) {
                result = servers
            }
        }
        
        return result
    }
    
    func forceDownload() {
        guard let url = cloudFileURL else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        
        // Also manually trigger a query update
        metadataQuery?.stop()
        metadataQuery?.start()
    }
}
