//
//  AnalyticsService.swift
//  
//
//  Created by Fredrik Häggbom on 2022-10-07.
//

import Foundation
import Combine

/// Analytics proxy that will collect events from views and services of the app and publish them to listeners. The subscribers to these events should send the to the specific analytics service.
public class AnalyticsService {
    public struct PageViewEvent {
        public let page:String
        public let properties:[String:Any]?
    }
    public struct ImpressionEvent {
        public let type:String
        public let piece:String?
        public let properties:[String:Any]?
    }
    public struct ErrorEvent {
        public let error:Error
        public let properties:[String:Any]?
    }
    public struct UserActionEvent {
        public let name:String
        public let action:String
        public let category:String
        public let properties:[String:Any]?
    }
    public struct CustomEvent {
        public let name:String
        public let properties:[String:Any]?
    }
    
    private let pageViewSubject = PassthroughSubject<PageViewEvent,Never>()
    private let impressionSubject = PassthroughSubject<ImpressionEvent,Never>()
    private let errorSubject = PassthroughSubject<ErrorEvent,Never>()
    private let customSubject = PassthroughSubject<CustomEvent,Never>()
    private let userActionSubject = PassthroughSubject<UserActionEvent,Never>()
    
    public let pageViewPublisher:AnyPublisher<PageViewEvent,Never>
    public let impressionPublisher:AnyPublisher<ImpressionEvent,Never>
    public let errorPublisher:AnyPublisher<ErrorEvent,Never>
    public let customPublisher:AnyPublisher<CustomEvent,Never>
    public let userActionPublisher:AnyPublisher<UserActionEvent,Never>
    
    /// Singleton used to access the published variables of the analytics proxy
    public static var shared = AnalyticsService.init()
    
    public init() {
        pageViewPublisher = pageViewSubject.eraseToAnyPublisher()
        impressionPublisher = impressionSubject.eraseToAnyPublisher()
        errorPublisher = errorSubject.eraseToAnyPublisher()
        customPublisher = customSubject.eraseToAnyPublisher()
        userActionPublisher = userActionSubject.eraseToAnyPublisher()
    }
    public func log(_ event:String, properties:[String:Any]? = nil) {
        customSubject.send(.init(name: event, properties: properties))
    }
    public func log(_ event:String, category:String, action:String, properties:[String:Any]? = nil) {
        userActionSubject.send(.init(name: event, action: action, category: category, properties: properties))
    }
    public func logContentImpression(_ type:String, piece:String? = nil, properties:[String:Any]? = nil) {
        impressionSubject.send(.init(type: type, piece: piece, properties: properties))
    }
    public func logPageView(_ view:String, properties:[String:Any]? = nil) {
        pageViewSubject.send(.init(page: view, properties: properties))
    }
    public func logPageView(_ view:Any, properties:[String:Any]? = nil) {
        pageViewSubject.send(.init(page: String(describing: type(of: view)), properties: properties))
    }
    public func logError(_ error: Error, properties: [String: AnyHashable]? = nil) {
        errorSubject.send(.init(error: error, properties: properties))
    }
}

extension AnalyticsService {
    public enum CustomEventType: String {
        case AdminAction = "AdminAction"
        case ButtonPressed = "ButtonPressed"
        case GeneralCondition = "GeneralCondition"
        case Feedback = "Feedback"
        case InstagramMediaPressed = "InstagramMediaPressed"
    }
}
