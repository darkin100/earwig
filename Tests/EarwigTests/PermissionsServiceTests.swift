import AVFoundation
import Speech
import XCTest
@testable import Earwig

final class PermissionsServiceTests: XCTestCase {
    func testAVStatusMapping() {
        XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.authorized), .granted)
        XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.notDetermined), .notDetermined)
        XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.denied), .denied)
        XCTAssertEqual(PermissionsService.map(AVAuthorizationStatus.restricted), .denied)
    }

    func testSpeechStatusMapping() {
        XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.authorized), .granted)
        XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.notDetermined), .notDetermined)
        XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.denied), .denied)
        XCTAssertEqual(PermissionsService.map(SFSpeechRecognizerAuthorizationStatus.restricted), .denied)
    }
}
