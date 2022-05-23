import XCTest
import Combine
@testable import PublicCalendar

var cancellables = Set<AnyCancellable>()
final class PublicCalendarTests: XCTestCase {
    func testIsHoliday() {
        let expectation = XCTestExpectation(description: "testIsHoliday")
        let c = PublicCalendar(years: [2019], fetchAutomatically: true, previewData: false)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let date = df.date(from: "2019-12-25")!
        c.fetch().sink { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:debugPrint("finished")
            }
        } receiveValue: { db in
            XCTAssert(db?.isHoliday(date: date) == true)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 20.0)
    }
    func testIsNotHoliday() {
        let expectation = XCTestExpectation(description: "testIsNotHoliday")
        let c = PublicCalendar(years: [2019], fetchAutomatically: true, previewData: false)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let date = df.date(from: "2019-12-23")!
        c.fetch().sink { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:debugPrint("finished")
            }
        } receiveValue: { db in
            XCTAssert(db?.isHoliday(date: date) == false)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 20.0)
    }
    func testNotFound() {
        let expectation = XCTestExpectation(description: "testNotFound")
        let c = PublicCalendar(years: [2019], fetchAutomatically: true, previewData: false)
        let df = DateFormatter()
        c.purge()
        df.dateFormat = "yyyy-MM-dd"
        let date = df.date(from: "2021-12-24")!
        c.fetch().sink { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:debugPrint("finished")
            }
        } receiveValue: { db in
            XCTAssert(db?.events(on: date).isEmpty == true)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 20.0)
    }
}
