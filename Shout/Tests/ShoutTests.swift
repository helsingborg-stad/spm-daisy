import XCTest
import Combine
@testable import Shout


var cancellables = Set<AnyCancellable>()
final class ShoutTests: XCTestCase {
    func testPublisher() {
        let expectation = XCTestExpectation(description: "testDatabase")
        let s = Shout("Testing")
        s.publisher.sink { event in
            XCTAssert(event.message == "test")
            XCTAssert(event.level == .info)
            XCTAssert(event.filename.hasSuffix("ShoutTests.swift"))
            XCTAssert(event.function == "testPublisher()")
            expectation.fulfill()
        }.store(in: &cancellables)
        s.info("test")
        wait(for: [expectation], timeout: 4)
    }
}
