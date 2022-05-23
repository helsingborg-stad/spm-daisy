# Meals

Meals provides a common interface for meal services implementing the `MealService` protocol.

## Usage 

```swift
import Meals 
import Combine
import SwiftUI

public class MyMealService : MealService {
    public func fetchMealsPublisher() -> AnyPublisher<[Meal], Error> {
        let subject = PassthroughSubject<[Meal],Error>()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            subject.send(Meals.previewData)
        }
        return subject.eraseToAnyPublisher()
    }
}

class StateManager {
    var meals:Meals
    init {
        let previewMode = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let meals = Meals(service: MyMealService(), fetchAutomatically: true, previewData: previewMode)
    }
}

struct FoodView: View {
    @EnvironmentObject var meals:Meals
    @State var items = [Meal]()
    var body: some View {
        List {
            Section(header: Text("Todays lunch")) {
                ForEach(items) { meal in
                    VStack(alignment: .leading) {
                        Text(meal.title ?? meal.occasion.rawValue).bold()
                        Text(meal.description)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }
        }
        .onReceive(meals.publisher(occation:.lunch)) { val in
            guard let val = val else {
                return
            }
            items = val
        }
    }
}

@main struct ExampleAssistantApp: App {
    @StateObject var appState = StateManager()
    var body: some Scene {
        WindowGroup {
            FoodView().environmentObject(appState.meals)
        }
    }
}
```

## Skolmaten.se service
Implements MealService from the swift package `Meals` and develivers meal information from Skolmaten.se via thier RSS-endpoint.

The `School` object implements the `MealService` protocol. You can provide the information to a school manually or by searching using either `Skolmaten.first` or `Skolmaten.filter`.
Once you have a `School` you can us it together with a `Meals` instance or create your own implementation using `School.fetchMealsPublisher(filter:offset:limit:)` method.  

```swift 
Skolmaten.first(county:"Skåne", municipality:"Helsingborg", school:"Råå förskola").sink { completion in
    switch completion {
    case .failure(let error): debugPrint(error)
    case .finished: break
    }
} receiveValue: { school in
    // Store your school for later use to speed up your implementation and remove redundant network requests.
    meals.service = school
}
```


## Mashie service
Implements MealService from the swift package `Meals` and develivers meal information from the Mashie online service. You can use the `MashieEaterie` as a meal service in the `Meals` library.

```swift 
/// Find the organization id, it should be in the url
let organization = "cb776b5e"

/// Use the full "mpi" url 
let url = URL(string: "https://mpi.mashie.com/public/menu/helsingborg+vof/\(organization)?country=se")!

/// The service scrapes the mashie website for information so you need to 
/// add the parameters for each meal yourself. Each paramter is compared to to a meal title in the HTML. 
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
let mashie = MashieEaterie(url: url, orgId: organization, parameters: parameters)

mashie.fetchMealsPublisher().sink { compl in
    switch compl {
    case .failure(let error): debugPrint(error)
    case .finished: break;
    }
} receiveValue: { meals in
    
}
```


## TODO

- [x] add list of available services
- [x] code-documentation
- [x] write tests
- [x] complete package documentation
- [ ] the `fetch` method should return a publisher, similar to what we did with the `spm-public-calendar` library
- [ ] perhaps we should change so that the date supplided in the publisher method fetches information for that date instead of just filtering the last fetch. 
