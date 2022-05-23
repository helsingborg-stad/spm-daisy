import Foundation
import SwiftUI
import Combine
import TextTranslator
import Shout

let defaultKeyMame = "DragomanCurrentBundleName"
/// Queue item of texts to be translated.
struct QueueItem {
    /// The texts to be translated
    var texts:[String]
    /// The language to translate from
    var from: LanguageKey
    /// The languages to translate to
    var to: Set<LanguageKey>
    /// Completion subject
    var subject:PassthroughSubject<Void,Error> = .init()
    /// Completion publisher
    var publisher:AnyPublisher<Void,Error>
    init(_ texts:[String], from:LanguageKey, to: [LanguageKey]) {
        self.texts = texts
        self.from = from
        self.to = Set<LanguageKey>(to)
        self.publisher = subject.eraseToAnyPublisher()
    }
}

/// Dragoman related errors
public enum DragomanError : Error {
    /// In case the isntance is disabled
    case disabled
    /// In case there is no assigned translation service
    case noTranslationService
    /// In case the translated data cannot be converted to a Data object
    case unableToConvertStringsToData
}
/// Dragoman is a localization and translation manager that uses a local device bundle to store .strings -files
public class Dragoman: ObservableObject {
    /// Indicates whether or not texts are being translated
    private var isTranslating:Bool = false
    /// Used to queue translation service calls and mitigate possible concurrency issues
    private var translationQueue = [QueueItem]()
    /// Used to identify a lanugage. Can be any string you desire but should be Apple Locale.languageCode compatible
    public typealias LanguageKey = String
    /// Used to decribe a value for a key
    public typealias Value = String
    /// Used to identify a value
    public typealias Key = String
    
    /// The base bundle where all .proj folder are stored
    private var baseBundle: Bundle {
        didSet {
            UserDefaults.standard.set(baseBundle.bundleURL.lastPathComponent, forKey: defaultKeyMame)
        }
    }
    /// The current app bundle, ie Bundle.main in your application
    private var appBundle: Bundle
    /// The name of the table where all strings are stored
    private let tableName: String = "Localizable"
    /// The translation service used to translate strings
    public var translationService: TextTranslationService?
    /// Cancellables storage
    private var cancellables = Set<AnyCancellable>()
    /// Triggeres when changes occurs
    private let changedSubject = PassthroughSubject<Void, Never>()
    /// Triggeres when a failure occurs
    public private(set) var supportedLanguages = [LanguageKey]()
    
    /// Indicates whether or not the dragoman translation service and file writes are disabled
    @Published public var disabled: Bool = false
    /// The bundle of the currently selected language
    @Published public private(set) var bundle: Bundle = Bundle.main
    /// The current language. When changed the bundles will update to the current language bundle
    @Published public var language:LanguageKey {
        didSet {
            updateBundles()
        }
    }
    /// Logging service used to publish events to logs or services
    public var logger:Shout = Shout("Dragoman")
    /// Publisher that triggers whenever a new file is written to disk
    public let changed: AnyPublisher<Void, Never>
    
    /// Initializes a new
    /// - Parameters:
    ///   - translationService: transaltion service to use when calling  translate(texts:from:to:)
    ///   - language: currently selected lanugage
    ///   - supportedLanguages: all supported languages
    public init(translationService: TextTranslationService? = nil, language:LanguageKey, supportedLanguages:[LanguageKey]) {
        self.language = language
        self.supportedLanguages = supportedLanguages
        if let name = UserDefaults.standard.string(forKey: defaultKeyMame), let b = Self.getBundle(for: name) {
            baseBundle = b
        } else if let bundle = try? Self.createBundle(tableName: tableName, languages: supportedLanguages) {
            baseBundle = bundle
        } else {
            baseBundle = Bundle.main
            disabled = true
        }
        appBundle = Self.appBundle(for: language)
        bundle = Self.languageBundle(bundle: baseBundle, for: language)
        self.translationService = translationService
        self.changed = changedSubject.eraseToAnyPublisher()
    }
    /// Load bundle from document directory (if it exists)
    /// - Parameter name: the bundle name, must include .bundle
    /// - Returns: a bundle if any
    static func getBundle(for name:String) -> Bundle? {
        let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
        let url = documents.appendingPathComponent(name, isDirectory: true)
        return Bundle(path: url.path)
    }
    /// Create a new bundle within the document directory
    /// - Parameters:
    ///   - tableName: .strings-file table name
    ///   - languages: language specific .lproj-folders to create
    /// - Returns: a new bundle
    static func createBundle(tableName:String, languages:[LanguageKey]) throws -> Bundle {
        let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!)
        let bundlePath = documents.appendingPathComponent(UUID().uuidString + ".bundle", isDirectory: true)
        try Self.createFoldersAndFiles(bundlePath: bundlePath, tableName: tableName, languages: languages)
        return Bundle(url: bundlePath)!
    }
    /// Creates bundle and language folders in given path
    /// - Parameters:
    ///   - bundlePath: the full path of the .bundle-folder
    ///   - tableName: the name of the .strings-file
    ///   - languages: language specific .lproj-folders to create
    static func createFoldersAndFiles(bundlePath:URL, tableName:String, languages:[LanguageKey]) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: bundlePath.path) == false {
            try manager.createDirectory(at: bundlePath, withIntermediateDirectories: true, attributes: [FileAttributeKey.protectionKey: FileProtectionType.complete])
        }
        for lang in languages {
            let langPath = bundlePath.appendingPathComponent("\(lang).lproj", isDirectory: true)
            if manager.fileExists(atPath: langPath.path) == false {
                try manager.createDirectory(at: langPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.protectionKey: FileProtectionType.complete])
            }
            let filePath = langPath.appendingPathComponent("\(tableName).strings")
            if manager.fileExists(atPath: filePath.path) == false {
                manager.createFile(atPath: filePath.path, contents: nil, attributes: [FileAttributeKey.protectionKey: FileProtectionType.complete])
            }
        }
    }
    /// Loads the a language bundle (LANG.lproj) from an application (typically Bundle.main)
    /// If no language bundle exits Bundle.main will be returned
    /// - Parameter language: langauge bundle to load
    /// - Returns: a language specific bundle
    static private func appBundle(for language:LanguageKey) -> Bundle {
        if let b = bundleByLanguageCode(bundle: Bundle.main, for: language) {
            return b
        }
        return Bundle.main
    }
    /// Loads the a language bundle (LANG.lproj) from a bundle
    /// If no language bundle exits `bundle` will be returned
    /// - Parameter language: langauge bundle to load
    /// - Returns: a language specific bundle
    static private func languageBundle(bundle:Bundle, for language:LanguageKey) -> Bundle {
        if let b = bundleByLanguageCode(bundle: bundle, for: language) {
            return b
        }
        return bundle
    }
    /// Loads the a language bundle (LANG.lproj) from a bundle if it exits
    /// - Parameter language: langauge bundle to load
    /// - Returns: a language specific bundle or nil
    static private func bundleByLanguageCode(bundle:Bundle, for language:LanguageKey) -> Bundle? {
        guard let path = bundle.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        guard let languageBundle = Bundle(path: path) else {
            return nil
        }
        return languageBundle
    }
    /// Remove all files from current bundle
    public func clean() throws {
        try clean(bundle:baseBundle)
    }
    /// Remove all files from bundle
    /// - Parameter bundle: the bundle to remove
    private func clean(bundle:Bundle) throws {
        if FileManager.default.fileExists(atPath: bundle.bundlePath) {
            try FileManager.default.removeItem(at: bundle.bundleURL)
        }
    }
    /// Removes all strings in all supported languages related to the specified keys
    /// - Parameter keys: keys to strings that should be removed
    public func remove(keys:[String]) throws {
        var table = translations(in: supportedLanguages)
        table.remove(strings: keys)
        try write(table)
    }
    /// Translate texts from a language to a list of languages.
    /// Each translation call is passed to a queue. A failed queue item will not cancel the remaining queued items.
    /// - Parameters:
    ///   - texts: the texts to translate, also used as keys to it's translated values
    ///   - from: original language
    ///   - to: languages to translate into, if nil the supportedLanguages will be used
    /// - Returns: completion publisher
    public func translate(_ texts: [String], from: LanguageKey, to: [LanguageKey]? = nil) -> AnyPublisher<Void,Error> {
        if disabled {
            return Fail(error: DragomanError.disabled).eraseToAnyPublisher()
        }
        let to = to ?? supportedLanguages
        let i = QueueItem(texts, from: from, to: to)
        self.translationQueue.append(i)
        DispatchQueue.main.async { [weak self] in
            self?.runQueue()
        }
        return i.publisher
    }
    /// Runs the ranslationQueue
    private func runQueue() {
        if isTranslating {
            return
        }
        guard let i = self.translationQueue.first else {
            return
        }
        isTranslating = true
        self.translationQueue.removeFirst()
        if disabled {
            i.subject.send(completion: .failure(DragomanError.disabled))
            runQueue()
            return
        }
        guard let translationService = translationService else {
            i.subject.send(completion: .failure(DragomanError.noTranslationService))
            runQueue()
            return
        }
        let table = translations(in: Array(i.to))
        var p:AnyCancellable?
        p = translationService.translate(i.texts, from: i.from, to: Array(i.to), storeIn: table).receive(on: DispatchQueue.main).sink(receiveCompletion: { [weak self] compl in
            switch compl {
            case .failure(let error): i.subject.send(completion: .failure(error))
            case .finished: break
            }
            self?.isTranslating = false
            self?.runQueue()
        }, receiveValue: { [weak self] table in
            guard let this = self else {
                self?.isTranslating = false
                self?.runQueue()
                return
            }
            var curr = this.translations(in: this.supportedLanguages)
            curr.merge(with: table)
            do {
                try this.write(table)
                i.subject.send()
            } catch {
                i.subject.send(completion: .failure(error))
            }
            if let p = p {
                this.cancellables.remove(p)
            }
            this.isTranslating = false
            this.runQueue()
        })
        if let p = p {
            cancellables.insert(p)
        }
    }
    /// Reads all translations from disk
    /// - Parameter languages: langauges to include
    /// - Returns: a transaltion table contining all translations and it's keys
    public func translations(in languages: [LanguageKey]) -> TextTranslationTable {
        var t = TextTranslationTable()
        for language in languages {
            if let url = baseBundle.url(forResource: tableName, withExtension: "strings", subdirectory: nil, localization: language), let stringsDict = NSDictionary(contentsOf: url) as? [String: String] {
                for (key, value) in stringsDict {
                    t.set(value: value, for: key, in: language)
                }
            }
        }
        return t
    }
    /// Checks if the text is translated in provided languages
    /// - Parameters:
    ///   - text: the text
    ///   - languages: languages to use, if nil supportedLanguages will be used as default value
    /// - Returns: true if translations found, false if not
    public func isTranslated(_ text:String, in languages:[LanguageKey]? = nil) -> Bool {
        let lang = languages ?? supportedLanguages
        let error = "## error no translation \(UUID().uuidString) ##"
        for l in lang {
            let str = Self.appBundle(for: language).localizedString(forKey: text, value: error, table: nil)
            if str == error, let b = Self.bundleByLanguageCode(bundle: baseBundle, for: l) {
                if b.localizedString(forKey: text, value: error, table: tableName) == error {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }
    /// Get string in currently selected language. This method will first check if the translation is available in the appBundle
    /// - Parameter key: a key that corrensponds with a locaized value
    /// - Parameter value: a default value to return in case no localized value can be found
    /// - Returns: returns a localized string. if no string is found and the `value` is set to a string, the `value` will be returned. If `value` is nil the `key` will be returned
    public func string(forKey key:String, value:String? = nil) -> String {
        let error = "## error no translation \(UUID().uuidString) ##"
        let str = appBundle.localizedString(forKey: key, value: error, table: nil)
        if str == error {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return str
    }
    /// Get string in the provided language. This method will first check if the translation is available in the appBundle
    /// - Parameter key: a key that corrensponds with a locaized value
    /// - Parameter language: the language in which to return the value
    /// - Parameter value: a default value to return in case no localized value can be found
    /// - Returns: returns a localized string. if no string is found and the `value` is set to a string, the `value` will be returned. If `value` is nil the `key` will be returned
    public func string(forKey key:String, in language:LanguageKey, value:String? = nil) -> String {
        if language == self.language {
            return string(forKey: key, value: value)
        }
        let error = "## error no translation \(UUID().uuidString) ##"
        let str = Self.appBundle(for: language).localizedString(forKey: key, value: error, table: nil)
        if str == error {
            return Self.languageBundle(bundle: baseBundle, for: language).localizedString(forKey: key, value: value, table: tableName)
        }
        return str
    }
    /// Get string in the provided locale. This method will first check if the translation is available in the appBundle
    /// - Parameter key: a key that corrensponds with a locaized value
    /// - Parameter locale: the locale in which to return the value (uses `Locale.languageCode`)
    /// - Parameter value: a default value to return in case no localized value can be found
    /// - Returns: returns a localized string. if no string is found and the `value` is set to a string, the `value` will be returned. If `value` is nil the `key` will be returned
    public func string(forKey key:String, with locale:Locale, value:String? = nil) -> String {
        guard let languageCode = locale.languageCode, supportedLanguages.contains(languageCode) else {
            return key
        }
        return string(forKey: key, in: languageCode,value: value)
    }
    /// Write a table to disk
    /// - Parameter translations: the transaltion table to be stored
    private func write(_ translations: TextTranslationTable) throws {
        if disabled {
            return
        }
        let old = baseBundle
        let new = try Self.createBundle(tableName: tableName, languages: supportedLanguages)
        for language in translations.db {
            let lang = language.key
            if !self.supportedLanguages.contains(lang) {
                logger.warning("language \(lang) not supported, ignoring")
                continue
            }
            let langPath = new.bundleURL.appendingPathComponent("\(lang).lproj", isDirectory: true)
            let sentences = language.value
            let res = sentences.reduce("", { $0 + "\"\(escape($1.key))\" = \"\(escape($1.value))\";\n" })
            let filePath = langPath.appendingPathComponent("\(tableName).strings")
            guard let data = res.data(using: .utf8) else {
                throw DragomanError.unableToConvertStringsToData
            }
            try data.write(to: filePath)
        }
        baseBundle = new
        updateBundles()
        do {
            try clean(bundle: old)
        }
        catch {
            logger.error(error)
        }
        changedSubject.send()
    }
    /// Updates `bundle` and `appBundle` using the latest `language` parameter.
    public func updateBundles() {
        bundle = Self.languageBundle(bundle: baseBundle, for: language)
        appBundle = Self.appBundle(for: language)
        changedSubject.send()
    }
}


/// Escapes double-quotes in string.
/// The function first removes all quotes and then adds them again to make sure the string cannot be escaped twice.
/// - Parameter string: the string to escape
/// - Returns: escaped string.
func escape(_ string:String) -> String {
    let str = string.replacingOccurrences(of: #"\""#, with: #"""#)
    return str.replacingOccurrences(of: "\"", with: "\\\"")
}
