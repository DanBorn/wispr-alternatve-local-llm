import Foundation
import XCTest
@testable import FluidPushToTalk

final class HermesAgentRunnerTests: XCTestCase {
    func testNativeImageCommandsPreserveOrderAndQuotePaths() {
        let urls = [
            URL(fileURLWithPath: "/tmp/first image.png"),
            URL(fileURLWithPath: "/tmp/second.png"),
        ]

        XCTAssertEqual(
            HermesAgentRunner.nativeImageCommands(for: urls),
            [
                #"/image "/tmp/first image.png""#,
                #"/image "/tmp/second.png""#,
            ]
        )
    }

    func testNativeImageCommandEscapesBackslashesAndQuotes() {
        let url = URL(fileURLWithPath: #"/tmp/a\b"c.png"#)

        XCTAssertEqual(
            HermesAgentRunner.nativeImageCommands(for: [url]),
            [#"/image "/tmp/a\\b\"c.png""#]
        )
    }

    func testSessionValidationRejectsExitZeroNotFoundText() {
        XCTAssertFalse(
            HermesAgentRunner.isValidSessionExport(
                "Session not found: stale-id\nUse a session ID from a previous CLI run."
            )
        )
    }

    func testSessionValidationAcceptsSessionJSON() {
        XCTAssertTrue(HermesAgentRunner.isValidSessionExport(#"{"messages":[]}"#))
    }
}
