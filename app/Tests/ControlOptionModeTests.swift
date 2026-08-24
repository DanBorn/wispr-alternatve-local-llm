import Foundation
import XCTest
@testable import FluidPushToTalk

final class ControlOptionModeTests: XCTestCase {
    func testMissingControlOptionModeDefaultsToDump() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))

        XCTAssertEqual(config.controlOptionMode, .dump)
    }

    func testHermesControlOptionModeRoundTripsWithoutLegacyEnabledFlag() throws {
        var config = AppConfig()
        config.controlOptionMode = .hermes

        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hermes = try XCTUnwrap(json["hermes_agent"] as? [String: Any])

        XCTAssertEqual(json["control_option_mode"] as? String, "hermes")
        XCTAssertNil(hermes["enabled"])
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: data).controlOptionMode, .hermes)
    }

    func testLegacyHermesEnabledDoesNotChangeDumpDefault() throws {
        let data = Data(#"{"hermes_agent":{"enabled":true}}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(config.controlOptionMode, .dump)
    }
}
