import Foundation
import XCTest
@testable import FluidPushToTalk

final class CommandResultGeneratorTests: XCTestCase {
    func testGeneratePropagatesProviderErrorWithoutTranscriptFallback() async {
        var prompts = PromptConfig()
        prompts.coreCommand.system = "Follow the command."
        prompts.coreCommand.userTemplate = "{{command}}\n{{information}}"
        let generator = CommandResultGenerator(
            prompts: prompts,
            llmClient: FailingCommandLLMClient()
        )

        do {
            _ = try await generator.generate(
                information: "Original transcript that must not be returned",
                command: "Rewrite it",
                imageURLs: []
            )
            XCTFail("Expected provider error to propagate")
        } catch {
            XCTAssertEqual(error as? StubProviderError, .unavailable)
        }
    }
}

private enum StubProviderError: Error, Equatable {
    case unavailable
}

private struct FailingCommandLLMClient: CommandLLMClient {
    func complete(systemPrompt: String, userPrompt: String, imageURLs: [URL]) async throws -> String {
        throw StubProviderError.unavailable
    }
}
