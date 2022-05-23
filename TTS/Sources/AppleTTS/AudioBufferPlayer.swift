import Foundation
import AVKit
import Combine
import FFTPublisher
import AudioSwitchboard

enum AudioPlayerStatus {
    case started
    case paused
    case stopped
    case cancelled
    case failed
}
struct AudioPlayerItem {
    var id: String
    var status: AudioPlayerStatus
    var error: Error?
}

/// Audioplayer based on the AVAudioEngine
class AudioBufferPlayer: ObservableObject {
    /// AudioBufferPlayer Errors
    enum AudioBufferPlayerError: Error {
        /// Triggered when audio input format cannot be determined
        case unableToInitlializeInputFormat
        /// Triggered when audio output format cannot be determined
        case unableToInitlializeOutputFormat
        /// Triggered if the audio converter cannot be configured (probaby due to unsupported formats)
        case unableToInitlializeAudioConverter
        /// Trigggered when the buffer format cannot be  determined
        case unableToInitlializeBufferFormat
        //case unknownBufferType
    }
    /// Instance used to produce and publish meter values
    weak var fft: FFTPublisher?
    /// Used to send player status updates
    private let statusSubject: PassthroughSubject<AudioPlayerItem, Never> = .init()
    /// Status update publisher
    let status: AnyPublisher<AudioPlayerItem, Never>
    /// Used to publish playback time of the audio file.
    let playbackTime: PassthroughSubject<Float, Never> = .init()
    /// The output format used in the AVAudioEngine
    private let outputFormat = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatFloat32, sampleRate: 22050, channels: 1, interleaved: false)
    /// Used to subscribe to the AudioSwitchboard claim publisher
    private var switchboardCancellable:AnyCancellable?
    /// Indicates whether or not the current utterance is playing
    private(set) var isPlaying: Bool = false
    /// The current audio converter
    private var converter: AVAudioConverter!
    /// Switchboard used to claim the audio channels
    private let audioSwitchboard:AudioSwitchboard
    /// The player used to play audio
    private let player: AVAudioPlayerNode = AVAudioPlayerNode()
    /// The audio buffer size. 512 is not officially supported by Apple but it works anyway. It's set to 512 to speed up FFT calculations and reduce lag.
    private let bufferSize: UInt32 = 512
    /// Number of buffers left in the queue
    private var bufferCounter: Int = 0
    /// Id of the currently playing audio
    private var currentlyPlaying: String? = nil {
        didSet {
            isPlaying = currentlyPlaying != nil
        }
    }
    /// Initializes a AudioBufferPlayer
    /// - Parameter audioSwitchboard: Switchboard used to claim the audio channels
    init(_ audioSwitchboard:AudioSwitchboard) {
        self.audioSwitchboard = audioSwitchboard
        self.status = statusSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
    private func play(buffer: AVAudioPCMBuffer, id: String) {
        self.bufferCounter += 1
        self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { (_) -> Void in
            DispatchQueue.main.async { [ weak self] in
                guard let this = self else {
                    return
                }
                this.bufferCounter -= 1
                if this.bufferCounter == 0, this.currentlyPlaying == id {
                    this.statusSubject.send(AudioPlayerItem(id: id, status: .stopped))
                    this.currentlyPlaying = nil
                    this.stop()
                }
            }
        }
    }
    /// Prepare AVAudioBuffer for AVAudioPlayerNode
    /// - Parameters:
    ///   - buffer: the buffer to prepare
    ///   - id: the id of the item to play
    private func prepare(buffer: AVAudioBuffer, id: String) {
        guard player.isPlaying else {
            return
        }
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength > 0 else {
            //self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unknownBufferType))
            return
        }
        if buffer.format.commonFormat == .otherFormat {
            play(buffer: pcmBuffer, id: id)
        } else {
            initializeConverter(id: id, buffer: buffer)
            guard let outputFormat = outputFormat else {
                self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeOutputFormat))
                return
            }
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: pcmBuffer.frameCapacity) else {
                self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeBufferFormat))
                return
            }
            do {
                try self.converter.convert(to: convertedBuffer, from: pcmBuffer)
                play(buffer: convertedBuffer, id: id)
            } catch {
                self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: error))
            }
        }
    }
    /// Publishes the current position of the player based on rate
    /// - Parameter rate: the rate of the audio
    private func postCurrentPosition(for rate: Float) {
        guard self.player.isPlaying else {
            return
        }
        if let nodeTime = self.player.lastRenderTime, let playerTime = self.player.playerTime(forNodeTime: nodeTime) {
            let elapsedSeconds = (Float(playerTime.sampleTime) / rate)
            self.playbackTime.send(elapsedSeconds)
        }
    }
    /// Initialize a new AVAudioConverter
    /// - Parameters:
    ///   - id: the id of the item to play
    ///   - buffer: the buffer used for conversion
    private func initializeConverter(id: String,buffer: AVAudioBuffer) {
        guard converter == nil else {
            return
        }
        guard let outputAudioFormat = outputFormat else {
            self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeOutputFormat))
            return
        }
        guard let c = AVAudioConverter(from: buffer.format, to: outputAudioFormat) else {
            self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeAudioConverter))
            return
        }
        converter = c
    }
    /// Continue playing a paused item
    func `continue`() {
        guard currentlyPlaying != nil else {
            return
        }
        if !player.isPlaying {
            player.play()
        }
    }
    /// Pauses the currently playing item
    func pause() {
        guard currentlyPlaying != nil else {
            return
        }
        if player.isPlaying {
            player.pause()
        }
    }
    /// Stops the currently playing item
    func stop() {
        if let currentlyPlaying = currentlyPlaying {
            statusSubject.send(AudioPlayerItem(id: currentlyPlaying, status: .cancelled))
        }
        converter = nil
        audioSwitchboard.stop(owner: "AppleTTS")
        player.stop()
        bufferCounter = 0
        currentlyPlaying = nil
        self.fft?.end()
    }
    /// Play an audiobuffer
    /// - Parameters:
    ///   - id: the id of the item to be played
    ///   - buffer: the buffer to be played
    func play(id: String, buffer: AVAudioBuffer) {
        guard let outputFormat = outputFormat else {
            stop()
            self.statusSubject.send(AudioPlayerItem(id: id, status: .failed, error: AudioBufferPlayerError.unableToInitlializeInputFormat))
            return
        }
        if id == self.currentlyPlaying {
            prepare(buffer: buffer, id: id)
            return
        }
        switchboardCancellable?.cancel()
        switchboardCancellable = audioSwitchboard.claim(owner: "AppleTTS").sink { [weak self] in
            self?.stop()
        }
        let audioEngine = audioSwitchboard.audioEngine
        currentlyPlaying = id
        bufferCounter = 0
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: outputFormat)
        let rate = Float(audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: self.bufferSize, format: audioEngine.mainMixerNode.outputFormat(forBus: 0)) { [weak self] (buffer, _) in
            guard let this = self else {
                return
            }
            buffer.frameLength = this.bufferSize
            DispatchQueue.main.async {
                guard this.player.isPlaying else {
                    return
                }
                this.fft?.consume(buffer: buffer.audioBufferList, frames: buffer.frameLength, rate: rate)
                this.postCurrentPosition(for: rate)
            }
        }
        try? audioSwitchboard.start(owner: "AppleTTS")
        self.player.play()
        self.statusSubject.send(AudioPlayerItem(id: id, status: .started))
        prepare(buffer: buffer, id: id)
    }
}
