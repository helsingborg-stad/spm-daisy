import Foundation
import Combine
import SwiftSoup
import AutomatedFetcher

/// Extension of the [Category:[Event]] dictionary
public extension Dictionary where Key == PublicCalendar.Category, Value == [PublicCalendar.Event] {
    /// Indicates whether or not the supplied date is on a holiday or not
    /// - Parameter date: any date, usually within in this year since the database only extends
    /// - Returns: is(true or is not(false) a holiday
    func isHoliday(date:Date) -> Bool {
        self[.holidays]?.contains { event in Calendar.current.isDate(event.date, inSameDayAs: date) } == true
    }
    /// Filters out all events on a specific date for a specific cateogiry or categories
    /// - Parameters:
    ///   - date: the date to filter on
    ///   - categories: the categories to filter on
    /// - Returns: an array of filtered events
    func events(on date:Date = Date(), in categories:[PublicCalendar.Category] = PublicCalendar.Category.allCases) -> [PublicCalendar.Event] {
        var events = [PublicCalendar.Event]()
        for f in categories {
            events.append(contentsOf: self[f]?.filter { Calendar.current.isDate($0.date, inSameDayAs: date) } ?? [])
        }
        return events.sorted { $0.date < $1.date }
    }
    
    /// Filters out all events in the specified categories
    /// - Parameters:
    ///   - categories: the categories to filter on
    /// - Returns: an array of filtered events
    func events(in categories:[PublicCalendar.Category] = PublicCalendar.Category.allCases) -> [PublicCalendar.Event] {
        var events = [PublicCalendar.Event]()
        for f in categories {
            events.append(contentsOf: self[f] ?? [])
        }
        return events.sorted { $0.date < $1.date }
    }
    /// Creates cache file url
    /// - Parameter name: the name of the file
    /// - Returns: a url
    static func fileUrl(with name:String) throws -> URL {
        let documentDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
        return documentDirectory.appendingPathComponent(name)
    }
    /// Writes the dicitonary to file
    /// - Parameter filename: a filename
    func write(to filename:String) {
        let enc = JSONEncoder()
        do {
            let data = try enc.encode(self)
            try data.write(to: Self.fileUrl(with: filename))
        } catch {
            debugPrint(error)
        }
    }
    /// Read dictionary data from file to memory
    /// - Parameter filename: a filename
    /// - Returns: the dictionary
    static func read(from filename:String) -> Self? {
        do {
            let data = try Data(contentsOf: fileUrl(with: filename))
            let res = try JSONDecoder().decode(Self.self, from: data)
            return res.isEmpty ? nil : res
        } catch {
            debugPrint(error)
        }
        return nil
    }
    /// Deletes the dictionary from disk
    /// - Parameter filename: a filename
    static func delete(filename:String) {
        do {
            try FileManager.default.removeItem(at: Self.fileUrl(with: filename))
        } catch {
            debugPrint(error)
        }
    }
}

/// Object that downloads and stores information about Swedish holidays from kalender.se
public class PublicCalendar : ObservableObject {
    /// Used for cache settings
    public struct CacheSettings {
        /// Key used when storing the last fetch date in UserDefaults
        public let lastFetchKey:String
        /// File name used to store cache
        public let cacheFilename:String
        
        /// Initializes a new CacheSettings object
        /// - Parameters:
        ///   - lastFetchKey: Key used when storing the last fetch date in UserDefaults. Default value is `PublicCalendarLastFetch`
        ///   - cacheFilename: File name used to store cache, defalt value is `PublicCalendar`
        public init(lastFetchKey:String = "PublicCalendarLastFetch",cacheFilename:String = "PublicCalendar") {
            self.lastFetchKey = lastFetchKey
            self.cacheFilename = cacheFilename
        }
        /// Default values
        public static let `default` = CacheSettings()
    }
    /// Private typealias for the value subject
    private typealias DBSubscriber = CurrentValueSubject<DB?,Never>
    /// The calendar value publsiher type
    public typealias DBPublisher = AnyPublisher<DB?,Never>
    /// The calendar value type
    public typealias DB = [Category:[Event]]
    /// Public calendar errors
    public enum PublicCalendarError : Error {
        case instanceDead
    }
    /// A calendar event
    public struct Event: Codable, Hashable, Equatable, Identifiable {
        /// A generated id of the event.
        public var id:String {
            return category.rawValue + "-" + title + "-" + date.description
        }
        /// The title of the event
        public var title:String
        /// The event date and time
        public var date:Date
        /// The event category
        public var category:Category
        /// Initializes a new Event object
        /// - Parameters:
        ///   - title: The title of the event
        ///   - date: The date and time of the event
        ///   - category: The event category
        public init(title:String,date:Date,category:Category) {
            self.title = title
            self.date = date
            self.category = category
        }
    }

    /// Event category descriptions
    public enum Category : String, CaseIterable, Codable, Equatable {
        /// Holidays
        case holidays
        /// Flag days
        case flagdays
        /// UN as in United Nations
        case undays
        /// Nights or "aftnar"
        case nights
        /// Theme days
        case themedays
        /// Information days
        case informationdays
        /// The url of the cateogry, add /[YEAR] to get a specific year
        var url:URL {
            switch self {
            case .holidays: return URL(string:"https://www.kalender.se/helgdagar")!
            case .flagdays: return URL(string:"https://www.kalender.se/flaggdagar")!
            case .undays: return URL(string:"https://www.kalender.se/fn-dagar")!
            case .nights: return URL(string:"https://www.kalender.se/aftnar")!
            case .themedays: return URL(string:"https://www.kalender.se/temadagar")!
            case .informationdays: return URL(string:"https://www.kalender.se/samhallsinformation")!
            }
        }
    }
    
    /// Which years to fetch. Don't add too many since each year crawles the kalender.se website.
    public var years = [Int]() {
        didSet {
            if fetchAutomatically && years != oldValue {
                fetch(force: true)
            }
        }
    }
    
    /// Instance cancellables
    private var cancellables = Set<AnyCancellable>()
    /// The latest value subject
    private let latestSubject:DBSubscriber
    /// The instance automated fetcher
    private let automatedFetcher:AutomatedFetcher<DB?>
    /// Indicates whether or not to use preview data
    private let previewData:Bool
    /// The instance cache settings
    private let cacheSettings:CacheSettings
    /// The current fetch subject, used by the fetch-function
    private var currentFetchSubject = PassthroughSubject<DB?,Error>()
    /// The lastest values publisher
    /// - Note: It's a CurrentValuePublisher so it will always yield a result. If no fetch has been performed and you subscribe before a fetch has been completed, you will get a nil result. You can use the fetch() method in case you want to wait for the most current result.
    public let latest:DBPublisher
    
    @Published public var fetchAutomatically = true {
        didSet { automatedFetcher.isOn = fetchAutomatically }
    }
    /// Initlialize new PublicCalendar object
    /// - Parameters:
    ///   - years: the years to fetch
    ///   - cacheSettings: the cache settings, default is `CacheSettings.default`
    ///   - fetchAutomatically: indicates whether or not the automated fetcher should be activated
    ///   - previewData: indicates whether or not the instance should be used for preview purposes.
    public init(years:[Int]? = nil, cacheSettings:CacheSettings = .default, fetchAutomatically:Bool = false, previewData:Bool = false) {
        let db = DB.read(from: cacheSettings.cacheFilename)
        if let y = years {
            self.years = y
        } else {
            let now = Calendar.current.component(.year, from: Date())
            self.years = [now - 1, now, now + 1]
        }
        self.cacheSettings = cacheSettings
        latestSubject = .init(db)
        latest = latestSubject.eraseToAnyPublisher()
        let date = UserDefaults.standard.object(forKey: cacheSettings.lastFetchKey) as? Date
        automatedFetcher = AutomatedFetcher<DB?>(latestSubject, lastFetch:date, isOn: fetchAutomatically, timeInterval: 60*60*24)
        self.previewData = previewData
        self.fetchAutomatically = true
        self.automatedFetcher.triggered.sink { [weak self] in
            self?.fetch()
        }.store(in: &cancellables)
        if fetchAutomatically {
            fetch()
        } else if db != nil {
            latestSubject.send(db)
        }
    }
    /// Subscribe to updates. The publisher subscribes to the `latest` paramter.
    /// - Parameters:
    ///   - categories: category filter
    ///   - date: date filter
    /// - Returns: [Event] publisher
    /// - Note: If the database is uninitiated and you subscribe before the fetch has completed, you will get an nil result. You can use the fetch() method in case you want to wait for the most current result.
    public func publisher(for categories:[Category] = Category.allCases, on date:Date = Date()) -> AnyPublisher<[Event]?,Never> {
        return latest.map { db in
            return db?.events(on: date, in: categories)
        }.eraseToAnyPublisher()
    }
    /// Fetches data from the kalender.se web site. If there is a fetch in progress the method will not cancel the current fetch.
    /// - Parameter force: force fetch regardless of automation parameters
    /// - Returns: a result publisher triggering once only
    @discardableResult public func fetch(force:Bool = false) -> AnyPublisher<DB?,Error>  {
        if previewData {
            latestSubject.send(Self.previewData)
            return CurrentValueSubject<DB?,Error>(Self.previewData).eraseToAnyPublisher()
        }
        if force == false && automatedFetcher.shouldFetch == false && latestSubject.value == nil {
            return CurrentValueSubject<DB?,Error>(self.latestSubject.value).eraseToAnyPublisher()
        }
        if automatedFetcher.fetching {
            return currentFetchSubject.eraseToAnyPublisher()
        }
        self.currentFetchSubject = PassthroughSubject<DB?,Error>()
        var p:AnyCancellable? = nil
        automatedFetcher.started()
        p = getContent().receive(on: DispatchQueue.main).sink { [weak self] completion in
            if case .failure(let error) = completion {
                self?.currentFetchSubject.send(completion: .failure(error))
            }
            self?.automatedFetcher.failed()
            if let p = p {
                self?.cancellables.remove(p)
            }
        } receiveValue: { [weak self] db in
            if let p = p {
                self?.cancellables.remove(p)
            }
            self?.latestSubject.send(db)
            self?.currentFetchSubject.send(db)
            self?.automatedFetcher.completed()
        }
        if let p = p {
            cancellables.insert(p)
        }
        return currentFetchSubject.eraseToAnyPublisher()
    }
    /// Removes the database from disk and removes the latest fetch date from the UserDefaults
    public func purge() {
        DB.delete(filename: cacheSettings.cacheFilename)
        UserDefaults.standard.removeObject(forKey: cacheSettings.lastFetchKey)
        self.latestSubject.send([:])
    }
    /// Get content from the kalender.se website
    /// - Returns: completion publisher
    private func getContent() -> AnyPublisher<DB,Error> {
        let years = self.years
        let cacheSettings = cacheSettings
        func crawlContent(for category:Category, year:Int) throws -> [Event]{
            var arr = [Event]()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let holidays = try Data(contentsOf: category.url.appendingPathComponent("\(year)"))
            guard let holidayHTML = String(data: holidays, encoding: .utf8) else {
                debugPrint("cannot decode string for \(category.url.absoluteString)")
                return arr
            }
            let els = try SwiftSoup.parse(holidayHTML).select(".table").select("tr")
            for (index, element) in els.array().enumerated() {
                if index == 0 {
                    continue
                }
                let tds = try element.select("td")
                let day = try tds[0].text()
                let title = try tds[1].select("a").text()
                guard let date = formatter.date(from: day) else {
                    debugPrint("cannot format date for \(category.url.absoluteString) from \"\(day)\"")
                    continue
                }
                let calDay = Event(title: title, date: date, category: category)
                arr.append(calDay)
            }
            return arr.sorted { $0.date < $1.date }
        }
        let subject = PassthroughSubject<DB,Error>()
        DispatchQueue.global().async {
            var res = DB()
            for y in years {
                for c in Category.allCases {
                    do {
                        res[c] = try crawlContent(for: c,year:y)
                    } catch {
                        debugPrint(error)
                    }
                }
            }
            res.write(to: cacheSettings.cacheFilename)
            UserDefaults.standard.setValue(Date(), forKey: cacheSettings.lastFetchKey)
            subject.send(res)
        }
        return subject.eraseToAnyPublisher()
    }
    /// Preview data
    public static let previewData: DB = [
        .holidays: [.init(title: "Preview event", date: Date(), category: .holidays)]
    ]
    /// Instance used for preview scenarios
    public static let previewInstance = PublicCalendar(previewData: true)
}
