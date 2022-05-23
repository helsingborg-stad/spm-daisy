import Foundation
import Combine
import AutomatedFetcher


/// Used for fetching information from services providing some kind of daily meal menu
public protocol MealService {
    
    /// Invokes a fetch and return a completion publisher
    func fetchMealsPublisher() -> AnyPublisher<[Meal],Error>
}
/// A representation of a single meal.
public struct Meal : Identifiable, Equatable, Hashable {
    
    /// The occation for when the meal is served.
    public enum Occasion: String, Equatable, Hashable {
        /// Breakfast
        case breakfast
        /// Lunch
        case lunch
        /// Dinner
        case dinner
        /// Supper
        case supper
        /// Unknown or undecided
        case undecided
    }
    
    /// A general description of the type of food.
    public enum FoodType: String, Equatable, Hashable {
        /// A full meal
        case meal
        /// A snack
        case snack
        /// A dessert
        case dessert
        /// Unknown or undecided
        case undecided
    }
    
    /// Tags that further decribe what kind of meal it is.
    public enum Tag: String, Equatable, Hashable {
        /// Vegetarian
        case vegetarian
        /// Vegan
        case vegan
        /// Easy to chew, important for the elderly
        case easyToChew
        /// An alternative to the main meal
        case alternative
        /// A simple meal, like a sandwich.
        case simple
    }
    
    /// The meal id, can be a concatenation of other info
    public let id:String
    /// The meal description, for example: "Hamburger with french fries, dipp and a side sallad"
    public let description:String
    /// Optional title for the meal, could be "Daily lunch"
    public let title:String?
    /// The date for when it's served. Time should not be a factor since occation describes the general time for when it's served.
    public let date:Date
    /// The occation for when the meal is served.
    public let occasion:Occasion
    /// The type of food
    public let type:FoodType
    /// Tags further describing the meal
    public let tags:Set<Tag>
    /// Further information about the meal such as ingredients, origin or something else.
    /// - Note: Change it to [String:String]?
    public let info:[String]
    /// Image or photo of the meal
    public let imageUrl:URL?
    /// The meal carbon footprint
    public let carbonFootprint:Double?
    /// Meal rating
    public let rating:Double?
    
    /// Returns a meal object
    /// - Parameters:
    ///   - id: The meal id, if no id is supplied the date and description is used to create an id
    ///   - description: The meal description, for example: "Hamburger with french fries, dipp and a side sallad"
    ///   - title: Optional title for the meal, could be "Daily lunch"
    ///   - date: The date for when it's served. Time should not be a factor since occation describes the general time for when it's served.
    ///   - occasion: The occation for when the meal is served.
    ///   - type: Tags further describing the meal
    ///   - tags: Tags further describing the meal
    ///   - info: Further information about the meal such as ingredients, origin or something else.
    ///   - imageUrl: Image or photo of the meal
    ///   - carbonFootprint: The meal carbon footprint
    ///   - rating: Meal rating
    public init(id:String? = nil, description:String, title:String? = nil, date:Date, occasion:Occasion = .undecided, type:FoodType = .undecided, tags:Set<Tag> = [], info:[String] = [], imageUrl:URL? = nil, carbonFootprint:Double? = nil, rating:Double? = nil) {
        if let id = id {
            self.id = id
        } else {
            self.id = String(describing: date) + "\(description)"
        }
        self.description = description
        self.info = info
        self.title = title
        self.date = date
        self.occasion = occasion
        self.type = type
        self.tags = tags
        self.imageUrl = imageUrl
        self.carbonFootprint = carbonFootprint
        self.rating = rating
    }
}

/// [Meal] array extension filterning meals with varius parameters
public extension Array where Element == Meal {
    
    /// Filter [Meal] with various parameters
    /// - Parameters:
    ///   - date: the date for when meal is served
    ///   - occation: the occation for when the meal is served
    ///   - foodType: the type of food served (`FoodType`)
    ///   - tags: tags further describing the meal.
    ///   - includeAnyTag: decides how to match tags, where `false` = (all tags must be present) or `true` = (any tag included)
    /// - Returns: new array containing the filtered [Meal]
    func filtered(by date:Date = Date(), occation:Meal.Occasion? = nil, foodType:Meal.FoodType? = nil, tags:Set<Meal.Tag> = [], includeAnyTag:Bool = false) -> [Meal] {
        return self.filter { meal in
            if Calendar.current.isDate(meal.date, inSameDayAs: date) == false { return false }
            if occation != nil && meal.occasion != occation { return false }
            if foodType != nil && meal.type != foodType { return false }
            if tags.isEmpty == false {
                if includeAnyTag {
                    if meal.tags.intersection(tags).isEmpty { return false }
                } else {
                    if  meal.tags.intersection(tags).count == tags.count { return false }
                }
            }
            return true
        }
    }
}

/// Meals provides a common interface for meal services implementing the `MealService` protocol.
public class Meals : ObservableObject {
    /// A subject that holds the most recently fetched meals from the provided meal service
    private let dataSubject = CurrentValueSubject<[Meal]?,Never>(nil)
    /// Pubisher storage
    private var publishers = Set<AnyCancellable>()
    /// Instance for managing automated fetches
    private let automatedFetcher:AutomatedFetcher<[Meal]?>
    
    /// Holds the last time the meals were fetched
    @Published public private(set) var lastFetch = Date()
    /// Turn preview data on or off. Use during development and especially in SwiftUI preview mode.
    @Published public private(set) var previewData:Bool = false
    /// Indicates whether or not a fetch is in progress.
    @Published public private(set) var fetching:Bool = false
    /// Indicates whether or not fetches should be managed automatically or manually
    @Published public var fetchAutomatically:Bool {
        didSet { automatedFetcher.isOn = fetchAutomatically }
    }
    /// Decides how often the automatic fetch should be triggered and if a non-forces fetch can be made.
    @Published public var fetchInterval:TimeInterval {
        didSet { automatedFetcher.timeInterval = fetchInterval }
    }
    
    /// A publisher holding the most recent fetched meals.
    public let latest:AnyPublisher<[Meal]?,Never>
    /// The currently used service
    public var service:MealService? {
        didSet {
            if fetchAutomatically {
                self.fetch()
            }
        }
    }
    
    /// Returns a `Meals` instance
    /// - Parameters:
    ///   - service: any service implementing the `MealService` protocol
    ///   - fetchAutomatically: decides whether or not fetches should be managed automatically or manually
    ///   - previewData: decides whether or not preview data is used (and the service ignored)
    public init(service:MealService?, fetchAutomatically:Bool = true, fetchInterval:TimeInterval = 60 * 60, previewData:Bool = false) {
        self.service = service
        self.fetchAutomatically = fetchAutomatically
        self.fetchInterval = fetchInterval
        self.previewData = previewData
        latest = dataSubject.eraseToAnyPublisher()
        automatedFetcher = AutomatedFetcher<[Meal]?>(dataSubject, isOn: fetchAutomatically, timeInterval: fetchInterval)
        automatedFetcher.triggered.sink { [weak self] in
            self?.fetch()
        }.store(in: &publishers)
        if fetchAutomatically {
            fetch()
        }
    }
    
    /// Crates a publisher that's filtering meals on a number of paramters
    /// - Parameters:
    ///   - date: when the meal is served
    ///   - occation: on which occation the meal is served
    ///   - foodType: the type of food (`FoodType`)
    ///   - tags: tags further describing the meal.
    /// - Returns: a non-failing [Meal]? publisher
    public func publisher(for date:Date? = nil, occation:Meal.Occasion? = nil, foodType:Meal.FoodType? = nil, tags:Set<Meal.Tag> = []) -> AnyPublisher<[Meal]?,Never> {
        dataSubject.map { meals in
            let date = date ?? Date()
            return meals?.filtered(by: date, occation: occation, foodType: foodType, tags: tags)
        }.eraseToAnyPublisher()
    }
    
    /// Triggers a fetch from the meal service.
    /// - Parameter force: force the method to fetch regardless of how recent it was fetched
    public func fetch(force:Bool = false) {
        if previewData {
            dataSubject.send(Self.previewData)
            return
        }
        if force == false && automatedFetcher.shouldFetch == false && dataSubject.value != nil {
            return
        }
        guard let service = service else { return}
        if fetching { return }
        
        var p:AnyCancellable?
        fetching = true
        p = service.fetchMealsPublisher().sink { [weak self] completion in
            switch completion {
            case .failure(let error): debugPrint(error)
            case .finished: break
            }
            self?.fetching = false
        } receiveValue: { [weak self] meals in
            self?.dataSubject.send(meals)
            self?.fetching = false
            self?.lastFetch = Date()
            if let p = p {
                self?.publishers.remove(p)
            }
        }
        if let p = p {
            publishers.insert(p)
        }
    }
    
    /// Data used in preview mode
    public static let previewData:[Meal] = [
        Meal(
            id: "test-preview-meal1",
            description: "Köttfärslimpa med rotmos",
            title: "Dagens lunch",
            date: Date(),
            occasion: .lunch,
            type: .meal
        ),
        Meal(
            id: "test-preview-meal2",
            description: "Blåbärsmuffins",
            title: "Dagens dessert",
            date: Date(),
            occasion: .lunch,
            type: .dessert
        )
    ]
    
    /// Instance of Meals used for preview purposes
    public static let previewInstance = Meals(service: nil, previewData: true)
}
