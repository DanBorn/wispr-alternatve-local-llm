import XCTest
@testable import FluidPushToTalk

final class PictureKeyLatchTests: XCTestCase {
    func testHeldKeyCapturesOnceUntilKeyUpRearmsIt() {
        var latch = PictureKeyLatch()
        var captures = 0

        XCTAssertTrue(latch.keyDown(isAutorepeat: false) {
            captures += 1
            return true
        })
        XCTAssertTrue(latch.keyDown(isAutorepeat: true) {
            captures += 1
            return true
        })
        XCTAssertEqual(captures, 1)
        XCTAssertTrue(latch.keyUp())

        XCTAssertTrue(latch.keyDown(isAutorepeat: false) {
            captures += 1
            return true
        })
        XCTAssertEqual(captures, 2)
    }

    func testRejectedStateDoesNotSwallowPressOrLaterRepeat() {
        var latch = PictureKeyLatch()
        var attempts = 0

        XCTAssertFalse(latch.keyDown(isAutorepeat: false) {
            attempts += 1
            return false
        })
        XCTAssertFalse(latch.keyDown(isAutorepeat: true) {
            attempts += 1
            return true
        })
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(latch.keyUp())
    }

    func testAutorepeatCannotStartAnUnownedCapture() {
        var latch = PictureKeyLatch()
        var attempts = 0

        XCTAssertFalse(latch.keyDown(isAutorepeat: true) {
            attempts += 1
            return true
        })
        XCTAssertEqual(attempts, 0)
        XCTAssertFalse(latch.keyUp())
    }
}
