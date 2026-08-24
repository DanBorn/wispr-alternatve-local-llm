import Foundation

protocol CommandLLMClient: Sendable {
    var displayName: String { get }

    func complete(systemPrompt: String, userPrompt: String, imageURLs: [URL]) async throws -> String
}

extension CommandLLMClient {
    var displayName: String {
        String(describing: Self.self)
    }
}
