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
}

/// A package that manages voice commands and translations, and, makes sure that TTS and STT is not interfering with eachother
public class Assistant<Keys: NLKeyDefinition> : ObservableObject {
    /// Used to clairify the order of `.speak((uttearance,tag))` method
    public typealias UtteranceString = String
    /// Used to clairify the order of `.speak((uttearance,tag))` method
    public typealias UtteranceTag = String
    /// NLParser for the supploed keys
    public typealias CommandBridge = NLParser<Keys>
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
            self.voiceCommands = voiceCommands ?? Keys.createLocalizedDatabasePlist(languages: supportedLocales)
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
    public let supportedLocales:[Locale]
    /// The main locale, used by the `TextTranslator` to manage translations when using nil `from` and `to` properties
    public let mainLocale:Locale
    
    /// Currently selected locale that changes language for the STT, NLParser and dragoman
    @Published public var locale:Locale {
        didSet {
            if let language = locale.languageCode {
                dragoman.language = language
            } else {
                debugPrint("unable to set dragoman language from \(locale)")
            }
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
    /// - Parameter settings: settings to be used
    public init(settings:Settings) {
        self.supportedLocales = settings.supportedLocales
        self.mainLocale = settings.mainLocale
        self.dragoman = Dragoman(translationService:settings.translator, language:settings.mainLocale.languageCode ?? "en", supportedLanguages: settings.supportedLocales.compactMap({$0.languageCode}))
        self.stt = STT(service: settings.sttService)
        self.tts = TTS(settings.ttsServices)
        self.translationBundle = dragoman.bundle
        self.locale = settings.mainLocale
        
        commandBridge = CommandBridge(
            locale: mainLocale,
            db: settings.voiceCommands,
            stringPublisher: sttStringPublisher.eraseToAnyPublisher()
        )
        commandBridge.locale = settings.mainLocale
        commandBridge.$contextualStrings.sink { [weak self] arr in
            self?.stt.contextualStrings = arr
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
        
        stt.locale = settings.mainLocale
        dragoman.language = settings.mainLocale.languageCode!
        commandBridge.locale = settings.mainLocale
        taskQueue.queue(.unspecified, using: stt)
    }
    /// Get localized string
    /// - Parameters:
    ///   - key: key representing the localized string
    ///   - locale: optional locale from the supportedLanguages. `self.locale` will be used if nil
    ///   - value: an optional default value used if the key is missing a localized value
    /// - Returns: the localized string
    public func string(forKey key:String, in locale:Locale? = nil, value:String? = nil) -> String {
        guard let languageKey = locale?.languageCode else {
            return dragoman.string(forKey: key, value: value)
        }
        return dragoman.string(forKey: key, in: languageKey, value: value)
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
        return TTSUtterance(self.string(forKey: key,in:locale ,value: value), locale: locale, tag: tag)
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
    @discardableResult public func speak(_ values:(UtteranceString,UtteranceTag?)..., interrupt:Bool = true) -> [TTSUtterance] {
        return speak(values,interrupt: interrupt)
    }
    /// Adds a set of strings (and tags) to be uttered by the TTS
    /// assistant.speak(("Hello User", "mytag"),("How are you?",nil), interrupt:true)
    /// - Parameters:
    ///   - values: touple representing a string and a tag
    ///   - interrupt: indicates whether or not to interrupt or queue the utterances
    /// - Returns: a set of utterances representing the provided values
    @discardableResult public func speak(_ values:[(UtteranceString,UtteranceTag?)], interrupt:Bool = true) -> [TTSUtterance] {
        var arr = [TTSUtterance]()
        for value in values {
            arr.append(self.utterance(for: value.0, tag: value.1))
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
    @discardableResult public func speak(_ strings:String..., interrupt:Bool = true) -> [TTSUtterance] {
        return speak(strings,interrupt: interrupt)
    }
    /// Adds a set of strings to be uttered by the TTS
    /// assistant.speak("Hello User","How are you?", interrupt:true)
    /// - Parameters:
    ///   - values: string to use for the utterance, using the current locale set in assistant
    ///   - interrupt: indicates whether or not to interrupt or queue the utterances
    /// - Returns: a set of utterances representing the provided values
    @discardableResult public func speak(_ strings:[String], interrupt:Bool = true) -> [TTSUtterance] {
        var arr = [TTSUtterance]()
        for string in strings {
            arr.append(self.utterance(for: string))
        }
        if interrupt {
            self.interrupt(using: arr)
        } else {
            self.queue(utterances: arr)
        }
        return arr
    }
    
    /// Cancells all currently running speech services, ie TTS or STT.
    public func cancelSpeechServices() {
        taskQueue.clear()
    }
    
    /// Listen (from STT result) for a set of key
    /// - Parameter keys: keys (or rather their acompaning values) to listen for
    /// - Returns: publisher triggered when a user utterance triggers one or more keys
    public func listen(for keys:[Keys]) -> AnyPublisher<CommandBridge.Result,Never> {
        return commandBridge.publisher(using: keys)
    }
    /// Translate a one or more strings
    /// - Parameters:
    ///   - strings: string (or strings) to translate
    ///   - from: the language of the strings provided, will use the `Assistant.mainLocale` if nil
    ///   - to: the langauges to translate into (languageCode), will use `Assistant.supportedLanguages` if nil
    @discardableResult public func translate(_ strings:String..., from:LanguageKey? = nil, to:[LanguageKey]? = nil) -> AnyPublisher<Void, Error>  {
        return translate(strings, from: from, to: to)
    }
    /// Translate a one or more strings
    /// - Parameters:
    ///   - strings: string (or strings) to translate
    ///   - from: the language of the strings provided, will use the `Assistant.mainLocale` if nil
    ///   - to: the langauges to translate into (languageCode), will use `Assistant.supportedLanguages` if nil
    @discardableResult public func translate(_ strings:String..., from:Locale? = nil, to:[Locale]? = nil) -> AnyPublisher<Void, Error> {
        if disabled {
            return Fail(error: AssistantError.disabled).eraseToAnyPublisher()
        }
        guard let from = (from ?? mainLocale).languageCode else {
            return Fail(error: AssistantError.invalidMainLocale).eraseToAnyPublisher()
        }
        let to = (to ?? supportedLocales).compactMap({$0.languageCode })
        return translate(strings, from: from, to: to)
    }
    /// Translate a one or more strings
    /// - Parameters:
    ///   - strings: string (or strings) to translate
    ///   - from: the language of the strings provided, will use the `Assistant.mainLocale` if nil
    ///   - to: the langauges to translate into (languageCode), will use `Assistant.supportedLanguages` if nil
    @discardableResult public func translate(_ strings:[String], from:LanguageKey? = nil, to:[LanguageKey]? = nil) -> AnyPublisher<Void, Error>  {
        if disabled {
            return Fail(error: AssistantError.disabled).eraseToAnyPublisher()
        }
        guard let from = from ?? mainLocale.languageCode else {
            return Fail(error: AssistantError.invalidMainLocale).eraseToAnyPublisher()
        }
        let to = to ?? supportedLocales.filter { $0.languageCode != nil }.compactMap({$0.languageCode})
        let publisher = dragoman.translate(strings, from: from, to: to)
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
