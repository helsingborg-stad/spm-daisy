import Combine
import Foundation
import CoreLocation
import AutomatedFetcher

/// Weather service protocol. Used by service providers to comply with the Weather service requirements
public protocol WeatherService {
    func fetch(using coordinates:Weather.Coordinates) -> AnyPublisher<[WeatherData],Error>
}
/// Weather privides a common interface that supplies weather data form any service implementing the `WeatherService` protocol.
public class Weather : ObservableObject {
    /// Coordinate object used when fetching data
    public struct Coordinates: Codable, Equatable, Hashable {
        /// Coordinate latitude
        public let latitude:Double
        /// Coordinate longitude
        public let longitude:Double
        /// Initializes a new coordinate object
        /// - Parameters:
        ///   - latitude: Coordinate latitude
        ///   - longitude: Coordinate longitude
        public init(latitude:Double, longitude:Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }
    /// Automated fetcher instance
    private var automatedFetcher:AutomatedFetcher<[WeatherData]?>
    /// Data subject
    private var dataSubject = CurrentValueSubject<[WeatherData]?,Never>(nil)
    /// Latest data publisher.
    public let latest:AnyPublisher<[WeatherData]?,Never>
    /// Current service. New values triggers a fetch if fetchAutomatically is active
    public var service:WeatherService? {
        didSet {
            if service == nil {
                return
            }
            if fetchAutomatically {
                fetch(force:true)
            }
        }
    }
    /// Cancellable storage
    private var publishers = Set<AnyCancellable>()
    /// Current coordinates. New values triggers a fetch if fetchAutomatically is active
    public var coordinates:Coordinates? {
        didSet {
            if oldValue != coordinates {
                if fetchAutomatically {
                    fetch(force:true)
                }
            }
        }
    }
    /// Indicates whether or not the automatic fetch is active
    @Published public var fetchAutomatically:Bool {
        didSet { automatedFetcher.isOn = fetchAutomatically }
    }
    /// Indicates whether or not preview data is being used
    @Published public private(set) var previewData:Bool = false
    /// Instantiates a new weather object
    /// - Parameters:
    ///   - service: weather service to use
    ///   - coordinates: coordinates to use when fetching data
    ///   - fetchAutomatically: Indicates whether or not the automatic fetch is active
    ///   - previewData: Indicates whether or not preview data is being used
    public init(service:WeatherService?, coordinates:Coordinates? = nil, fetchAutomatically:Bool = true, previewData:Bool = false) {
        self.previewData = previewData
        self.fetchAutomatically = fetchAutomatically
        self.coordinates = coordinates
        self.latest = dataSubject.eraseToAnyPublisher()
        self.service = service
        self.automatedFetcher = AutomatedFetcher<[WeatherData]?>(dataSubject, isOn: fetchAutomatically)
        automatedFetcher.triggered.sink { [weak self] in
            self?.fetch()
        }.store(in: &publishers)
        if fetchAutomatically {
            fetch()
        }
    }
    /// Fetch data from service
    /// - Parameter force: force overrides the automatic fetcher and retrieves data regarldess.
    /// - Note: Will not fetch if missing coordinates or service
    public func fetch(force:Bool = false) {
        if previewData {
            dataSubject.send(Self.previewData)
            return
        }
        if force == false && automatedFetcher.shouldFetch == false && dataSubject.value == nil {
            return
        }
        guard let coordinates = coordinates else {
            return
        }
        guard let service = service else {
            return
        }
        automatedFetcher.started()
        var p:AnyCancellable?
        p = service.fetch(using: coordinates).receive(on: DispatchQueue.main).sink { [weak self] completion in
            if case .failure(let error) = completion {
                debugPrint(error)
            }
            self?.automatedFetcher.failed()
        } receiveValue: { [weak self] data in
            self?.dataSubject.send(data.sorted(by: { $0.dateTimeRepresentation < $1.dateTimeRepresentation }))
            self?.automatedFetcher.completed()
            if let p = p {
                self?.publishers.remove(p)
            }
        }
        if let p = p {
            publishers.insert(p)
        }
    }
    /// Weather data closest in time relative to the data parameter. This publisher will trigger again when recieveing new values underlying data (i.e `latest` publisher)
    /// - Parameter date: the date to be used for comparison
    /// - Returns: a value publisher, will result a nil value if no weather data has been retrieved.
    public func closest(to date:Date? = nil) -> AnyPublisher<WeatherData?,Never> {
        return dataSubject.map { data in
            let date = date ?? Date()
            return data?.sorted { w1, w2 in
                abs(w1.dateTimeRepresentation.timeIntervalSince(date)) < abs(w2.dateTimeRepresentation.timeIntervalSince(date))
            }.first
        }.eraseToAnyPublisher()
    }
    
    /// All weather data between the two dates. This publisher will trigger again when recieveing new values underlying data (i.e `latest` publisher)
    /// - Parameters:
    ///   - from: from data
    ///   - to: to date
    /// - Returns: a value publisher, will result in a nil value if no weather data has been retrieved.
    public func betweenDates(from: Date, to:Date) -> AnyPublisher<[WeatherData]?,Never> {
        return dataSubject.map { data in
            return data?.filter { $0.dateTimeRepresentation >= from && $0.dateTimeRepresentation <= to }
        }.eraseToAnyPublisher()
    }
    /// Data used for preview scenarios
    public static let previewData: [WeatherData] = [
        .init(dateTimeRepresentation: Date().addingTimeInterval(60),
              airPressure: 1018,
              airTemperature: 20.1,
              airTemperatureFeelsLike: 24,
              horizontalVisibility: 49.2,
              windDirection: 173,
              windSpeed: 5.7,
              windGustSpeed: 9.2,
              relativeHumidity: 71,
              thunderProbability: 1,
              totalCloudCover: 6,
              lowLevelCloudCover: 2,
              mediumLevelCloudCover: 0,
              highLevelCloudCover: 5,
              minPrecipitation: 0,
              maxPrecipitation: 0,
              frozenPrecipitationPercentage: 0,
              meanPrecipitationIntensity: 0,
              medianPrecipitationIntensity: 0,
              precipitationCategory: .none,
              symbol: .variableCloudiness,
              latitude: 56.0014127,
              longitude: 12.7416203)
    ]
    /// Instance used for preview scenarios
    public static let previewInstance:Weather = Weather(service: nil, previewData: true)
    
    /// Get the heat index adusted temperature
    /// - Parameters:
    ///   - t: temperature
    ///   - r: humidity
    /// - Returns: heat index adjusted temperature
    public static func heatIndexAdjustedTemperature(temperature t:Double, humidity r:Double) -> Double {
        /// https://en.wikipedia.org/wiki/Heat_index
        if t < 27 || r < 40 {
            return t
        }
        let c1:Double = -8.78469475556
        let c2:Double = 1.61139411
        let c3:Double = 2.33854883889
        let c4:Double = -0.14611605
        let c5:Double = -0.012308094
        let c6:Double = -0.0164248277778
        let c7:Double = 0.002211732
        let c8:Double = 0.00072546
        let c9:Double = -0.000003582
        return c1 + (c2 * t) + (c3 * r) + (c4 * t * r + c5 * pow(t,2)) + (c6 * pow(r,2)) + (c7 * pow(t,2) * r) + (c8 * t * pow(r,2)) + (c9 * pow(t,2) * pow(r,2))
    }

    /// Get the effective temperature, ie windchill temperature
    /// - Parameters:
    ///   - t: temperature in celcius
    ///   - v: wind speed in meters per second
    /// - Returns: wind chill temperature
    /// - Note
    /// Information found at https://www.smhi.se/kunskapsbanken/meteorologi/vindens-kyleffekt-1.259
    public static func windChillAdjustedTemperature(temperature t:Double, wind v:Double) -> Double {
        if t > 10 || t < -40 || v < 2 || v > 35{
            return t
        }
        return 13.12 + 0.6215 * t - 13.956 * pow(v, 0.16) + 0.48669 * t * pow(v, 0.16)
    }


    /// Calculates the dew point
    /// - Parameters:
    ///   - humidity: relative humidity (1 to 100)
    ///   - temperature: temperature in celcius
    /// - Returns: the dew point adjusted temperature
    /// - Note:
    /// Information found at https://github.com/malexer/meteocalc/blob/master/meteocalc/dewpoint.py
    public static func dewPointAdjustedTemperature(humidity:Double, temperature:Double) -> Double {
        let bpos = 17.368
        let cpos = 238.88
        let bneg = 17.966
        let cneg = 247.15

        let b = temperature > 0 ? bpos : bneg
        let c = temperature > 0 ? cpos : cneg

        let pa = humidity / 100 * pow(M_E, b * temperature / (c + temperature))

        return c * log(pa) / (b - log(pa))
    }

    //public func calculateDewPointAlternate1(humidity:Double,temperature:Double) -> Double {
    //    /// https://stackoverflow.com/questions/27288021/formula-to-calculate-dew-point-from-temperature-and-humidity
    //    return (temperature - (14.55 + 0.114 * temperature) * (1 - (0.01 * humidity)) - pow(((2.5 + 0.007 * temperature) * (1 - (0.01 * humidity))),3) - (15.9 + 0.117 * temperature) * pow((1 - (0.01 * humidity)), 14))
    //}
    //
    //public func calculateDewPointAlternate2(humidity:Double,temperature:Double) -> Double {
    //    /// https://gist.github.com/sourceperl/45587ea99ff123745428
    //    let A = 17.27
    //    let B = 237.7
    //    let alpha = ((A * temperature) / (B + temperature)) + log(humidity/100.0)
    //    return (B * alpha) / (A - alpha)
    //}

}

