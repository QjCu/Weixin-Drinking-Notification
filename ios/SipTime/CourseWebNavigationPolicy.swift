import Foundation

/// Navigation rules shared by the address bar, normal frames and sign-in popups.
/// Legacy course/portal callbacks use HTTP; the IAAA password page remains HTTPS.
enum CourseWebNavigationPolicy {
    static let defaultSchoolAddress = "http://elective.pku.edu.cn/"

    enum Decision: Equatable {
        case allow
        case block(String)
    }

    static let legacyHTTPHosts: Set<String> = ["elective.pku.edu.cn", "portal.pku.edu.cn"]

    /// WebKit represents window.open() without arguments as a non-nil, empty URL.
    /// It creates a blank popup context, rather than navigating the address bar.
    static func navigationURL(_ url: URL?, isNewWindow: Bool) -> URL? {
        if isNewWindow, url == nil || url?.absoluteString.isEmpty == true {
            return URL(string: "about:blank")
        }
        return url
    }

    static func addressURL(_ input: String) -> URL? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let value = input.contains("://") ? input : "https://" + input
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              decision(for: url, isMainFrame: true, isNewWindow: false) == .allow else { return nil }
        return url
    }

    static func decision(for url: URL, isMainFrame: Bool, isNewWindow: Bool) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about", !isMainFrame || isNewWindow,
           ["about:blank", "about:srcdoc"].contains(url.absoluteString.lowercased()) {
            return .allow
        }
        guard let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else {
            return .block("登录跳转地址无效或包含内嵌凭据，请从学校网站入口重新打开。")
        }
        if scheme == "https" { return .allow }
        if scheme == "http", legacyHTTPHosts.contains(host), url.port == nil || url.port == 80 {
            return .allow
        }
        if scheme == "http" {
            return .block("已阻止未适配的 HTTP 跳转（\(diagnosticTarget(url))）。当前仅兼容北大选课网和校内门户的旧版 HTTP 页面；认证页面请使用 HTTPS。")
        }
        return .block("暂不支持此登录跳转（\(scheme.isEmpty ? "未知协议" : scheme)）。请使用学校网页入口，或登录后通过截图导入。")
    }

    /// Never surface URLs' query, fragment, userinfo or path, which may carry SSO tickets.
    static func diagnosticTarget(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "unknown"
        let host = url.host?.lowercased() ?? "unknown"
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
