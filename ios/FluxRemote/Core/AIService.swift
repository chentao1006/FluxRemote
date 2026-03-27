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
        
        let usePublic = aiConfig?.usePublicService ?? true
        
        if usePublic {
            return try await client.sendPublicRequest(systemPrompt: systemPrompt, userPrompt: prompt)
        } else {
            // Use server-side /api/ai
            let response: AIResponse = try await apiClient.request("/api/ai", method: "POST", body: ["prompt": prompt, "system_prompt": systemPrompt])
            return response.data
        }
    }
}
