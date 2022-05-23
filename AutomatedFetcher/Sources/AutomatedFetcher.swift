import Combine
import Foundation

/// An timer based async fetching manager
public class AutomatedFetcher<DataType:Any> : ObservableObject {
    private var subjectCancellable: AnyCancellable? = nil
    private var timerCancellable: AnyCancellable? = nil
    private var triggeredSubject = PassthroughSubject<Void,Never>()
    private var lastFetch:Date
    
    /// The fetch triggered publisher
    public let triggered:AnyPublisher<Void,Never>

    /// Indicates whether or not the instance is currently fetching
    @Published public private(set) var fetching:Bool = false
    
    /// Indicates whether or not the instance is active
    @Published public var isOn:Bool = true {
        didSet { configure() }
    }
    /// Indicates how often the fetcher should trigger
    @Published public var timeInterval:TimeInterval {
        didSet { configure() }
    }
    /// Indicates whether or not the instance should be fetching or not
    public var shouldFetch:Bool {
        return fetching == false && lastFetch.addingTimeInterval(timeInterval).timeIntervalSinceNow <= 0 
    }
    
    /// Instantiates a new AutomatedFetcher instance.
    /// - Parameters:
    ///   - subject: a subject used to trigger a fetch
    ///   - lastFetch: last fetch occured
    ///   - isOn: activated or deactivated
    ///   - timeInterval: the TimeInterval of each fetch
    /// - Note: The subject is used to monitor subscriptions to a publisher. If a publisher lacks subscribes, then fethcing a new value is clearly not neccessary.
    public init(_ subject:CurrentValueSubject<DataType,Error>, lastFetch date:Date? = nil, isOn:Bool = true, timeInterval:TimeInterval = 60) {
        self.timeInterval = timeInterval
        self.isOn = isOn
        self.lastFetch = date ?? Date().addingTimeInterval(timeInterval * -1 - 1)
        triggered = triggeredSubject.eraseToAnyPublisher()
        configure()
        subjectCancellable = subject.handleEvents(receiveSubscription: subscriptionRecieved)
        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    }
    
    /// Instantiates a new AutomatedFetcher instance
    /// - Parameters:
    ///   - subject: a subject used to trigger a fetch
    ///   - lastFetch: last fetch occured
    ///   - isOn: activated or deactivated
    ///   - timeInterval: the TimeInterval of each fetch
    /// - Note: The subject is used to monitor subscriptions to a publisher. If a publisher lacks subscribes, then fethcing a new value is clearly not neccessary.
    public init(_ subject:CurrentValueSubject<DataType,Never>, lastFetch date:Date? = nil, isOn:Bool = true, timeInterval:TimeInterval = 60) {
        self.timeInterval = timeInterval
        self.isOn = isOn
        self.lastFetch = date ?? Date().addingTimeInterval(timeInterval * -1 - 1)
        triggered = triggeredSubject.eraseToAnyPublisher()
        configure()
        subjectCancellable = subject.handleEvents(receiveSubscription: subscriptionRecieved)
        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    }
    
    /// Instantiates a new AutomatedFetcher instance.
    /// - Parameters:
    ///   - subject: a subject used to trigger a fetch
    ///   - lastFetch: last fetch occured
    ///   - isOn: activated or deactivated
    ///   - timeInterval: the TimeInterval of each fetch
    /// - Note: The subject is used to monitor subscriptions to a publisher. If a publisher lacks subscribes, then fethcing a new value is clearly not neccessary.
    public init(_ subject:PassthroughSubject<DataType,Error>, lastFetch date:Date? = nil, isOn:Bool = true, timeInterval:TimeInterval = 60) {
        self.timeInterval = timeInterval
        self.isOn = isOn
        self.lastFetch = date ?? Date().addingTimeInterval(timeInterval * -1 - 1)
        triggered = triggeredSubject.eraseToAnyPublisher()
        configure()
        subjectCancellable = subject.handleEvents(receiveSubscription: subscriptionRecieved)
        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    }
    
    /// Instantiates a new AutomatedFetcher instance
    /// - Parameters:
    ///   - subject: a subject used to trigger a fetch
    ///   - lastFetch: last fetch occured
    ///   - isOn: activated or deactivated
    ///   - timeInterval: the TimeInterval of each fetch
    /// - Note: The subject is used to monitor subscriptions to a publisher. If a publisher lacks subscribes, then fethcing a new value is clearly not neccessary.
    public init(_ subject:PassthroughSubject<DataType,Never>, lastFetch date:Date? = nil, isOn:Bool = true, timeInterval:TimeInterval = 60) {
        self.timeInterval = timeInterval
        self.isOn = isOn
        self.lastFetch = date ?? Date().addingTimeInterval(timeInterval * -1 - 1)
        triggered = triggeredSubject.eraseToAnyPublisher()
        configure()
        subjectCancellable = subject.handleEvents(receiveSubscription: subscriptionRecieved)
        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    }
    
    /// Triggeres whenever the data subject recieves a subscription
    /// - Parameter sub: the subscriber
    private func subscriptionRecieved(_ sub: Subscription) {
        if self.isOn == true {
            self.triggeredSubject.send()
        }
    }
    /// Should be called when a fetch has been started
    public func started() {
        fetching = true
    }
    /// Should be called when a fetch has been completed
    public func completed() {
        fetching = false
        lastFetch = Date()
    }
    /// Should be called when a fetch has failed
    public func failed() {
        fetching = false
    }
    /// Configures the timer
    private func configure() {
        timerCancellable?.cancel()
        timerCancellable = nil
        if isOn == false {
            return
        }
        timerCancellable = Timer.publish(every: timeInterval, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.triggeredSubject.send()
            }
    }
}
