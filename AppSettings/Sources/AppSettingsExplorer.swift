//
//  SwiftUIView.swift
//  
//
//  Created by Tomas Green on 2021-09-17.
//

import SwiftUI

/// AppSettings extension used by the AppSettingsExplorer view
extension AppSettings {
    /// ConfigContainer representing the default plist file
    var defaultConfigContianer:AppSettingsExplorer.ConfigContainer? {
        guard let c = self.defaultConfig else {
            return nil
        }
        return AppSettingsExplorer.ConfigContainer(title: "Standard", config: c)
    }
    /// ConfigContainer representing the MDM App Config
    var managedConfigContianer:AppSettingsExplorer.ConfigContainer? {
        guard let c = self.managedConfig else {
            return nil
        }
        return AppSettingsExplorer.ConfigContainer(title: "Managed", config: c)
    }
    /// ConfigContainer representing the current config, could be either managed, default or mixed.
    var currentConfigContinaer:AppSettingsExplorer.ConfigContainer? {
        guard let c = self.config else {
            return nil
        }
        return AppSettingsExplorer.ConfigContainer(title: "Current", config: c)
    }
    /// Array that holds all containers, ie. defaultConfigContianer, managedConfigContianer and currentConfigContinaer
    var containers:[AppSettingsExplorer.ConfigContainer] {
        var arr = [AppSettingsExplorer.ConfigContainer]()
        if let c = currentConfigContinaer {
            arr.append(c)
        }
        if let c = managedConfigContianer {
            arr.append(c)
        }
        if let c = defaultConfigContianer {
            arr.append(c)
        }
        return arr
    }
    /// App Settings explorer view
    public struct AppSettingsExplorer: View {
        /// Container object holding the config and a title.
        public struct ConfigContainer {
            /// The config title or name, localizable
            public let title:LocalizedStringKey
            /// The config file
            public let config:Config
            /// Initializes a new ConfigContainer
            /// - Parameters:
            ///   - title: The config title or name, localizable
            ///   - config: The config file
            public init(title:LocalizedStringKey, config:Config) {
                self.title = title
                self.config = config
            }
        }
        /// List configs
        var configs:[ConfigContainer]
        /// Overlay used in case the list is empty
        var overlay:some View {
            Group {
                if configs.count != 0 {
                    EmptyView()
                } else {
                    Text(LocalizedStringKey("Missing configuration"))
                }
            }
        }
        /// View body
        public var body: some View {
            Form {
                ForEach(0..<configs.count) { i in
                    let container = configs[i]
                    Section(header:Text(container.title)) {
                        ForEach(container.config.keyValueRepresentation.sorted(by: >), id: \.key) { key, value in
                            VStack(alignment:.leading) {
                                Text(key).font(.headline)
                                Text(value).font(.body)
                            }
                        }
                    }
                }
            }
            .overlay(overlay)
            #if os(iOS) || os(tvOS) || os(watchOS)
            .listStyle(GroupedListStyle())
            .navigationBarTitle(LocalizedStringKey("App Config"))
            #endif
        }
    }
    /// Explorer view that represents the AppSettings instance configuration
    public var explorer: AppSettingsExplorer {
        return AppSettingsExplorer(configs: containers)
    }
}

struct PreviewAppConfig : AppSettingsConfig {
    func combine(deafult config: PreviewAppConfig?) -> PreviewAppConfig {
        return self
    }
    var keyValueRepresentation: [String : String] {
        var dict = [String:String]()
        if let stringValue = stringValue {
            dict["String"] = "\(stringValue)"
        }
        if let secretStringValue = secretStringValue {
            dict["Secret string"] = String.mask(secretStringValue,percentage: 50)
        }
        if let intValue = intValue {
            dict["Integer"] = "\(intValue)"
        }
        if let boolValue = boolValue {
            dict["Bool"] = "\(boolValue)"
        }
        if let doubleValue = doubleValue {
            dict["Double"] = "\(doubleValue)"
        }
        return dict
    }
    var stringValue:String?
    var secretStringValue:String?
    var intValue:Int?
    var boolValue:Bool?
    var doubleValue:Double?
}
struct AppSettingsExplorer_Previews: PreviewProvider {
    static var settings:AppSettings<PreviewAppConfig> {
        let c = AppSettings<PreviewAppConfig>()
        c.set(config: PreviewAppConfig(
            stringValue: "A string",
            secretStringValue: "My secret string",
            intValue: 1,
            boolValue: false,
            doubleValue: 2.2)
        )
        return c
    }
    static var previews: some View {
        settings.explorer
    }
}

