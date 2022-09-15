import XCTest
import Combine
import TTS
import STT
import AudioSwitchboard
import TextTranslator
@testable import Assistant

enum VoiceCommands : String, CaseIterable, CustomStringConvertible {
    var description: String {
        return self.rawValue
    }
    case leave
    case home
    case weather
    case food
    case calendar
    case instagram
}
let firstTest = "test string 1"
let firstTestTranslated = "test string 1 has been translated"

let secondTest = "test string 2"
let secondTestTranslated = "test string 2 has been translated"

let supportedLocales = [Locale(identifier: "en_US"),Locale(identifier: "sv_SE")]

class TestTextTranslator : TextTranslationService {
    var availableLocalesPublisher: AnyPublisher<Set<Locale>?, Never> {
        return $availableLocales.eraseToAnyPublisher()
    }
    @Published var availableLocales: Set<Locale>? = nil
    var translationDict = [String:String]()
    init() {
        translationDict[firstTest] = firstTestTranslated
        translationDict[secondTest] = secondTestTranslated
    }
    func translate(_ texts: [TranslationKey : String], from: LanguageKey, to: [LanguageKey], storeIn table: TextTranslationTable) -> FinishedPublisher {
        let subj = FinishedSubject()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            var table = table
            for (key,_) in texts {
                for l in to {
                    if table.db[l] == nil {
                        table.db[l] = [:]
                    }
                    if let val = self.translationDict[key] {
                        table.set(value: val, for: key, in: l)
                    } else {
                        table.set(value: "unknown key \(key)", for: key, in: l)
                    }
                }
            }
            subj.send(table)
        }
        return subj.eraseToAnyPublisher()
    }
    
    func translate(_ texts: [String], from: LanguageKey, to: [LanguageKey], storeIn table: TextTranslationTable) -> FinishedPublisher {
        let subj = FinishedSubject()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            var table = table
            for key in texts {
                for l in to {
                    if let val = self.translationDict[key] {
                        table.set(value: val, for: key, in: l)
                    } else {
                        table.set(value: "unknown key \(key)", for: key, in: l)
                    }
                }
            }
            subj.send(table)
        }
        return subj.eraseToAnyPublisher()
    }
    
    func translate(_ text: String, from: LanguageKey, to: LanguageKey) -> TranslatedPublisher {
        let subj = TranslatedSubject()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            subj.send(TranslatedString(language: to, key: text, value: "mock translation"))
        }
        return subj.eraseToAnyPublisher()
    }
}
class TestSTT : STTService {
    var availableLocalesPublisher: AnyPublisher<Set<Locale>?, Never> {
        $availableLocales.eraseToAnyPublisher()
    }
    @Published var availableLocales: Set<Locale>? = [Locale(identifier: "en_US"),Locale(identifier: "sv_SE")]
    var locale: Locale = Locale(identifier: "en_US")
    var contextualStrings: [String] = []
    var mode: STTMode = .unspecified
    var resultPublisher: STTRecognitionPublisher
    var statusPublisher: STTStatusPublisher
    var errorPublisher: STTErrorPublisher
    var resultSubject = STTRecognitionSubject()
    var statusSubject = STTStatusSubject()
    var errorSubject = STTErrorSubject()
    var available: Bool = true
    var status:STTStatus = .idle {
        didSet {
            self.statusSubject.send(status)
        }
    }
    func start() {
        self.status = .recording
    }
    
    func stop() {
        self.status = .idle
    }
    func send(_ text:String) {
        if self.status == .recording {
            self.resultSubject.send(STTResult(text, confidence: 100, locale: self.locale))
        }
    }
    func done() {
        self.stop()
    }
    init() {
        resultPublisher = resultSubject.eraseToAnyPublisher()
        statusPublisher = statusSubject.eraseToAnyPublisher()
        errorPublisher = errorSubject.eraseToAnyPublisher()
    }
    
}
func createDB() -> NLParser.DB {
    var db = NLParser.DB()
    let commands = [
        VoiceCommands.leave.rawValue:["back","backwards"],
        VoiceCommands.home.rawValue:["home"],
        VoiceCommands.weather.rawValue:["weather","rain"],
        VoiceCommands.food.rawValue:["food","i am hungry"],
        VoiceCommands.calendar.rawValue:["calendar","today"],
        VoiceCommands.instagram.rawValue:["instagram"]
    ]
    for l in supportedLocales {
        db[l] = commands
    }
    return db
}
extension Assistant.CommandBridge.Result {
    func contains(_ key: VoiceCommands) -> Bool {
        return contains(key.description)
    }
}
extension Assistant {
    func listen(for keys:[VoiceCommands]) -> AnyPublisher<CommandBridge.Result,Never> {
        return listen(for: keys.map({ $0.description }))
    }
}
var switchboard = AudioSwitchboard()
var cancellabels = Set<AnyCancellable>()
final class AssistantTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()
    func testNLParser() {
        let locale = Locale(identifier:"en_US")
        let db = createDB()
        let pub = PassthroughSubject<String,Never>()
        var shouldhit = VoiceCommands.allCases
        let nlparser = NLParser(locale: locale, db: db, stringPublisher: pub.eraseToAnyPublisher())
        nlparser.publisher(using: VoiceCommands.allCases).sink { result in
            for v in VoiceCommands.allCases {
                if result.contains(v) {
                    shouldhit.removeAll { $0 == v }
                }
            }
        }.store(in: &cancellabels)
        pub.send("back")
        pub.send("home")
        pub.send("weathermap")
        pub.send("i am hungry")
        pub.send("today")
        
        XCTAssertFalse(shouldhit.contains(.food)) // found
        XCTAssert(shouldhit.contains(.weather)) // not found
        XCTAssert(shouldhit.contains(.instagram)) // not found
    }
    func testAssistant() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let sttService = TestSTT()
        var shouldhit = VoiceCommands.allCases
        let assistant = Assistant(
            sttService: sttService,
            ttsServices: AppleTTS(audioSwitchBoard: switchboard),
            supportedLocales: [Locale(identifier: "en_US"),Locale(identifier: "sv_SE")],
            translator: TestTextTranslator(),
            voiceCommands: createDB()
        )
        assistant.listen(for: VoiceCommands.allCases).sink { result in
            debugPrint(result)
            for v in VoiceCommands.allCases {
                if result.contains(v) {
                    shouldhit.removeAll { $0 == v }
                }
            }
        }.store(in: &cancellabels)
        sttService.send("back")
        sttService.send("home")
        sttService.send("weathermap")
        sttService.send("hey i am hungry now")
        sttService.send("today")
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
            debugPrint(shouldhit)
            XCTAssertFalse(shouldhit.contains(.food))
            XCTAssert(shouldhit.contains(.weather))
            XCTAssert(shouldhit.contains(.instagram))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
    func testLocaleSupport() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let sttService = TestSTT()

        let assistant = Assistant(
            sttService: sttService,
            ttsServices: AppleTTS(audioSwitchBoard: switchboard),
            supportedLocales: [Locale(identifier: "en_US"),Locale(identifier: "sv_SE")],
            translator: TestTextTranslator(),
            voiceCommands: createDB()
        )
        assistant.languageUpdatesAvailablePublisher.sink { locales in
            guard let locales = assistant.getAvailableLangaugeCodes() else {
                print("nothing?")
                return
            }
            print(locales.map({ $0}))
            XCTAssert(locales.contains("en"))
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 5)
    }
}
