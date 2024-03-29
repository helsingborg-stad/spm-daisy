import Foundation
import AVFoundation
import SwiftUI
import Combine

import TTS
import STT
import TextTranslator
import Dragoman
import AudioSwitchboard

/// Errors thrown by the assistant
public enum AssistantError: Error {
    /// In case a task is hinidered by the assistant being disabled
    case disabled
    /// In case the main locale is invalid (ie missing a languageCode)
    case invalidMainLocale
    /// If missing valid to-language during translation
    case emptyTranslationLanguage
}

/// A package that manages voice commands and translations, and, makes sure that TTS and STT is not interfering with eachother
public class Assistant: ObservableObject {
    /// Used to clairify the order of `.speak((uttearance,tag))` method
    public typealias UtteranceString = String
    /// Used to clairify the order of `.speak((uttearance,tag))` method
    public typealias UtteranceTag = String
    /// NLParser for the supported keys
    public typealias CommandBridge = NLParser
    /// Settings used to configure the assistans
    public struct Settings {
        /// The stt service used
        public let sttService: STTService
        /// A list of TTSServices to use. The first available will be used
        public let ttsServices: [TTSService]
        /// Supported locales, used by dragoman, NLParser etc
        public let supportedLocales:[Locale]
        /// The main locale, used by the `TextTranslator` to manage translations when using nil `from` and `to` properties
        public let mainLocale:Locale
        /// The voice commands available in the app
        public let voiceCommands:CommandBridge.DB
        /// The text translator service
        public let translator:TextTranslationService?
        /// Initializes a new instance
        /// - Parameters:
        ///   - sttService: The stt service used
        ///   - ttsServices: A list of TTSServices to use. The first available will be used
        ///   - supportedLocales: Supported locales, mapped to dragoman, NLParser etc. Default is an empty array which is populated from `Bundle.main.localizations`
        ///   - mainLocale: The main locale, used by the `TextTranslator` to manage translations when using nil `from` and `to` properties. Default is the first language in the supportedLanguages, or Locale.current
        ///   - translator: The voice commands available in the app
        ///   - voiceCommands: The text translator service
        public init(
            sttService: STTService,
            ttsServices: TTSService...,
            supportedLocales:[Locale] = [],
            mainLocale:Locale? = nil,
            translator:TextTranslationService? = nil,
            voiceCommands:CommandBridge.DB? = nil
        ) {
            var supportedLocales = supportedLocales
            if supportedLocales.count == 0 {
                Bundle.main.localizations.forEach { str in
                    supportedLocales.append(Locale(identifier: str))
                }
            }
            self.sttService = sttService
            self.ttsServices = ttsServices
            self.supportedLocales = supportedLocales
            self.mainLocale = mainLocale ?? supportedLocales.first ?? Locale.current
            self.translator = translator
            self.voiceCommands = voiceCommands ?? NLParser.readLocalizedDatabasePlist()
        }
    }
    
    /// Publishes strings to the `NLParser`
    private let sttStringPublisher = PassthroughSubject<String,Never>()
    /// Cancellable store
    private var cancellables = Set<AnyCancellable>()
    /// Parses STT strings for commands
    private let commandBridge:CommandBridge
    
    /// SST singleton
    public let stt: STT
    /// TTS singleton
    public let tts: TTS
    /// Manages translations and localizations
    public let dragoman: Dragoman
    /// Manages a queue of tasks, typically TTS utterances and speech recognition.
    public let taskQueue = TaskQueue()
    /// Supported locales, used by dragoman, NLParser etc
    public var supportedLocales:[Locale]
    /// The main locale, used by the `TextTranslator` to manage translations when using nil `from` and `to` properties
    public let mainLocale:Locale
    /// Preffered TTS gender
    public var ttsGender: TTSGender = .other
    /// Adjust the pitch of the TTS voice, a value between 0 and 2 where default is 1
    public var ttsPitch: Double? = nil
    /// Adjust the rate of the TTSvoice, a value between 0 and 2 where default is 1
    public var ttsRate: Double? = nil
    
    /// Currently selected locale that changes language for the STT, NLParser and dragoman
    @Published public var locale:Locale {
        didSet {
            dragoman.language = locale.identifier
            stt.locale = locale
            commandBridge.locale = locale
        }
    }
    /// Indicates whether or not the assistant is disabled or not
    /// - Note: Also disables Dragoman, STT and TTS
    @Published public var disabled:Bool = false {
        didSet {
            dragoman.disabled = disabled
            tts.disabled = disabled
            stt.disabled = disabled
        }
    }
    /// Indicates whether or not the tts is currently playing an utterance
    @Published public private(set) var isSpeaking:Bool = false
    /// The currently playing tts utterance
    @Published public private(set) var currentlySpeaking:TTSUtterance? = nil
    /// The current dragoman translaton bundle based ont the selected language
    @Published public private(set) var translationBundle:Bundle
    /// Currently available locales for all services (TTS,STT,TextTranslation)
    @Published public private(set) var availableLocales:Set<Locale>? = nil

    /// Used to keep track of updated locales
    private var textTranslationServiceSubscriber:AnyCancellable? = nil
    /// Currently available locales publisher subject
    private var languageUpdatesAvailableSubject = PassthroughSubject<Void,Never>()
    public var languageUpdatesAvailablePublisher:AnyPublisher<Void,Never> {
        languageUpdatesAvailableSubject.eraseToAnyPublisher()
    }
    /// Exposes a publisher for the $isSpeaking property
    public var isSpeakingPublisher:AnyPublisher<Bool,Never> {
        $isSpeaking.eraseToAnyPublisher()
    }
    /// Exposes a publisher for the $currentlySpeaking property
    public var currentlySpeakingPublisher:AnyPublisher<TTSUtterance?,Never> {
        $currentlySpeaking.eraseToAnyPublisher()
    }
    /// Exposes a publisher for the $translationBundle property
    public var translationBundlePublisher:AnyPublisher<Bundle,Never> {
        $translationBundle.eraseToAnyPublisher()
    }
    /// Initialize a new instans with the provided settings
    /// - Parameters:
    ///   - sttService: The stt service used
    ///   - ttsServices: A list of TTSServices to use. The first available will be used
    ///   - supportedLocales: Supported locales, mapped to dragoman, NLParser etc. Default is an empty array which is populated from `Bundle.main.localizations`
    ///   - mainLocale: The main locale, used by the `TextTranslator` to manage translations when using nil `from` and `to` properties. Default is the first language in the supportedLanguages, or Locale.current
    ///   - translator: The voice commands available in the app
    ///   - voiceCommands: The text translator service
    ///   - ttsGender: Preffered TTS gender
    ///   - ttsPitch: Adjust the pitch of the TTS voice, a value between 0 and 2 where default is 1
    ///   - ttsRate: Adjust the rate of the TTSvoice, a value between 0 and 2 where default is 1
    ///   - audioSwitchboard: Appending your AudioSwitchboard will automatically turn on or off stt and tts depending on harware availability.
    public init(
        sttService: STTService,
        ttsServices: TTSService...,
        supportedLocales:[Locale] = [],
        mainLocale:Locale? = nil,
        translator:TextTranslationService? = nil,
        voiceCommands:CommandBridge.DB? = nil,
        ttsGender:TTSGender = .other,
        ttsPitch:Double? = nil,
        ttsRate:Double? = nil,
        audioSwitchboard:AudioSwitchboard? = nil
    ) {
        let mainLocale =  mainLocale ?? supportedLocales.first ?? Locale.current
        var supportedLocales = supportedLocales
        if supportedLocales.count == 0 {
            Bundle.main.localizations.forEach { str in
                supportedLocales.append(Locale(identifier: str))
            }
        }
        self.supportedLocales = supportedLocales
        self.mainLocale = mainLocale
        self.dragoman = Dragoman(translationService:translator, language:mainLocale.languageCode ?? "en")
        self.stt = STT(service: sttService)
        self.tts = TTS(ttsServices)
        self.translationBundle = dragoman.bundle
        self.locale = mainLocale
        self.ttsGender = ttsGender
        self.ttsPitch = ttsPitch
        self.ttsRate = ttsRate

        commandBridge = CommandBridge(
            locale: mainLocale,
            db: voiceCommands ?? NLParser.readLocalizedDatabasePlist(),
            stringPublisher: sttStringPublisher.eraseToAnyPublisher()
        )
        commandBridge.locale = mainLocale
        commandBridge.$contextualStrings.sink { [weak self] arr in
            self?.stt.contextualStrings = arr
        }.store(in: &cancellables)
        
        audioSwitchboard?.$availableServices.sink { [weak self] services in
            self?.tts.disabled = services.contains(.play) == false
            self?.stt.disabled = services.contains(.record) == false
        }.store(in: &cancellables)
        
        stt.results.sink { [weak self] res in
            self?.sttStringPublisher.send(res.string)
        }.store(in: &cancellables)
        
        dragoman.$bundle.receive(on: DispatchQueue.main).sink { [weak self] bundle in
            self?.translationBundle = bundle
        }.store(in: &cancellables)
        
        tts.$currentlySpeaking.sink { [weak self] utterance in
            self?.currentlySpeaking = utterance
        }.store(in: &cancellables)
        
        tts.$isSpeaking.sink { [weak self] b in
            self?.isSpeaking = b
        }.store(in: &cancellables)
        
        
        stt.availableLocalesPublisher.sink { [weak self] _ in
            self?.updateAvailableLocales()
        }.store(in: &cancellables)
        
        dragoman.availableLocalesPublisher.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateAvailableLocales()
        }.store(in: &cancellables)
        
        tts.availableLocalesPublisher.sink { [weak self] _ in
            self?.updateAvailableLocales()
        }.store(in: &cancellables)
        
        stt.locale = mainLocale
        dragoman.language = mainLocale.languageCode!
        commandBridge.locale = mainLocale
        taskQueue.queue(.unspecified, using: stt)
    }
    /// Get localized string
    /// - Parameters:
    ///   - key: key representing the localized string
    ///   - locale: optional locale from the supportedLanguages. `self.locale` will be used if nil
    ///   - value: an optional default value used if the key is missing a localized value
    /// - Returns: the localized string
    public func string(forKey key:String, in locale:Locale? = nil, value:String? = nil) -> String {
        guard let languageKey = locale?.identifier else {
            return dragoman.string(forKey: key, value: value)
        }
        return dragoman.string(forKey: key, in: languageKey, value: value)
    }
    /// Get localized formatted string
    /// - Parameters:
    ///   - key: key representing the localized string
    ///   - locale: optional locale from the supportedLanguages. `self.locale` will be used if nil
    ///   - value: an optional default value used if the key is missing a localized value
    ///   - arguments: formatting values
    /// - Returns: the localized formatted string
    public func formattedString(forKey key:String,  in locale:Locale? = nil,value:String? = nil, _ arguments:CVarArg...) -> String {
        let result = string(forKey: key, in: locale, value: value)
        return String(format: result, locale: locale, arguments: arguments)
    }
    /// Creates an utterance
    /// - Parameters:
    ///   - key: key representing the localized string
    ///   - locale: optional locale from the supportedLanguages. `self.locale` will be used if nil
    ///   - value: an optional default value used if the key is missing a localized value
    ///   - tag: an optional value used to tag the utterance
    /// - Returns: an utterance configured with provided values
    public func utterance(for key:String, in locale:Locale? = nil, value:String? = nil, tag:String? = nil) -> TTSUtterance {
        let locale = locale ?? self.locale
        return TTSUtterance(
            self.string(forKey: key,in:locale ,value: value),
            ssml: nil,
            gender: ttsGender,
            locale: locale,
            rate: ttsRate,
            pitch: ttsPitch,
            tag: tag
        )
    }
    // MARK: Task Queue
    /// Interrupt other tasks with a set of utterances
    /// - Parameters:
    ///   - utterances: utterances to speak
    ///   - startSTT: start STT after queue has finished
    /// - Returns: the TTSTask representing the interruption
    @discardableResult public func interrupt(using utterances:[TTSUtterance], startSTT:Bool = true) -> TTSTask {
        let task = TTSTask(service: tts, utterances: utterances)
        taskQueue.interrupt(with: task)
        if startSTT {
            taskQueue.queue(.unspecified, using: stt)
        }
        return task
    }
    /// Interrupt other tasks with an utterance
    /// - Parameters:
    ///   - utterances: utterance to speak
    ///   - startSTT: start STT after queue has finished
    /// - Returns: the TTSTask representing the interruption
    @discardableResult public func interrupt(using utterance:TTSUtterance, startSTT:Bool = true) -> TTSTask {
        let task = TTSTask(service: tts, utterance: utterance)
        taskQueue.interrupt(with: task)
        if startSTT {
            taskQueue.queue(STTTask(service: stt, mode: .unspecified))
        }
        return task
    }
    /// Interrupt other tasks and start the STT
    /// - Parameter mode: the STT mode to use
    /// - Returns: the STTTask representing the interruption
    @discardableResult public func interrupt(using mode:STTMode = .unspecified) -> STTTask {
        let task = STTTask(service: stt, mode: mode)
        taskQueue.interrupt(with: task)
        return task
    }
    /// Add an utterance to the task queue
    /// - Parameter utterance: the utterance to queue
    /// - Returns: the TTSTask representing the queued item
    @discardableResult public func queue(utterance:TTSUtterance) -> TTSTask {
        let task = TTSTask(service: tts, utterance: utterance)
        taskQueue.queue(task)
        return task
    }
    /// Add an set of utterances to the task queue
    /// - Parameter utterances: the utterances to queue
    /// - Returns: the TTSTask representing the queued items
    @discardableResult public func queue(utterances:[TTSUtterance]) -> TTSTask {
        let task = TTSTask(service: tts, utterances: utterances)
        taskQueue.queue(task)
        return task
    }
    
    // MARK: Speaking strings
    /// Adds a set of strings (and tags) to be uttered by the TTS
    /// assistant.speak(("Hello User", "mytag"),("How are you?",nil), interrupt:true)
    /// - Parameters:
    ///   - values: touple representing a string and a tag
    ///   - interrupt: indicates whether or not to interrupt or queue the utterances
    /// - Returns: a set of utterances representing the provided values
    @discardableResult public func speak(_ values:(UtteranceString,UtteranceTag?)..., interrupt:Bool = true, readEmojis:Bool = false) -> [TTSUtterance] {
        return speak(values, interrupt: interrupt, readEmojis: readEmojis)
    }
    /// Adds a set of strings (and tags) to be uttered by the TTS
    /// assistant.speak(("Hello User", "mytag"),("How are you?",nil), interrupt:true)
    /// - Parameters:
    ///   - values: touple representing a string and a tag
    ///   - interrupt: indicates whether or not to interrupt or queue the utterances
    /// - Returns: a set of utterances representing the provided values
    @discardableResult public func speak(_ values:[(UtteranceString,UtteranceTag?)], interrupt:Bool = true, readEmojis:Bool = false) -> [TTSUtterance] {
        var arr = [TTSUtterance]()
        for value in values {
            arr.append(self.utterance(for: readEmojis ? value.0 : value.0.withoutEmojis, tag: value.1))
        }
        if interrupt {
            self.interrupt(using: arr)
        } else {
            self.queue(utterances: arr)
        }
        return arr
    }
    /// Adds a set of strings to be uttered by the TTS
    /// assistant.speak("Hello User","How are you?", interrupt:true)
    /// - Parameters:
    ///   - values: string to use for the utterance, using the current locale set in assistant
    ///   - interrupt: indicates whether or not to interrupt or queue the utterances
    /// - Returns: a set of utterances representing the provided values
    @discardableResult public func speak(_ strings:String..., interrupt:Bool = true, readEmojis:Bool = false) -> [TTSUtterance] {
        return speak(strings, interrupt: interrupt, readEmojis: readEmojis)
    }
    /// Adds a set of strings to be uttered by the TTS
    /// assistant.speak("Hello User","How are you?", interrupt:true)
    /// - Parameters:
    ///   - values: string to use for the utterance, using the current locale set in assistant
    ///   - interrupt: indicates whether or not to interrupt or queue the utterances
    /// - Returns: a set of utterances representing the provided values
    @discardableResult public func speak(_ strings:[String], interrupt:Bool = true, readEmojis:Bool = false) -> [TTSUtterance] {
        var arr = [TTSUtterance]()
        for string in strings {
            arr.append(self.utterance(for: readEmojis ? string : string.withoutEmojis))
        }
        self.speak(arr,interrupt: interrupt)
        return arr
    }
    public func speak(_ utterances:[TTSUtterance], interrupt:Bool) {
        if interrupt {
            self.interrupt(using: utterances)
        } else {
            self.queue(utterances: utterances)
        }
    }
    public func speak(_ utterances:TTSUtterance..., interrupt:Bool) {
        if interrupt {
            self.interrupt(using: utterances)
        } else {
            self.queue(utterances: utterances)
        }
    }
    /// Notifies listeners of locale updates
    private func updateAvailableLocales(){
        languageUpdatesAvailableSubject.send()
    }
    /// Get currently available locales. For each service included the set will return nil of one of the services returns nil
    /// - Parameters:
    ///   - includeTTSService: indicates whether or not to include TTS available locales
    ///   - includeSTTService: indicates whether or not to include STT available locales
    ///   - includeTextTranslation: indicates whether or not to include TextTranslationService available locales
    /// - Returns: a set of locales
    public func getAvailableLangaugeCodes(includeTTSService:Bool = true, includeSTTService:Bool = true, includeTextTranslation:Bool = true) -> Set<String>? {
        var set = Set<String>()
        var ttsSet:Set<String>?
        var sttSet:Set<String>?
        var textSet:Set<String>?

        if includeTTSService, let locales = tts.availableLocales {
            var tempSet = Set<String>()
            for l in locales {
                guard let code = l.languageCode else {
                    continue
                }
                tempSet.insert(code)
            }
            ttsSet = tempSet
        }
        if includeSTTService, let locales = stt.availableLocales {
            var tempSet = Set<String>()
            for l in locales {
                guard let code = l.languageCode else {
                    continue
                }
                tempSet.insert(code)
            }
            sttSet = tempSet
        }
        if includeTextTranslation, let locales = dragoman.availableLocales {
            var tempSet = Set<String>()
            for l in locales {
                guard let code = l.languageCode else {
                    continue
                }
                tempSet.insert(code)
            }
            textSet = tempSet
        }
        if let s = ttsSet {
            set = set.union(s)
        }
        if let s = sttSet {
            set = set.union(s)
        }
        if let s = textSet {
            set = set.union(s)
        }
        if let s = ttsSet {
            set = set.intersection(s)
        }
        if let s = sttSet {
            set = set.intersection(s)
        }
        if let s = textSet {
            set = set.intersection(s)
        }
        return set
    }

    /// Cancells all currently running speech services, ie TTS or STT.
    public func cancelSpeechServices() {
        taskQueue.clear()
    }
    
    /// Listen (from STT result) for a set of key
    /// - Parameter keys: keys (or rather their acompaning values) to listen for
    /// - Returns: publisher triggered when a user utterance triggers one or more keys
    public func listen(for keys:[CustomStringConvertible]) -> AnyPublisher<CommandBridge.Result,Never> {
        return commandBridge.publisher(using: keys.map({ $0.description }))
    }
    /// Translate a one or more strings
    /// - Parameters:
    ///   - strings: string (or strings) to translate
    ///   - from: the language of the strings provided, will use the `Assistant.mainLocale` if nil
    ///   - to: the langauges to translate into (languageCode), will use `Assistant.supportedLanguages` if nil
    ///   - ignoreTranslatedValues: Calls the translation service regladless of the value already existing in dragoman
    /// - Returns: completion publisher
    @discardableResult public func translate(_ strings:String..., from:Locale? = nil, to:[Locale]? = nil, ignoreTranslatedValues:Bool = false) -> AnyPublisher<Void, Error>  {
        return translate(strings, from: from, to: to,ignoreTranslatedValues:ignoreTranslatedValues)
    }
    /// Translate a one or more strings
    /// - Parameters:
    ///   - strings: string (or strings) to translate
    ///   - from: the language of the strings provided, will use the `Assistant.mainLocale` if nil
    ///   - to: the langauges to translate into (languageCode), will use `Assistant.supportedLanguages` if nil
    ///   - ignoreTranslatedValues: Calls the translation service regladless of the value already existing in dragoman
    /// - Returns: completion publisher
    @discardableResult public func translate(_ strings:[String], from:Locale? = nil, to:[Locale]? = nil, ignoreTranslatedValues:Bool = false) -> AnyPublisher<Void, Error>  {
        if disabled {
            return Fail(error: AssistantError.disabled).eraseToAnyPublisher()
        }
        let fromLang = from?.identifier ?? mainLocale.identifier
        var toLang = (to ?? supportedLocales).map({$0.identifier})
        toLang.removeAll { $0 == fromLang }
        if toLang.isEmpty {
            return Fail(error: AssistantError.emptyTranslationLanguage).eraseToAnyPublisher()
        }
        var toTranslate = [String]()
        if ignoreTranslatedValues {
            toTranslate = strings
        } else {
            for t in strings {
                if dragoman.isTranslated(t, in: toLang) {
                    continue
                }
                toTranslate.append(t)
            }
            if toTranslate.count == 0 {
                return Result.Publisher(()).eraseToAnyPublisher()
            }
        }
        let publisher = dragoman.translate(toTranslate, from: fromLang, to: toLang)
        var cancellable:AnyCancellable?
        cancellable = publisher.sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
            }
            if let c = cancellable {
                self.cancellables.remove(c)
            }
        } receiveValue: {
            if let c = cancellable {
                self.cancellables.remove(c)
            }
        }
        if let c = cancellable {
            self.cancellables.insert(c)
        }
        return publisher
    }
    /// Creates a container view and adding the appropriate environment objects from `Assitant` to `Content`
    /// - Returns: a container view
    public func containerView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        Self.ContainerView.init(assistant: self, content: content)
    }
    /// A container view and adding the appropriate environment objects from `Assitant` to `Content`
    public struct ContainerView<Content: View>: View {
        /// The assistant to be used within the view
        @ObservedObject var assistant:Assistant
        /// Your content
        let content: () -> Content
        /// Initializes a new view
        /// - Parameters:
        ///   - assistant: The assistant to be used within the view
        ///   - content: Your content
        public init(assistant: Assistant, @ViewBuilder content: @escaping () -> Content) {
            self.assistant = assistant
            self.content = content
        }
        /// The body of the view and the following environment objects and variables
        /// ```swift
        /// content()
        ///     .environmentObject(assistant)
        ///     .environmentObject(assistant.tts)
        ///     .environmentObject(assistant.stt)
        ///     .environmentObject(assistant.taskQueue)
        ///     .environmentObject(assistant.dragoman)
        ///     .environment(\.locale, assistant.locale)
        /// ```
        public var body: some View {
            content()
                .environmentObject(assistant)
                .environmentObject(assistant.tts)
                .environmentObject(assistant.stt)
                .environmentObject(assistant.taskQueue)
                .environmentObject(assistant.dragoman)
                .environment(\.locale, assistant.locale)
        }
    }

}

public extension String {
    var withoutEmojis: String {
        return self.filter { !($0.isEmoji) }
    }
}

extension Character {
    var isSimpleEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
    }
    var isCombinedIntoEmoji: Bool { unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false }
    var isEmoji: Bool { isSimpleEmoji || isCombinedIntoEmoji }
}
