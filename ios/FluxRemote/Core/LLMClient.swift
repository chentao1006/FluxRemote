import Foundation
import CryptoKit

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
}

struct ChatResponse: Codable {
    struct Choice: Codable {
        let message: ChatMessage
    }
    let choices: [Choice]
}

@MainActor
class LLMClient: ObservableObject {
    @Published var isIdentifying = false
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()
    
    // The secret is stored in Config.xcconfig and mapped to Info.plist via $(SERVICE_SECRET)
    private var serviceSecret: String {
        return Bundle.main.infoDictionary?["ServiceSecret"] as? String ?? ""
    }
    
    private var publicServiceURL: String {
        return Bundle.main.infoDictionary?["PublicServiceURL"] as? String ?? "openai.ct106.com/v1"
    }
    
    private func getDeviceId() -> String {
        if let id = UserDefaults.standard.string(forKey: "deviceId") {
            return id
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceId")
        return id
    }
    
    private func generateToken(deviceId: String) -> String {
        let hour = Int(Date().timeIntervalSince1970 / 3600)
        let input = serviceSecret + deviceId + "\(hour)"
        let digest = Insecure.MD5.hash(data: input.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func sendPublicRequest(systemPrompt: String, userPrompt: String) async throws -> String {
        let url = URL(string: "https://\(publicServiceURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let deviceId = getDeviceId()
        let token = generateToken(deviceId: deviceId)
        request.addValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.addValue(token, forHTTPHeaderField: "X-Token")
        
        let chatRequest = ChatRequest(
            model: "gpt-4o-mini",
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ]
        )
        
        request.httpBody = try JSONEncoder().encode(chatRequest)
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LLMClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(body)"])
        }
        
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
}
