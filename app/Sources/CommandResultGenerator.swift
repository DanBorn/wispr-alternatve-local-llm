import Foundation

final class CommandResultGenerator: @unchecked Sendable {
    private let prompts: PromptConfig
    private let llmClient: any CommandLLMClient

    init(prompts: PromptConfig, llmClient: any CommandLLMClient) {
        self.prompts = prompts
        self.llmClient = llmClient
    }

    func generate(information: String, command: String, imageURLs: [URL] = []) async throws -> String {
        let request = normalizedRequest(information: information, command: command)

        let startedAt = Date()
        log("sending command request to \(llmClient.displayName)...")
        let prompt = commandPrompt(
            information: request.information,
            command: request.command
        )
        if !imageURLs.isEmpty {
            log("command image context attached (\(imageURLs.count) image(s))")
        }
        let content = try await llmClient.complete(
            systemPrompt: prompts.coreCommand.system,
            userPrompt: prompt,
            imageURLs: imageURLs
        )
        log(
            "command response received from \(llmClient.displayName) in \(formatSeconds(Date().timeIntervalSince(startedAt))) (\(content.count) chars)"
        )
        return content
    }

    private struct CommandRequest {
        let information: String
        let command: String
    }

    private func normalizedRequest(information: String, command: String) -> CommandRequest {
        if looksLikeAnswerInstruction(information), looksLikeStandaloneQuestion(command) {
            log("command request normalized: using command segment as question")
            let normalizedQuestion = canonicalStandaloneQuestion(command)
            return CommandRequest(
                information: normalizedQuestion,
                command: information
            )
        }
        return CommandRequest(
            information: canonicalStandaloneQuestion(information),
            command: command
        )
    }

    private func looksLikeAnswerInstruction(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.count <= 80 else {
            return false
        }
        let phrases = [
            "beantworte",
            "beantwortet",
            "antwort",
            "answer",
            "frage",
            "question",
        ]
        return phrases.contains { normalized.contains($0) }
    }

    private func looksLikeStandaloneQuestion(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty, normalized.count <= 160 else {
            return false
        }
        if normalized.hasSuffix("?") {
            return true
        }
        let starts = [
            "was ",
            "wer ",
            "wie ",
            "wo ",
            "wann ",
            "warum ",
            "wieso ",
            "weshalb ",
            "what ",
            "who ",
            "how ",
            "where ",
            "when ",
            "why ",
        ]
        return starts.contains { normalized.hasPrefix($0) }
    }

    private func canonicalStandaloneQuestion(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        guard normalized.hasPrefix("was sind "), normalized.count <= 80 else {
            return text
        }
        var subject = String(trimmed.dropFirst("Was sind ".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if subject.hasSuffix("?") {
            subject.removeLast()
        }
        subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            return text
        }
        return "Erkläre kurz: \(subject)."
    }

    private func commandPrompt(information: String, command: String) -> String {
        return renderPromptTemplate(
            prompts.coreCommand.userTemplate,
            values: [
                "command": command,
                "information": information,
            ]
        )
    }

    private func renderPromptTemplate(_ template: String, values: [String: String]) -> String {
        values.reduce(template) { rendered, item in
            rendered.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
        }
    }
}
