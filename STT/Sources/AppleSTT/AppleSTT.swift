import Foundation
import AVKit
import Speech
import Intents
import Combine
import FFTPublisher
import AudioSwitchboard

func createLocaleSet() -> Set<Locale> {
    var set = Set<Locale>()
    for l in SFSpeechRecognizer.supportedLocales() {
        set.insert(.init(identifier: l.identifier.replacingOccurrences(of: "-", with: "_")))
    }
    return set
}

/// AppleSTT Errors
public enum AppleSTTError : Error {
    /// User denied use of micophone
    case microphonePermissionsDenied
    /// User denied use of speech recognizer
    case speechRecognizerPermissionsDenied
    /// Unable to start the speech recognition without a good reason
    case unableToStartSpeechRecognition
    /// The service is unavailable
    case unavailable
    /// Trying to use an unsupported locale
    case unsupportedLocale
}

/// The AppleSTT is a STTService implementation using the Apple `SFSpeechRecognizer` framework
public class AppleSTT: STTService, ObservableObject {
    /// Indicates whether or not the service is available
    /// - Note: Setting the availability to false will trigger change of status and immediately stops the current recognition session
    public private(set) var available:Bool = true {
        didSet {
            if available == false {
                self.stop()
                self.status = .unavailable
            } else if oldValue == false && available{
                status = .idle
            }
        }
    }
    /// Currently available locales publisher
    public var availableLocalesPublisher: AnyPublisher<Set<Locale>?, Never> {
        return $availableLocales.eraseToAnyPublisher()
    }
    /// Currently available locales
    @Published public private(set) var availableLocales: Set<Locale>? = createLocaleSet()
    /// The current locale used to recgonize speech.
    /// - Note: changing the locale will reset the current recognitions session, if one is ongoing
    public var locale: Locale = Locale.current {
        didSet { settingsUpdated() }
    }
    /// Determines the maximum duration of slience allowed. Once triggered the instance will terminate the recognition session and publish the final restuls.
    /// - Note: The threshold will only trigger after the recognizer has identified speech, if the user is silent the threshold will be ignored.
    public var maxSilence:TimeInterval = 2
    /// Used to increase accuracy of the speech recognizer
    public var contextualStrings: [String] = [] {
        didSet { settingsUpdated() }
    }
    /// Used to set the mode of the speech recognizer.
    public var mode: STTMode = .unspecified {
        didSet { settingsUpdated() }
    }
    /// Private subjects used to publish results
    private let resultSubject: STTRecognitionSubject = .init()
    /// Private subjects used to publish status
    private let statusSubject: STTStatusSubject = .init()
    /// Private subjects used to publish errors
    private let errorSubject: STTErrorSubject = .init()
    
    /// Publishes complete or intermittently incomplete recognition results
    public let resultPublisher: STTRecognitionPublisher
    /// Publishes the current status of the service
    public let statusPublisher: STTStatusPublisher
    /// Publishes errors occoring
    public let errorPublisher: STTErrorPublisher
    /// The current status of the service
    private var status:STTStatus = .idle {
        didSet {
            statusSubject.send(status)
        }
    }
    /// Cancellable store
    private var cancellables = Set<AnyCancellable>()
    /// Specific cancellable for the audio switchboard cancellation callback
    private var switchboardCancellable:AnyCancellable?
    /// Optional fft publishing meter values from the microhpone
    private weak var fft:FFTPublisher? = nil
    /// AudioSwitchboard used to manage audio ownership
    private let audioSwitchboard:AudioSwitchboard
    /// The bus used to tap the microphone
    private let bus:AVAudioNodeBus = 0
    /// The current recognizer
    private var recognizer:SFSpeechRecognizer? = nil
    /// The current recognizing request
    private var recognitionRequest:SFSpeechAudioBufferRecognitionRequest?
    /// The current recognition task
    private var recognitionTask: SFSpeechRecognitionTask?
    /// The most recent result
    private var currentResult:STTResult?
    /// A timer used gother with the maxSilence to determine whether or not the user is done recording.
    private var clearTimer:Timer?
    /// Starts a timer that monitors the users precense, and determines when to stop recording.
    /// - Note: this function will not be called if the mode is set to dictation. Once the timer has been triggerd it will be restarted is the mode is set to `dictaion` or `unspecified`.
    private func startTimer() {
        clearTimer?.invalidate()
        clearTimer = nil
        clearTimer = Timer.scheduledTimer(withTimeInterval: maxSilence, repeats: true, block: { [locale,currentResult] (timer) in
            guard let currentResult = currentResult else {
                return
            }
            let r = STTResult(currentResult.string, confidence: currentResult.confidence, locale:locale, isFinal:true)
            self.resultSubject.send(r)
            if self.status == .recording {
                if self.mode == .dictation || self.mode == .unspecified {
                    self.restart()
                } else {
                    self.stop()
                }
            }
        })
    }
    /// Internal stop function that releases instances, stops timers, releases audio ownershop etc.
    private func internalStop() {
        clearTimer?.invalidate()
        clearTimer = nil
        recognitionRequest?.endAudio()
        audioSwitchboard.stop(owner: "AppleSTT")
        recognitionRequest = nil
        recognitionTask = nil
        currentResult = nil
        fft?.end()
    }
    /// Used to restart the service when settings are changed. Only triggers a restart if currently recording
    private func settingsUpdated() {
        if self.status == .recording {
            self.restart()
        }
    }
    /// Indicates whether or not the use of Microphone and SFSpeechRecognizer has been accepted
    private var permissionsResolved:Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted && SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    /// Restarts the service if available.
    private func restart() {
        internalStop()
        if !available {
            return
        }
        status = .preparing
        /// Finalizes the start/restart and starts recording if possible.
        func finalize() {
            do {
                try self.startRecording()
            } catch {
                self.status = .idle
                self.errorSubject.send(AppleSTTError.microphonePermissionsDenied)
            }
        }
        /// Resolves all permissions to the microphone and SFSpeechRecognizer
        func resolveAccess() {
            let audioSession = AVAudioSession.sharedInstance()
            if audioSession.recordPermission == .denied {
                self.status = .idle
                self.errorSubject.send(AppleSTTError.microphonePermissionsDenied)
                return
            }
            if audioSession.recordPermission == .undetermined {
                audioSession.requestRecordPermission { status in
                    if audioSession.recordPermission == .denied {
                        self.status = .idle
                        self.errorSubject.send(AppleSTTError.microphonePermissionsDenied)
                    } else {
                        resolveAccess()
                    }
                }
                return
            }
            if SFSpeechRecognizer.authorizationStatus() == .denied {
                self.errorSubject.send(AppleSTTError.speechRecognizerPermissionsDenied)
                return
            }
            if SFSpeechRecognizer.authorizationStatus() == .authorized {
                DispatchQueue.main.async {
                    finalize()
                }
            } else {
                SFSpeechRecognizer.requestAuthorization { authStatus in
                    if authStatus == SFSpeechRecognizerAuthorizationStatus.authorized {
                        resolveAccess()
                    } else {
                        self.status = .idle
                        self.errorSubject.send(AppleSTTError.speechRecognizerPermissionsDenied)
                    }
                }
            }
        }
        if permissionsResolved {
            finalize()
        } else {
            resolveAccess()
        }
    }
    /// Start a new recording
    private func startRecording() throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            self.status = .idle
            self.errorSubject.send(AppleSTTError.unsupportedLocale)
            return
        }
        switchboardCancellable = audioSwitchboard.claim(owner: "AppleSTT").sink { [weak self] in
            self?.stop()
        }
        let audioEngine = audioSwitchboard.audioEngine
        self.recognizer = recognizer
        let inputNode = audioEngine.inputNode
        let inputNodeFormat = inputNode.inputFormat(forBus: bus)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.status = .idle
            self.errorSubject.send(AppleSTTError.unableToStartSpeechRecognition)
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        switch mode {
            case .dictation: recognitionRequest.taskHint = .dictation
            case .unspecified: recognitionRequest.taskHint = .unspecified
            case .task: recognitionRequest.taskHint = .confirmation
            case .search: recognitionRequest.taskHint = .search
        }
        
        recognitionRequest.contextualStrings = contextualStrings
        recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let this = self else {
                return
            }
            if this.status == .idle {
                return
            }
            if let error = error as NSError? {
                if [203, 216].contains(error.code) {
                    this.restart()
                }
                return
            }
            guard let result = result else {
                return
            }
            if this.status == .recording && this.mode != .dictation {
                this.startTimer()
            }
            let parts = result.bestTranscription.segments.map { STTResult.Segment.init(string: $0.substring, confidence: Double($0.confidence)) }
            let r = STTResult(result.bestTranscription.formattedString, segments: parts,locale:this.locale, isFinal: result.isFinal)
            if this.currentResult?.string == r.string && this.currentResult?.confidence == r.confidence && this.currentResult?.isFinal == r.isFinal  {
                return
            }
            this.currentResult = r
            this.resultSubject.send(r)
            if result.isFinal {
                if this.status == .recording {
                    if this.mode == .dictation || this.mode == .unspecified {
                        this.restart()
                    } else {
                        this.stop()
                    }
                } else if this.status == .processing {
                    this.status = .idle
                }
            }
        }
        let rate = Float(inputNodeFormat.sampleRate)
        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputNodeFormat) { [weak self] (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            /// Reducing the frameLeth to 512 makes the FFT considerably faster.
            /// It's something of a hack since apple doens't allow buffersize below in the installTap method.
            /// There is a risk that this function will cause an error at some point.
            buffer.frameLength = 512
            self?.recognitionRequest?.append(buffer)
            self?.fft?.consume(buffer: buffer.audioBufferList, frames: buffer.frameLength, rate: rate)
        }
        try? audioSwitchboard.start(owner: "AppleSTT")
        status = .recording
    }
    
    /// initializes a new AppleSTT service instance
    /// - Parameters:
    ///   - audioSwitchboard:  AudioSwitchboard used to manage audio ownership
    ///   - fft: Optional fft publishing meter values from the microhpone
    ///   - maxSilence: Determines the maximum duration of slience allowed. Once triggered the instance will terminate the recognition session and publish the final restuls.
    public init(audioSwitchboard: AudioSwitchboard, fft:FFTPublisher? = nil, maxSilence:TimeInterval = 2) {
        self.resultPublisher = resultSubject.eraseToAnyPublisher()
        self.statusPublisher = statusSubject.eraseToAnyPublisher()
        self.errorPublisher = errorSubject.eraseToAnyPublisher()
        self.fft = fft
        self.maxSilence = maxSilence
        self.audioSwitchboard = audioSwitchboard
        self.available = audioSwitchboard.availableServices.contains(.record)
        audioSwitchboard.$availableServices.sink { [weak self] services in
            if services.contains(.record) == false {
                self?.stop()
                self?.available = false
            } else {
                self?.available = true
            }
        }.store(in: &cancellables)
    }
    /// Start the service if available
    public func start() {
        if !self.available {
            self.errorSubject.send(AppleSTTError.unavailable)
            return
        }
        guard status == .idle else {
            return
        }
        self.restart()
    }
    
    /// Stops the service immediately if started. Publishes a final result based on the currently recognized string.
    public func stop() {
        guard status == .recording || status == .preparing else {
            return
        }
        status = .idle
        recognitionTask?.cancel()
        internalStop()
    }
    
    /// Stops the service but waits for the recognizer to publish it's final result.
    public func done() {
        guard status == .recording || status == .preparing else {
            return
        }
        if currentResult == nil {
            status = .idle
        } else {
            status = .processing
        }
        recognitionTask?.finish()
        internalStop()
    }
    /// Returns whether or not SFSpeechRecognizer supports the given locale
    /// - Parameter locale: the locale to compare with
    /// - Returns: true if available false if not
    public static func hasSupportFor(locale:Locale) -> Bool {
        guard let langauge = locale.languageCode else {
            return false
        }
        return SFSpeechRecognizer.supportedLocales().contains { $0.identifier.starts(with: langauge) }
    }
}

