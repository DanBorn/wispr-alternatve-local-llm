import CryptoKit
import Foundation

struct CommandImageAttachment: Sendable {
    let path: String
    let mimeType: String
    let byteCount: Int
    let base64CharacterCount: Int
    let sha256: String
    let dataURL: String
}

struct CommandHTTPResponseMetadata: Sendable {
    let statusCode: Int
    let byteCount: Int
    let requestID: String
}

enum CommandRequestDiagnostics {
    static func sanitizedProviderMessage(_ message: String) -> String {
        var sanitized = message
        let replacements: [(pattern: String, replacement: String)] = [
            (#"data:[^;\s"']+;base64,[A-Za-z0-9+/=_-]+"#, "<redacted-data-url>"),
            (#"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer <redacted>"),
            (#"(?i)\b(?:sk|csk)-[A-Za-z0-9_-]{8,}\b"#, "<redacted-api-key>"),
            (#"(?i)(api[_ -]?key\s*[:=]\s*)[^\s,;}]+"#, "$1<redacted>"),
            (#"(?i)(authorization\s*[:=]\s*)[^\r\n,;}]*"#, "$1<redacted>"),
        ]
        for item in replacements {
            guard let expression = try? NSRegularExpression(pattern: item.pattern) else {
                continue
            }
            sanitized = expression.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: item.replacement
            )
        }
        return String(sanitized.prefix(500))
    }

    static func loadAttachments(from urls: [URL]) throws -> [CommandImageAttachment] {
        try urls.map { url in
            let data = try Data(contentsOf: url)
            let base64 = data.base64EncodedString()
            let mimeType = mimeType(for: url)
            return CommandImageAttachment(
                path: url.path,
                mimeType: mimeType,
                byteCount: data.count,
                base64CharacterCount: base64.count,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                dataURL: "data:\(mimeType);base64,\(base64)"
            )
        }
    }

    static func logRequest(
        logger: @Sendable (String) -> Void,
        requestID: String,
        provider: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        attachments: [CommandImageAttachment],
        timeout: TimeInterval,
        payloadBytes: Int,
        buildDuration: TimeInterval
    ) {
        logger(
            "command_request request_id=\(requestID) provider=\(provider) model=\(model) "
                + "prompt_chars=\(systemPrompt.count + userPrompt.count) "
                + "system_prompt_chars=\(systemPrompt.count) user_prompt_chars=\(userPrompt.count) "
                + "image_count=\(attachments.count) timeout_seconds=\(seconds(timeout)) "
                + "payload_bytes=\(payloadBytes) build_duration_ms=\(milliseconds(buildDuration))"
        )
        for (index, attachment) in attachments.enumerated() {
            logger(
                "command_request_image request_id=\(requestID) index=\(index + 1) "
                    + "path=\(quoted(attachment.path)) bytes=\(attachment.byteCount) "
                    + "mime=\(attachment.mimeType) base64_chars=\(attachment.base64CharacterCount) "
                    + "sha256=\(attachment.sha256)"
            )
        }
    }

    static func logAttemptStart(
        logger: @Sendable (String) -> Void,
        requestID: String,
        provider: String,
        attempt: Int,
        maximumAttempts: Int
    ) {
        logger(
            "command_request_attempt request_id=\(requestID) provider=\(provider) "
                + "attempt=\(attempt)/\(maximumAttempts) phase=start"
        )
    }

    static func logAttemptResult(
        logger: @Sendable (String) -> Void,
        requestID: String,
        provider: String,
        attempt: Int,
        maximumAttempts: Int,
        outcome: String,
        duration: TimeInterval,
        response: CommandHTTPResponseMetadata?,
        error: Error? = nil
    ) {
        var message = "command_request_attempt request_id=\(requestID) provider=\(provider) "
            + "attempt=\(attempt)/\(maximumAttempts) outcome=\(outcome) "
            + "duration_ms=\(milliseconds(duration)) "
            + "http_status=\(response.map { String($0.statusCode) } ?? "none") "
            + "response_bytes=\(response?.byteCount ?? 0) "
            + "response_request_id=\(quoted(response?.requestID ?? "none"))"
        if let error {
            let nsError = error as NSError
            message += " error_domain=\(quoted(nsError.domain)) error_code=\(nsError.code)"
        }
        logger(message)
    }

    static func logRetry(
        logger: @Sendable (String) -> Void,
        requestID: String,
        provider: String,
        reason: String
    ) {
        logger("command_request_retry request_id=\(requestID) provider=\(provider) retry_reason=\(reason)")
    }

    static func logTerminalFailure(
        logger: @Sendable (String) -> Void,
        requestID: String,
        provider: String,
        error: Error
    ) {
        let nsError = error as NSError
        logger(
            "command_request_terminal request_id=\(requestID) provider=\(provider) outcome=failure "
                + "error_domain=\(quoted(nsError.domain)) error_code=\(nsError.code)"
        )
    }

    static func responseMetadata(data: Data, response: HTTPURLResponse) -> CommandHTTPResponseMetadata {
        let headerRequestID = response.value(forHTTPHeaderField: "x-request-id")
            ?? response.value(forHTTPHeaderField: "request-id")
            ?? "none"
        return CommandHTTPResponseMetadata(
            statusCode: response.statusCode,
            byteCount: data.count,
            requestID: headerRequestID
        )
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "image/png"
        }
    }

    private static func milliseconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f", max(0, interval) * 1_000)
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.3f", interval)
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}
