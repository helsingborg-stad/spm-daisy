//
//  AnalyticsTests.swift
//  
//
//  Created by Fredrik Häggbom on 2022-10-07.
//
import XCTest
import Combine
import Foundation
import Analytics

final class AnalyticsTests: XCTestCase {
    private let exampleAnalyticsName = "LaibanAppSampleAnalyticsInformation"
    private let delay = DispatchTime.now() + 0.2
    private var cancellables: Set<AnyCancellable>!
    private var analyticsService: AnalyticsService!

    override func setUp() {
        super.setUp()
        cancellables = []
        analyticsService = AnalyticsService()
    }
    
    func testPageView() {
        let expectation = self.expectation(description: "Analytics")
        var analyticsName: String?
        
        analyticsService.pageViewPublisher.sink { event in
            analyticsName = event.page
            expectation.fulfill()
        }.store(in: &cancellables)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            self.analyticsService.logPageView(self.exampleAnalyticsName)
        }
        waitForExpectations(timeout: 3)
        XCTAssertEqual(analyticsName, self.exampleAnalyticsName)
    }
    
    func testCustomEvent() {
        let expectation = self.expectation(description: "Analytics")
        var analyticsName: String?
        
        analyticsService.customPublisher.sink { event in
            analyticsName = event.name
            expectation.fulfill()
        }.store(in: &cancellables)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            self.analyticsService.log(self.exampleAnalyticsName)
        }
        waitForExpectations(timeout: 3)
        XCTAssertEqual(analyticsName, self.exampleAnalyticsName)
    }
    
    func testUserAction() {
        let expectation = self.expectation(description: "Analytics")
        var analyticsName: String?
        var userAction: String?
        let loggedUserAction = "Pressed button"
        
        analyticsService.userActionPublisher.sink { event in
            analyticsName = event.name
            userAction = event.action
            expectation.fulfill()
        }.store(in: &cancellables)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            self.analyticsService.log(self.exampleAnalyticsName, category: "", action: loggedUserAction)
        }
        waitForExpectations(timeout: 3)
        XCTAssertEqual(analyticsName, self.exampleAnalyticsName)
        XCTAssertEqual(userAction, loggedUserAction)
    }
    
    func testError() {
        let expectation = self.expectation(description: "Analytics")
        var error: String?
        
        analyticsService.errorPublisher.sink { event in
            error = (event.error as NSError).domain
            expectation.fulfill()
        }.store(in: &cancellables)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            self.analyticsService.logError(NSError.init(domain: self.exampleAnalyticsName, code:1))
        }
        waitForExpectations(timeout: 3)
        XCTAssertEqual(error, self.exampleAnalyticsName)
    }
}
