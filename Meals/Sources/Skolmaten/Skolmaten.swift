import Foundation
import Combine
import SwiftSoup

/// Protocol describing a navigation link between a child and a parent, from county to school
protocol SkolmatenNavigationLink {
    var url:URL { get }
    var parentURL:URL? { get }
    var title:String { get }
    init(url:URL, title:String, parentURL:URL?)
}

/// Extending `County` with the `SkolmatenNavigationLink` protocol
extension Skolmaten.County : SkolmatenNavigationLink { }

/// Extending `School` with the `SkolmatenNavigationLink` protocol
extension Skolmaten.School : SkolmatenNavigationLink { }

/// Extending `Municipality` with the `SkolmatenNavigationLink` protocol
extension Skolmaten.Municipality : SkolmatenNavigationLink { }

/// Used for fetching the `String` -representation of a web page
/// - Parameter url: the web page url
/// - Returns: a `String` publisher
func fetchStringPublisher(for url:URL) -> AnyPublisher<String,Error> {
    URLSession.shared.dataTaskPublisher(for: url)
        .tryMap { element -> String in
            guard let httpResponse = element.response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 400 else { throw URLError(.badServerResponse) }
            guard let res = String(data: element.data, encoding: .utf8) else { throw URLError(.cannotParseResponse) }
            return res
        }.eraseToAnyPublisher()
}

/// Used for crawling links from the Skolmaten.se website
/// - Parameter url: the web page URL
/// - Returns: an `[Item]`-publisher
func fetchLink<Item:SkolmatenNavigationLink>(url:URL) -> AnyPublisher<[Item],Error> {
    return fetchStringPublisher(for:url).tryMap { string in
        guard let baseURL = URL(string: "https://skolmaten.se") else {
            throw URLError(.badURL)
        }
        var result = [Item]()
        let els = try SwiftSoup.parse(string).select(".tiny ul.links ul a")
        for el in els {
            guard let title = try? el.text() else { continue }
            guard let urlString = try? el.attr("href") else { continue }
            guard !urlString.starts(with: "javascript") else { continue }
            guard !urlString.starts(with: "/information") else { continue }
            result.append(Item(url: baseURL.appendingPathComponent(urlString), title: title, parentURL: url))
        }
        return result
    }
    .receive(on: DispatchQueue.main).eraseToAnyPublisher()
}

/// Skolmaten is a library used for fetching meal information from Skolmaten.se.
public class Skolmaten {
    /// RSS filter
    public enum Filter : String {
        case days
    }
    
    /// Custom Skolmaten error
    public enum SkolmatenError : Error {
        /// No search result
        case searchResultsEmpty
        /// Insufficient input
        case insufficientInput
        /// Bad county name
        case badCounty
        /// Bad municipality name
        case badMunicipality
        /// Bad school name
        case badSchool
    }
    /// Represents a school and how to fetch meal information from the skolmaten.se rss feed.
    public struct School : Codable, Identifiable, Equatable, MealService {
        /// Identifying the school by it's url
        public var id:String { url.absoluteString }
        /// The title, or name of the school
        public let title:String
        /// The parent url, typically a `Municipality`
        public let parentURL:URL?
        /// The web url for the school
        public let url:URL
        
        /// Initializes a new school instance
        /// - Parameters:
        ///   - url: The web url for the school
        ///   - title: The school title or name
        ///   - parentURL: The parent url, typically a `Municipality`
        public init(url: URL, title: String, parentURL: URL?) {
            self.title = title
            self.url = url
            self.parentURL = parentURL
        }
        
        /// Used for fetching meals from Skolmaten.se. This function is used by `Meals`.
        /// - Returns: a `[Meal]` publisher
        public func fetchMealsPublisher() -> AnyPublisher<[Meal], Error> {
            fetchMealsPublisher(filter: .days,offset: -7, limit: 14)
        }
        
        /// A method for fetching meals from Skolmaten.se
        /// - Parameters:
        ///   - filter: can be used when filtering meals
        ///   - offset: offset in `filter`, a value of -1 where filter is `.days` fetches meals from yesterday.
        ///   - limit: the number of `filter` to return, a value of 2 where filter is `.days` fetches meals 2 days from offset.
        /// - Returns: a `[Meal]` publisher
        public func fetchMealsPublisher(filter:Filter = .days, offset:Int? = nil, limit:Int? = nil) -> AnyPublisher<[Meal],Error> {
            var baseURL = url
            baseURL.appendPathComponent("rss")
            baseURL.appendPathComponent(filter.rawValue)
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            components.queryItems = []
            if let offset = offset {
                components.queryItems?.append(URLQueryItem(name: "offset", value: "\(offset)"))
            }
            if let limit = limit {
                components.queryItems?.append(URLQueryItem(name: "limit", value: "\(limit)"))
            }
            guard let url = components.url else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            var request = URLRequest(url: url)
            request.addValue("application/rss+xml; charset=UTF-8", forHTTPHeaderField: "content-type")
            return fetchStringPublisher(for:url)
                .tryMap { string in
                    let formatter = DateFormatter()
                    formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss zzz" // Tue, 07 Jul 2020 00:00:00 GMT
                    formatter.locale = Locale(identifier: "en_US")
                    var result = [Meal]()
                    let els = try SwiftSoup.parse(string).getElementsByTag("item")
                    for el in els {
                        guard let dateString = try? el.getElementsByTag("pubDate").text(), let date = formatter.date(from: dateString) else {
                            continue
                        }
                        guard let description = try? el.getElementsByTag("description").text() else {
                            continue
                        }
                        let meals = description.components(separatedBy: "<br/>")
                        guard !meals.isEmpty else {
                            continue
                        }
                        meals.forEach { m in
                            result.append(Meal(description: m, date: date))
                        }
                    }
                    return result
                }
            .receive(on: DispatchQueue.main).eraseToAnyPublisher()
        }
    }
    
    /// A representation of a `Municipality` link at Skolmaten.se
    public struct Municipality : Identifiable,Equatable {
        /// Identifying the object by it's url
        public var id:String {
            url.absoluteString
        }
        /// The web url for the object
        public let url:URL
        /// The title or name of the `Municipality`
        public let title:String
        /// The parent url for the object, typically a `County`
        public let parentURL: URL?
        
        
        /// Initializes a new `Municipality`
        /// - Parameters:
        ///   - url: The web url for the `Municipality`
        ///   - title: The title or name of the `Municipality`
        ///   - parentURL: The parent url for the object, typically a `County`
        public init(url: URL, title: String, parentURL: URL?) {
            self.url = url
            self.title = title
            self.parentURL = parentURL
        }
        
        /// Used when fething schools locaed within the `Municipality`
        public var fetchSchoolsPublisher: AnyPublisher<[School],Error> {
            return fetchLink(url: url)
        }
    }
    
    /// A representation of a `County` link at Skolmaten.se
    public struct County : Identifiable,Equatable {
        /// Identifying the object by it's url
        public var id:String {
            url.absoluteString
        }
        /// The web url for the object
        public let url:URL
        /// The title or name of the `County`
        public let title:String
        /// The parent url for the object, should be typically https://skolmaten.se
        public let parentURL: URL?
        
        /// Initializes a new `County`
        /// - Parameters:
        ///   - url: The web url for the object
        ///   - title: The title or name of the `County`
        ///   - parentURL: The parent url for the object, typically https://skolmaten.se
        public init(url: URL, title: String, parentURL: URL?) {
            self.url = url
            self.title = title
            self.parentURL = parentURL
        }
        
        /// Used for fetching a list of `Municipality`
        public var fetchMunicipalitiesPublisher: AnyPublisher<[Municipality],Error> {
            return fetchLink(url: url)
        }
        /// Used for fetching a list of `County` from skolmaten.se
        static public var fetchCountiesPublisher: AnyPublisher<[County],Error> {
            guard let url = URL(string: "https://skolmaten.se") else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            return fetchLink(url: url)
        }
    }
    /// Used for fetching the first school by it's parameters
    /// - Parameters:
    ///   - county: first county by value
    ///   - municipality: first municipality by value
    ///   - school: first school by value
    /// - Returns: a `School`-publisher
    /// - Note: Use sparsely since each request makes a full crawl from skolmaten.se to the municipality website.
    public static func first(county:String, municipality:String, school:String) -> AnyPublisher<School,Error> {
        let county = county.lowercased()
        let municipality = municipality.lowercased()
        let school = school.lowercased()
        return County.fetchCountiesPublisher
            .tryMap({ counties -> Skolmaten.County in
                guard let m = counties.first(where: { $0.title.lowercased().contains(county) }) else {
                    throw SkolmatenError.badCounty
                }
                return m
            })
            .flatMap { $0.fetchMunicipalitiesPublisher }
            .tryMap({ municipalites -> Skolmaten.Municipality in
                guard let m = municipalites.first(where: { $0.title.lowercased().contains(municipality) }) else {
                    throw SkolmatenError.badMunicipality
                }
                return m
            })
            .flatMap { $0.fetchSchoolsPublisher }
            .tryMap({ schools -> Skolmaten.School in
                guard let m = schools.first(where: { $0.title.lowercased().contains(school) }) else {
                    throw SkolmatenError.badSchool
                }
                return m
            })
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Used for searching schools by it's parameters
    /// - Parameters:
    ///   - county: all counties containing value
    ///   - municipality: all municipalities containing value (in parenting counties)
    ///   - school: all schools containing value (in parenting municipalities)
    /// - Returns: returns a [School]-publisher
    /// - Note: Use sparsely since each request makes a full crawl from skolmaten.se to each municipality website.
    @available(iOS 14.0, *)
    @available(macOS 11.0, *)
    public static func filter(county:String, municipality:String, school:String) -> AnyPublisher<[School],Error> {
        guard county.count > 2 && municipality.count > 2 && municipality.count > 2 else {
            return Fail(error:SkolmatenError.insufficientInput).eraseToAnyPublisher()
        }
        return County.fetchCountiesPublisher
            .flatMap { $0.filter { $0.title.contains(county) }.publisher }
            .flatMap { $0.fetchMunicipalitiesPublisher }
            .flatMap { $0.filter { $0.title.contains(municipality) }.publisher }
            .flatMap { $0.fetchSchoolsPublisher }
            .map { $0.filter { $0.title.contains(school) } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()

    }
}
