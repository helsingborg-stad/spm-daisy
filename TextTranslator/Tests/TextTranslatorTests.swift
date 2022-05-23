import XCTest
import Combine

@testable import TextTranslator

var cancellables = Set<AnyCancellable>()

enum Strings: String, CaseIterable {
    case string1 = "test string 1"
    case string2 = "test string 2"
    static let dictionary:[String:String] = [
        Strings.string1.rawValue: Strings.string1.translatedValue,
        Strings.string2.rawValue: Strings.string2.translatedValue
    ]
    var translatedValue:String {
        switch self {
        case .string1: return "test string 1 has been translated"
        case .string2: return "test string 2 has been translated"
        }
    }
    static func translation(for key:String) -> String {
        return Self(rawValue: key)?.translatedValue ?? "unable to translate \(key)"
    }
}

class TestTextTranslator : TextTranslationService {
    var availableLocalesPublisher: AnyPublisher<Set<Locale>?, Never> {
        return $availableLocales.eraseToAnyPublisher()
    }
    
    @Published var availableLocales: Set<Locale>? = nil
    
    func translate(_ texts: [TranslationKey : String], from: LanguageKey, to: [LanguageKey], storeIn table: TextTranslationTable) -> FinishedPublisher {
        let subj = FinishedSubject()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            var table = table
            for (key,_) in texts {
                for l in to {
                    if table.db[l] == nil {
                        table.db[l] = [:]
                    }
                    table.set(value: Strings.translation(for: key), for: key, in: l)
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
                    table.set(value: Strings.translation(for: key), for: key, in: l)
                }
            }
            subj.send(table)
        }
        return subj.eraseToAnyPublisher()
    }
    func translate(_ text: String, from: LanguageKey, to: LanguageKey) -> TranslatedPublisher {
        return CurrentValueSubject<TranslatedString,Error>(
            TranslatedString(
                language: to,
                key: text,
                value: Strings.translation(for: text)
            )
        ).eraseToAnyPublisher()
    }
}

final class TextTranslatorTests: XCTestCase {
    func testTranslateSingleValue() {
        let translator = TextTranslator(service: TestTextTranslator())
        translator.translate(Strings.string1.rawValue, from: "se", to: "en").sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: { string in
            XCTAssert(Strings.string1.rawValue == string.key)
            XCTAssert(Strings.string1.translatedValue == string.value)
        }.store(in: &cancellables)
    }
    func testTranslateMultipleValues() {
        let translator = TextTranslator(service: TestTextTranslator())
        translator.translate(Strings.allCases.map { $0.rawValue }, from: "se", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: { table in
            XCTAssert(table.value(forKey: Strings.string1.rawValue, in: "en") == Strings.string1.translatedValue)
            XCTAssert(table.value(forKey: Strings.string2.rawValue, in: "en") == Strings.string2.translatedValue)
        }.store(in: &cancellables)
    }
    func testTranslationTable() {
        let keys = Strings.allCases.map { $0.rawValue }
        var table = TextTranslationTable()
        
        XCTAssert(table.translationExists(forKey: Strings.string1.rawValue, in: "en") == false)
        table.set(value: Strings.string1.translatedValue, for: Strings.string1.rawValue, in: "en")
        
        XCTAssert(table.translationExists(forKey: Strings.string1.rawValue, in: "en") == true)
        XCTAssert(table.hasUntranslatedValues(for: keys, in: ["en"]))
        
        let dict = table.findUntranslated(using: keys, in: ["en"])
        
        XCTAssert(dict[Strings.string2.rawValue] == ["en"])
        XCTAssertNil(dict[Strings.string1.rawValue])
        
        table.remove(strings: keys)
        XCTAssert(table.isEmpty)
    }
    func testMergeTables() {
        let keys = Strings.allCases.map { $0.rawValue }
        var table = TextTranslationTable()
        var table2 = TextTranslationTable()
        table.set(value: Strings.string1.translatedValue, for: Strings.string1.rawValue, in: "en")
        table2.set(value: Strings.string2.translatedValue, for: Strings.string2.rawValue, in: "en")
        
        XCTAssert(table.hasUntranslatedValues(for: keys, in: ["en"]))
        table.merge(with: table2)
        XCTAssertFalse(table.hasUntranslatedValues(for: keys, in: ["en"]))
    }
    func testFailure() {
        let translator = TextTranslator(service:nil)
        translator.translate(Strings.allCases.map { $0.rawValue }, from: "se", to: ["en"]).sink { compl in
            if case let .failure(error) = compl, let e = error as? TextTranslatorError {
                XCTAssert(e == TextTranslatorError.missingService)
            } else {
                XCTFail("Incorrect error?")
            }
        } receiveValue: { table in
            XCTFail("Should not have completed")
        }.store(in: &cancellables)
    }
    func testLocales() {
        let expectation = XCTestExpectation(description: "testLocales")
        let service =  TestTextTranslator()
        let translator = TextTranslator(service:service)
        translator.availableLocalesPublisher.sink { locales in
            guard let locales = locales else {
                return
            }
            XCTAssertTrue(locales.count == 2)
            XCTAssertTrue(translator.hasSupport(for: Locale(identifier: "sv_SE"), exact: true))
            XCTAssertFalse(translator.hasSupport(for: Locale(identifier: "sv"), exact: true))
            XCTAssertTrue(translator.hasSupport(for: Locale(identifier: "sv"), exact: false))
            expectation.fulfill()
        }.store(in: &cancellables)
        service.availableLocales = [Locale(identifier: "sv_SE"),Locale(identifier: "en_US")]
        wait(for: [expectation], timeout: 10)
    }
}
