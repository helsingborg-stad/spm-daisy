import Foundation
import Combine
import SwiftUI
import Analytics


/// UserDefaults extension for managed config
extension UserDefaults {
    /// Returns the managed config dictionary
    @objc dynamic var managedConfig: [String:Any]? {
        return dictionary(forKey: "com.apple.configuration.managed")
    }
}

/// PropertyListDecoder used to decode the default plist file
let decoder = PropertyListDecoder()

/// A protocol used when implementing a config usable by the AppSettings class
public protocol AppSettingsConfig : Codable, Equatable {
    /// Used to combine the managed config with the default config.
    /// - Returns: the a config, either mixed, managed (`self`) or default `config` depending on your needs
    func combine(deafult config:Self?) -> Self
    /// A key value representation of your config. Used by the AppSettingsExplorer
    /// If you have sensitive data, you might want to override this function and mask some of the values.
    /// Have a look at the String.mask extensions provided by this framework
    var keyValueRepresentation: [String : String] { get }
}
/// Convenient AppSettingsConfig extensions
extension AppSettingsConfig {
    /// Decode using the default decoder
    /// - Parameter data: data to decode
    /// - Returns: the decoded config
    static func decoded(from data:Data) throws -> Self {
        return try decoder.decode(Self.self, from: data)
    }
    /// Decode from a dictionary
    /// - Parameter dictionary: dictionary to decode
    /// - Returns: the decoded config
    static func decoded(from dictionary:[String:Any]) throws -> Self {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }
    /// Read a plist file from disk
    /// - Parameters:
    ///   - name: the name of the file
    ///   - bundle: the bundle where the file is located
    /// - Returns: the config represtation of the file
    static func read(name:String, bundle:Bundle = Bundle.main) -> Self? {
        guard let plistPath: String = bundle.path(forResource: name, ofType: "plist") else {
            return nil
        }
        guard let data = FileManager.default.contents(atPath: plistPath) else {
            return nil
        }
        do {
            return try decoded(from: data)
        } catch {
            AnalyticsService.shared.logError(error)
            debugPrint(error)
        }
        return nil
    }
    /// Read a plist file from disk
    /// - Parameters:
    ///   - name: the name of the file
    ///   - bundle: the bundle where the file is located
    /// - Returns: the config represtation of the file
    static func read(url:URL) -> Self? {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return nil
        }
        do {
            return try decoded(from: data)
        } catch {
            AnalyticsService.shared.logError(error)
            debugPrint(error)
        }
        return nil
    }
    /// Used to combine the managed config with the default config.
    /// - Returns: the a config, either mixed, managed (`self`) or default `config` depending on your needs
    public func combine(deafult config:Self?) -> Self {
        return self
    }
    /// Returns a key value representation of the config using the Mirror(reflecting:) class.
    /// - Warning: **Do not use if your configuration contains sensitive information.**
    public var keyValueReflection: [String : String] {
        func value(from any:Any) -> String? {
            if let v = any as? String {
                return v
            } else if let v = any as? Int {
                return "\(v)"
            } else if let v = any as? Double {
                return "\(v)"
            } else if let v = any as? Bool {
                return "\(v)"
            }
            return String(describing: any)
        }
        var dict = [String : String]()
        for child in Mirror(reflecting: self).children {
            guard let label = child.label else {
                continue
            }
            if let value = value(from: child.value) {
                dict[label] = value
            }
        }
        return dict
    }
    public var keyValueRepresentation: [String : String] {
        return [:]
    }
}
public extension String {
    /// Used to mask a string
    /// ```swift
    /// let str = String.mask("my secret")
    /// print(str == "*****cret")
    /// ```
    /// - Parameters:
    ///   - string: the string to be masked
    ///   - leave: the number of characters to NOT mask
    ///   - all: mask the whole string regarldess of the count
    /// - Returns: the masked string
    static func mask(_ string:String?, leave numChars:Int) -> String? {
        guard let string = string else {
            return nil
        }
        let c = string.count
        if c < 1 {
            return string
        }
        if numChars == 0 {
            return String(repeating: "*", count: c)
        }
        if numChars >= c {
            return string
        }
        return String(repeating: "*", count: c-numChars) + string.suffix(numChars)
    }
    /// Used to mask a string
    /// ```swift
    /// let str = String.mask("my secret")
    /// print(str == "*****cret")
    /// ```
    /// - Parameters:
    ///   - string: the string to be masked
    ///   - percentage: the percentage of characters to mask from 0% to 100%
    /// - Returns: the masked string
    static func mask(_ string:String?, percentage:Int) -> String? {
        guard let string = string else {
            return nil
        }
        let c = string.count
        if c < 1 {
            return string
        }
        let count = Int(Double(percentage)/100 * Double(c))
        if count <= 0 {
            return string
        }
        if count >= c {
            return String(repeating: "*", count: c)
        }
        return String(repeating: "*", count: count) + string.suffix(count)
    }
}
/// Package to mange app-config or plist-formatted config files.
/// To make things a little easier in your implementation you should create a typealias of your generic type
/// ```swift
/// typealias MyAppSettings = AppSettings<MyConfig>
/// class MyState : ObservableObject {
///     let settings:MyAppSettings
///     init() {
///         self.settings = MyAppSettings(defaultsFromFile:Bundle.main.url(forResource: "defaultsettings", withExtension: "plist"))
///         settings.$config.sink { config in
///             guard let config = config else {
///                 return
///             }
///         }.store(in:&cancellables)
///     }
/// }
/// ```
public class AppSettings<Config: AppSettingsConfig>: ObservableObject {
    /// Current config
    @Published public private(set) var config:Config?
    
    /// URL to a plist file
    private let url:URL?
    /// Mix plist file and managed config with eachother if true,
    private let mixWithDefault:Bool
    /// Bundle used to read the plist file
    private var appConfigPublisher:AnyCancellable?
    /// Initializes a new config
    /// - Parameters:
    ///   - url: deafult plist file url
    ///   - managedConfigEnabled: enable or disable MDM AppConfig (default = true)
    ///   - mixWithDefault: Mix plist file and managed config with eachother if true. The mix is is managed by the implementor of AppSettingsConfig (default = true)
    public init(defaultsFromFile url:URL? = nil, managedConfigEnabled:Bool = true, mixWithDefault:Bool = true) {
        self.url = url
        self.mixWithDefault = true
        if managedConfigEnabled {
            if let c = managedConfig {
                self.set(config:resolve(managed: c))
            } else {
                self.set(config:defaultConfig)
            }
            appConfigPublisher = UserDefaults.standard.publisher(for: \.managedConfig).tryMap { dict -> Config? in
                guard let dict = dict else {
                    return nil
                }
                return try Config.decoded(from: dict)
            }.replaceError(with: nil).sink(receiveValue: { [weak self] config in
                if let config = config {
                    self?.set(config: self?.resolve(managed: config))
                } else {
                    self?.set(config: self?.defaultConfig)
                }
            })
        } else {
            self.set(config:defaultConfig)
        }
    }
    /// Resolve mixing of configs
    /// - Parameter managed config: the managed config
    /// - Returns: the mixed result
    func resolve(managed config:Config) -> Config {
        if mixWithDefault == false {
            return config
        }
        return config.combine(deafult: defaultConfig)
    }
    /// Assign `self.config` using `config`
    /// - Parameter config: the config to assign
    func set(config:Config?) {
        if config == self.config {
            return
        }
        self.config = config
    }
    /// Returns the default config using the instance filename and bundle
    public var defaultConfig:Config? {
        guard let url = url else {
            return nil
        }
        return Config.read(url: url)
    }
    /// Returns the managed config from UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed")
    public var managedConfig:Config? {
        guard let dict = UserDefaults.standard.managedConfig, let c = try? Config.decoded(from: dict) else {
            return nil
        }
        return c
    }
}
