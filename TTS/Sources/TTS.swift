import Combine
import Foundation
import SwiftUI

/// A publisher used to publish word boundary events
public typealias TTSWordBoundaryPublisher = AnyPublisher<TTSWordBoundary, Never>
/// A publisher used to publish status events
public typealias TTSStatusPublisher = AnyPublisher<TTSUtterance, Never>
/// A void publisher used to publish various events
public typealias TTSMiscPublisher = AnyPublisher<Void, Never>
/// A publisher used to publish TTSFailures
public typealias TTSFailedPublisher = AnyPublisher<TTSFailure, Never>
/// A void publisher used to publish failures
public typealias TTSWordBoundarySubject = PassthroughSubject<TTSWordBoundary, Never>
/// A subject used to publish status events
public typealias TTSStatusSubject = PassthroughSubject<TTSUtterance, Never>
/// A subject used to publish various events
public typealias TTSMiscSubject = PassthroughSubject<Void, Never>
/// A subject used to publish failures
public typealias TTSFailedSubject = PassthroughSubject<TTSFailure, Never>

/// Enum describing voice genders
public enum TTSGender: String, Codable, CaseIterable, Identifiable {
    /// The id of the gender, returns the string rawValue
    public var id: String {
        return rawValue
    }
    /// female gender
    case female
    /// male gender
    case male
    /// other, unspecified gender (rename to unspecified at some point, right now it's just confusing)
    case other
}
/// TTS error
public enum TTSError: Error {
    /// utterance not found error
    case utteranceNotFound
    /// missing tts service error
    case missingTTSService
}
/// Object used for a TTSUtterance. The object is passed to a TTSService that in turn uses the information to find the best available voice.
public struct TTSVoice {
    /// An id that can be used by a TTSService to determine which voice to choose
    public var id: String = "default"
    /// A name that can be used by a TTSService to determine which voice to choose
    public var name: String = "default"
    /// The gender of the voice
    public var gender: TTSGender = .other
    /// Adjust the pitch of the voice, a value between 0 and 2 where default is 1
    public var pitch: Double? = nil
    /// Adjust the rate of the voice, a value between 0 and 2 where default is 1
    public var rate: Double? = nil
    /// The locale to be used to decide which language to use for the utterance.
    public var locale: Locale
    /// Initializes a new voice
    /// - Parameters:
    ///   - gender: the gender of the voice
    ///   - locale: The locale to be used to decide which language to use for the utterance.
    public init(gender: TTSGender, locale: Locale) {
        self.gender = gender
        self.locale = locale
    }
    /// Initializes a new voice
    /// - Parameters:
    ///   - id: An id that can be used by a TTSService to determine which voice to choose
    ///   - name: A name that can be used by a TTSService to determine which voice to choose
    ///   - gender: The gender of the voice
    ///   - rate: Adjust the pitch of the voice
    ///   - pitch: Adjust the pitch of the utterance
    ///   - locale: The locale to be used to decide which language to use for the utterance.
    public init(id: String = "default", name: String = "default", gender: TTSGender = .other, rate:Double? = nil, pitch:Double? = nil, locale: Locale) {
        self.id = id
        self.name = name
        self.gender = gender
        self.locale = locale
        self.rate = rate
        self.pitch = pitch
    }
}
/// A failure object used by the TTS to publish utterance failures
public struct TTSFailure {
    /// Utterance failed
    public var utterance: TTSUtterance
    /// Error occured
    public var error: Error
    /// Initializes a new TTSFailure object
    /// - Parameters:
    ///   - utterance: Utterance failed
    ///   - error: Error occured
    public init(utterance: TTSUtterance, error: Error) {
        self.utterance = utterance
        self.error = error
    }
}
/// Object used to indicate TTSUtterance word boundary.
public struct TTSWordBoundary {
    /// Utterance used for word boundary
    public let utterance: TTSUtterance
    /// Word boundary information
    public let wordBoundary: TTSUtteranceWordBoundary
    /// Initializes a new `TTSWordBoundary` object
    /// - Parameters:
    ///   - utterance: Utterance used for word boundary
    ///   - wordBoundary: Word boundary information
    public init(utterance: TTSUtterance, wordBoundary: TTSUtteranceWordBoundary) {
        self.utterance = utterance
        self.wordBoundary = wordBoundary
    }
}
/// Holds information about a TTSUtterance word woundary
public struct TTSUtteranceWordBoundary {
    /// The string or word being uttered
    public let string: String
    /// The range in the original string
    public let range: Range<String.Index>
    /// Initializes a new wordoundary object
    /// - Parameters:
    ///   - string: The string or word being uttered
    ///   - range: The range in the original string
    public init(string: String, range: Range<String.Index>) {
        self.string = string
        self.range = range
    }
}
/// Describes the status of a TTSUtterance
public enum TTSUtteranceStatus: String, Equatable {
    /// No latest status
    case none
    /// Utterance queued by `TTS`
    case queued
    /// Utterance being prepared by the `TTSService`
    case preparing
    /// Utterance paused
    case paused
    /// Utterance completed playing
    case finished
    /// Utterance being spoken
    case speaking
    /// Uttearnce was cancelled at some point
    case cancelled
    /// Utterance failed playback
    case failed
}
/// Alias used as the identifying type of the TTSService
public typealias TTSServiceIdentifier = String

/// The TTSService protocol used by TTS providers
public protocol TTSService : AnyObject {
    /// The id of the TTS service provider
    var id:TTSServiceIdentifier { get }
    /// Indicated whether or not the service is available
    var available:Bool { get }
    /// Should be triggered when an utterance has been cancelled by the service
    var cancelledPublisher: TTSStatusPublisher { get }
    /// Should be triggered when the service has finsihed playing an utterance
    var finishedPublisher: TTSStatusPublisher { get }
    /// Should be triggered when the service has started playing an utterance
    var startedPublisher: TTSStatusPublisher { get }
    /// Should be triggered when the service is speaking an utterance
    var speakingWordPublisher: TTSWordBoundaryPublisher { get }
    /// Should be triggered when the service failed to play an utterance
    var failurePublisher: TTSFailedPublisher { get }
    /// Used to pause an utterance
    func pause()
    /// Used to continue a currently paused utterance
    func `continue`()
    /// Used to stop a currently playing utterance
    func stop()
    /// Used to start playing an utterance
    func start(utterance: TTSUtterance)
    /// Used to determine whether or not the TTS supports a perticular locale
    func hasSupportFor(locale:Locale, gender:TTSGender?) -> Bool
    /// Currently available service locales publisher
    /// The locales must be formatted as `language_REGION` or just `language` (don't use hyphens)
    var availableLocalesPublisher: AnyPublisher<Set<Locale>?,Never> { get }
    /// Currently available service locales
    /// The locales must be formatted as `language_REGION` or just `language` (don't use hyphens)
    var availableLocales:Set<Locale>? { get }
    /// Clears the TTS services cache files.  Only impleemted if  TTS service is caching files
    func clearCache()
}
extension TTSService {
    //To make clearCache() optional:
    public func clearCache() {}
}
/// Object describing an utterance to be played.
public struct TTSUtterance: Identifiable, Equatable {
    /// Equality check checking the id of the instance only
    /// - Returns: true if equal, false if not
    public static func == (lhs: TTSUtterance, rhs: TTSUtterance) -> Bool {
        lhs.id == rhs.id
    }
    /// Subject used to publish the status of an utterance
    internal var statusSubject = CurrentValueSubject<TTSUtteranceStatus,Never>(.none)
    /// Subject used to publish the words being spken in an utterance
    internal var wordBoundarySubject = PassthroughSubject<TTSUtteranceWordBoundary,Never>()
    /// Subject used when the utterance failes
    internal var failureSubject = PassthroughSubject<Error,Never>()
    /// The id (UUID) of the utterance
    public let id = UUID().uuidString
    /// Utterance tag, can be used to identify an utterance.
    public let tag:String?
    /// The string to be uttered
    public let speechString: String
    /// Coressponding utterance ssml (if any).
    public let ssml: String?
    /// The voice properties being used bu the TTSService to determine what voice to use for the utterance
    public let voice: TTSVoice
    /// Publishes utterance status events
    public var statusPublisher:AnyPublisher<TTSUtteranceStatus,Never>
    /// Publishes words being spoken
    public var wordBoundaryPublisher:AnyPublisher<TTSUtteranceWordBoundary,Never>
    /// Publsihes failures
    public var failurePublisher:AnyPublisher<Error,Never>
    /// Initializes a new TTSUtterance
    /// - Parameters:
    ///   - speechString: The string to be uttered
    ///   - ssml: SSML utterance (used if supported by the TTSService)
    ///   - voice: The voice properties being used bu the TTSService to determine what voice to use for the utterance
    ///   - tag: Utterance tag, can be used to identify an utterance.
    public init(_ speechString: String, ssml:String? = nil, voice: TTSVoice, tag:String? = nil) {
        self.speechString = speechString
        self.ssml = ssml
        self.voice = voice
        self.tag = tag
        self.statusPublisher = statusSubject.eraseToAnyPublisher()
        self.wordBoundaryPublisher = wordBoundarySubject.eraseToAnyPublisher()
        self.failurePublisher = failureSubject.eraseToAnyPublisher()
    }
    /// Initializes a new TTSUtterance
    /// - Parameters:
    ///   - speechString: The string to be uttered
    ///   - ssml: SSML utterance (used if supported by the TTSService)
    ///   - gender: The gender of the voice
    ///   - locale: The locale to be used to decide which language to use for the utterance.
    ///   - rate: Adjust the pitch of the voice
    ///   - pitch: Adjust the pitch of the utterance
    ///   - tag: Utterance tag, can be used to identify an utterance.
    public init(_ speechString: String, ssml:String? = nil, gender: TTSGender = .female, locale: Locale = .current, rate:Double? = nil, pitch:Double? = nil, tag:String? = nil) {
        self.speechString = speechString
        self.ssml = ssml
        self.tag = tag
        self.voice = TTSVoice(gender: gender, rate: rate, pitch: pitch, locale: locale)
        self.statusPublisher = statusSubject.eraseToAnyPublisher()
        self.wordBoundaryPublisher = wordBoundarySubject.eraseToAnyPublisher()
        self.failurePublisher = failureSubject.eraseToAnyPublisher()
    }
    /// Update the status of the utterance
    /// - Parameter status: status to publish
    func updateStatus(_ status:TTSUtteranceStatus) {
        if statusSubject.value != status {
            statusSubject.send(status)
        }
    }
}

/// TTS provides a common interface for Text To Speech services implementing the `TTSService` protocol.
/// It also manages the TTSUtterance status, something that typically is not implemented by `TTSService`
public class TTS: ObservableObject {
    /// The play queue
    private var queue: [TTSUtterance] = []
    /// Cancellable store
    private var cancellables = Set<AnyCancellable>()
    /// The currenly used service, reset occurs when queueing an item
    private var currentService:TTSService? = nil
    /// The currently selected service
    private var services = [TTSService]()
    
    private let queuedSubject: TTSStatusSubject = .init()
    private let preparingSubject: TTSStatusSubject = .init()
    private let speakingSubject: TTSStatusSubject = .init()
    private let pausedSubject: TTSStatusSubject = .init()
    private let cancelledSubject: TTSStatusSubject = .init()
    private let finishedSubject: TTSStatusSubject = .init()
    private let finishedQueueSubject: TTSMiscSubject = .init()
    private let failedSubject: TTSFailedSubject = .init()
    private let speakingWordSubject: TTSWordBoundarySubject = .init()
    
    /// Currently available locales publisher subject
    private var availableLocalesSubject = CurrentValueSubject<Set<Locale>?,Never>(nil)
    /// Currently available locales publisher
    public var availableLocalesPublisher: AnyPublisher<Set<Locale>?,Never> {
        return availableLocalesSubject.eraseToAnyPublisher()
    }
    /// Currently available locales
    public private(set) var availableLocales:Set<Locale>? = nil
    /// Indicates whether or not the TTS is playing an utterance
    @Published public private(set) var isSpeaking: Bool = false
    /// The currently played utterance
    @Published public private(set) var currentlySpeaking: TTSUtterance?
    /// Indicates whether or not the TTS is disables
    @Published public var disabled: Bool = false {
        didSet {
            if disabled {
                cancelAll()
            }
        }
    }
    /// Triggered when a new utterance is added to the queue
    public var queued: TTSStatusPublisher
    /// Triggered when an utterance is being prepared for playback
    public var preparing: TTSStatusPublisher
    /// Triggered when an utterance is being spoken
    public var speaking: TTSStatusPublisher
    /// Triggered when an utterance is paused
    public var paused: TTSStatusPublisher
    /// Triggered when an utterance is cancelled
    public var cancelled: TTSStatusPublisher
    /// Triggered when an utterance is finished
    public var finished: TTSStatusPublisher
    /// Triggered when the queue is empty after playback
    public var finishedQueue: TTSMiscPublisher
    /// Triggered when the a failure/error occurs
    public var failed: TTSFailedPublisher
    /// Triggered when the a word is being spoken
    public var speakingWord: TTSWordBoundaryPublisher

    /// Determines the best available service for the given voice
    /// - Parameter voice: used to check locale and gender
    /// - Returns: the first service in the list of services that are available and supports the given properties
    private func bestAvailableService(for voice:TTSVoice) -> TTSService? {
        services.first(where: { $0.hasSupportFor(locale: voice.locale, gender: voice.gender) })
    }
    /// Determines whether or not any service has support for a given gender and locale
    /// - Parameter voice: used to check locale and gender
    /// - Returns: true if supported, false if not
    public func hasSupport(for voice:TTSVoice) -> Bool {
        return services.contains(where: { $0.hasSupportFor(locale: voice.locale, gender: voice.gender) })
    }
    /// Dequeue an utterance, ie removed it from the queue
    /// - Parameter utterance: the utterance to remove
    private func dequeue(_ utterance: TTSUtterance) {
        queue.removeAll { $0.id == utterance.id }
    }
    /// Run the queue by selcting the top utterance and playing it
    private func runQueue() {
        if isSpeaking {
            return
        }
        guard let utterance = queue.first else {
            notSpeaking()
            finishedQueueSubject.send()
            return
        }
        guard let service = bestAvailableService(for: utterance.voice) else {
            failed(TTSFailure.init(utterance: utterance, error: TTSError.missingTTSService))
            return
        }
        currentService = service
        currentlySpeaking = utterance
        isSpeaking = true
        preparingSubject.send(utterance)
        utterance.updateStatus(.preparing)
        service.start(utterance: utterance)
    }
    /// Used to reset instance variables related to a currently playing utterance
    private func notSpeaking() {
        currentService = nil
        currentlySpeaking = nil
        isSpeaking = false
    }
    /// Used when cancelling an utterance
    /// - Parameter utterance: the utterance to cancel
    private func cancelled(_ utterance:TTSUtterance) {
        cancelledSubject.send(utterance)
        utterance.updateStatus(.cancelled)
        dequeue(utterance)
        if currentlySpeaking == utterance {
            notSpeaking()
            runQueue()
        }
    }
    /// Used to trigger failure events
    /// - Parameter utterance: the failure to publish
    private func failed(_ failure:TTSFailure) {
        failedSubject.send(failure)
        failure.utterance.updateStatus(.failed)
        failure.utterance.failureSubject.send(failure.error)
        dequeue(failure.utterance)
        notSpeaking()
        runQueue()
    }
    /// Used when finishing an utterance
    /// - Parameter utterance: the utterance that finished
    private func finished(_ utterance:TTSUtterance) {
        finishedSubject.send(utterance)
        utterance.updateStatus(.finished)
        dequeue(utterance)
        notSpeaking()
        runQueue()
    }
    /// Used when finishing an utterance
    /// - Parameter utterance: the utterance that's started
    private func started(_ utterance:TTSUtterance) {
        speakingSubject.send(utterance)
        utterance.updateStatus(.speaking)
    }
    /// Used to trigger events related to utterance word boundary
    /// - Parameter wordBoundary: word boundary from TTS service
    private func speakingWord(_ wordBoundary:TTSWordBoundary) {
        speakingWordSubject.send(wordBoundary)
        wordBoundary.utterance.wordBoundarySubject.send(wordBoundary.wordBoundary)
    }
    
    /// Initializes a new TTS instance
    /// - Parameter services: possible services
    public init(_ services:TTSService...) {
        self.queued = queuedSubject.eraseToAnyPublisher()
        self.preparing = preparingSubject.eraseToAnyPublisher()
        self.speaking = speakingSubject.eraseToAnyPublisher()
        self.paused = pausedSubject.eraseToAnyPublisher()
        self.cancelled = cancelledSubject.eraseToAnyPublisher()
        self.finished = finishedSubject.eraseToAnyPublisher()
        self.finishedQueue = finishedQueueSubject.eraseToAnyPublisher()
        self.failed = failedSubject.eraseToAnyPublisher()
        self.speakingWord = speakingWordSubject.eraseToAnyPublisher()
        services.forEach { s in
            self.add(service: s)
        }
    }
    /// Initializes a new TTS instance
    /// - Parameter services: possible services
    public init(_ services:[TTSService]) {
        self.queued = queuedSubject.eraseToAnyPublisher()
        self.preparing = preparingSubject.eraseToAnyPublisher()
        self.speaking = speakingSubject.eraseToAnyPublisher()
        self.paused = pausedSubject.eraseToAnyPublisher()
        self.cancelled = cancelledSubject.eraseToAnyPublisher()
        self.finished = finishedSubject.eraseToAnyPublisher()
        self.finishedQueue = finishedQueueSubject.eraseToAnyPublisher()
        self.failed = failedSubject.eraseToAnyPublisher()
        self.speakingWord = speakingWordSubject.eraseToAnyPublisher()
        services.forEach { s in
            self.add(service: s)
        }
    }
    
    /// Add a service to the list of possible services to use
    /// - Parameters:
    ///   - service: the service to add
    ///   - prioritized: determines if the service is added to the top of the list of services
    public func add(service:TTSService, prioritized:Bool = false) {
        if prioritized {
            self.services.insert(service, at: 0)
        } else {
            self.services.append(service)
        }
        if service.availableLocales != nil {
            updateAvailableLocales(service.availableLocales)
        }
        service.cancelledPublisher.receive(on: DispatchQueue.main).sink { [weak self] u in
            self?.cancelled(u)
        }.store(in: &cancellables)
        service.finishedPublisher.receive(on: DispatchQueue.main).sink { [weak self] u in
            self?.finished(u)
        }.store(in: &cancellables)
        service.startedPublisher.receive(on: DispatchQueue.main).sink { [weak self] u in
            self?.started(u)
        }.store(in: &cancellables)
        service.speakingWordPublisher.receive(on: DispatchQueue.main).sink { [weak self] w in
            self?.speakingWord(w)
        }.store(in: &cancellables)
        service.failurePublisher.receive(on: DispatchQueue.main).sink { [weak self] f in
            self?.failed(f)
        }.store(in: &cancellables)
        service.availableLocalesPublisher.receive(on: DispatchQueue.main).sink { [weak self] locales in
            self?.updateAvailableLocales(locales)
        }.store(in: &cancellables)
    }
    /// Queue a list of utterances for playback
    /// - Parameter utterances: utterances to queue
    public final func queue(_ utterances: [TTSUtterance]) {
        if disabled {
            return
        }
        for utterance in utterances {
            queue(utterance)
        }
    }
    /// Queue a utterance for playback
    /// - Parameter utterance: utterance to queue
    public final func queue(_ utterance: TTSUtterance) {
        if disabled {
            return
        }
        queue.append(utterance)
        queuedSubject.send(utterance)
        utterance.updateStatus(.queued)
        runQueue()
    }
    /// Play a list if utterances and immediately cancel all queued utterances, including the currently played utterance
    /// - Parameter utterances: utterance to play
    public final func play(_ utterances: [TTSUtterance]) {
        cancelAll()
        queue(utterances)
    }
    /// Play a utterance and immediately cancel all queued utterances, including the currently played utterance
    /// - Parameter utterance: utterance to play
    public final func play(_ utterance: TTSUtterance) {
        cancelAll()
        queue(utterance)
    }
    /// Cancells all utterances in the queue, including the currently played utterance
    public final func cancelAll() {
        queue.forEach { u in
            cancelledSubject.send(u)
            u.updateStatus(.cancelled)
        }
        queue.removeAll()
        currentService?.stop()
        notSpeaking()
    }
    /// Cancels a specific utterance and continue playing the queue (if not empty)
    /// - Parameter utterance: utterance to cancel
    public final func cancel(_ utterance: TTSUtterance) {
        if utterance.id == currentlySpeaking?.id {
            currentService?.stop()
        } else {
            dequeue(utterance)
        }
    }
    /// Pause the currently palyed utterance
    public final func pause() {
        guard let u = currentlySpeaking else {
            return
        }
        currentService?.pause()
        pausedSubject.send(u)
        u.updateStatus(.paused)
    }
    /// Pause the currently paused utterance
    public final func `continue`() {
        guard let u = currentlySpeaking else {
            return
        }
        currentService?.continue()
        speakingSubject.send(u)
        u.updateStatus(.speaking)
    }
    /// Clears the TTS servces cache folder if TTS service using cache
    public func clearCache() {
        services.forEach { $0.clearCache() }
    }
    /// Updates the currently available locales using a set ot locales
    private func updateAvailableLocales(_ locales:Set<Locale>?) {
        if let locales = locales {
            if availableLocales == nil {
                availableLocales = .init(locales)
            } else {
                availableLocales = availableLocales?.union(locales)
            }
        }
        availableLocalesSubject.send(availableLocales)
    }
}
