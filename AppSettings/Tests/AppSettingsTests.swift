import XCTest
import Combine
@testable import AppSettings

private let valueString = "string"
private let valueInt = 1
private let valueBool = false
private var cancellables = Set<AnyCancellable>()

final class AppSettingsTests: XCTestCase {
    struct TestConfig : Codable, AppSettingsConfig {
        let valueString:String?
        let valueInt:Int?
        let valueBool:Bool?
        var keyValueRepresentation: [String : String] {
            return keyValueReflection
        }
    }
    typealias TestSettings = AppSettings<TestConfig>
    func testDecodeDictionary() {
        var dict = [String:Any]()
        dict["valueString"] = "string"
        dict["valueInt"] = 1
        dict["valueBool"] = true
        
        UserDefaults.standard.setValue(dict, forKey: "test")
        if let d2 = UserDefaults.standard.dictionary(forKey: "test") {
            do {
                let config = try TestConfig.decoded(from: d2)
                XCTAssert(config.valueString == (dict["valueString"] as? String))
                XCTAssert(config.valueInt == (dict["valueInt"] as? Int))
                XCTAssert(config.valueBool == (dict["valueBool"] as? Bool))
            }
            catch {
                XCTFail(error.localizedDescription)
            }
        } else {
            XCTFail("no value")
        }
        
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "test"))
    }
    func testSettings() {
        let expectation = XCTestExpectation(description: "testSettings")
        let encoder = PropertyListEncoder()
        
        let config = TestConfig(valueString: valueString, valueInt: valueInt, valueBool: valueBool)
        do {
            let data = try encoder.encode(config)
            let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
            let file = dir.appendingPathComponent("testfile.plist")
            try data.write(to: file)
            let settings = TestSettings(defaultsFromFile: file, managedConfigEnabled: false, mixWithDefault: false)
            settings.$config.sink { config in
                guard let config = config else {
                    debugPrint("no config")
                    return
                }
                XCTAssert(config.valueString == valueString)
                XCTAssert(config.valueInt == valueInt)
                XCTAssert(config.valueBool == valueBool)
                expectation.fulfill()
            }.store(in: &cancellables)
        } catch {
            XCTFail(error.localizedDescription)
        }
        
        wait(for: [expectation], timeout: 10)
    }
    func testManagedSettings() {
        let expectation = XCTestExpectation(description: "testManagedSettings")
        let encoder = PropertyListEncoder()
        
        let config = TestConfig(valueString: valueString, valueInt: valueInt, valueBool: valueBool)
        do {
            
            let data = try encoder.encode(config)
            let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
            let file = dir.appendingPathComponent("testfile.plist")
            try data.write(to: file)
            let settings = TestSettings(defaultsFromFile: file, managedConfigEnabled: true, mixWithDefault: true)
            settings.$config.sink { config in
                guard let config = config else {
                    debugPrint("no config")
                    return
                }
                debugPrint(config)
                XCTAssert(config.valueString == valueString)
                XCTAssert(config.valueInt == valueInt)
                XCTAssert(config.valueBool == valueBool)
                expectation.fulfill()
            }.store(in: &cancellables)
        } catch {
            XCTFail(error.localizedDescription)
        }
        UserDefaults.standard.set(["valueInt":3], forKey: "com.apple.configuration.managed")
        wait(for: [expectation], timeout: 10)
    }
    func testMask() {
        let testString = "abcdefghij"
        XCTAssert(String.mask(testString, leave: testString.count + 5)  == testString)
        XCTAssert(String.mask(testString, leave: testString.count)      == testString)
        XCTAssert(String.mask(testString, leave: 3)                     == "*******hij")
        XCTAssert(String.mask(testString, leave: 0)                     == "**********")
        XCTAssert(String.mask(nil,        leave: 3)                     == nil)
        XCTAssert(String.mask("",         leave: 3)                     == "")
        
        XCTAssert(String.mask(testString, percentage: 0)                == testString)
        XCTAssert(String.mask(testString, percentage: 50)               == "*****fghij")
        XCTAssert(String.mask(testString, percentage: 100)              == "**********")
        XCTAssert(String.mask(nil,        percentage: 50)               == nil)
        XCTAssert(String.mask("",         percentage: 50)               == "")
    }
}
