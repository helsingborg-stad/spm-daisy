import XCTest
import Combine
@testable import Weather

final class WeatherTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    func testObservation() {
        let expectation = XCTestExpectation(description: "Fetch SMHI data")
        SMHIObservations.publisher(forStation: "karlstad", parameter: "1", period: "latest-hour").sink(receiveCompletion: { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:debugPrint("finished")
            }
        }, receiveValue: { val in
            guard let value = val.value.first else {
                XCTFail("no values")
                expectation.fulfill()
                return
            }
            if val.parameter.key == "13", let str = SMHIObservations.ConditionCodeDescription[value.value] {
                debugPrint(str)
            } else if val.parameter.key == "1" {
                debugPrint(value.value + "°")
            }
            expectation.fulfill()
        }).store(in: &self.cancellables)
        wait(for: [expectation], timeout: 10.0)
    }
    func testHistoricalObservationValues() {
        let expectation = XCTestExpectation(description: "Fetch SMHI data")
        SMHIObservations.publisher(forStation: "helsingborg", parameter: "7", period: "latest-months").sink(receiveCompletion: { compl in
            switch compl {
            case .failure(let error):
                debugPrint(error)
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:debugPrint("finished")
            }
        }, receiveValue: { val in
            debugPrint(val.station.name,val.parameter.name,val.period.from,val.period.to, val.value.count)
            expectation.fulfill()
        }).store(in: &self.cancellables)
        wait(for: [expectation], timeout: 60*2)
    }
    func testLocation() {
        let expectation = XCTestExpectation(description: "Fetch SMHI data")
        SMHIObservations.publisher(latitude: 59.323840, longitude:13.466290, parameter: "1", period: "latest-hour").sink(receiveCompletion: { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:debugPrint("finished")
            }
        }, receiveValue: { val in
            guard let value = val.value.first else {
                XCTFail("no values")
                expectation.fulfill()
                return
            }
            debugPrint(val.station.name)
            if val.parameter.key == "13", let str = SMHIObservations.ConditionCodeDescription[value.value] {
                debugPrint(str)
            } else if val.parameter.key == "1" {
                debugPrint(value.value + "°")
            }
            expectation.fulfill()
        }).store(in: &self.cancellables)
        wait(for: [expectation], timeout: 10.0)
    }
    func testParameters() {
        let expectation = XCTestExpectation(description: "Fetch SMHI observation data")
        SMHIObservations.publisher.sink { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:
                debugPrint("finished resources")
            }
        } receiveValue: { data in
            data.resource.sorted(by: { Int($0.key)! < Int($1.key)! }).forEach { param in
                print(param.key, param.title,param.summary)
            }
            expectation.fulfill()
        }.store(in: &self.cancellables)
        wait(for: [expectation], timeout: 10.0)
    }
    func testForeacast() {
        let expectation = XCTestExpectation(description: "Fetch SMHI observation data")
        
        SMHIForecastService().fetch(using: .init(latitude: 56.0014127, longitude: 12.7416203)).sink { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                expectation.fulfill()
            case .finished:
                debugPrint("finished resources")
            }
        } receiveValue: { w in
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 10.0)
    }
    func testWeather() {
        let expectation = XCTestExpectation(description: "Fetch SMHI observation data")
        let service = SMHIForecastService()
        let weather = Weather(service: service, fetchAutomatically:  true)
        weather.coordinates = .init(latitude: 59.323840, longitude: 13.466290)
        weather.latest.sink { data in
            guard data != nil else {
                return
            }
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 10.0)
    }
    func testWeatherNonAutomatic() {
        let expectation = XCTestExpectation(description: "Fetch SMHI observation data")
        let service = SMHIForecastService()
        let weather = Weather(service: service, fetchAutomatically:  false, previewData: true)
        weather.coordinates = .init(latitude: 59.323840, longitude: 13.466290)
        weather.latest.sink { data in
            guard data != nil else {
                return
            }
            XCTFail("should not complete")
        }.store(in: &cancellables)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { timer in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
