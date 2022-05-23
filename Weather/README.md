# Weather

Weather privides a common interface that supplies weather data form any service implementing the `WeatherService` protocol. 

## Usage
```swift
let weather = Weather(service:MyWeatherService())

/// The closest() method will provide you with data closest in time whenever it's available or if the underlying data changes.
weather.closest().sink { data in 
    guard let data = data else {
        return
    }
    print(data.symbol.emoji)
}.store(in: &publishers)

weather.coordinates = .init(latitude: 56.046411, longitude: 12.694454) 
```

The weather framework also contains some usful functions for processing meterological values, such as:

- `Weather.heatIndexAdjustedTemperature(temperature:humidity:)`
- `Weather.windChillAdjustedTemperature(temperature:wind:)`
- `Weather.dewPointAdjustedTemperature(humidity:temperature:)`

## SMHI
The package includes an implementation of SMHI weather services.

### Forecast
`SMHIForecastService` is a concrete implementation of the weather service protocol.
Simply add `SMHIForecastService()` as the service parameter in `Weather` and you're good to go.

> More information on forecast data can be found here: https://opendata.smhi.se/apidocs/metfcst/index.html

### Meterological observations
The package also supports collecting information from SMHI observations service. However, since the SHMI backend does not support collecting mutliple parameters at once, it has **not yet been adapted** to the `WeatherService` protocol. Either way you can use it for fething data using the following functions:

- `SMHIObservations.publisher(forStation:parameter:period:)`
- `SMHIObservations.publisher(latitude:longitude:parameter:period:)`

> More information on observation data can be found here: https://opendata.smhi.se/apidocs/metobs/index.html


## TODO

- [x] add list of services
- [x] code-documentation
- [ ] make SMHIObservations WeatherService compatible
- [x] write tests
- [x] complete package documentation
