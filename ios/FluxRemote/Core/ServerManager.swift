import Foundation
import Observation

struct ServerConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var username: String?
    var isSelected: Bool = false
    var isAuthenticated: Bool = false
    
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
        // Multi-device sync logic:
        // 1. Keep all servers from cloud.
        // 2. Add local servers that don't exist in cloud (newly created local servers).
        // 3. Update local servers that have a match in cloud.
        
        var merged = cloudServers
        let cloudIds = Set(cloudServers.map { $0.id })
        
        // Add local-only servers (don't overwrite cloud with older local versions for now, simple merge)
        for localServer in self.servers {
            if !cloudIds.contains(localServer.id) {
                merged.append(localServer)
            }
        }
        
        // Preserve selection if possible
        let selectedId = self.selectedServer?.id
        
        isCloudUpdating = true
        self.servers = merged
        
        // If the previously selected server is still here, re-select it if cloud didn't have a selection
        if let sid = selectedId, !self.servers.contains(where: { $0.isSelected }) {
            for i in 0..<self.servers.count {
                if self.servers[i].id == sid {
                    self.servers[i].isSelected = true
                }
            }
        }
        
        saveLocalOnly()
        isCloudUpdating = false
        
        // If we added something from local to the merge, upload it back to sync other devices
        if merged.count > cloudServers.count {
            CloudSyncManager.shared.upload(servers: merged)
        }
    }
    
    var selectedServer: ServerConfig? {
        if let selected = servers.first(where: { $0.isSelected }) {
            return selected
        }
        return servers.first
    }
    
    func selectServer(_ server: ServerConfig) {
        for i in 0..<servers.count {
            servers[i].isSelected = (servers[i].id == server.id)
        }
        saveServers()
    }
    
    func addServer(_ server: ServerConfig) {
        var newServer = server
        if servers.isEmpty {
            newServer.isSelected = true
        }
        servers.append(newServer)
        saveServers()
    }
    
    func updateServer(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }
    
    func removeServer(_ server: ServerConfig) {
        let wasSelected = server.isSelected
        servers.removeAll { $0.id == server.id }
        if wasSelected, !servers.isEmpty {
            servers[0].isSelected = true
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
                let oldServer = ServerConfig(name: "Default Server", url: oldURL, username: oldUser, isSelected: true)
                self.servers = [oldServer]
                saveServers()
            }
        }
        
        if isCloudSyncEnabled, let cloudServers = CloudSyncManager.shared.download() {
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
        
        if let data = try? Data(contentsOf: url),
           let servers = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            return servers
        }
        return nil
    }
}
