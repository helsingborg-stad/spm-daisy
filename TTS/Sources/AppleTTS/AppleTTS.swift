import Foundation
import AVFoundation
import Combine
import FFTPublisher
import AudioSwitchboard

func createLocaleSet() -> Set<Locale> {
    return Set(AVSpeechSynthesisVoice.speechVoices().map { Locale(identifier: $0.language.replacingOccurrences(of: "-", with: "_"))})
}


/// Constant for AVSpeechUtterance minimum pitch
let AVSpeechUtteranceMinimumSpeechPitch:CFloat = 0.5
/// Constant for AVSpeechUtterance maximum pitch
let AVSpeechUtteranceMaximumSpeechPitch:CFloat = 2
/// Constant for AVSpeechUtterance default pitch
let AVSpeechUtteranceDefaultSpeechPitch:CFloat = 1

/// Calculated pitch from voice input
/// - Parameter voice: voice to extract pitch from
/// - Returns: AVSpeechUtterance adjusted pitch
func pitch(from voice:TTSVoice) -> Float {
    guard let r = voice.pitch else {
        return AVSpeechUtteranceDefaultSpeechPitch
    }
    let rate = Float(r) * AVSpeechUtteranceDefaultSpeechPitch
    return min(max(rate,AVSpeechUtteranceMinimumSpeechPitch),AVSpeechUtteranceMaximumSpeechPitch)
}
/// Calculated rate from voice input
/// - Parameter voice: voice to extract rate from
/// - Returns: AVSpeechUtterance adjusted rate
func rate(from voice:TTSVoice) -> Float {
    guard let r = voice.rate else {
        return AVSpeechUtteranceDefaultSpeechRate
    }
    let rate = Float(r) * AVSpeechUtteranceDefaultSpeechRate
    return min(max(rate,AVSpeechUtteranceMinimumSpeechRate),AVSpeechUtteranceMaximumSpeechRate)
}
/// AppleTTS errors
public enum AppleTTSError : Error {
    /// If service unavailable
    case unavailable
    /// If the language is unsupported
    case missingVoiceForLocale
}

/// AppleTTS is a implementation of AVSpeechSynthesizer adapted to the TTSService protocol
/// - Note: AppleTTS does not manage the `TTSUtterance` status, use `TTS` to get status updates
public class AppleTTS: NSObject, TTSService, AVSpeechSynthesizerDelegate, ObservableObject {
    /// The id or name of of the service
    public let id: TTSServiceIdentifier = "AppleTTS"
    /// Used when an utterance is cancelled
    private let cancelledSubject: TTSStatusSubject = .init()
    /// Used when an utterance is finsihed
    private let finishedSubject: TTSStatusSubject = .init()
    /// Used when an utterance is started
    private let startedSubject: TTSStatusSubject = .init()
    /// Used when the a word boundary is hit
    private let speakingWordSubject: TTSWordBoundarySubject = .init()
    /// Used upon failure
    private let failureSubject: TTSFailedSubject = .init()
    
    /// The sythensier
    private var synthesizer = AVSpeechSynthesizer()
    /// Used for the subscription to AudioBufferPlayer
    private var playerPublisher: AnyCancellable?
    /// Local db keeping track of utterances.
    private var db = [AVSpeechUtterance: TTSUtterance]()
    /// Audio player used to play utterances
    private var audioPlayer:AudioBufferPlayer
    /// Used for storeing cancellables
    private var cancellables = Set<AnyCancellable>()
    
    /// Triggers when an utterance is cancelled
    public var cancelledPublisher: TTSStatusPublisher  { cancelledSubject.eraseToAnyPublisher() }
    /// Triggers when an utterance is finsihed
    public var finishedPublisher: TTSStatusPublisher { finishedSubject.eraseToAnyPublisher() }
    /// Triggers when an utterance is started
    public var startedPublisher: TTSStatusPublisher { startedSubject.eraseToAnyPublisher() }
    /// Triggers when the a word boundary is hit
    public var speakingWordPublisher: TTSWordBoundaryPublisher { speakingWordSubject.eraseToAnyPublisher() }
    /// Triggers upon failure
    public var failurePublisher: TTSFailedPublisher { failureSubject.eraseToAnyPublisher() }
    /// Indicates whether or not the service is available
    public private(set) var available:Bool = true
    /// Used to publish FFT data from the AudioBufferPlayer
    public weak var fft: FFTPublisher? {
        didSet {
            audioPlayer.fft = fft
        }
    }
    /// Currently available locales publisher
    public var availableLocalesPublisher: AnyPublisher<Set<Locale>?, Never> {
        return $availableLocales.eraseToAnyPublisher()
    }
    /// Currently available locales
    @Published public private(set) var availableLocales: Set<Locale>? = createLocaleSet()

    /// Initializes a new AppleTTS instance
    /// - Parameters:
    ///   - audioSwitchBoard: Ssed to manage audio usage
    ///   - fft: Used to publish FFT data from the AudioBufferPlayer
    public init(audioSwitchBoard:AudioSwitchboard, fft: FFTPublisher? = nil) {
        audioPlayer = AudioBufferPlayer(audioSwitchBoard)
        synthesizer = AVSpeechSynthesizer()
        
        if #available(iOS 14.0, *) {
            synthesizer.usesApplicationAudioSession = true
        }
        super.init()
        synthesizer.delegate = self
        self.fft = fft
        audioPlayer.fft = fft
        
        self.available = audioSwitchBoard.availableServices.contains(.play)
        audioSwitchBoard.$availableServices.sink { [weak self] services in
            if services.contains(.play) == false {
                self?.stop()
                self?.available = false
            } else {
                self?.available = true
            }
        }.store(in: &cancellables)
        
        playerPublisher = audioPlayer.status.sink { [weak self] (item) in
            guard let this = self else {
                return
            }
            guard let record = this.db.first(where: { $0.value.id == item.id }) else {
                return
            }
            if item.status == .cancelled {
                this.db[record.key] = nil
                this.cancelledSubject.send(record.value)
            } else if item.status == .started {
                this.startedSubject.send(record.value)
            } else if item.status == .stopped {
                this.db[record.key] = nil
                this.finishedSubject.send(record.value)
                this.stop()
            } else if item.status == .failed, let error = item.error {
                this.db.forEach { (key, value) in
                    if value.id == item.id {
                        this.failureSubject.send(TTSFailure(utterance: value, error: error))
                    }
                }
                this.db[record.key] = nil
                this.stop()
            }
        }
    }
    /// Pause the utterance
    public func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        audioPlayer.pause()
    }
    /// Continue playing the utterance
    public func `continue`() {
        synthesizer.continueSpeaking()
        audioPlayer.continue()
    }
    /// Stop utterance
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer.stop()
    }
    /// Start utterance
    /// - Parameter utterance: the utterance to play
    public func start(utterance: TTSUtterance) {
        if !available {
            failureSubject.send(.init(utterance: utterance, error: AppleTTSError.unavailable))
            return
        }
        if synthesizer.isSpeaking {
            stop()
        }
        guard let v = bestVoice(for: utterance.voice) else {
            failureSubject.send(.init(utterance: utterance, error: AppleTTSError.missingVoiceForLocale))
            return
        }
        let u = AVSpeechUtterance(string: utterance.speechString)
        u.voice = v
        u.volume = 1
        u.rate = rate(from: utterance.voice)
        u.pitchMultiplier = pitch(from: utterance.voice)
        db[u] = utterance
        synthesizer.write(u) { (buff) in
            if self.db[u] == utterance {
                self.audioPlayer.play(id: utterance.id, buffer: buff)
            }
        }
    }
    /// Finds the best voice available for the utternace based on the properties of `TTSVoice`. Best avilable means quality enhanced first.
    /// - Parameter voice: used to find the best available voice
    /// - Returns: best avilable `AVSpeechSynthesisVoice`
    private func bestVoice(for voice: TTSVoice) -> AVSpeechSynthesisVoice? {
        guard hasSupportFor(locale: voice.locale) else {
            return nil
        }
        let lang = voice.locale.identifier.replacingOccurrences(of: "_", with: "-")
        var voices = AVSpeechSynthesisVoice.speechVoices().filter { v in v.language == lang }
        voices.sort { (v1, _) in v1.quality == .enhanced }
        for v in voices {
            if voice.gender == .other {
                return v
            } else if voice.gender == .female && v.gender == .female {
                return v
            } else if voice.gender == .male && v.gender == .male {
                return v
            }
        }
        return firstVoice(for: voice)
    }
    /// Finds the first voice available for the utternace based on the properties of `TTSVoice`
    /// - Parameter voice: used to find the first available voice
    /// - Returns: first avilable `AVSpeechSynthesisVoice`
    private func firstVoice(for voice: TTSVoice) -> AVSpeechSynthesisVoice? {
        guard hasSupportFor(locale: voice.locale) else {
            return nil
        }
        let lang = voice.locale.languageCode ?? voice.locale.identifier.replacingOccurrences(of: "_", with: "-")
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { v in v.language.prefix(2) == lang }
        for v in voices {
            if voice.gender == .other {
                return v
            } else if voice.gender == .female && v.gender == .female {
                return v
            } else if voice.gender == .male && v.gender == .male {
                return v
            }
        }
        if !voices.isEmpty {
            return voices.first
        }
        return AVSpeechSynthesisVoice(identifier: lang)
    }
    /// Implementation from AVSpeechSynthesizerDelegate. When called the instance will report word boundary to the speakingWord publisher
    /// - Parameters:
    ///   - synthesizer: sythensizer used
    ///   - characterRange: range of characters
    ///   - utterance: the utterance
    public final func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard let u = db[utterance] else {
            return
        }
        guard let range = Range(characterRange, in: u.speechString) else {
            return
        }
        let word = String(u.speechString[range])
        speakingWordSubject.send(TTSWordBoundary(utterance: u, wordBoundary: TTSUtteranceWordBoundary(string: word, range: range)))
    }
    /// Returns whether or not AVSpeechSynthesis supports the given locale
    /// - Parameter locale: the locale to compare with
    /// - Returns: true if available false if not
    public func hasSupportFor(locale:Locale, gender:TTSGender? = nil) -> Bool {
        guard let langauge = locale.languageCode else {
            return false
        }
        var arr = AVSpeechSynthesisVoice.speechVoices()
        if let gender = gender {
            arr = arr.filter { gender.isEqual(to: $0.gender) }
        }
        return arr.contains { $0.language.starts(with: langauge) }
    }
}

/// Extension for TTSGender
extension TTSGender {
    /// Equality check between AVSpeechSynthesisVoiceGender and TTSGender
    /// - Parameter gender: The gender to compare with
    /// - Returns: true if `TTSGender` is equals to `AVSpeechSynthesisVoiceGender`. Always true if `TTSGender` is equals to `.other` or `AVSpeechSynthesisVoiceGender` is equals to `.unspecified`
    func isEqual(to gender:AVSpeechSynthesisVoiceGender) -> Bool {
        if self == .other || gender == .unspecified { return true }
        if gender == .male && self == .male { return true }
        if gender == .female && self == .female { return true }
        return false
    }
}
