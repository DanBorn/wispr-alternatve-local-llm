import Foundation
import XCTest
@testable import FluidPushToTalk

final class RecordingRoutePolicyTests: XCTestCase {
    func testOneSegmentHermesAppliesOnlyToDumpActionInHermesMode() {
        XCTAssertTrue(RecordingRoutePolicy.isOneSegmentHermes(action: .dump, mode: .hermes))
        XCTAssertFalse(RecordingRoutePolicy.isOneSegmentHermes(action: .dump, mode: .dump))
        XCTAssertFalse(RecordingRoutePolicy.isOneSegmentHermes(action: .paste, mode: .hermes))
    }

    func testScreenshotsAreAcceptedForPasteAndControlOptionButNotBluetooth() {
        XCTAssertTrue(RecordingRoutePolicy.supportsScreenshots(action: .paste))
        XCTAssertTrue(RecordingRoutePolicy.supportsScreenshots(action: .dump))
        XCTAssertFalse(RecordingRoutePolicy.supportsScreenshots(action: .bluetooth))
    }

    func testDumpCommandImagesAreArchivedButNeverSentToProvider() {
        let images = [URL(fileURLWithPath: "/tmp/one.png"), URL(fileURLWithPath: "/tmp/two.png")]

        XCTAssertEqual(RecordingRoutePolicy.providerImages(action: .paste, images: images), images)
        XCTAssertEqual(RecordingRoutePolicy.providerImages(action: .dump, images: images), [])
        XCTAssertEqual(RecordingRoutePolicy.deliveryImages(action: .dump, images: images), images)
        XCTAssertEqual(RecordingRoutePolicy.deliveryImages(action: .paste, images: images), [])
    }
}
