@testable import Connectivity
import OHHTTPStubs
import UIKit
import XCTest

class ConnectivityTests: XCTestCase {
    private let timeout: TimeInterval = 5.0

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        OHHTTPStubs.removeAllStubs()
    }

    private func stubHost(_ host: String, withHTMLFrom fileName: String) {
        stub(condition: isHost(host)) { _ in
            let stubPath = OHPathForFile(fileName, type(of: self))
            return fixture(filePath: stubPath!, headers: ["Content-Type": "text/html"])
        }
    }

    func testSuccessfulConnectivityCheckUsingSysConfig() {
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")
        let expectation = XCTestExpectation(description: "Connectivity check succeeds")
        let connectivity = Connectivity()
        connectivity.framework = .systemConfiguration
        let connectivityChanged: (Connectivity) -> Void = { connectivity in
            XCTAssertEqual(connectivity.status, .connectedViaWiFi)
            expectation.fulfill()
        }
        connectivity.whenConnected = connectivityChanged
        connectivity.whenDisconnected = connectivityChanged
        connectivity.startNotifier()
        wait(for: [expectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testSuccessfulConnectivityCheckUsingNetwork() {
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")
        let expectation = XCTestExpectation(description: "Connectivity check succeeds")
        let connectivity = Connectivity()
        connectivity.framework = .network
        let connectivityChanged: (Connectivity) -> Void = { connectivity in
            XCTAssertTrue(connectivity.isConnected)
            expectation.fulfill()
        }
        connectivity.whenConnected = connectivityChanged
        connectivity.whenDisconnected = connectivityChanged
        connectivity.startNotifier()
        wait(for: [expectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testFailedConnectivityCheckUsingSysConfig() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let expectation = XCTestExpectation(description: "Connectivity checks fails")
        let connectivity = Connectivity()
        connectivity.framework = .systemConfiguration
        let connectivityChanged: (Connectivity) -> Void = { connectivity in
            XCTAssertEqual(connectivity.status, .connectedViaWiFiWithoutInternet)
            expectation.fulfill()
        }
        connectivity.whenConnected = connectivityChanged
        connectivity.whenDisconnected = connectivityChanged
        connectivity.startNotifier()
        wait(for: [expectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testFailedConnectivityCheckUsingNetwork() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let expectation = XCTestExpectation(description: "Connectivity checks fails")
        let connectivity = Connectivity()
        connectivity.framework = .network
        let connectivityChanged: (Connectivity) -> Void = { connectivity in
            XCTAssertFalse(connectivity.isConnected)
            expectation.fulfill()
        }
        connectivity.whenConnected = connectivityChanged
        connectivity.whenDisconnected = connectivityChanged
        connectivity.startNotifier()
        wait(for: [expectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testContainsStringValidation() {
        checkValidation(
            string: "a test",
            matchedBy: "test",
            expectedResult: true,
            using: .containsExpectedResponseString
        )
        checkValidation(
            string: "est",
            matchedBy: "test",
            expectedResult: false,
            using: .containsExpectedResponseString
        )
    }

    func testEqualsStringValidation() {
        checkValidation(
            string: "test",
            matchedBy: "test",
            expectedResult: true,
            using: .equalsExpectedResponseString
        )
        checkValidation(
            string: "est",
            matchedBy: "test",
            expectedResult: false,
            using: .equalsExpectedResponseString
        )
    }

    func testRegexStringValidation() {
        checkValidation(
            string: "test1234",
            matchedBy: "test[0-9]+",
            expectedResult: true,
            using: .matchesRegularExpression
        )
        checkValidation(
            string: "testa1234",
            matchedBy: "test[0-9]+",
            expectedResult: false,
            using: .matchesRegularExpression
        )
    }

    func testCustomValidation() {
        // swiftlint:disable:next nesting
        final class Validator: ConnectivityResponseValidator {
            func isResponseValid(url: URL, response _: URLResponse?, data: Data?) -> Bool {
                let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                return url.host == "example.com" &&
                    str.hasPrefix("1") &&
                    str.hasSuffix("z")
            }
        }

        let validator = Validator()
        let example = URL(string: "https://example.com")!
        XCTAssertTrue(validator.isResponseValid(
            url: example,
            response: nil,
            data: "11234z".data(using: .utf8)
        ))
        XCTAssertFalse(validator.isResponseValid(
            url: URL(string: "https://apple.com")!,
            response: nil,
            data: "11234z".data(using: .utf8)
        ))
        XCTAssertFalse(validator.isResponseValid(
            url: example,
            response: nil,
            data: "21234y".data(using: .utf8)
        ))
    }

    // MARK: - Backgrounding

    func testConnectivityCheckOnApplicationDidBecomeActive() {
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = true
        connectivity.framework = .systemConfiguration
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [disconnectedNotificationExpectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testConnectivityDoesNotCheckOnApplicationDidBecomeActive() {
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.framework = .systemConfiguration
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        disconnectedNotificationExpectation.isInverted = true
        wait(for: [disconnectedNotificationExpectation], timeout: timeout / 2)
        connectivity.stopNotifier()
    }

    // MARK: - Polling

    func testConnectivityDetectedWhenPolling() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = true
        connectivity.pollingInterval = 0.1
        connectivity.framework = .systemConfiguration
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [disconnectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testConnectivityNotDetectedWhenNotPolling() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = false
        connectivity.pollingInterval = 0.1
        connectivity.framework = .systemConfiguration
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [disconnectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        connectedNotificationExpectation.isInverted = true
        wait(for: [connectedNotificationExpectation], timeout: timeout / 2)
        connectivity.stopNotifier()
    }

    func testConnectivityDetectedWhenPollingOfflineOnlyAndConnectionOffline() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = true
        connectivity.pollWhileOfflineOnly = true
        connectivity.pollingInterval = 0.1
        connectivity.framework = .systemConfiguration
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [disconnectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testConnectivityNotDetectedWhenPollingOfflineOnlyAndConnectionOnline() {
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = true
        connectivity.pollWhileOfflineOnly = true
        connectivity.pollingInterval = 0.1
        connectivity.framework = .systemConfiguration
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        disconnectedNotificationExpectation.isInverted = true
        wait(for: [disconnectedNotificationExpectation], timeout: timeout / 2)
        connectivity.stopNotifier()
    }

    func testConnectivityDetectedWhenPollingUsingNetwork() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = true
        connectivity.pollingInterval = 0.1
        connectivity.framework = .network
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [disconnectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testConnectivityNotDetectedWhenNotPollingUsingNetwork() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = false
        connectivity.pollingInterval = 0.1
        connectivity.framework = .network
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [disconnectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        connectedNotificationExpectation.isInverted = true
        wait(for: [connectedNotificationExpectation], timeout: timeout / 2)
        connectivity.stopNotifier()
    }

    func testConnectivityDetectedWhenPollingOfflineOnlyAndConnectionOfflineUsingNetwork() {
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = true
        connectivity.pollWhileOfflineOnly = true
        connectivity.pollingInterval = 0.1
        connectivity.framework = .network
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [disconnectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)
        connectivity.stopNotifier()
    }

    func testConnectivityNotDetectedWhenPollingOfflineOnlyAndConnectionOnlineUsingNetwork() {
        stubHost("www.apple.com", withHTMLFrom: "success-response.html")
        let connectivity = Connectivity()
        connectivity.checkWhenApplicationDidBecomeActive = false
        connectivity.isPollingEnabled = true
        connectivity.pollWhileOfflineOnly = true
        connectivity.pollingInterval = 0.1
        connectivity.framework = .network
        connectivity.startNotifier()

        // First notification will be posted on invocation of `startNotifier`.
        let connectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        wait(for: [connectedNotificationExpectation], timeout: timeout)

        // In order for another notification to be posted the connectivity status will need to change.
        stubHost("captive.apple.com", withHTMLFrom: "failure-response.html")
        stubHost("www.apple.com", withHTMLFrom: "failure-response.html")

        // Posting `UIApplication.didBecomeActiveNotification` will trigger another check.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let disconnectedNotificationExpectation = expectation(
            forNotification: Notification.Name.ConnectivityDidChange,
            object: connectivity,
            handler: nil
        )
        disconnectedNotificationExpectation.isInverted = true
        wait(for: [disconnectedNotificationExpectation], timeout: timeout / 2)
        connectivity.stopNotifier()
    }
}

private extension XCTestCase {
    // Test helper for ConnectivityResponseStringValidator
    func checkValidation(
        string: String,
        matchedBy matchStr: String,
        expectedResult: Bool,
        using mode: ConnectivityResponseStringValidationMode,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let validator = ConnectivityResponseStringValidator(
            validationMode: mode,
            expectedResponse: matchStr
        )
        let result = validator.isResponseValid(
            url: URL(string: "https://example.com")!,
            response: nil,
            data: string.data(using: .utf8)
        )
        let modeStr: String
        switch mode {
        case .containsExpectedResponseString: modeStr = "contains"
        case .equalsExpectedResponseString: modeStr = "equals"
        case .matchesRegularExpression: modeStr = "regexp"
        }
        let expectedResultStr = expectedResult ? "match" : "not match"
        XCTAssertEqual(
            result,
            expectedResult,
            "Expected \"\(string)\" to \(expectedResultStr) \(matchStr) via `\(modeStr)`",
            file: file,
            line: line
        )
    }
}
