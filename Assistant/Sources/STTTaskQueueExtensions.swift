//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-06-07.
//

import Foundation
import Combine
import STT

/// An implementation of `QueueTask` for the `STT`
/// - Warning: Once the task has been completed, it cannot be reused.
public class STTTask : QueueTask {
    public let id = UUID()
    /// Subject used for ending the task
    let endSubject = PassthroughSubject<Void, Never>()
    public var end:AnyPublisher<Void,Never> {
        return endSubject.eraseToAnyPublisher()
    }
    /// An instance of the STT used by the task
    weak var service: STT?
    /// The mode to be used when staring the task
    private let mode:STTMode
    /// Cancellables store
    private var cancellables = Set<AnyCancellable>()
    /// Indicates whether or not the task has been paused
    private var paused = false
    /// Instansiated a new `STTTask`
    /// - Parameters:
    ///   - service: the `STT`
    ///   - mode: the mode to be used when starting the task
    public init(service:STT, mode:STTMode = .unspecified) {
        self.service = service
        self.mode = mode
    }
    public func run(){
        if paused {
            self.continue()
            return
        }
        guard let service = service else {
            tearDown()
            return
        }
        var started:Bool = false
        service.mode = mode
        service.$status.sink { [weak self] status in
            guard let this = self else {
                return
            }
            if status == .unavailable || (started && status == .idle) {
                if this.paused == false {
                    this.tearDown()
                }
            } else {
                started = true
            }
        }.store(in: &cancellables)
        service.start()
    }
    public func interrupt() {
        tearDown()
    }
    public func pause() {
        paused = true
        service?.stop()
    }
    public func `continue`() {
        paused = false
        service?.start()
    }
    /// Used to tear down the instance. Stops the STT and publishes the `end` event.
    /// - Warning: The instance cannot be reused after this method has been called
    func tearDown() {
        endSubject.send()
        endSubject.send(completion: .finished)
        service?.stop()
        service = nil
        cancellables.removeAll()
    }
}

public extension STT {
    /// Creates a new `STTTask` using the underlying `STT`
    /// - Parameter mode: the `STTMode` to use for the task
    /// - Returns: an instance of a STTTask
    func task(with mode:STTMode = .unspecified) -> STTTask {
        return STTTask(service: self, mode: mode)
    }
}
public extension TaskQueue {
    /// Queue a `STTtask` with the provided properties
    /// - Parameters:
    ///   - mode: The mode to use when starting the task
    ///   - stt: The stt instance to use
    func queue(_ mode:STTMode = .unspecified, using stt:STT) {
        queue(STTTask(service: stt, mode: mode))
    }
    /// Interrupt the queue with an `STTtask` using the provided properties. More information in can be found in the documentation of `TaskQueue.interrupt`
    /// - Parameters:
    ///   - mode: The mode to use when starting the task
    ///   - stt: The stt instance to use
    func interrupt(with mode:STTMode = .unspecified, using stt:STT) {
        interrupt(with: STTTask(service: stt, mode: mode))
    }
    /// Interject the queue with an `STTtask` using the provided properties. More information in can be found in the documentation of `TaskQueue.interject`
    /// - Parameters:
    ///   - mode: The mode to use when starting the task
    ///   - stt: The stt instance to use
    func interject(with mode:STTMode = .unspecified, using stt:STT) {
        interject(with: STTTask(service: stt, mode: mode))
    }
}
