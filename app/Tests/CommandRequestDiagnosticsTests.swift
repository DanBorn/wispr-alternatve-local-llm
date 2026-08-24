import XCTest
@testable import FluidPushToTalk

final class CommandRequestDiagnosticsTests: XCTestCase {
    func testProviderMessageRedactsDataURLsAndCredentials() {
        let raw = """
        invalid image data:image/png;base64,QUJDREVGRw== \
        Authorization=Bearer secret-token-123 \
        api_key=csk-thismustberemoved123456 \
        sk-also-secret-123456
        """

        let sanitized = CommandRequestDiagnostics.sanitizedProviderMessage(raw)

        XCTAssertTrue(sanitized.contains("<redacted-data-url>"))
        XCTAssertTrue(sanitized.contains("<redacted>"))
        XCTAssertFalse(sanitized.contains("QUJDREVGRw"))
        XCTAssertFalse(sanitized.contains("secret-token"))
        XCTAssertFalse(sanitized.contains("csk-this"))
        XCTAssertFalse(sanitized.contains("sk-also"))
    }

    func testProviderMessageRedactsEntireBasicAuthorizationValue() {
        let sanitized = CommandRequestDiagnostics.sanitizedProviderMessage(
            "Authorization: Basic dXNlcjpwYXNz\nprovider error"
        )

        XCTAssertEqual(sanitized, "Authorization: <redacted>\nprovider error")
        XCTAssertFalse(sanitized.contains("Basic"))
        XCTAssertFalse(sanitized.contains("dXNlcjpwYXNz"))
    }
}
