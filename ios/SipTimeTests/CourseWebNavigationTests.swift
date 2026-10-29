import XCTest
#if canImport(SipTimeCore)
@testable import SipTimeCore
#else
@testable import SipTime
#endif

final class CourseWebNavigationTests: XCTestCase {
    private func decision(_ value: String, main: Bool = true, popup: Bool = false) -> CourseWebNavigationPolicy.Decision {
        CourseWebNavigationPolicy.decision(for: URL(string: value)!, isMainFrame: main, isNewWindow: popup)
    }

    func testIAAAHTTPSLoginAndEncodedHTTPReturnAddressArePreserved() throws {
        let login = "https://iaaa.pku.edu.cn/iaaa/oauth.jsp?appID=syllabus&redirectUrl=http%3A%2F%2Felective.pku.edu.cn%2Felective2008%2FssoLogin.do"
        let url = try XCTUnwrap(CourseWebNavigationPolicy.addressURL(login))
        XCTAssertEqual(url.absoluteString, login)
        XCTAssertEqual(decision(login), .allow)
    }

    func testLegacyPKUCallbacksCanCompleteIncludingPort80AndPopup() {
        for host in ["elective.pku.edu.cn", "portal.pku.edu.cn"] {
            XCTAssertEqual(decision("http://\(host)/ssoLogin.do?token=test-ticket"), .allow)
            XCTAssertEqual(decision("http://\(host):80/ssoLogin.do"), .allow)
            XCTAssertEqual(decision("http://\(host)/", main: false), .allow)
            XCTAssertEqual(decision("http://\(host)/", popup: true), .allow)
        }
    }

    func testOtherHTTPAndLookalikeHostsRemainBlocked() {
        for url in ["http://iaaa.pku.edu.cn/iaaa/oauth.jsp", "http://example.edu/",
                    "http://elective.pku.edu.cn.evil.example/", "http://sub.elective.pku.edu.cn/",
                    "http://elective.pku.edu.cn:8080/", "http://portal.pku.edu.cn:81/"] {
            XCTAssertNotEqual(decision(url), .allow, url)
        }
    }

    func testEmbeddedCredentialsAndLocalFileSchemesAreBlocked() {
        for url in ["https://user:secret@iaaa.pku.edu.cn/", "http://user@elective.pku.edu.cn/",
                    "file:///private/state.json", "javascript:alert(1)", "data:text/html,hello",
                    "customschool://login/success"] {
            XCTAssertNotEqual(decision(url), .allow, url)
        }
    }

    func testWindowOpenBlankAndLocalFramesWorkWithoutAllowingTypedBlankPage() {
        XCTAssertEqual(decision("about:blank", main: false), .allow)
        XCTAssertEqual(decision("about:blank", popup: true), .allow)
        XCTAssertEqual(decision("about:srcdoc", main: false), .allow)
        XCTAssertNotEqual(decision("about:blank"), .allow)
        XCTAssertNotEqual(decision("about:config", main: false), .allow)
        XCTAssertNil(CourseWebNavigationPolicy.addressURL("about:blank"))
        XCTAssertNil(CourseWebNavigationPolicy.addressURL("javascript:alert(1)"))
    }

    func testWindowOpenEmptyRequestURLBecomesBlankOnlyInNewWindowContext() throws {
        let empty = try XCTUnwrap(URL(string: ""))
        XCTAssertEqual(CourseWebNavigationPolicy.navigationURL(empty, isNewWindow: true)?.absoluteString, "about:blank")
        XCTAssertEqual(CourseWebNavigationPolicy.navigationURL(nil, isNewWindow: true)?.absoluteString, "about:blank")
        XCTAssertEqual(CourseWebNavigationPolicy.navigationURL(empty, isNewWindow: false), empty)
        XCTAssertNil(CourseWebNavigationPolicy.navigationURL(nil, isNewWindow: false))
        let callback = URL(string: "http://elective.pku.edu.cn/ssoLogin.do?token=example")!
        XCTAssertEqual(CourseWebNavigationPolicy.navigationURL(callback, isNewWindow: true), callback)
        let relative = URL(string: "not-a-blank-page")!
        XCTAssertEqual(CourseWebNavigationPolicy.navigationURL(relative, isNewWindow: true), relative)
    }

    func testAddressBarDefaultsToHTTPSAndAllowsExplicitLegacySchoolAddress() throws {
        XCTAssertEqual(try XCTUnwrap(CourseWebNavigationPolicy.addressURL(" iaaa.pku.edu.cn/iaaa/oauth.jsp \n")).scheme, "https")
        XCTAssertEqual(try XCTUnwrap(CourseWebNavigationPolicy.addressURL("http://elective.pku.edu.cn/")).scheme, "http")
        XCTAssertNil(CourseWebNavigationPolicy.addressURL(""))
        XCTAssertNil(CourseWebNavigationPolicy.addressURL("http://unrelated.example/"))
        XCTAssertNil(CourseWebNavigationPolicy.addressURL("https://user:pass@school.example/"))
    }

    func testBlockedNavigationDiagnosticDoesNotLeakTicketsOrCredentials() {
        let url = URL(string: "http://user:password@unknown.example/sensitive-path?token=private-ticket#secret")!
        XCTAssertEqual(CourseWebNavigationPolicy.diagnosticTarget(url), "http://unknown.example")
        let result = String(describing: decision("http://unknown.example/ssoLogin.do?token=private-ticket#secret"))
        XCTAssertFalse(result.contains("private-ticket"))
        XCTAssertFalse(result.contains("secret"))
        XCTAssertFalse(result.contains("ssoLogin.do"))
    }
}
