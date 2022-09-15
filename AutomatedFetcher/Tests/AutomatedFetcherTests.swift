import XCTest
import Combine
@testable import AutomatedFetcher

var cancellables = Set<AnyCancellable>()

class MyNetworkFether {
    let value = PassthroughSubject<String,Never>()
    let fetcher:AutomatedFetcher<String>
    var cancellables = Set<AnyCancellable>()
    init() {
        fetcher = AutomatedFetcher<String>(value, isOn: true, timeInterval: 40)
        fetcher.triggered.sink { [weak self] in
            self?.fetch()
        }.store(in: &cancellables)
    }
    func fetch() {
        fetcher.started()
        URLSession.shared.dataTaskPublisher(for: URL(string: "https://gist.githubusercontent.com/tomasgreen/74f5d8c9a6642f9d4d64348c63ccd25d/raw/b50e9cd07780b65ec2e27cf75db66243661e53d4/activities.json")!)
            .map { $0.data }
            .tryMap { data -> String in
                guard let value = String(data: data,encoding:.utf8) else {
                    throw URLError(.unknown)
                }
                return value
            }.sink { [weak self] compl in
                switch compl {
                case .failure(let error):
                    debugPrint(error)
                    self?.fetcher.failed()
                case .finished: break;
                }
            } receiveValue: { [weak self] value in
                self?.fetcher.completed()
                self?.value.send(value)
            }.store(in: &cancellables)
    }
}
final class AutomatedFetcherTests: XCTestCase {
    func testSubscriptionFetch() {
        let expectation = XCTestExpectation(description: "testFetcher")
        
        var currentValue = "Start"
        let value = CurrentValueSubject<String,Never>(currentValue)
        
        let fetcher = AutomatedFetcher<String>(value, isOn: true, timeInterval: 2)
        debugPrint(fetcher.shouldFetch)
        fetcher.triggered.sink {
            currentValue = "End"
            value.send(currentValue)
        }.store(in: &cancellables)
        
        value.sink { value in
            XCTAssert(currentValue == value)
            if value == "End" {
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 4.0)
    }
    func testTimerFetch() {
        let expectation = XCTestExpectation(description: "testTimerFetch")
        let currentValue = "Start"
        let value = CurrentValueSubject<String,Never>(currentValue)
        let fetcher = AutomatedFetcher<String>(value, isOn: true, timeInterval: 2)
        var count = 0
        fetcher.triggered.sink {
            debugPrint("triggered")
            count += 1
            if count == 2 {
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
            fetcher.isOn = false
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                fetcher.isOn = true
            }
        }
        wait(for: [expectation], timeout: 10.0)
    }
    func testNoSubscribers() {
        let expectation = XCTestExpectation(description: "testNoSubscribers")
        let currentValue = "Start"
        let value = CurrentValueSubject<String,Never>(currentValue)
        let fetcher = AutomatedFetcher<String>(value, isOn: true, timeInterval: 10)
        
        fetcher.triggered.sink {
            XCTFail("Should not have triggered")
        }.store(in: &cancellables)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
    }
    func testExampleClass() {
        let expectation = XCTestExpectation(description: "testExampleClass")
        let f = MyNetworkFether()
        f.value.sink { string in
            expectation.fulfill()
        }.store(in: &cancellables)
        f.fetch()
        wait(for: [expectation], timeout: 10.0)
    }
    func testShouldFetch() {
        let expectation = XCTestExpectation(description: "testExampleClass")
        let f = MyNetworkFether()
        XCTAssert(f.fetcher.shouldFetch)
        f.value.sink { string in
            expectation.fulfill()
            XCTAssertFalse(f.fetcher.shouldFetch)
        }.store(in: &cancellables)
        f.fetch()
        wait(for: [expectation], timeout: 10.0)
    }
}
