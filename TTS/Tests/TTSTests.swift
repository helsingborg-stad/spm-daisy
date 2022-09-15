import XCTest
import AudioSwitchboard
import Combine
import Speech
@testable import TTS


var switchBoard = AudioSwitchboard()
final class TTSTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()
    let tts = TTS(AppleTTS(audioSwitchBoard: switchBoard))
    func testFinished() {
        let expectation = XCTestExpectation(description: "testFinished")
        let u = TTSUtterance.init("Hej", voice: TTSVoice.init(locale: Locale(identifier: "sv-SE")))
        var statuses:[TTSUtteranceStatus] = [.none,.queued,.preparing,.speaking,.finished]
        u.statusPublisher.sink { status in
            statuses.removeAll { $0 == status }
            if status == .finished {
                XCTAssert(statuses.count == 0)
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testFailure() {
        let expectation = XCTestExpectation(description: "testFailure")
        let u = TTSUtterance.init("Hej", voice: TTSVoice.init(locale: Locale(identifier: "hr-HR")))
        var statuses:[TTSUtteranceStatus] = [.none,.queued,.failed]
        u.failurePublisher.sink { error in
            expectation.fulfill()
            XCTAssert(statuses.count == 0)
        }.store(in: &cancellables)
        u.statusPublisher.sink { status in
            statuses.removeAll { $0 == status }
            debugPrint(status)
        }.store(in: &cancellables)
        tts.play(u)
        wait(for: [expectation], timeout: 10)
    }
    func testCancelled() {
        let expectation = XCTestExpectation(description: "testCancelled")
        let tts = TTS(AppleTTS(audioSwitchBoard: switchBoard))
        let u = TTSUtterance.init("Hej", voice: TTSVoice.init(locale: Locale(identifier: "sv-SE")))
        var statuses:[TTSUtteranceStatus] = [.none,.queued,.preparing,.speaking,.cancelled]
        u.statusPublisher.sink { status in
            statuses.removeAll { $0 == status }
            if status == .speaking {
                tts.cancel(u)
            }
            if status == .cancelled {
                XCTAssert(statuses.count == 0)
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testWordBoundary() {
        XCTFail("Test broken due to changes in iOS 16")
        let expectation = XCTestExpectation(description: "testCancelled")
        let tts = TTS(AppleTTS(audioSwitchBoard: switchBoard))
        let string = "Hello world"
        let u = TTSUtterance.init(string, voice: TTSVoice.init(locale: Locale(identifier: "en-US")))
        var words = string.split(separator: " ").map { String($0) }
        u.wordBoundaryPublisher.sink { boundary in
            XCTAssert(string[boundary.range] == boundary.string)
            words.removeAll { $0 == boundary.string }
        }.store(in: &cancellables)
        u.statusPublisher.sink { status in
            if status == .finished {
                XCTAssert(words.count == 0)
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testAppleSupport() {
        let tts = AppleTTS(audioSwitchBoard: switchBoard)
        XCTAssertTrue(tts.hasSupportFor(locale: Locale(identifier: "sv-SE")))
        XCTAssertTrue(tts.hasSupportFor(locale: Locale(identifier: "sv")))
        XCTAssertTrue(tts.hasSupportFor(locale: Locale(identifier: "sv"), gender:.other))
        XCTAssertTrue(tts.hasSupportFor(locale: Locale(identifier: "sv"), gender:.female))
        XCTAssertFalse(tts.hasSupportFor(locale: Locale(identifier: "sv"), gender:.male))
        XCTAssertFalse(tts.hasSupportFor(locale: Locale(identifier: "")))
        XCTAssertFalse(tts.hasSupportFor(locale: Locale(identifier: "hr-HR")))
    }
    func testGender() {
        XCTAssertTrue(TTSGender.male.isEqual(to: AVSpeechSynthesisVoiceGender.male))
        XCTAssertTrue(TTSGender.male.isEqual(to: AVSpeechSynthesisVoiceGender.unspecified))
        XCTAssertFalse(TTSGender.male.isEqual(to: AVSpeechSynthesisVoiceGender.female))
        
        XCTAssertTrue(TTSGender.female.isEqual(to: AVSpeechSynthesisVoiceGender.female))
        XCTAssertTrue(TTSGender.female.isEqual(to: AVSpeechSynthesisVoiceGender.unspecified))
        XCTAssertFalse(TTSGender.female.isEqual(to: AVSpeechSynthesisVoiceGender.male))
        
        XCTAssertTrue(TTSGender.other.isEqual(to: AVSpeechSynthesisVoiceGender.male))
        XCTAssertTrue(TTSGender.other.isEqual(to: AVSpeechSynthesisVoiceGender.female))
        XCTAssertTrue(TTSGender.other.isEqual(to: AVSpeechSynthesisVoiceGender.unspecified))
    }
    func testRateAndPitch() {
        let voiceDefault = TTSVoice(id: "test", name: "test", gender: .male, rate: nil, pitch: nil, locale: Locale(identifier: "sv-SE"))
        XCTAssert(pitch(from: voiceDefault) == AVSpeechUtteranceDefaultSpeechPitch)
        XCTAssert(rate(from: voiceDefault) == AVSpeechUtteranceDefaultSpeechRate)
        
        let voiceWithinRange = TTSVoice(id: "test", name: "test", gender: .male, rate: 0.6, pitch: 1.2, locale: Locale(identifier: "sv-SE"))
        XCTAssert(rate(from: voiceWithinRange) == AVSpeechUtteranceDefaultSpeechRate * 0.6)
        XCTAssert(pitch(from: voiceWithinRange) == AVSpeechUtteranceDefaultSpeechPitch * 1.2)
        
        let voiceOutOfLowerRange = TTSVoice(id: "test", name: "test", gender: .male, rate: 0, pitch: 0, locale: Locale(identifier: "sv-SE"))
        XCTAssert(rate(from: voiceOutOfLowerRange) == AVSpeechUtteranceMinimumSpeechRate)
        XCTAssert(pitch(from: voiceOutOfLowerRange) == AVSpeechUtteranceMinimumSpeechPitch)
        
        let voiceOutOfUpperRange = TTSVoice(id: "test", name: "test", gender: .male, rate: 3, pitch: 3, locale: Locale(identifier: "sv-SE"))
        XCTAssert(rate(from: voiceOutOfUpperRange) == AVSpeechUtteranceMaximumSpeechRate)
        XCTAssert(pitch(from: voiceOutOfUpperRange) == AVSpeechUtteranceMaximumSpeechPitch)
        debugPrint(AVSpeechUtteranceMinimumSpeechRate,AVSpeechUtteranceDefaultSpeechRate,AVSpeechUtteranceMaximumSpeechRate)
        let expectation = XCTestExpectation(description: "testFinished")
        let u = TTSUtterance("Såhär låter dina inställningar", gender: .other, locale: Locale(identifier: "sv-SE"), rate: 1, pitch: 1, tag: "test")
        var statuses:[TTSUtteranceStatus] = [.none,.queued,.preparing,.speaking,.finished]
        u.statusPublisher.sink { status in
            statuses.removeAll { $0 == status }
            if status == .finished {
                XCTAssert(statuses.count == 0)
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testLocaleSupport() {
        let expectation = XCTestExpectation(description: "testLocaleSupport")
        let tts = TTS(AppleTTS(audioSwitchBoard: switchBoard))
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
