import Foundation
import Observation

@MainActor
@Observable
class AIService {
    static let shared = AIService()
    
    private let client = LLMClient()
    
    func analyze(prompt: String, systemPrompt: String, apiClient: RemoteAPIClient) async throws -> String {
        let aiConfig = apiClient.aiConfig
        
        guard aiConfig?.enabled ?? false else {
            throw NSError(domain: "AIService", code: 403, userInfo: [NSLocalizedDescriptionKey: "AI features are disabled in settings."])
        }
        
        return try await client.sendRequest(systemPrompt: systemPrompt, userPrompt: prompt, customConfig: aiConfig)
    }
    
    func analyzeStream(prompt: String, systemPrompt: String, apiClient: RemoteAPIClient) -> AsyncThrowingStream<String, Error> {
        var aiConfig = apiClient.aiConfig
        
        // Fallback to ServerManager shared config if apiClient one is nil or disabled
        if aiConfig == nil || !(aiConfig?.enabled ?? false) {
            aiConfig = ServerManager.shared.sharedAIConfig
        }
        
        guard let config = aiConfig, config.enabled ?? false else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "AIService", code: 403, userInfo: [NSLocalizedDescriptionKey: "AI features are disabled in settings."]))
            }
        }
        
        let shouldStream = aiConfig?.stream ?? true
        
        if shouldStream {
            return client.sendRequestStream(systemPrompt: systemPrompt, userPrompt: prompt, customConfig: aiConfig)
        } else {
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let response = try await client.sendRequest(systemPrompt: systemPrompt, userPrompt: prompt, customConfig: aiConfig)
                        continuation.yield(response)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}
