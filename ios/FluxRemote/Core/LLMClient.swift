import Foundation
import CryptoKit

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool?
}

struct ChatResponse: Codable {
    struct Choice: Codable {
        let message: ChatMessage
    }
    let choices: [Choice]
}

struct ChatStreamResponse: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

final class LLMClient: Sendable {
    private let isIdentifying = false
    
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
    
    func sendRequest(systemPrompt: String, userPrompt: String, customConfig: AIConfig? = nil) async throws -> String {
        let isPublic = customConfig?.usePublicService ?? true
        let url: URL
        var apiKey: String = ""
        var model: String = "gpt-4o-mini"
        
        if isPublic {
            url = URL(string: "https://\(publicServiceURL)/chat/completions")!
        } else {
            let customURL = customConfig?.url ?? ""
            let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            url = URL(string: "\(base)/chat/completions")!
            apiKey = customConfig?.key ?? ""
            model = customConfig?.model ?? "gpt-4o"
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if isPublic {
            let deviceId = getDeviceId()
            let token = generateToken(deviceId: deviceId)
            request.addValue(deviceId, forHTTPHeaderField: "X-Device-Id")
            request.addValue(token, forHTTPHeaderField: "X-Token")
        } else {
            if !apiKey.isEmpty {
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let chatRequest = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            stream: false
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
    
    func sendRequestStream(systemPrompt: String, userPrompt: String, customConfig: AIConfig? = nil) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let isPublic = customConfig?.usePublicService ?? true
            let urlStr: String
            let apiKey: String
            let model: String
            
            if isPublic {
                urlStr = "https://\(publicServiceURL)/chat/completions"
                apiKey = ""
                model = "gpt-4o-mini"
            } else {
                let customURL = customConfig?.url ?? ""
                let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
                urlStr = "\(base)/chat/completions"
                apiKey = customConfig?.key ?? ""
                model = customConfig?.model ?? "gpt-4o"
            }
            
            guard let url = URL(string: urlStr) else {
                continuation.finish(throwing: NSError(domain: "LLMClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"]))
                return
            }

            let task = Task.detached {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    
                    if isPublic {
                        let deviceId = self.getDeviceId()
                        let token = self.generateToken(deviceId: deviceId)
                        request.addValue(deviceId, forHTTPHeaderField: "X-Device-Id")
                        request.addValue(token, forHTTPHeaderField: "X-Token")
                    } else {
                        if !apiKey.isEmpty {
                            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        }
                    }
                    
                    let chatRequest = ChatRequest(
                        model: model,
                        messages: [
                            ChatMessage(role: "system", content: systemPrompt),
                            ChatMessage(role: "user", content: userPrompt)
                        ],
                        stream: true
                    )
                    
                    request.httpBody = try JSONEncoder().encode(chatRequest)
                    
                    let (result, response) = try await self.session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.finish(throwing: NSError(domain: "LLMClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(statusCode))"]))
                        return
                    }
                    
                    var receivedAnyContent = false
                    for try await line in result.lines {
                        try Task.checkCancellation()
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedLine.isEmpty { continue }
                        
                        if trimmedLine.hasPrefix("data:") {
                            let dataStr = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                            if dataStr == "[DONE]" {
                                break
                            }
                            
                            if let data = dataStr.data(using: .utf8),
                               let decoded = try? JSONDecoder().decode(ChatStreamResponse.self, from: data),
                               let content = decoded.choices.first?.delta.content {
                                receivedAnyContent = true
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    if !receivedAnyContent {
                        continuation.yield("Error: No streaming content received from API.")
                    }
                    
                    continuation.finish()
                } catch {
                    if error is CancellationError {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
