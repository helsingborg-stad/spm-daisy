import XCTest
@testable import STT
import AudioSwitchboard
import Combine


var switchBoard = AudioSwitchboard()

final class STTTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()
    func testAppleSupport() {
        XCTAssertTrue(AppleSTT.hasSupportFor(locale: Locale(identifier: "sv-SE")))
        XCTAssertTrue(AppleSTT.hasSupportFor(locale: Locale(identifier: "sv")))
        XCTAssertFalse(AppleSTT.hasSupportFor(locale: Locale(identifier: "")))
        XCTAssertFalse(AppleSTT.hasSupportFor(locale: Locale(identifier: "benz-TZ")))
    }
    func testLocaleSupport() {
        let expectation = XCTestExpectation(description: "testLocaleSupport")
        let tts = STT(service:AppleSTT(audioSwitchboard: switchBoard))
        tts.availableLocalesPublisher.sink { locales in
            guard let locales = locales else {
                print("nothing?")
                return
            }
            print(locales)
            XCTAssert(locales.contains(Locale(identifier: "sv_SE")))
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 2)
    }
}
