import Foundation
import Observation
import SwiftUI

// MARK: - Models

struct MetricPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
    let netIn: Double
    let netOut: Double
}

// MARK: - Remote API Client

@MainActor
@Observable
class RemoteAPIClient {
    var baseURL: URL?
    var isAuthenticated: Bool = false
    var currentUser: String?
    var isLoading: Bool = false
    var errorMessage: String?
    var features: FeatureToggles = FeatureToggles()
    var aiConfig: AIConfig?
    var languageManager: AppLanguageManager?
    
    // Shared state for persistent content
    var dashboardStats: RemoteSystemStats? = nil
    var dashboardHistory: [MetricPoint] = []
    var dockerContainers: [DockerContainer] = []
    var nginxSites: [NginxSite] = []
    var launchAgents: [LaunchAgentItem] = []
    var logItems: [LogItem] = []
    var processItems: [RemoteProcess] = []
    var configItems: [ConfigItem] = []
    
    let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
        
        // Load selected server from ServerManager
        if let server = ServerManager.shared.selectedServer {
            self.baseURL = server.baseURL
            self.isAuthenticated = ServerManager.shared.isServerAuthenticated(server.id)
            self.currentUser = server.username
        }
    }
    
    func switchServer(to server: ServerConfig) {
        // Reset state for new server
        self.baseURL = server.baseURL
        self.isAuthenticated = ServerManager.shared.isServerAuthenticated(server.id)
        self.currentUser = server.username
        
        // Clear cached data for previous server
        self.dashboardStats = nil
        self.dashboardHistory = []
        self.dockerContainers = []
        self.nginxSites = []
        self.launchAgents = []
        self.logItems = []
        self.processItems = []
        self.configItems = []
        self.features = FeatureToggles()
        self.aiConfig = nil
        
        ServerManager.shared.selectServer(server)
        
        if isAuthenticated {
            Task { await fetchSettings() }
        }
    }
    
    func login(urlString: String, credentials: [String: String]) async {
        isLoading = true
        errorMessage = nil
        
        var cleanURL = urlString
        if cleanURL.hasSuffix("/") { cleanURL.removeLast() }
        
        var finalURLString = cleanURL
        if !finalURLString.hasSuffix("/") { finalURLString += "/" }
        
        guard let url = URL(string: finalURLString) else {
            errorMessage = languageManager?.t("common.invalidURLFormat") ?? "Invalid URL format"
            isLoading = false
            return
        }
        
        self.baseURL = url
        
        do {
            let body = try JSONEncoder().encode(credentials)
            var request = URLRequest(url: url.appendingPathComponent("/api/auth/login"))
            request.httpMethod = "POST"
            request.timeoutInterval = 15.0
            
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                errorMessage = languageManager?.t("common.authFailed") ?? "Authentication failed"
                isLoading = false
                return
            }
            
            // Success
            isAuthenticated = true
            currentUser = credentials["username"]
            
            // Update ServerManager
            if let existingServer = ServerManager.shared.servers.first(where: { $0.url == cleanURL }) {
                var updated = existingServer
                updated.username = currentUser
                ServerManager.shared.setAuthenticated(true, for: updated.id)
                ServerManager.shared.updateServer(updated)
                ServerManager.shared.selectServer(updated) // Ensure it's selected
            } else {
                // Should not happen if we add server before login, but just in case
                let newServer = ServerConfig(name: cleanURL, url: cleanURL, username: currentUser)
                ServerManager.shared.addServer(newServer)
                ServerManager.shared.setAuthenticated(true, for: newServer.id)
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func logout() {
        isAuthenticated = false
        currentUser = nil
        
        // Update ServerManager
        if let server = ServerManager.shared.selectedServer {
            ServerManager.shared.setAuthenticated(false, for: server.id)
        }
    }
    
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let baseURL = baseURL, let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL) else {
            throw NSError(domain: "APIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "No Base URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FluxRemote/1.0", forHTTPHeaderField: "User-Agent")
        
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        // Set dynamic Accept-Language
        if let lang = languageManager?.selectedLanguage, lang != .system {
            request.setValue(lang.rawValue, forHTTPHeaderField: "Accept-Language")
        }
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 401 {
                logout()
            }
            
            var errorMsg = "HTTP Error \(httpResponse.statusCode)"
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = json["details"] as? String {
                    errorMsg = msg
                } else if let msg = json["error"] as? String {
                    errorMsg = msg
                }
            }
            
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // Support for Encodable models
    func request<T: Decodable, B: Encodable>(_ path: String, method: String = "GET", encodableBody: B? = nil) async throws -> T {
        guard let baseURL = baseURL, let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL) else {
            throw NSError(domain: "APIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "No Base URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        // Set dynamic Accept-Language
        if let lang = languageManager?.selectedLanguage, lang != .system {
            request.setValue(lang.rawValue, forHTTPHeaderField: "Accept-Language")
        } else {
            request.setValue("zh-Hans,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        }
        
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3.1 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        if let body = encodableBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 401 {
                logout()
            }
            
            var errorMsg = "HTTP Error \(httpResponse.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = json["details"] as? String {
                    errorMsg = msg
                } else if let msg = json["error"] as? String {
                    errorMsg = msg
                }
            }
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func fetchSettings() async {
        do {
            let response: ServerSettingsResponse = try await request("/api/settings")
            await MainActor.run {
                if let feats = response.data.features {
                    self.features = feats
                }
                self.aiConfig = response.data.ai
            }
        } catch {
            print("Fetch settings for features failed: \(error)")
        }
    }
}
