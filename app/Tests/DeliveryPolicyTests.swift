import XCTest
@testable import FluidPushToTalk

final class DeliveryPolicyTests: XCTestCase {
    func testDisabledPasteIsSkipped() {
        XCTAssertEqual(
            DeliveryPolicy.permission(for: .clipboard, pasteEnabled: false, dumpEnabled: true),
            .skipped(reason: "clipboard paste is disabled")
        )
    }

    func testDisabledDumpIsSkipped() {
        XCTAssertEqual(
            DeliveryPolicy.permission(for: .dump, pasteEnabled: true, dumpEnabled: false),
            .skipped(reason: "markdown dump is disabled")
        )
    }

    func testEnabledAndBluetoothRoutesAreAllowed() {
        XCTAssertEqual(
            DeliveryPolicy.permission(for: .clipboard, pasteEnabled: true, dumpEnabled: false),
            .allowed
        )
        XCTAssertEqual(
            DeliveryPolicy.permission(for: .dump, pasteEnabled: false, dumpEnabled: true),
            .allowed
        )
        XCTAssertEqual(
            DeliveryPolicy.permission(for: .bluetoothKeyboard, pasteEnabled: false, dumpEnabled: false),
            .allowed
        )
    }
}
