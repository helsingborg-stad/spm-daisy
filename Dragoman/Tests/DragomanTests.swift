import XCTest
import Combine
import TextTranslator
@testable import Dragoman


var cancellables = Set<AnyCancellable>()

let firstTest = "test string 1"
let firstTestTranslated = "test string 1 has been translated"

let secondTest = "test string 2"
let secondTestTranslated = "test string 2 has been translated"

class TestTextTranslator : TextTranslationService {
    var availableLocalesPublisher: AnyPublisher<Set<Locale>?, Never> {
        return $availableLocales.eraseToAnyPublisher()
    }
    
    @Published var availableLocales: Set<Locale>? = [Locale(identifier: "sv_SE")]
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
let translator = TestTextTranslator()
final class DragomanTests: XCTestCase {
    func testSoftClean() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(translationService: translator, language: "sv")
        try? dragoman.clean()
        dragoman.translate([firstTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            do {
                try dragoman.clean(soft: true)
            } catch {
                XCTFail(error.localizedDescription)
            }
            XCTAssert(dragoman.string(forKey: firstTest, in: "en-US") == firstTestTranslated)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 10)
    }
    func testTranslate() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(translationService: translator, language: "sv")
        try? dragoman.clean()
        dragoman.translate([firstTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssert(dragoman.string(forKey: firstTest, in: "en-US") == firstTestTranslated)
            dragoman.language = "en"
            dragoman.translate([secondTest], from: "sv", to: ["en"]).sink { compl in
                if case let .failure(error) = compl {
                    debugPrint(error)
                    XCTFail(error.localizedDescription)
                }
            } receiveValue: {
                let str = dragoman.string(forKey: secondTest, in: "en")
                print(str)
                XCTAssert(dragoman.string(forKey: secondTest, in: "en") == secondTestTranslated)
                
                let dragoman2 = Dragoman(language: "sv")
                XCTAssert(dragoman2.string(forKey: firstTest, in: "en") == firstTestTranslated)
                XCTAssert(dragoman2.string(forKey: secondTest, in: "en") == secondTestTranslated)
                
                expectation.fulfill()
            }.store(in: &cancellables)
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 10)
    }
    func testLanguageIdentifier() {
        //let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(translationService: translator, language: "sv")
        try? dragoman.clean()
        dragoman.add(bundle: Bundle.module)
        XCTAssertTrue(dragoman.string(forKey: "this_is_a_test", in:"en-US") == "en-US translation")
        XCTAssertTrue(dragoman.string(forKey: "this_is_a_test", in:"en_US") == "en-US translation")
        XCTAssertTrue(dragoman.string(forKey: "this_is_a_test", in:"en") == "en translation")
        
        //wait(for: [expectation], timeout: 5)
    }
    func testTranslationQueue() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(translationService: translator, language: "en")
        try? dragoman.clean()
        dragoman.translate([firstTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssert(dragoman.string(forKey: firstTest) == firstTestTranslated)
            XCTAssert(dragoman.string(forKey: secondTest) == secondTest)
        }.store(in: &cancellables)
        
        dragoman.translate([secondTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssert(dragoman.string(forKey: firstTest) == firstTestTranslated)
            XCTAssert(dragoman.string(forKey: secondTest) == secondTestTranslated)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 5)
    }
    func testCurrentLanguage() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(translationService: translator, language: "sv")
        try? dragoman.clean()
        dragoman.translate([firstTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssert(dragoman.string(forKey: firstTest) == firstTest)
            dragoman.language = "en"
            XCTAssert(dragoman.string(forKey: firstTest) == firstTestTranslated)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 5)
    }
    func testRemove() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(translationService: translator, language: "sv")
        try? dragoman.clean()
        dragoman.language = "en"
        dragoman.translate([firstTest,secondTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssert(dragoman.string(forKey: firstTest) == firstTestTranslated)
            XCTAssert(dragoman.string(forKey: secondTest) == secondTestTranslated)
            try? dragoman.remove(keys: [firstTest])
            XCTAssert(dragoman.string(forKey: firstTest) == firstTest)
            XCTAssert(dragoman.string(forKey: secondTest) == secondTestTranslated)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 5)
    }
    func testIsTranslated() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(translationService: translator, language: "sv")
        try? dragoman.clean()
        dragoman.language = "en"
        dragoman.translate([firstTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssertFalse(dragoman.isTranslated(firstTest, in: ["en-US"],exactMatch: true))
            XCTAssertTrue(dragoman.isTranslated(firstTest, in: ["en-US"],exactMatch: false))
            XCTAssertFalse(dragoman.isTranslated(secondTest, in: ["en"]))
            XCTAssertFalse(dragoman.isTranslated(firstTest, in: ["pt"]))
            XCTAssertFalse(dragoman.isTranslated(firstTest, in: ["pt","en"]))
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 5)
    }
    func testLocaleSupport() {
        let expectation = XCTestExpectation(description: "testLocaleSupport")
        let dragoman = Dragoman(translationService: translator, language: "sv")
        dragoman.availableLocalesPublisher.sink { locales in
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
