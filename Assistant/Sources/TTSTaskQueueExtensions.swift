//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-06-07.
//

import Foundation
import Combine
import TTS

/// An implementation of `QueueTask` for the `TTS`
/// - Warning: Once the task has been completed, it cannot be reused!
public class TTSTask : QueueTask {
    public let id = UUID()
    /// Subject used for ending the task
    let endSubject = PassthroughSubject<Void, Never>()
    public var end:AnyPublisher<Void,Never> {
        return endSubject.eraseToAnyPublisher()
    }
    /// Cancellables store
    private var cancellables = Set<AnyCancellable>()
    /// An instance of the TTS used by the task
    private weak var service: TTS?
    /// The utterances to queue
    private var utterances:[TTSUtterance]
    /// Initialize a new instance
    /// - Parameters:
    ///   - service: the service to use in the task
    ///   - utterance: the utterance to play
    public init(service:TTS,utterance:TTSUtterance) {
        self.service = service
        self.utterances = [utterance]
    }
    /// Initialize a new instance
    /// - Parameters:
    ///   - service: the service to use in the task
    ///   - utterances: the utterances to play
    public init(service:TTS,utterances:[TTSUtterance]) {
        self.service = service
        self.utterances = utterances
    }
    public func run(){
        guard let service = service else {
            tearDown()
            return
        }
        if service.disabled {
            tearDown()
            return
        }
        service.finished.sink { [weak self] u in
            guard let this = self else {
                return
            }
            this.utterances.removeAll { $0.id == u.id }
            if this.utterances.isEmpty {
                this.tearDown()
            }
        }.store(in: &cancellables)
        service.play(utterances)
    }
    
    public func interrupt() {
        for u in utterances {
            service?.cancel(u)
        }
        tearDown()
    }
    
    public func pause() {
        service?.pause()
    }
    public func `continue`() {
        service?.continue()
    }
    /// Used to tear down the instance.
    /// - Warning: The instance cannot be reused after this method has been called
    func tearDown() {
        utterances.removeAll()
        endSubject.send()
        endSubject.send(completion: .finished)
        service = nil
        cancellables.removeAll()
    }
}
public extension TaskQueue {
    /// Add an utterance to the queue. More information in can be found in the documentation of `TaskQueue.queue`
    /// - Parameters:
    ///   - utterance: the utterance to queue
    ///   - tts: the TTS instance to use
    func queue(_ utterance:TTSUtterance, using tts:TTS) {
        queue(TTSTask(service: tts, utterance: utterance))
    }
    /// Add an set of utterances to the queue. More information in can be found in the documentation of `TaskQueue.queue`
    /// - Parameters:
    ///   - utterance: the utterances to queue
    ///   - tts: the TTS instance to use
    func queue(_ utterances:[TTSUtterance], using tts:TTS) {
        queue(utterances.map({ TTSTask(service: tts, utterance: $0) }))
    }
    /// Interrupts the queue with an utterance. More information in can be found in the documentation of `TaskQueue.interrupt`
    /// - Parameters:
    ///   - utterance: the utterance to use for interruption
    ///   - tts: the TTS instance to use
    func interrupt(with utterance:TTSUtterance, using tts:TTS) {
        interrupt(with: TTSTask(service: tts, utterance: utterance))
    }
    /// Interrupts the queue with a set of utterances. More information in can be found in the documentation of `TaskQueue.interrupt`
    /// - Parameters:
    ///   - utterance: the utterances to use for interruption
    ///   - tts: the TTS instance to use
    func interrupt(with utterances:[TTSUtterance], using tts:TTS) {
        interrupt(with: utterances.map({ TTSTask(service: tts, utterance: $0) }))
    }
    /// Interject the queue with an utterance. More information in can be found in the documentation of `TaskQueue.interject`
    /// - Parameters:
    ///   - utterance: the utterance to use for interjection
    ///   - tts: the TTS instance to use
    func interject(with utterance:TTSUtterance, using tts:TTS) {
        interject(with: TTSTask(service: tts, utterance: utterance))
    }
    
    /// Interject the queue with a set of utterances. More information in can be found in the documentation of `TaskQueue.interject`
    /// - Parameters:
    ///   - utterance: the utterances to use for interjection
    ///   - tts: the TTS instance to use
    func interject(with utterances:[TTSUtterance], using tts:TTS) {
        interject(with: utterances.map({ TTSTask(service: tts, utterance: $0) }))
    }
}
