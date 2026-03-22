import Foundation
import Observation
import SwiftUI

// MARK: - Language Management

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case chinese = "zh-Hans"
    case english = "en"
    
    var id: String { self.rawValue }
    
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .chinese: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        }
    }
    
    var displayNameKey: String {
        switch self {
        case .system: return "common.systemDefault"
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

@MainActor
@Observable
class AppLanguageManager {
    var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "app_language")
        }
    }
    
    init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        self.selectedLanguage = AppLanguage(rawValue: saved) ?? .system
    }
    
    func t(_ key: String) -> String {
        let langCode = selectedLanguage == .system ? nil : selectedLanguage.rawValue
        
        // 1. Try to find the bundle for the selected language
        if let langCode = langCode,
           let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let result = bundle.localizedString(forKey: key, value: nil, table: nil)
            if result != key {
                return result
            }
        }
        
        // 2. Fallback to NSLocalizedString which handles system language correctly
        // and also looks into the main bundle for .xcstrings entries.
        return NSLocalizedString(key, value: key, comment: "")
    }
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
    
    let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
        
        // Load session from defaults
        if let savedURL = UserDefaults.standard.string(forKey: "flux_remote_url") {
            var urlStr = savedURL
            if !urlStr.hasSuffix("/") { urlStr += "/" }
            self.baseURL = URL(string: urlStr)
        }
        self.isAuthenticated = UserDefaults.standard.bool(forKey: "flux_remote_auth")
        self.currentUser = UserDefaults.standard.string(forKey: "flux_remote_user")
    }
    
    func login(urlString: String, credentials: [String: String]) async {
        isLoading = true
        errorMessage = nil
        
        var cleanURL = urlString
        if cleanURL.hasSuffix("/") { cleanURL.removeLast() }
        
        var finalURLString = cleanURL
        if !finalURLString.hasSuffix("/") { finalURLString += "/" }
        
        guard let url = URL(string: finalURLString) else {
            errorMessage = "Invalid URL format"
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
                errorMessage = "Authentication failed"
                isLoading = false
                return
            }
            
            // Success
            isAuthenticated = true
            currentUser = credentials["username"]
            
            UserDefaults.standard.set(cleanURL, forKey: "flux_remote_url")
            UserDefaults.standard.set(true, forKey: "flux_remote_auth")
            UserDefaults.standard.set(currentUser, forKey: "flux_remote_user")
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func logout() {
        isAuthenticated = false
        currentUser = nil
        UserDefaults.standard.set(false, forKey: "flux_remote_auth")
        UserDefaults.standard.removeObject(forKey: "flux_remote_user")
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
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
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
            }
        } catch {
            print("Fetch settings for features failed: \(error)")
        }
    }
}
