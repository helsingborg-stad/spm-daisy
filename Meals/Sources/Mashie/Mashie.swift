import Foundation
import Combine
import SwiftSoup

/// MashieEaterie is a library for fetching meal information from the Mashie. The class implements `MealService` and can be used together with the `Meals` library.
/// - Note: This is a fraglile implementation. Hopefully it can be completely rewritten once Mashie decides to supply a service-API.
public struct MashieEaterie : MealService {
    /// MashieEaterie errors
    enum MashieEaterieError : Error {
        /// Download string decoding failure
        case dataFailure(URL)
    }
    
    /// Temporary object that decodes meal information
    struct Info: Codable {
        /// Meal score/rating
        let score:Double?
        /// Meal climate impact
        let kgCo2E:Double?
        /// Meal image
        let imageUrl:URL?
    }
    
    /// MashieEaterie parsing parameter, used when scraping the webiste for meal information
    public struct Parameter {
        /// Meal occatyion (not used for html comparison)
        public let occation:Meal.Occasion
        /// Type of food (not used for html comparison)
        public let foodType:Meal.FoodType
        /// Meal tags (not used for html comparison)
        public let tags:Set<Meal.Tag>
        /// Title of meal used to compare with html content
        public let title:String
        /// Misc meal information (not used for html comparison)
        public let info:[String]
        /// Initializes a new Parameter
        /// - Parameters:
        ///   - occation: Meal occatyion (not used for html comparison)
        ///   - foodType: Type of food (not used for html comparison)
        ///   - title: Meal tags (not used for html comparison)
        ///   - tags: Title of meal used to compare with html content
        ///   - info: Misc meal information (not used for html comparison)
        public init(occation:Meal.Occasion, foodType:Meal.FoodType = .undecided, title:String, tags:Set<Meal.Tag> = [],info:[String] = []) {
            self.occation = occation
            self.foodType = foodType
            self.tags = tags
            self.title = title
            self.info = info
        }
    }
    /// Parameters used when scraping the website
    public let parameters:[Parameter]
    /// Target url, exmaple https://mpi.mashie.com/public/menu/.....
    public let url:URL
    /// The organization id, can be found in the mpi url.
    public let orgId:String
    /// Wether or not to fetch rating, climate impact and meal image.
    public let fetchInfo:Bool
    /// Instantiates a new MashieEaterie object.
    /// - Parameters:
    ///   - url: Target url, exmaple https://mpi.mashie.com/public/menu/.....
    ///   - The organization id, can be found in the mpi url.
    ///   - parameters: Parameters used when scraping the website, see parameter documentation for more information
    ///   - fetchInfo: Wether or not to fetch rating, climate impact and meal image. This feature makes a separate request for each meal, exluede if you don't plan on using the information.
    public init(url:URL, orgId:String, parameters:[Parameter], fetchInfo:Bool = false) {
        self.url = url
        self.orgId = orgId
        self.parameters = parameters
        self.fetchInfo = true
    }
    /// Publisher that fetches meast using the given parameters
    /// - Returns: a fetch publiher
    public func fetchMealsPublisher() -> AnyPublisher<[Meal], Error> {
        let s = PassthroughSubject<[Meal],Error>()
        DispatchQueue.global().async {
            var arr = [Meal]()
            do {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let mashie = try Data(contentsOf: url)
                guard let mashieHTML = String(data: mashie, encoding: .utf8) else {
                    s.send(completion: .failure(MashieEaterieError.dataFailure(url)))
                    return
                }
                let doc = try SwiftSoup.parse(mashieHTML)
                let weeks = try doc.getElementsByClass("container-week")
                for week in weeks.prefix(1) {
                    let dayElements = try week.getElementsByClass("container-fluid no-print")
                    for dayElement in dayElements {
                        guard let dateString = try dayElement.getElementById("dayMenuDate")?.attr("js-date"), let date = formatter.date(from: dateString) else {
                            debugPrint("cannot format date for \(url.absoluteString)")
                            continue
                        }
                        let menuItems = try dayElement.getElementsByClass("day-alternative-wrapper")
                        for menuItem in menuItems {
                            
                            let id = try menuItem.getElementsByClass("modal").first()?.attr("id").replacingOccurrences(of: "modal-", with: "")
                            let container = try menuItem.getElementsByClass("day-alternative")
                            var info:Info? = nil
                            if fetchInfo, let id = id {
                                if let infoData = try? Data(contentsOf: URL(string:"https://mpi.mashie.com/public/internal/meals/\(id)/rating?orgId=\(orgId)")!) {
                                    info = try? JSONDecoder().decode(Info.self, from: infoData)
                                }
                            }
                            let foodItemTitle = try container.select("strong")
                            let foodItemContents = try foodItemTitle.select("span")
                            
                            let title = try foodItemTitle.html()
                            let removeFromTitle = try foodItemContents.outerHtml()
                            let cleanedTitle = title.replacingOccurrences(of: removeFromTitle, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            let foodItem = try foodItemContents.text()
                            
                            guard let p = parameters.first(where: { $0.title == cleanedTitle }) else {
                                continue
                            }
                            arr.append(
                                Meal(
                                    id:id,
                                    description: foodItem,
                                    title: p.title,
                                    date: date,
                                    occasion: p.occation,
                                    type: p.foodType,
                                    tags: p.tags,
                                    imageUrl:info?.imageUrl,
                                    carbonFootprint:info?.kgCo2E,
                                    rating:info?.score
                                )
                            )
                        }
                    }
                }
                s.send(arr)
            } catch {
                s.send(completion: .failure(error))
            }
        }
        return s.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
}
