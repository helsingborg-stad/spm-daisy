//
//  Shout.swift
//  LaibanApp-iOS
//
//  Created by Tomas Green on 2020-03-03.
//  Copyright © 2020 Evry AB. All rights reserved.
//

import Foundation
import Combine
import os.log

/// Converts a value to Any
/// - Returns: Any-representable value
private func unwrap<T>(_ any: T) -> Any {
    let mirror = Mirror(reflecting: any)
    guard mirror.displayStyle == .optional, let first = mirror.children.first else {
        return any
    }
    return first.value
}

public protocol Shoutable {
    static var log:Shout.Publisher { get }
}

/// An abstraction layer on top of OSLog with level/severity categorisation and combine-publisher features
public class Shout: ObservableObject {
    /// Event subject for publishing
    public typealias Subject = PassthroughSubject<Event,Never>
    /// Event publisher
    public typealias Publisher = AnyPublisher<Event,Never>
    /// Describes a shoutable event
    public struct Event: Equatable {
        /// The severity level.
        public enum Level : String, Equatable {
            /// Informational event
            case info
            /// Some kind of warning
            case warning
            /// An outright failure
            case error
            /// Returns an amoji describing the level
            public var emoji:String {
                switch self  {
                case .info: return "ℹ️"
                case .warning: return "⚠️"
                case .error: return "🚫"
                }
            }
        }
        /// The level/severity of the event
        public let level:Level
        /// The originating filename
        public let filename:String
        /// The originating line number
        public let lineNumber:Int
        /// The originating line function
        public let function:String
        /// The event message
        public let message:String
        /// A description containing all properties according to a specific format "emoji [filename:function:lineNumber] messsage"
        public let description:String
        /// Instansiates a new Event and assigns description
        /// - Parameters:
        ///    - items: an array of items mapped to a message
        ///    - level: the severity/level, `.info` default
        ///    - filename: the originating filename, `#file` default
        ///    - lineNumber: the originating line number, `#line` default
        ///    - function: the originating line function, `#function` default
        public init (_ items: [Any], level:Level = .info, filename: String = #file, lineNumber: Int = #line, function: String = #function) {
            self.message = items.compactMap({ (item) -> String in
                return String(describing: unwrap(item))
            }).joined(separator: " ")
            self.level = level
            self.filename = filename
            self.lineNumber = lineNumber
            self.function = function
            self.description = "\(level.emoji) [" + String(filename.split(separator: "/").last ?? "NOFILE") + ":\(function):\(lineNumber)] " + message
        }
        /// Creates an info-event with the provided properties
        /// - Parameters:
        ///   - items: an array of items mapped to a message
        ///   - filename: the originating filename, `#file` default
        ///   - lineNumber: the originating line number, `#line` default
        ///   - function: the originating line function, `#function` default
        /// - Returns: an Event instantiated with the provided properties and level `info`
        public static func info(_ items: Any..., filename: String = #file, lineNumber: Int = #line, function: String = #function) -> Event {
            return Event(items, level:.info, filename: filename, lineNumber: lineNumber, function: function)
        }
        /// Creates a warning-event with the provided properties
        /// - Parameters:
        ///   - items: an array of items mapped to a message
        ///   - filename: the originating filename, `#file` default
        ///   - lineNumber: the originating line number, `#line` default
        ///   - function: the originating line function, `#function` default
        /// - Returns: an Event instantiated with the provided properties and level `warning`
        public static func warning(_ items: Any..., filename: String = #file, lineNumber: Int = #line, function: String = #function) -> Event {
            return Event(items, level:.warning, filename: filename, lineNumber: lineNumber, function: function)
        }
        /// Creates an error-event with the provided properties
        /// - Parameters:
        ///   - items: an array of items mapped to a message
        ///   - filename: the originating filename, `#file` default
        ///   - lineNumber: the originating line number, `#line` default
        ///   - function: the originating line function, `#function` default
        /// - Returns: an Event instantiated with the provided properties and level `error`
        public static func error(_ items: Any..., filename: String = #file, lineNumber: Int = #line, function: String = #function) -> Event {
            return Event(items, level:.error, filename: filename, lineNumber: lineNumber, function: function)
        }
    }
    /// The category, or label of the instance
    public let category: String
    /// Whether or not instance will write to `os_log` or not
    public var disabled = false
    /// Event-publisher subject
    private let subject = Subject()
    /// Event-publisher
    public var publisher:Publisher
    /// An OSLog instance used for logging events
    private let logger: OSLog
    /// Logging publishers attached.
    private var publishers = Set<AnyCancellable>()
    /// Instantiates a new instance with a category/label
    /// - Parameter category: the category/label
    public init(_ category: String) {
        self.category = category
        self.publisher = subject.eraseToAnyPublisher()
        self.logger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "unknown app", category: category)
    }
    /// Writes an info-event to the log using the provided properties
    /// - Parameters:
    ///   - items: an array of items mapped to a message
    ///   - filename: the originating filename, `#file` default
    ///   - lineNumber: the originating line number, `#line` default
    ///   - function: the originating line function, `#function` default
    public func info(_ items: Any..., filename: String = #file, lineNumber: Int = #line, function: String = #function) {
        log(Event.info(items,filename: filename,lineNumber: lineNumber,function: function))
    }
    /// Writes a warning-event to the log using the provided properties
    /// - Parameters:
    ///   - items: an array of items mapped to a message
    ///   - filename: the originating filename, `#file` default
    ///   - lineNumber: the originating line number, `#line` default
    ///   - function: the originating line function, `#function` default
    public func warning(_ items: Any..., filename: String = #file, lineNumber: Int = #line, function: String = #function) {
        log(Event.warning(items,filename: filename,lineNumber: lineNumber,function: function))
    }
    /// Writes an error-event to the log using the provided properties
    /// - Parameters:
    ///   - items: an array of items mapped to a message
    ///   - filename: the originating filename, `#file` default
    ///   - lineNumber: the originating line number, `#line` default
    ///   - function: the originating line function, `#function` default
    public func error(_ items: Any..., filename: String = #file, lineNumber: Int = #line, function: String = #function) {
        log(Event.error(items,filename: filename,lineNumber: lineNumber,function: function))
    }
    /// Log an event and publish via subject
    /// - Parameter event: the event to publish / log
    private func log(_ event:Event) {
        if disabled {
            return
        }
        subject.send(event)
        os_log("%@", event.description)
    }
    /// Attaches a log publisher to the instance. When the `Publisher` triggers the assign event will be written to the log
    /// - Parameter publisher: the event publisher
    public func attach(_ publisher:Publisher) {
        publisher.sink { [weak self] event in
            self?.log(event)
        }.store(in: &publishers)
    }
}
