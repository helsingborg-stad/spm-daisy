import XCTest
import Combine
@testable import Instagram

final class InstagramTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()
    func testFetchMedia() {
//        let expectation = XCTestExpectation(description: "testFetchMedia")
//        let i = Instagram()
//        i.mediaPublisher().sink { completion in
//            if case .failure(let error) = completion {
//                XCTFail(String(describing: err))
//            } else {
//                XCTFail("done?")
//            }
//
//        } receiveValue: { arr in
//            XCTAssert(arr.isEmpty == false)
//            //XCTAssert((arr.first(where: { $0.mediaType == .album})?.children.count) ?? 0 > 0 )
//            //debugPrint(arr.first(where: { $0.mediaType == .album})?.children)
//            expectation.fulfill()
//        }.store(in: &cancellables)
//        wait(for: [expectation], timeout: 10.0)
    }
}
