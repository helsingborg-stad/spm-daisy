//
//  Command.swift
//  ExampleAssistant
//
//  Created by Tomas Green on 2021-06-10.
//

import Foundation
import STT
import Combine

/// Natural lanugage string parser
public class NLParser: ObservableObject {
    public typealias Key = String
    /// A dictionary type describing the NLParser database (entities associated with a locale)
    public typealias DB = [Locale:Entity]
    
    /// A dictionary type describing key -> values (values/strings associated with a key)
    public typealias Entity = [Key:[String]]
    /// Publishes events for when a value is found in a string.
    public typealias ResultPublisher = AnyPublisher<Result,Never>
    
    /// Result object used for publishing parser results
    public struct Result {
        /// The collection of entities found in a provided string
        public let collection:Set<Entity>
        /// String used for parsing (ie originating string)
        public let string:String
        /// Searches the collection for keys
        /// - Parameter key: the key to search for
        /// - Returns: true if found, false if not
        public func contains(_ key : CustomStringConvertible) -> Bool {
            collection.contains { db in
                db.keys.contains(key.description)
            }
        }
    }
    /// The database containing languages, keys and values
    private var db: DB
    /// Publisher used to trigger the parser to search and publish results
    private var stringPublisher:AnyPublisher<String,Never>
    /// The current locale, will trigger a change in contextual strings
    @Published public var locale:Locale = Locale.current {
        didSet {
            updateContextualStrings()
        }
    }
    /// A set of strings derived from the database and the current locale. The strings can be used to improve the accuracy of an STT
    @Published public private(set) var contextualStrings:[String] = []
    
    /// Initializes a new instance
    /// - Parameters:
    ///   - locale: The current locale (defaults to  Locale.current)
    ///   - db: The database containing languages, keys and values
    ///   - stringPublisher: Publisher used to trigger the parser to search and publish results
    init(locale:Locale = .current, db:DB, stringPublisher:AnyPublisher<String,Never>) {
        self.db = db
        self.locale = locale
        self.stringPublisher = stringPublisher
        updateContextualStrings()
    }
    /// Initializes a new instance by reading from a `Bundle.main` plist file
    /// - Parameters:
    ///   - languages: The set of languages to populate the database with
    ///   - fileName: The name of plist file
    ///   - stringPublisher: Publisher used to trigger the parser to search and publish results
    init(locale:Locale = .current, fileName: String, stringPublisher:AnyPublisher<String,Never>) {
        db = Self.readLocalizedDatabasePlist(fileName:fileName)
        self.locale = locale
        self.stringPublisher = stringPublisher
        updateContextualStrings()
    }
    /// Updates the contextual strings based on the current locale
    func updateContextualStrings() {
        var str = [String]()
        guard let dict = db[locale] else {
            return
        }
        dict.keys.forEach({ key in
            if let arr = dict[key] {
                str.append(contentsOf: arr)
            }
        })
        self.contextualStrings = str
    }
    /// Publishes results parsed from the `stringPublisher`
    /// - Parameter keys: The keys to use for parsing
    /// - Returns: A result publisher
    func publisher<K:CustomStringConvertible>(using keys:[K]) -> ResultPublisher {
        return publisher(using: keys.map({ $0.description }))
    }
    /// Publishes results parsed from the `stringPublisher`
    /// - Parameter keys: The keys to use for parsing
    /// - Returns: A result publisher
    func publisher(using keys:[Key]) -> ResultPublisher {
        return stringPublisher.map { [weak self] string -> Result in
            guard let this = self else {
                return Result(collection: Set([]), string:string)
            }
            guard let collection = this.db[this.locale]?.filter({ key,value in
                return keys.contains(key)
            }) else {
                return Result(collection: Set([]), string:string)
            }
            var set = Set<Entity>()
            for dict in collection {
                let values = dict.value.filter({ string.range(of: "\\b\($0)\\b", options: [.regularExpression,.caseInsensitive]) != nil})
                if !values.isEmpty {
                    set.insert([dict.key:values])
                }
            }
            return Result(collection: set, string:string)
        }.eraseToAnyPublisher()
    }
    /// Reads a local plist file and created a `Database`
    /// - Returns: a generated database
    static func readLocalizedDatabasePlist(fileName:String = "VoiceCommands") -> NLParser.DB {
        var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
        var db = NLParser.DB()
        func bundle(for language:Locale) -> Bundle {
            guard let b = Bundle.main.path(forResource: language.identifier, ofType: "lproj") else {
                return Bundle.main
            }
            return Bundle(path: b) ?? Bundle.main
        }
        var missing = [Locale]()
        for identifier in Locale.availableIdentifiers {
            let lang = Locale(identifier: identifier)
            db[lang] = [String:[String]]()
            let bundle = bundle(for: lang)
            guard let path = bundle.path(forResource: fileName, ofType: "plist") else {
                missing.append(lang)
                continue
            }
            do {
                guard let plistXML = FileManager.default.contents(atPath: path) else {
                    continue
                }
                let data = try PropertyListSerialization.propertyList(from: plistXML, options: .mutableContainersAndLeaves, format: &propertyListFormat)
                guard let pListData = data as? [String:[String]] else {
                    continue
                }
                db[lang] = pListData
            } catch {
                print(error)
                continue
            }
        }
        if !missing.isEmpty {
            debugPrint("missing voicecommand support for languages:",missing)
        }
        return db
    }
}
