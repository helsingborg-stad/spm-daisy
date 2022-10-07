//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-10-01.
//

// https://opendata.smhi.se/apidocs/metobs/index.html
import Foundation
import Combine
import CoreLocation

let baseUrlString = "https://opendata-download-metobs.smhi.se/api/version/1.0"
let baseUrl = URL(string: baseUrlString)!

/// Errors for various failrues occuring though the SMHI Observations api
public enum SMHIObservationsErrors: Error {
    case unknown
    case missingResource
    case missingPeriod
    case missingPeriodData
    case missingStation
    case invalidNumberOfRowsInCSV
    case invalidStationDataInCSV
    case invalidPeriodDataInCSV
    case invalidParameterDataInCSV
    case invalidDateInCSV
}

/// Ussed for keeping track what of what field is being processed when decoding a CVS
enum CurrentlyProcessingCSVField {
    case station
    case parameter
    case period
    case data
}
/// Stores cancellables
var cancellables = Set<AnyCancellable>()

/// Calls upon the [SMHI Meterological Observaion API](https://opendata.smhi.se/apidocs/metobs/index.html)
public struct SMHIObservations {
    /// Describes a link to a resource
    public struct Link : Codable,Equatable {
        /// The relationship
        public let rel: String
        /// The resource value type, for example "application/json"
        public let type: String
        /// The resource URL
        public let href: URL
    }
    /// Describes a rsource in the METOBS api
    public struct Resource: Codable, Equatable {
        /// Describes a geographical bounding box
        public struct GeoBox: Codable, Equatable {
            /// Minimum latitude
            public let minLatitude:Double
            /// Minimum longitude
            public let minLongitude:Double
            /// Maximum latitude
            public let maxLatitude:Double
            /// Maximum longirude
            public let maxLongitude:Double
        }
        /// Geographical bounding box of the resrouce
        public let geoBox:GeoBox
        /// The key for the resource, typically an int
        public let key:String
        /// Last update
        public let updated:Date
        /// The name of the resource
        public let title:String
        /// Summary, or descripting of the values the resource holds
        public let summary:String
        /// Links to related assets
        public let link: [Link]
        /// Fetch-publisher of the first available json link
        public var jsonPublisher: AnyPublisher<Parameter,Error>  {
            guard let l = link.first(where: { $0.type == "application/json"}) else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return URLSession.shared.dataTaskPublisher(for: l.href)
                .tryMap {$0.data}
                .decode(type: Parameter.self, decoder: decoder)
                .eraseToAnyPublisher()
        }
    }
    /// The root of the api
    public struct Service : Codable, Equatable {
        /// The key or version used when fetching api values
        public let key:String
        /// Last updated
        public let updated:Date
        /// The title of the service
        public let title:String
        /// Further description of the service
        public let summary:String
        /// Links to related assets
        public let link: [Link]
        /// Service resources
        public let resource: [Resource]
        /// Fetch-publusher using the `baseUrlString` to call upon the api
        public static var jsonPublisher: AnyPublisher<Service,Error>  {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            guard let url = URL(string: "\(baseUrlString).json") else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            return URLSession.shared.dataTaskPublisher(for: url)
                .tryMap {$0.data}
                .decode(type: Service.self, decoder: decoder)
                .eraseToAnyPublisher()
        }
    }
    /// Describes a weather station
    public struct Station : Codable, Equatable {
        /// The name of the station
        public let name: String
        /// The station owner, for exampel "SMHI"
        public let owner: String
        /// The station owner category, for example "SMHI"
        public let ownerCategory: String
        /// The station id
        public let id: Int
        /// Height above sea level (probably meters?)
        public let height: Double
        /// The center latitude of the station
        public let latitude: Double
        /// The center longitude of the station
        public let longitude: Double
        /// Describes whether or not the station is active
        public let active: Bool
        /// Active from data
        public let from: Date
        /// Active to data
        public let to: Date
        /// The key for the station, typically a string representation of the id
        public let key: String
        /// Last updated
        public let updated: Date
        /// Usually the same as the resource title
        public let title: String
        /// A summary for the station
        public let summary: String
        /// Links to related assets
        public let link: [Link]
        /// Fetch-publisher of the first available json link.
        public var jsonPublisher: AnyPublisher<StationParameter,Error>  {
            guard let l = link.first(where: { $0.type == "application/json"}) else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return URLSession.shared.dataTaskPublisher(for: l.href)
                .tryMap {$0.data}
                .decode(type: StationParameter.self, decoder: decoder)
                .eraseToAnyPublisher()
        }
        /// `CLLocation` representation of the station coordinates
        public var location:CLLocation {
            return CLLocation(latitude: latitude, longitude: longitude)
        }
    }
    /// Describes a meterological parameter
    public struct Parameter : Codable, Equatable {
        /// The key for the parameter
        public let key:String
        /// Last updated
        public let updated:Date
        /// Title describing the parameter
        public let title:String
        /// Futher description of the parameter properties
        public let summary:String
        /// The type of expected value
        public let valueType:String
        /// Available stations
        public let station:[Station]
        /// Station sets
        public let stationSet:[StationSet]?
        /// Returns the closest station by geolocation
        /// - Parameters:
        ///   - latitude: desired latitude
        ///   - longitude: desired longitude
        /// - Returns: closest station provided location
        public func closestStationFor(latitude:Double, longitude:Double) -> Station? {
            let loc = CLLocation(latitude: latitude, longitude: longitude)
            return station.filter { $0.active == true }.min(by: { loc.distance(from: $0.location) < loc.distance(from: $1.location) })
        }
        /// Returns a fetch publisher for a paremter with key
        /// - Parameter key: the key of the parameter
        /// - Returns: network-publisher
        public func publisher(for key:String) -> AnyPublisher<Parameter,Error>  {
            let u = baseUrl.appendingPathComponent("parameter").appendingPathComponent("\(key).json")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return URLSession.shared.dataTaskPublisher(for: u)
                .tryMap {$0.data}
                .decode(type: Parameter.self, decoder: decoder)
                .eraseToAnyPublisher()
        }
    }
    /// Describes a set of stations with related data summary
    public struct StationSet:Codable,Equatable {
        /// The key for the station set
        public let key:String
        /// Last updated
        public let updated:Date
        /// The title of the station set
        public let title:String
        /// Further description of the station set
        public let summary:String
        /// Links to related assets
        public let link:[Link]
    }
    /// Describes the position of a station parameter
    public struct Position: Codable, Equatable {
        /// Data availabity start
        public let from:Date
        /// Data availabity end
        public let to:Date
        /// Height above sea level (meters?)
        public let height:Double
        /// The latitude of the station parameter
        public let latitude:Double
        /// The longitude of the station parameter
        public let longitude:Double
        /// `CLLocation` representation of the coordinates
        public var location:CLLocation {
            return CLLocation(latitude: latitude, longitude: longitude)
        }
    }
    /// Describes a period for data
    public struct Period: Codable, Equatable {
        /// The key for the period, used to fetch data from the api
        public let key:String
        /// Last updated
        public let updated:Date
        /// The title for the period
        public let title:String
        /// Further description of the period
        public let summary:String
        /// Links to related assets
        public let link:[Link]
        /// Fech-publisher for the first available json link
        public var jsonPublisher: AnyPublisher<PeriodDetails,Error>  {
            guard let l = link.first(where: { $0.type == "application/json"}) else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return URLSession.shared.dataTaskPublisher(for: l.href)
                .tryMap {$0.data}
                .decode(type: PeriodDetails.self, decoder: decoder)
                .eraseToAnyPublisher()
        }
    }
    /// Details about a period.
    public struct PeriodDetails: Codable, Equatable {
        /// The key of te period details
        public let key:String
        /// Last updated
        public let updated:Date
        /// The title of the period details
        public let title:String
        /// Further description of the period details
        public let summary:String
        /// First availble data
        public let from:Date
        /// Most recent availble data
        public let to:Date
        /// Links to related assets
        public let link:[Link]
        /// Fetch-publisher of the first available json link.
        public let data:[PeriodData]
    }
    /// Describes the link to the actual parameter data
    public struct PeriodData: Codable, Equatable {
        /// The key for the data
        public let key:String?
        /// Last updated
        public let updated:Date
        /// The title of the data
        public let title:String
        /// Further description of the data
        public let summary:String
        /// Links to related assets
        public let link: [Link]
        /// Fetch-publisher of the first available json link.
        public var jsonPublisher: AnyPublisher<Value,Error>  {
            guard let l = link.first(where: { $0.type == "application/json"}) else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return URLSession.shared.dataTaskPublisher(for: l.href)
                .map { $0.data }
                .decode(type: Value.self, decoder: decoder)
            
                .eraseToAnyPublisher()
        }
        /// Returns an appropriate fetch-publisher depending on avaiable link data, either JSON or CSV.
        public var fetchPublisher : AnyPublisher<Value,Error>  {
            if link.contains(where: { $0.type == "application/json"}) {
                return jsonPublisher
            }
            if link.contains(where: { $0.type == "text/plain"}) {
                return csvPublisher
            }
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        /// Fetch-publisher of the first available csv link.
        public var csvPublisher: AnyPublisher<Value,Error>  {
            guard let l = link.first(where: { $0.type == "text/plain"}) else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            return URLSession.shared.dataTaskPublisher(for: l.href)
                .map { $0.data }
                .tryMap({ d -> String in
                    guard let str = String(data: d, encoding: .utf8) else { throw URLError(.cannotDecodeContentData)}
                    return str
                })
                .tryMap({ string in
                    try SMHIObservations.process(csv: string,link:l)
                })
                .eraseToAnyPublisher()
        }
    }
    /// Describes a stations parameter
    public struct StationParameter: Codable, Equatable {
        /// The parameter key
        public let key:String
        /// Last updated
        public let updated:Date
        /// The title of the parameter
        public let title:String
        /// The owner of the station
        public let owner:String
        /// The owner category of the station
        public let ownerCategory:String
        /// Whether or not the parameter/station is active
        public let active:Bool
        /// Further description of the parameter/station
        public let summary:String
        /// Data availability start
        public let from:Date
        /// Data availability end
        public let to:Date
        /// The position of the parameter/station
        public let position:[Position]
        /// The available pariods for the parameter/station
        public let period:[Period]
        /// Links to related assets
        public let link:[Link]
    }
    /// The value form a stations parameter period
    public struct Value: Codable, Equatable {
        /// Meterological data
        public struct ValueData: Codable, Equatable {
            /// Date of data
            public let date:Date
            /// The actual value
            public let value:String
            /// The quality of the data, either G (green), Y (yellow), R (red)
            public let quality:String
        }
        /// The related parameter
        public struct ValueParameter: Codable, Equatable {
            /// The parameter key
            public let key:String
            /// The parameter name
            public let name:String
            /// Summary further descirbing the parameter
            public let summary:String
            /// Unit of measure
            public let unit:String
        }
        /// The related station
        public struct ValueStation: Codable, Equatable {
            /// The station key
            public let key:String
            /// The station name
            public let name:String
            /// The owner of the station
            public let owner:String
            /// The owner category of the station
            public let ownerCategory:String
            /// Height above sea level (probably meters?)
            public let height:Double
        }
        /// The realted period
        public struct ValuePeriod: Codable, Equatable {
            /// The period key
            public let key:String
            /// Period start
            public let from:Date
            /// Period end
            public let to:Date
            /// Further description of the period
            public let summary:String
            /// How often samples are taken, for example every 15 minutes
            public let sampling:String
        }
        /// The data
        public let value:[ValueData]
        /// Last updated
        public let updated:Date
        /// Related parameter
        public let parameter:ValueParameter
        /// Related station
        public let station:ValueStation
        /// Related period
        public let period:ValuePeriod
        /// Value positions
        public let position:[Position]
        /// Links to related assets
        public let link:[Link]
    }
    /// Processes a csv and returns a value object
    /// - Parameters:
    ///   - string: the csv string
    ///   - link: the originating link
    /// - Returns: processed value
    public static func process(csv string:String,link:Link) throws -> Value {
        var processing:CurrentlyProcessingCSVField?
        var final = [Value.ValueData]()
        let measurements = string.split(separator: "\n")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        var station:Value.ValueStation?
        var parameter:Value.ValueParameter?
        var period:Value.ValuePeriod?
        var position:Position?
        for row in measurements {
            if processing == nil && row.contains("Stationsnamn") {
                debugPrint(row)
                processing = .station
                continue
            } else if processing == .station && row.starts(with: "Parameternamn") {
                debugPrint(row)
                processing = .parameter
                continue
            } else if processing == .parameter && row.starts(with: "Tidsperiod") {
                debugPrint(row)
                processing = .period
                continue
            } else if processing == .period && row.starts(with: "Datum") {
                debugPrint(row)
                processing = .data
                continue
            }
            if processing == .station {
                let stationData = row.split(separator: ";")
                debugPrint(stationData)
                guard stationData.count >= 3, let height = Double(stationData[3]) else {
                    throw SMHIObservationsErrors.invalidStationDataInCSV
                }
                station = Value.ValueStation(key: String(stationData[1]), name: String(stationData[0]), owner: "", ownerCategory: "", height: height)
            } else if processing == .parameter {
                let parameterData = row.split(separator: ";")
                debugPrint(parameterData)
                guard parameterData.count >= 3 else { throw SMHIObservationsErrors.invalidParameterDataInCSV }
                parameter = Value.ValueParameter(key: "", name: String(parameterData[0]), summary: String(parameterData[1]), unit: String(parameterData[2]))
            } else if processing == .period {
                let periodData = row.split(separator: ";")
                debugPrint(periodData)
                guard periodData.count >= 5, let latitude = Double(periodData[3]), let longitude = Double(periodData[4]), let periodHeight = Double(periodData[2]) else {
                    continue
                }
                guard let from = df.date(from: String(periodData[0]+"Z")), let to = df.date(from: String(periodData[1])+"Z") else {
                    continue
                }
                period = Value.ValuePeriod(key: "", from: from, to: to, summary: "", sampling: "")
                position = Position(from: from, to: to, height: periodHeight, latitude: latitude, longitude: longitude)
            } else if processing == .data {
                let values = row.split(separator: ";")
                guard values.count >= 4 else {
                    debugPrint("invalid number of columns: \(values.count)")
                    continue
                }
                let dateString = "\(values[0]) \(values[1])Z"
                guard let date = df.date(from: dateString) else {
                    debugPrint("invalid date: \(dateString)")
                    continue
                }
                final.append(Value.ValueData(date: date, value: String(values[2]), quality:String(values[3])))
            }
        }
        guard let sta = station else {
            throw SMHIObservationsErrors.invalidStationDataInCSV
        }
        guard let par = parameter  else {
            throw SMHIObservationsErrors.invalidParameterDataInCSV
        }
        guard let per = period else {
            throw SMHIObservationsErrors.invalidPeriodDataInCSV
        }
        guard let pos = position else {
            throw SMHIObservationsErrors.invalidPeriodDataInCSV
        }
        return Value.init(value: final, updated: per.to, parameter: par, station: sta, period: per, position: [pos], link: [link])
    }
    // Holds the descriptions for meterological conditions
    public struct ConditionCodeDescription {
        /// Shared instance
        static let shared = ConditionCodeDescription()
        /// Dictionary of keys and values
        private let dict:[String:String]
        /// Subscript returning the description of a code/`key`
        static subscript(key: String) -> String? {
            get {
                shared.dict[key]
            }
        }
        /// Initializes the `dict`
        private init() {
            var dict = [String:String]()
            dict["0"] = "Molnens utveckling har icke kunnat observeras eller icke observerats"
            dict["1"] = "Moln har upplösts helt eller avtagit i utsträckning, i mäktighet eller i täthet"
            dict["2"] = "Molnhimlen i stort sett oförändrad"
            dict["3"] = "Moln har bildats eller tilltagit i utsträckning, i mäktighet eller i täthet"
            dict["4"] = "Sikten nedsatt av brandrök eller fabriksrök"
            dict["5"] = "Torrdis (solrök)"
            dict["6"] = "Stoft svävar i luften, men uppvirvlas ej av vinden vid observationsterminen ."
            dict["7"] = "Stoft eller sand uppvirvlas av vinden men ingen utpräglad sandvirvel och ingen sandstorm inom synhåll"
            dict["8"] = "Utpräglad stoft- eller sandvirvel vid obsterminen eller under senaste timmen meningen sandstorm"
            dict["9"] = "Sandstorm under senaste timmen eller inom synhåll vid obs-terminen"
            dict["10"] = "Fuktdis med sikt 1-10 km"
            dict["11"] = "Låg dimma i bankar på stationen, skiktets mäktighet överstiger ej 2 m på land eller 10 m till sjöss"
            dict["12"] = "Mer eller mindre sammanhängande låg dimma på stationen, skiktets mäktighet överstiger ej 2 m på land eller 10 m till sjöss"
            dict["13"] = "Kornblixt"
            dict["14"] = "Nederbörd inom synhåll, som ej når marken eller havsytan (fallstrimmor)"
            dict["15"] = "Nederbörd, som når marken eller havsytaninom synhåll på ett avstånd större än 5 km från stationen"
            dict["16"] = "Nederbörd, som når marken eller havsytan inom synhåll på ett avstånd mindre än 5 km, men ej på stationen"
            dict["17"] = "Åska vid observationsterminen men ingen nederbörd på stationen"
            dict["18"] = "Utpräglade starka vindbyar på stationen eller inom synhåll vid obs-terminen eller under senaste timmen"
            dict["19"] = "Skydrag eller tromb på stationen eller inom synhåll vid obs-terminen eller under senaste timmen"
            dict["20"] = "Duggregn eller kornsnö under senaste timmen men ej vid observationsterterminen"
            dict["21"] = "Regn under senaste timmen men ej vid observationsterterminen"
            dict["22"] = "Snöfall under senaste timmen men ej vid observationsterterminen"
            dict["23"] = "Snöblandat regn eller iskorn under senaste timmen men ej vid observationsterterminen"
            dict["24"] = "Underkylt regn eller duggregn under senaste timmen men ej vid observationsterterminen"
            dict["25"] = "Regnskura runder senaste timmen men ej vid observationsterterminen"
            dict["26"] = "Byar av snö eller snöblandat regn under senaste timmen men ej vid observationsterterminen"
            dict["27"] = "Byar av hagel med eller utan regn under senaste timmen men ej vid observationsterterminen"
            dict["28"] = "Dimma under senaste timmen men ej vid observationsterterminen"
            dict["29"] = "Åska (med eller utan nederbörd) under senaste timmen men ej vid observationsterterminen"
            dict["30"] = "Lätt eller måttlig sandstorm har avtagit istyrka under senaste timmen"
            dict["31"] = "Lätt eller måttlig sandstorm utan märkbar förändring under senaste timmen"
            dict["32"] = "Lätt eller måttlig sandstorm har börjat eller tilltagit i styrka under senaste timmen"
            dict["33"] = "Kraftig sandstorm har avtagit i styrka under senaste timmen"
            dict["34"] = "Kraftig sandstorm utan märkbar förändring under senaste timmen"
            dict["35"] = "Kraftig sandstorm har börjat eller tilltagit i styrka under senaste timmen"
            dict["36"] = "Lågt och lätt eller måttligt snödrev"
            dict["37"] = "Lågt men tätt snödrev"
            dict["38"] = "Högt men lätt eller måttligt snödrev"
            dict["39"] = "Högt och tätt snödrev"
            dict["40"] = "Dimma inom synhåll vid observationsterminen, nående över ögonhöjd (dock ej dimma på stationen under senaste timmen) (VV ?10)"
            dict["41"] = "Dimma i bankar på stationen (VV< 10)"
            dict["42"] = "Dimma, med skymt av himlen, har blivit lättare under senaste timmen"
            dict["43"] = "Dimma, utan skymt av himlen, har blivit lättare under senaste timmen"
            dict["44"] = "Dimma, med skymt av himlen, oförändrad under senaste timmen"
            dict["45"] = "Dimma, utan skymt av himlen, oförändrad under senaste timmen"
            dict["46"] = "Dimma, med skymt av himlen, har börjat eller tätnat under senaste timmen"
            dict["47"] = "Dimma, utan skymt av himlen, har börjat eller tätnat under senaste timmen"
            dict["48"] = "Underkyld dimma, med skymt av himlen"
            dict["49"] = "Underkyld dimma, utan skymt av himlen"
            dict["50"] = "Lätt duggregn med avbrott"
            dict["51"] = "Lätt duggregn, ihållande"
            dict["52"] = "Måttligt duggregn med avbrott"
            dict["53"] = "Måttligt duggregn, ihållande"
            dict["54"] = "Tätt duggregn med avbrott"
            dict["55"] = "Tätt duggregn, ihållande"
            dict["56"] = "Lätt underkylt duggregn"
            dict["57"] = "Måttligt eller tätt underkylt duggregn"
            dict["58"] = "Lätt duggregn tillsammans med regn"
            dict["59"] = "Måttligt eller tätt duggregn tillsammans med regn"
            dict["60"] = "Lätt regn med avbrott"
            dict["61"] = "Lätt regn, ihållande"
            dict["62"] = "Måttligt regn med avbrott"
            dict["63"] = "Måttligt regn, ihållande"
            dict["64"] = "Starkt regn med avbrott"
            dict["65"] = "Starkt regn ihållande"
            dict["66"] = "Lätt underkylt regn"
            dict["67"] = "Måttligt eller starkt underkylt regn"
            dict["68"] = "Lätt regn eller duggregn tillsammans med snö"
            dict["69"] = "Måttligt eller starkt regn eller duggregn tillsammans med snö"
            dict["70"] = "Lätt snöfall med avbrott"
            dict["71"] = "Lätt snöfall, ihållande"
            dict["72"] = "Måttligt snöfall med avbrott"
            dict["73"] = "Måttligt snöfall, ihållande"
            dict["74"] = "Tätt snöfall med avbrott"
            dict["75"] = "Tätt snöfall, ihållande"
            dict["76"] = "Isnålar (med el. utan dimma)"
            dict["77"] = "Kornsnö (med el. utan dimma)"
            dict["78"] = "Enstaka snöstjärnor (med el. utan dimma)"
            dict["79"] = "Iskorn"
            dict["80"] = "Lätta regnskurar"
            dict["81"] = "Måttliga eller kraftiga regnskurar"
            dict["82"] = "Mycket kraftiga regnskurar (skyfall)"
            dict["83"] = "Lätt snöblandat regn i byar"
            dict["84"] = "Måttligt eller kraftigt snöblandat regn i byar"
            dict["85"] = "Lätta snöbyar"
            dict["86"] = "Måttliga eller kraftiga snöbyar"
            dict["87"] = "Lätta byar av småhagel eller snöhagel (trindsnö) med eller utan regn eller snöblandat regn"
            dict["88"] = "Måttliga eller kraftiga byar av småhagel eller snöhagel (trindsnö) med eller utan regn eller snöblandat regn"
            dict["89"] = "Lätta byar av ishagel med eller utan regn eller snöblandat regn, utan åska"
            dict["90"] = "Måttliga eller kraftiga byar av ishagel med eller utan regn eller snöblandat regn, utan åska"
            dict["91"] = "Lätt regn vid observationsterminen, åskväder under senaste timmen men ej vid observationsterminen"
            dict["92"] = "Måttligt el. starkt regn vid observationsterminen, åskväder under senaste timmen men ej vid observationsterminen"
            dict["93"] = "Lätt snöfall, snöblandat regn eller hagel vid observationsterminen, åskväder under senaste timmen men ej vid observationsterminen"
            dict["94"] = "Måttligt el. starkt snöfall, snöblandat regn eller hagel vid observationsterminen, åskväder under senaste timmen men ej vid observationsterminen"
            dict["95"] = "Svagt eller måttligt åskväder vid observationsterminen utan hagel men med regn eller snö"
            dict["96"] = "Svagt eller måttligt åskväder vid observationsterminen med hagel"
            dict["97"] = "Kraftigt åskväder vid observationsterminen utan hagel men med regn eller snö"
            dict["98"] = "Kraftigt åskväder vid observationsterminen med sandstorm"
            dict["99"] = "Kraftigt åskväder vid observationsterminen med hagel"
            dict["100"] = "Inget signifikant väder observerat"
            dict["101"] = "Moln har upplösts helt eller avtagit i utsträckning, i mäktighet eller i täthet, under senste timmen"
            dict["102"] = "Molnhimlen i stort sett oförändrad under senste timmen"
            dict["103"] = "Moln har bildats eller tilltagit i utsträckning, i mäktighet eller i täthet, under senste timmen"
            dict["104"] = "Dis eller rök, eller stoft som är spritt i luften, sikt större eller lika med 1 km"
            dict["105"] = "Dis eller rök, eller stoft som är spritt i luften, sikt mindre än 1 km"
            dict["110"] = "Fuktdis med sikt 1-10 km"
            dict["111"] = "Isnålar"
            dict["112"] = "Blixt på avstånd"
            dict["118"] = "Utpräglade starka vindbyar"
            dict["120"] = "Dimma"
            dict["121"] = "Nederbörd"
            dict["122"] = "Duggregn eller kornsnö"
            dict["123"] = "Regn"
            dict["124"] = "Snöfall"
            dict["125"] = "Underkylt duggregn eller regn"
            dict["126"] = "Åskväder (med eller utan nederbörd)"
            dict["127"] = "Snödrev eller sandstorm"
            dict["128"] = "Snödrev eller sandstorm, sikt större eller lika med 1 km"
            dict["129"] = "Snödrev eller sandstorm, sikt mindre än 1 km"
            dict["130"] = "Dimma"
            dict["131"] = "Dimma i bankar på stationen"
            dict["132"] = "Dimma, har blivit lättare under senaste timmen"
            dict["133"] = "Dimma, oförändrad under senaste timmen"
            dict["134"] = "Dimma, har börjat eller tätnat under senaste timmen"
            dict["135"] = "Underkyld dimma"
            dict["140"] = "Nederbörd"
            dict["141"] = "Lätt eller måttlig nederbörd"
            dict["142"] = "Kraftig nederbörd"
            dict["143"] = "Flytande nederbörd, lätt eller måttlig"
            dict["144"] = "Flytande nederbörd, kraftig"
            dict["145"] = "Fast nederbörd, lätt eller måttlig"
            dict["146"] = "Fast nederbörd, kraftig"
            dict["147"] = "Lätt eller måttlig underkyld nederbörd"
            dict["148"] = "Kraftig underkyld nederbörd"
            dict["150"] = "Duggregn"
            dict["151"] = "Lätt duggregn"
            dict["152"] = "Måttligt duggregn"
            dict["153"] = "Tätt duggregn"
            dict["154"] = "Lätt underkylt duggregn"
            dict["155"] = "Måttligt underkylt duggregn"
            dict["156"] = "Tätt duggregn"
            dict["157"] = "Lätt duggregn tillsammans med regn"
            dict["158"] = "Måttligt eller tätt duggregn tillsammans med regn"
            dict["160"] = "Regn"
            dict["161"] = "Lätt regn"
            dict["162"] = "Måttligt regn"
            dict["163"] = "Starkt regn"
            dict["164"] = "Lätt underkylt regn"
            dict["165"] = "Måttligt underkylt regn"
            dict["166"] = "Starkt underkylt regn"
            dict["167"] = "Lätt regn eller duggregn tillsammans med snö"
            dict["168"] = "Måttligt eller starkt regn eller duggregn tillsammans med snö"
            dict["170"] = "Snöfall"
            dict["171"] = "Lätt snöfall"
            dict["172"] = "Måttligt snöfall"
            dict["173"] = "Tätt snöfall"
            dict["174"] = "Lätt småhagel"
            dict["175"] = "Måttligt småhagel"
            dict["176"] = "Kraftigt småhagel"
            dict["177"] = "Kornsnö"
            dict["178"] = "Isnålar"
            dict["180"] = "Regnskurar"
            dict["181"] = "Lätta regnskurar"
            dict["182"] = "Måttliga regnskurar"
            dict["183"] = "Kraftiga regnskurar"
            dict["184"] = "Mycket kraftiga regnskurar (skyfall)"
            dict["185"] = "Lätta snöbyar"
            dict["186"] = "Måttliga snöbyar"
            dict["187"] = "Kraftiga snöbyar"
            dict["189"] = "Hagel"
            dict["190"] = "Åskväder"
            dict["191"] = "Svagt eller måttligt åskväder utan nederbörd"
            dict["192"] = "Svagt eller måttligt åskväder med regnskurar eller snöbyar"
            dict["193"] = "Svagt eller måttligt åskväder med hagel"
            dict["194"] = "Kraftigt åskväder utan nederbörd"
            dict["195"] = "Kraftigt åskväder med regnskurar eller snöbyar"
            dict["196"] = "Kraftigt åskväder med hagel"
            dict["199"] = "Tromb eller Tornado"
            dict["204"] = "Vulkanaska som spridits högt upp i luften"
            dict["206"] = "Tjockt stoftdis, sikt mindre än 1 km"
            dict["207"] = "Vattenstänk vid station pga blåst"
            dict["208"] = "Drivande stoft (eller sand)"
            dict["209"] = "Kraftig stoft- eller sandstorm på avstånd (Haboob)"
            dict["210"] = "Snödis"
            dict["211"] = "Snöstorm eller kraftigt snödrev som ger extremt dålig sikt"
            dict["213"] = "Blixt mellan moln och marken"
            dict["217"] = "Åska utan regnskur"
            dict["219"] = "Tromb eller tornado (förödande) vid stationen eller inom synhåll under den senaste timmen"
            dict["220"] = "Avlagring av vulkanaska"
            dict["221"] = "Avlagring av stoft eller sand"
            dict["222"] = "Dagg"
            dict["223"] = "Utfällning av blöt snö"
            dict["224"] = "Lätt eller måttlig dimfrost"
            dict["225"] = "Kraftig dimfrost"
            dict["226"] = "Rimfrost"
            dict["227"] = "Kraftig isbeläggning pga underkyld nederbörd"
            dict["228"] = "Isskorpa"
            dict["230"] = "Stoft- eller sandstorm med temperatur under fryspunkten"
            dict["239"] = "Kraftigt snödrev och/eller snöfall"
            dict["241"] = "Dimma till havs"
            dict["242"] = "Dimma i dalgång"
            dict["243"] = "Sjörök i Arktis eller vid Antarktis"
            dict["244"] = "Advektionsdimma (över vatten)"
            dict["245"] = "Advektionsdimma (över land)"
            dict["246"] = "Dimma över is eller snö"
            dict["247"] = "Tät dimma, sikt 60-90 m"
            dict["248"] = "Tät dimma, sikt 30-60 m"
            dict["249"] = "Tät dimma, sikt mindre än 30 m"
            dict["250"] = "Duggregn, intensitet mindre än 0,10 mm/timme"
            dict["251"] = "Duggregn, intensitet 0,10-0,19 mm/timme"
            dict["252"] = "Duggregn, intensitet 0,20-0,39 mm/timme"
            dict["253"] = "Duggregn, intensitet 0,40-0,79 mm/timme"
            dict["254"] = "Duggregn, intensitet 0,80-1,59 mm/timme"
            dict["255"] = "Duggregn, intensitet 1,60-3,19 mm/timme"
            dict["256"] = "Duggregn, intensitet 3,20-6,39 mm/timme"
            dict["257"] = "Duggregn, intensitet större än 6,40 mm/timme"
            dict["259"] = "Duggregn och snöfall"
            dict["260"] = "Regn, intensitet mindre än 1,0 mm/timme"
            dict["261"] = "Regn, intensitet 1,0-1,9 mm/timme"
            dict["262"] = "Regn, intensitet 2,0-3,9 mm/timme"
            dict["263"] = "Regn, intensitet 4,0-7,9 mm/timme"
            dict["264"] = "Regn, intensitet 8,0-15,9 mm/timme"
            dict["265"] = "Regn, intensitet 16,0-31,9 mm/timme"
            dict["266"] = "Regn, intensitet 32,0-63,9 mm/timme"
            dict["267"] = "Regn, intensitet större än 64,0 mm/timme"
            dict["270"] = "Snö, intensitet mindre än 1,0 cm/timme"
            dict["271"] = "Snö, intensitet 1,0-1,9 cm/timme"
            dict["272"] = "Snö, intensitet 2,0-3,9 cm/timme"
            dict["273"] = "Snö, intensitet 4,0-7,9 cm/timme"
            dict["274"] = "Snö, intensitet 8,0-15,9 cm/timme"
            dict["275"] = "Snö, intensitet 16,0-31,9 cm/timme"
            dict["276"] = "Snö, intensitet 32,0-63,9 cm/timme"
            dict["277"] = "Snö, intensitet större än 64,0 cm/timme"
            dict["278"] = "Snöfall eller isnålar från en klar himmel"
            dict["279"] = "Frysande blötsnö"
            dict["280"] = "Regn"
            dict["281"] = "Underkylt regn"
            dict["282"] = "Snöblandat regn"
            dict["283"] = "Snöfall"
            dict["284"] = "Småhagel eller snöhagel"
            dict["285"] = "Småhagel eller snöhagel tillsammans med regn"
            dict["286"] = "Småhagel eller snöhagel tillsammans med snöblandat regn"
            dict["287"] = "Småhagel eller snöhagel tillsammans med snö"
            dict["288"] = "Hagel"
            dict["289"] = "Hagel tillsammans med regn"
            dict["290"] = "Hagel tillsammans med snöblandat regn"
            dict["291"] = "Hagel tillsammans med snö"
            dict["292"] = "Skurar eller åska till havs"
            dict["293"] = "Skurar eller åska över berg"
            dict["508"] = "Inga signifikanta fenomen att rapportera, rådande och gammalt väder utelämnas"
            dict["509"] = "Ingen observation, data ej tillgängligt, rådande och gammalt väder utelämnas"
            dict["510"] = "Rådande och gammalt väder saknas men förväntades."
            dict["511"] = "Saknat värde"
            self.dict = dict
        }
    }
    /// Returns a `Value` publisher for a specific station,parameter and period
    /// - Parameters:
    ///   - station: the selected station
    ///   - key: the selected parameter key
    ///   - period: the selected period
    /// - Returns: `Value` publisher
    public static func publisher(forStation station:String, parameter key:String, period:String)  -> AnyPublisher<Value,Error> {
        return Service.jsonPublisher
            .tryMap({ p -> Resource  in
                guard let r = p.resource.first(where: { $0.key == key }) else {
                    throw SMHIObservationsErrors.missingResource
                }
                return r
            })
            .flatMap { $0.jsonPublisher }
            .tryMap { p -> Station in
                guard let s = p.station.first(where: { $0.active == true && $0.name.lowercased().contains(station)}) else {
                    throw SMHIObservationsErrors.missingStation
                }
                return s
            }
            .flatMap { $0.jsonPublisher }
            .tryMap { pd -> Period in
                guard let v = pd.period.first(where: { $0.key == period }) else {
                    throw SMHIObservationsErrors.missingPeriod
                }
                return v
            }
            .flatMap { $0.jsonPublisher }
            .tryMap { d -> PeriodData in
                guard let f = d.data.first else {
                    throw SMHIObservationsErrors.missingPeriodData
                }
                return f
            }
            .flatMap { $0.fetchPublisher}
            .eraseToAnyPublisher()
    }
    /// Returns a `Value` publisher for the closes station to given location, a parameter and a period.
    /// - Parameters:
    ///   - latitude: the latitude of the desired position
    ///   - longitude: the longitude of the desired position
    ///   - key: the selected parameter key
    ///   - period: the selected period
    /// - Returns: `Value` publisher
    public static func publisher(latitude:Double, longitude:Double, parameter key:String, period:String) -> AnyPublisher<Value,Error> {
        return Service.jsonPublisher
            .tryMap({ p -> Resource  in
                guard let r = p.resource.first(where: { $0.key == key }) else {
                    throw SMHIObservationsErrors.missingResource
                }
                return r
            })
            .flatMap { $0.jsonPublisher }
            .tryMap { p -> Station in
                guard let s = p.closestStationFor(latitude: latitude, longitude: longitude) else {
                    throw SMHIObservationsErrors.missingStation
                }
                return s
            }
            .flatMap { $0.jsonPublisher }
            .tryMap { pd -> Period in
                guard let v = pd.period.first(where: { $0.key == period }) else {
                    throw SMHIObservationsErrors.missingPeriod
                }
                return v
            }
            .flatMap { $0.jsonPublisher }
            .tryMap { d -> PeriodData in
                guard let f = d.data.first else {
                    throw SMHIObservationsErrors.missingPeriodData
                }
                return f
            }
            .flatMap { $0.fetchPublisher}
            .eraseToAnyPublisher()
    }
    /// Returns the `Service.jsonPublisher`
    public static var publisher:AnyPublisher<Service,Error> {
        return Service.jsonPublisher
    }
}
