//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-08-10.
//

import Foundation

/// Describes symbols related to a specific weather condition.
public enum WeatherSymbol : String, Equatable {
    case clearSky
    case nearlyClearSky
    case variableCloudiness
    case halfclearSky
    case cloudySky
    case overcast
    case fog
    case lightRainShowers
    case moderateRainShowers
    case heavyRainShowers
    case thunderstorm
    case lightSleetShowers
    case moderateSleetShowers
    case heavySleetShowers
    case lightSnowShowers
    case moderateSnowShowers
    case heavySnowShowers
    case lightRain
    case moderateRain
    case heavyRain
    case thunder
    case lightSleet
    case moderateSleet
    case heavySleet
    case lightSnowfall
    case moderateSnowfall
    case heavySnowfall
    /// Emoji representation of the value
    public var emoji:String {
        switch self {
        case .clearSky: return "☀️"
        case .nearlyClearSky: return "🌤"
        case .variableCloudiness: return "⛅️"
        case .halfclearSky: return "⛅️"
        case .cloudySky: return "🌥"
        case .overcast: return "☁️"
        case .fog: return "🌫"
        case .lightRainShowers: return "🌧"
        case .moderateRainShowers: return "🌧"
        case .heavyRainShowers: return "💧"
        case .thunderstorm: return "⛈"
        case .lightSleetShowers: return "🌨"
        case .moderateSleetShowers: return "🌨"
        case .heavySleetShowers: return "💧"
        case .lightSnowShowers: return "🌧"
        case .moderateSnowShowers: return "🌧"
        case .heavySnowShowers: return "🌧"
        case .lightRain: return "🌧"
        case .moderateRain: return "🌧"
        case .heavyRain: return "🌧"
        case .thunder: return "⚡️"
        case .lightSleet: return "🌨"
        case .moderateSleet: return "🌨"
        case .heavySleet: return "🌨"
        case .lightSnowfall: return "🌨"
        case .moderateSnowfall: return "🌨"
        case .heavySnowfall: return "❄️"
        }
    }
    /// SFSymbol representation of the value
    public var sfSymbol:String {
        switch self {
        case .clearSky: return "sub.max.fill"
        case .nearlyClearSky: return "cloud.sun.fill"
        case .variableCloudiness: return "cloud.sun.fill"
        case .halfclearSky: return "cloud.sun.fill"
        case .cloudySky: return "cloud.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .lightRainShowers: return "cloud.drizzle.fill"
        case .moderateRainShowers: return "cloud.rain.fill"
        case .heavyRainShowers: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.fill"
        case .lightSleetShowers: return "cloud.sleet.fill"
        case .moderateSleetShowers: return "cloud.sleet.fill"
        case .heavySleetShowers: return "cloud.sleet.fill"
        case .lightSnowShowers: return "cloud.snow.fill"
        case .moderateSnowShowers: return "cloud.snow.fill"
        case .heavySnowShowers: return "cloud.snow.fill"
        case .lightRain: return "cloud.rain.fill"
        case .moderateRain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunder: return "cloud.sun.bolt.fill"
        case .lightSleet: return "cloud.sleet.fill"
        case .moderateSleet: return "cloud.sleet.fill"
        case .heavySleet: return "cloud.sleet.fill"
        case .lightSnowfall: return "cloud.snow.fill"
        case .moderateSnowfall: return "cloud.snow.fill"
        case .heavySnowfall: return "snow"
        }
    }
}
/// Descibes a type of precipitation
public enum WeatherPrecipitation : String, Equatable {
    case none
    case snow
    case snowAndRain
    case rain
    case drizzle
    case freezingRain
    case freezingDrizzle
    /// Emoji representing the type of precipitation
    public var emoji:String {
        switch self {
        case .none: return ""
        case .snow: return "❄️"
        case .snowAndRain: return "❄️"
        case .rain: return "💧"
        case .drizzle: return "💧"
        case .freezingRain: return "💧"
        case .freezingDrizzle: return "💧"
        }
    }
}
/// Data attatched to a specific point in time.
public struct WeatherData : Equatable,Identifiable {
    /// The id of the data
    public var id:String {
        "weather-at-\(dateTimeRepresentation)"
    }
    /// Indicates whether or not the data is a forcast or not
    public let isForcast:Bool
    /// The date and point in time of the data
    public let dateTimeRepresentation:Date
    /// Air pressure in mbar
    public let airPressure:Double
    /// Air temperature in celcius
    public let airTemperature:Double
    /// Air temperature in celcius adjusted to heat index and wind chill effect
    public let airTemperatureFeelsLike:Double
    /// Amount of horizontal visibilty in km
    public let horizontalVisibility:Double
    
    /// Wind direction in degrees from north (0 to 359)
    public let windDirection:Double
    /// Wind speed in m/s
    public let windSpeed:Double
    /// Wind gust speed in m/s
    public let windGustSpeed:Double
    
    /// Relative air humudity in % (0-100)
    public let relativeHumidity:Int
    /// The probabiity of thunder in % (0-100=
    public let thunderProbability:Int
    
    /// Mean value of total cloud cover
    public let totalCloudCover:Int
    /// Mean value of low cloud cover
    public let lowLevelCloudCover:Int
    /// Mean value of medium cloud cover
    public let mediumLevelCloudCover:Int
    /// Mean value of high cloud cover
    public let highLevelCloudCover:Int
    
    /// Minimum amount of precipitation in mm/h
    public let minPrecipitation:Double
    /// Maximum amount of precipitation in mm/h
    public let maxPrecipitation:Double
    /// Amount of frozen precipitation in % (0-100)
    public let frozenPrecipitationPercentage:Int
    
    /// Mean precipitation intensity in mm/h
    public let meanPrecipitationIntensity:Double
    /// Median precipitation intensity in mm/h
    public let medianPrecipitationIntensity:Double
    
    /// Precipitation category
    public let precipitationCategory:WeatherPrecipitation
    /// Symbol describing the weather
    public let symbol:WeatherSymbol
    /// The latitude of the weather readings
    public let latitude:Double
    /// The longitude of the weather readings
    public let longitude:Double
    
    /// Initializes a new WeatherData object
    /// - Parameters:
    ///   - isForcast: Indicates whether or not the data is a forcast or not
    ///   - dateTimeRepresentation: The date and point in time of the data
    ///   - airPressure: Air pressure in mbar
    ///   - airTemperature: Air temperature in celcius
    ///   - airTemperatureFeelsLike: Air temperature in celcius adjusted to heat index and wind chill effect
    ///   - horizontalVisibility: Amount of horizontal visibilty in km
    ///   - windDirection: Wind direction in degrees from north (0 to 359)
    ///   - windSpeed: Wind speed in m/s
    ///   - windGustSpeed: Wind gust speed in m/s
    ///   - relativeHumidity: Relative air humudity in % (0-100)
    ///   - thunderProbability: The probabiity of thunder in % (0-100=
    ///   - totalCloudCover: Mean value of total cloud cover
    ///   - lowLevelCloudCover: Mean value of low cloud cover
    ///   - mediumLevelCloudCover: Mean value of medium cloud cover
    ///   - highLevelCloudCover: Mean value of high cloud cover
    ///   - minPrecipitation: Minimum amount of precipitation in mm/h
    ///   - maxPrecipitation: Maximum amount of precipitation in mm/h
    ///   - frozenPrecipitationPercentage: Amount of frozen precipitation in % (0-100)
    ///   - meanPrecipitationIntensity: Mean precipitation intensity in mm/h
    ///   - medianPrecipitationIntensity: Median precipitation intensity in mm/h
    ///   - precipitationCategory: Precipitation category
    ///   - symbol: Symbol describing the weather
    ///   - latitude: The latitude of the weather readings
    ///   - longitude: The longitude of the weather readings
    public init(
        isForcast:Bool = true,
        
        dateTimeRepresentation:Date,
        airPressure:Double,
        airTemperature:Double,
        airTemperatureFeelsLike:Double,
        horizontalVisibility:Double,
        
        windDirection:Double,
        windSpeed:Double,
        windGustSpeed:Double,
        
        relativeHumidity:Int,
        thunderProbability:Int,
        
        totalCloudCover:Int,
        lowLevelCloudCover:Int,
        mediumLevelCloudCover:Int,
        highLevelCloudCover:Int,
        
        minPrecipitation:Double,
        maxPrecipitation:Double,
        frozenPrecipitationPercentage:Int,
        
        meanPrecipitationIntensity:Double,
        medianPrecipitationIntensity:Double,
        
        precipitationCategory:WeatherPrecipitation,
        symbol:WeatherSymbol,
        latitude: Double,
        longitude: Double) {
            self.isForcast = isForcast
            self.dateTimeRepresentation = dateTimeRepresentation
            self.airPressure = airPressure
            self.airTemperature = airTemperature
            self.airTemperatureFeelsLike = airTemperatureFeelsLike
            self.horizontalVisibility = horizontalVisibility
            
            self.windDirection = windDirection
            self.windSpeed = windSpeed
            self.windGustSpeed = windGustSpeed
            
            self.relativeHumidity = relativeHumidity
            self.thunderProbability = thunderProbability
            
            self.totalCloudCover = totalCloudCover
            self.lowLevelCloudCover = lowLevelCloudCover
            self.mediumLevelCloudCover = mediumLevelCloudCover
            self.highLevelCloudCover = highLevelCloudCover
            
            self.minPrecipitation = minPrecipitation
            self.maxPrecipitation = maxPrecipitation
            self.frozenPrecipitationPercentage = frozenPrecipitationPercentage
            
            self.meanPrecipitationIntensity = meanPrecipitationIntensity
            self.medianPrecipitationIntensity = medianPrecipitationIntensity
            
            self.precipitationCategory = precipitationCategory
            self.symbol = symbol
            self.latitude = latitude
            self.longitude = longitude
        }
}
