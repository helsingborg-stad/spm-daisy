import AVFoundation
import Combine
import UIKit

/// Internal publisher
typealias AudioSwitchboardSubject = PassthroughSubject<Void, Never>

/// Switchboard stop-publisher
public typealias AudioSwitchboardPublisher = AnyPublisher<Void, Never>

/// Support package for libraries that uses audio services in iOS. The class manages AVAudioEngine resets and AVAudioSession activity
public class AudioSwitchboard :ObservableObject {
    
    /// Describes the available audio services (input/outputs)
    public enum AvailableService: CaseIterable {
        case play
        case record
    }
    
    /// Used to store internal subscribers
    private var cancellables = Set<AnyCancellable>()
    
    /// Audioengine instance
    public let audioEngine:AVAudioEngine
    
    
    /// Current available audio services (input/outputs)
    @Published public private(set) var availableServices = [AvailableService]()
    
    /// Indicates if the switchboard is running or not, might not be entierly correct since the AVAudioEngine is not very reliable
    @Published public private(set) var shouldBeRunning:Bool = false
    
    /// The current session owner
    @Published public private(set) var currentOwner:String?
    
    /// Switchboard subscribers
    private var subscribers = [String:AudioSwitchboardSubject]()
    
    
    /// Initializes a new AudioSwitchboard
    /// - Parameters:
    ///   - audioEngine: default value is a new AVAudioEngine instance
    ///   - startAudioSessionImmediately: indicates whether or not to start the AVAudioSession immediately upon instantiation
    public init(audioEngine:AVAudioEngine = .init() ,startAudioSessionImmediately:Bool = true) {
        self.audioEngine = audioEngine
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification, object: nil).sink { [weak self] notif in
            self?.startAudioSession()
            
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification, object: nil).sink { [weak self] notif in
            self?.startAudioSession()
        }.store(in: &cancellables)
        if startAudioSessionImmediately {
            startAudioSession()
        }
    }
    /// Start the AVAudioSession and pupulate available services
    public func startAudioSession() {
        self.availableServices = self.activate()
    }
    
    /// Stops and resets the audioEngine but only if the owner is the same as the `currentOwner`. The logic behind this functionality is to stop accidental shutdowns of the audioengine. Before the reset the function contacts all subscribers to make the neccesary adjustments for the change of ownership.
    /// - Parameter owner: the owner
    public func stop(owner:String) {
        if owner != self.currentOwner {
            return
        }
        subscribers.forEach { key,value in
            if key != owner {
                value.send()
            }
        }
        subscribers.removeAll()
        reset()
    }
    /// Resets the audioEngine
    public func reset() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        audioEngine.outputNode.removeTap(onBus: 0)
        audioEngine.inputNode.reset()
        audioEngine.mainMixerNode.reset()
        audioEngine.outputNode.reset()
        audioEngine.stop()
        audioEngine.attachedNodes.forEach { node in
            if node != audioEngine.outputNode && node != audioEngine.inputNode && node != audioEngine.mainMixerNode {
                audioEngine.detach(node)
                node.reset()
            }
        }
        audioEngine.reset()
        shouldBeRunning = false
    }
    
    /// Starts the audioengine but only if the owner is the same as `currentOwner`. The logic behind this functionality is to stop accidental resets of the audioengine.
    /// - Parameter owner: the owner
    public func start(owner:String) throws {
        if owner != self.currentOwner {
            return
        }
        audioEngine.prepare()
        try audioEngine.start()
        shouldBeRunning = true
    }
    /// Claims the and set's the `currentOwner`. This function immediately changes ownership and triggers the `stop(owner:)` method.
    /// - Parameter owner: the owner
    /// - Returns: a stop publisher used when another owner claims (ie stops) the switchboard.
    @discardableResult public func claim(owner:String) -> AudioSwitchboardPublisher {
        self.currentOwner = owner
        stop(owner: owner)
        let p = AudioSwitchboardSubject()
        subscribers[owner] = p
        return p.eraseToAnyPublisher()
    }
    /// Activates the AudioSession and returns the available audio services.
    /// - Returns: all available audio services
    private func activate() -> [AvailableService]{
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers,.duckOthers,.interruptSpokenAudioAndMixWithOthers,.allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            return AvailableService.allCases
        } catch {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .mixWithOthers,.duckOthers,.interruptSpokenAudioAndMixWithOthers,.allowBluetooth])
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                return [AvailableService.play]
            } catch {
                return []
            }
        }
    }
}
