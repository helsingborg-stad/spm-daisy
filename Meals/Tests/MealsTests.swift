import XCTest
@testable import Meals
import Combine

var cancellables = Set<AnyCancellable>()
final class MealsTests: XCTestCase {
    func testSkolmatenFirstSchool() {
        let expectation = XCTestExpectation(description: "Fetch schools")
        Skolmaten.first(county: "skåne", municipality: "helsingborg", school: "råå").sink { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                debugPrint(error)
                expectation.fulfill()
            case .finished:
                debugPrint("finished resources")
            }
        } receiveValue: { school in
            XCTAssert(school.title.contains("Råå förskola"))
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 20.0)
    }
    func testGetMeals() {
        let expectation = XCTestExpectation(description: "Mealstest")
        let school = Skolmaten.School.init(url: URL(string: "https://skolmaten.se/raa-forskola/")!, title: "Råå förskola", parentURL: URL(string: "https://skolmaten.se/d/helsingborgs-stad/"))
        let meals = Meals(service: school)
        let d = Date().addingTimeInterval(60*60*24)
        meals.publisher(for: d).sink { meals in
            guard let meals = meals else {
                return
            }
            XCTAssert(meals.contains { Calendar(identifier: Calendar.Identifier.gregorian).isDate($0.date, inSameDayAs: d)})
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 20.0)
    }
    func testMashie() {
        let organization = "cb776b5e"
        let url = URL(string: "https://mpi.mashie.com/public/menu/helsingborg+vof/\(organization)?country=se")!
        
        let parameters:[MashieEaterie.Parameter] = [
            .init(occation:.lunch,  foodType: .undecided,   title: "Dagens middag", tags:[]),
            .init(occation:.lunch,  foodType: .undecided,   title: "Dagens middag mos", tags:[.easyToChew]),
            .init(occation:.lunch,  foodType: .undecided,   title: "Dagens alternativ", tags:[.alternative]),
            .init(occation:.lunch,  foodType: .undecided,   title: "Dagens alternativ mos", tags:[.alternative,.easyToChew]),
            .init(occation:.lunch,  foodType: .undecided,   title: "Dagens gröna", tags:[.vegetarian]),
            .init(occation:.lunch,  foodType: .undecided,   title: "Dagens gröna mos", tags:[.vegetarian,.easyToChew]),
            .init(occation:.lunch,  foodType: .dessert,     title: "Dessert"),
            .init(occation:.dinner, foodType: .undecided,   title: "Kvällsmat", tags:[]),
            .init(occation:.dinner, foodType: .undecided,   title: "Kvällsmat mos", tags:[.easyToChew]),
            .init(occation:.dinner, foodType: .undecided,   title: "Kvällsmat avvikelse veg", tags:[.vegetarian]),
            .init(occation:.dinner, foodType: .undecided,   title: "Kvällsmat avvikelse veg mos", tags:[.vegetarian,.easyToChew]),
            .init(occation:.dinner, foodType: .undecided,   title: "Kvällens enkla", tags:[.simple]),
            .init(occation:.dinner, foodType: .undecided,   title: "Kvällens enkla mos", tags:[.simple,.easyToChew])
        ]
        let expectation = XCTestExpectation(description: "testMashie")
        let mashie = MashieEaterie(url: url, orgId: organization, parameters: parameters)
        mashie.fetchMealsPublisher().sink { compl in
            switch compl {
            case .failure(let error):
                XCTFail(error.localizedDescription)
                debugPrint(error)
                expectation.fulfill()
            case .finished:
                debugPrint("finished resources")
            }
        } receiveValue: { meals in
            XCTAssert(meals.count > 0)
            expectation.fulfill()
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 20.0)
    }
}
