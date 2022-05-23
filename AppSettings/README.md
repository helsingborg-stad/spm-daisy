# AppSettings

Package to mange app-config or plist-formatted config files. 

## Usage


### Inherit from AppSettingsConfig
Firstly you need to create a implementation of AppSettingsConfig

```swift
struct MyConfig : Codable, AppSettingsConfig{
    let myServiceKey:String?
    let enableMyService:Bool?
}
```

In case you want the managed config to be mixed with values for your default plist, you can override the default `combine(default config:)` method.

```swift
extension  MyConfig: AppSettingsConfig {
    func combine(deafult config: MyConfig?) -> MyConfig {
        guard let config = config else {
            return self
        }
        return Self(
            myServiceKey: self.myServiceKey ?? config.myServiceKey,
            enableMyService: self.enableMyService ?? config.enableMyService,
        )
    }
}
```

This library also supports a SwiftUI configuration explorer view, in order for that view to propertly display your configuration you have to ovverride the default `keyValueRepresentation:[String:String]` property.
```swift
extension  MyConfig: AppSettingsConfig {
    var keyValueRepresentation: [String : String] {
        /// The dictionary key will be treated like a LocalizedStringKey. The value will not
        var dict = [String:String]()
        dict["My service"]              = String.mask(myServicekey, percentage: 80) ?? "none"
        dict["My service activated"]    = enableMyService == false
        return dict
    }
    // If you don't have any sensitive information inside your configuration you can return `self.keyValueReflection`.
    // The keys returned will be the property names.
     
    // var keyValueRepresentation: [String : String] {
    //    self.keyValueReflection
    // }
     
}
```

### Using AppSettings
Once you have your config you can setup an AppSettings instance. Before you do you might want to create a typealias that can be used throughout your app.

In case you want a default configuration file bundled with the app, make sure it's a valid plist file. _The framwork does not support loading of configuration files over a network._

```swift
import Combine
import SwiftUI
import AppSettings

typealias MyAppSettings = AppSettings<MyConfig>
var cancellables = Set<AnyCancellable>()

class MyState : ObservableObject {
    let settings:MyAppSettings
    let myService = MyService()
    init() {
        let defaultFileUrl = Bundle.main.url(forResource: "DefaultSettings", withExtension: "plist")
        self.settings = MyAppSettings(
            defaultsFromFile: defaultFileUrl, 
            managedConfigEnabled: true, // enable manage config
            mixWithDefault: true // alllow managed config to be mixed with default values
        )
        settings.$config.sink { [weak self] config in
            self?.myService.key = config?.myServiceKey
            self?.myService.enabled = config?.enableMyService ?? false
        }.store(in:&cancellables)
    }
}
```

### AppSettings explorer
If you wish to see the result of your configuration you can use the instance specific explorer view

```swift 
class ContentView : View {
    @EnvironmentObject var state = MyState()
    var body: some View {
        state.settings.explorer
    }
}
```

## TODO

- [x] support "blended" configurations
- [x] code-documentation
- [x] write tests
- [x] complete package documentation

