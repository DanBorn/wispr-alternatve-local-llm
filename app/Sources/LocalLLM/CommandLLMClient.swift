import Foundation

protocol CommandLLMClient: AnyObject, Sendable {
    var displayName: String { get }
    var requiresWarmUp: Bool { get }

    func warmUp(systemPrompt: String) async throws
    func complete(systemPrompt: String, userPrompt: String, imageURLs: [URL]) async throws -> String
}

extension CommandLLMClient {
    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt, imageURLs: [])
    }
}

enum CommandLLMClientFactory {
    static func make(config: LocalLLMConfig) -> CommandLLMClient {
        switch config.provider {
        case .azureOpenAI, .openAICompatible, .cerebras:
            AzureOpenAICommandLLMClient(config: config)
        case .mlx:
            LocalMLXChatSession(config: config)
        }
    }
}
