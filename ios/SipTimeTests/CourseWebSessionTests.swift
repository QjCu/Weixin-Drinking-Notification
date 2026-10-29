#if canImport(UIKit) && canImport(WebKit) && !canImport(SipTimeCore)
import XCTest
import UIKit
import WebKit
@testable import SipTime

/// Local HTML exercises the real WebKit delegate path without school accounts or network requests.
@MainActor
final class CourseWebSessionTests: XCTestCase {
    func testBlankLoginPopupPreservesOpenerSharedSessionAndClose() async throws {
        let session = CourseWebSession()
        let root = session.webView
        let window = makeWindow(containing: root)
        defer { session.shutdown(); window.isHidden = true }
        try await loadFixture(root, body: "<p>Login fixture</p>")

        _ = try await root.evaluateJavaScript("window.loginPopup = window.open('about:blank', 'login'); true;")
        try await waitUntil("Login popup was not created") { session.pages.count == 2 }
        let popup = session.webView
        attach(popup, to: window)
        try await waitForJavaScript(popup, expression: "document.body != null && window.opener != null")
        XCTAssertFalse(popup === root)
        XCTAssertFalse(root.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(popup.configuration.websiteDataStore === root.configuration.websiteDataStore)
        let hasOpener = try await popup.evaluateJavaScript("window.opener !== null") as? Bool
        XCTAssertEqual(hasOpener, true)

        // An authentication popup must retain its real window.opener and be able to close itself.
        _ = try? await popup.evaluateJavaScript("window.opener.openerResult = 'connected'; window.close(); true;")
        try await waitUntil("Closed popup did not return to its parent") { session.pages.count == 1 }
        XCTAssertTrue(session.webView === root)
        let marker = try await root.evaluateJavaScript("window.openerResult") as? String
        XCTAssertEqual(marker, "connected")
    }

    func testCaptureReadsActivePopupAndStripsFormValues() async throws {
        let session = CourseWebSession()
        let root = session.webView
        let window = makeWindow(containing: root)
        defer { session.shutdown(); window.isHidden = true }
        try await loadFixture(root, body: "<table><tr><td>parent-only-course</td></tr></table>")
        _ = try await root.evaluateJavaScript("window.loginPopup = window.open('about:blank', 'login'); true;")
        try await waitUntil("Login popup was not created") { session.pages.count == 2 }
        let popup = session.webView
        attach(popup, to: window)
        try await waitForJavaScript(popup, expression: "document.body != null && window.opener != null")
        _ = try await popup.evaluateJavaScript("""
            document.body.innerHTML = '<table><tr><td>active-popup-course</td></tr></table>' +
              '<input value="private-form-sentinel"><textarea>private-text-sentinel</textarea>';
            true;
            """)
        let captured = await session.capture()
        let html = try XCTUnwrap(captured)
        XCTAssertTrue(html.contains("active-popup-course"))
        XCTAssertFalse(html.contains("parent-only-course"))
        XCTAssertFalse(html.contains("private-form-sentinel"))
        XCTAssertFalse(html.contains("private-text-sentinel"))
    }

    func testShutdownResolvesPendingJavaScriptConfirmation() async throws {
        let session = CourseWebSession()
        let root = session.webView
        let window = makeWindow(containing: root)
        defer { session.shutdown(); window.isHidden = true }
        try await loadFixture(root, body: "<p>Confirmation fixture</p>")
        let completed = expectation(description: "JavaScript confirmation completion was released")
        let evaluation = Task {
            defer { completed.fulfill() }
            _ = try? await root.evaluateJavaScript("window.confirm('Continue fixture?'); true;")
        }
        try await waitUntil("JavaScript confirmation was not presented") { session.dialog != nil }
        session.shutdown()
        XCTAssertNil(session.dialog)
        await fulfillment(of: [completed], timeout: 10)
        evaluation.cancel()
    }

    private func loadFixture(_ webView: WKWebView, body: String) async throws {
        webView.loadHTMLString("<html><body>\(body)<script>window.fixtureReady = true;</script></body></html>",
                               baseURL: URL(string: "https://iaaa.pku.edu.cn/"))
        try await waitForJavaScript(webView, expression: "window.fixtureReady === true")
    }

    private func waitForJavaScript(_ webView: WKWebView, expression: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let value = try? await webView.evaluateJavaScript("Boolean(\(expression))"),
               value as? Bool == true { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Local WebKit fixture was not ready: \(expression)")
        throw FixtureError.timeout
    }

    private func waitUntil(_ message: String, predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 25_000_000) }
        guard predicate() else { XCTFail(message); throw FixtureError.timeout }
    }

    private func makeWindow(containing webView: WKWebView) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIViewController()
        window.rootViewController?.loadViewIfNeeded()
        attach(webView, to: window)
        window.makeKeyAndVisible()
        return window
    }

    private func attach(_ webView: WKWebView, to window: UIWindow) {
        guard let host = window.rootViewController?.view else { return }
        webView.frame = host.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(webView)
    }

    private enum FixtureError: Error { case timeout }
}
#endif
