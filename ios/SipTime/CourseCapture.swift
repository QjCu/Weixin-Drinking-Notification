import SwiftUI
import PhotosUI
import Vision
import ImageIO
import WebKit
import UIKit

/// PhotosPicker grants access only to the selected image. Recognition runs on-device.
struct ScreenshotImportButton: View {
    var onRecognized: ([CourseOCRLine]) -> Void
    var onFailure: (String) -> Void
    @State private var selection: PhotosPickerItem?
    @State private var isRecognizing = false

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            HStack {
                Label(isRecognizing ? "正在识别截图…" : "选择课表截图", systemImage: "photo")
                if isRecognizing { Spacer(); ProgressView() }
            }
        }
        .disabled(isRecognizing)
        .task(id: selection) {
            guard let item = selection else { return }
            isRecognizing = true
            defer {
                isRecognizing = false
                // Clearing permits retrying the same photo after correcting/cropping or an OCR failure.
                selection = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CourseCaptureError.message("无法读取图片，请重新选择截图。")
                }
                try Task.checkCancellation()
                let lines = try await CourseScreenshotRecognizer.recognize(data: data)
                try Task.checkCancellation()
                onRecognized(lines)
            } catch is CancellationError {
                // Leaving the screen cancels importing; no error needs to be shown.
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }
}

private enum CourseCaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum CourseScreenshotRecognizer {
    static func recognize(data: Data) async throws -> [CourseOCRLine] {
        guard data.count <= 25 * 1024 * 1024 else {
            throw CourseCaptureError.message("图片超过 25 MB，请裁剪为课程结果表后重试。")
        }
        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                      width.doubleValue * height.doubleValue <= 40_000_000 else {
                    throw CourseCaptureError.message("图片无法读取或尺寸过大，请裁剪课程结果表后重试。")
                }
                // ImageIO applies EXIF orientation before Vision reads the image.
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 6000
                ]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    throw CourseCaptureError.message("无法解码图片，请使用清晰的 PNG 或 JPEG 截图。")
                }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.003
                try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                let lines = (request.results ?? []).compactMap { observation -> CourseOCRLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let bounds = observation.boundingBox
                    return CourseOCRLine(text: candidate.string, x: Double(bounds.minX), y: Double(bounds.minY),
                                         width: Double(bounds.width), height: Double(bounds.height))
                }
                guard !lines.isEmpty else {
                    throw CourseCaptureError.message("没有识别到文字。请截取完整、清晰的课程结果表，包含课程名、教室信息和选课结果。")
                }
                return lines
            }
        }.value
    }
}

/// School authentication and page extraction remain in this device's ephemeral WebKit session.
@MainActor
struct CourseWebImportView: View {
    var onCapture: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = CourseWebSession()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("学校教务网站地址", text: $browser.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { browser.openAddress() }
                    Button("前往") { browser.openAddress() }
                }
                .padding()
                Text("登录后打开选课结果页面，再点“识别当前页面”。支持北大旧版选课网及门户的 HTTP 跳转；IAAA 登录请使用 HTTPS。网页会话仅保存在本机内存中。")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.bottom, 8)
                if browser.pages.count > 1 {
                    HStack {
                        Label("网页已打开新窗口", systemImage: "rectangle.on.rectangle")
                        Spacer()
                        Button("返回上一窗口") { browser.closePopup() }
                    }
                    .font(.caption).padding(.horizontal).padding(.bottom, 8)
                }
                if let error = browser.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .padding(.horizontal).padding(.bottom, 8)
                }
                if browser.isLoading { ProgressView().frame(maxWidth: .infinity).padding(.bottom, 4) }
                CourseWebContent(pages: browser.pages)
                HStack(spacing: 28) {
                    Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!browser.canGoBack).accessibilityLabel("后退")
                    Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!browser.canGoForward).accessibilityLabel("前进")
                    Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("重新载入")
                    Spacer()
                    Text(browser.webView.url?.host ?? "尚未打开网页")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding()
            }
            .navigationTitle("从网页导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(browser.isCapturing ? "正在读取…" : "识别当前页面") {
                        Task {
                            if let html = await browser.capture() {
                                onCapture(html)
                                dismiss()
                            }
                        }
                    }
                    .disabled(browser.isLoading || browser.isCapturing || browser.webView.url == nil)
                }
            }
            .alert(browser.dialog?.title ?? "网页提示", isPresented: dialogPresentation) {
                if browser.dialog?.kind == .prompt {
                    TextField("输入内容", text: $browser.promptText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if browser.dialog?.kind != .alert {
                    Button("取消", role: .cancel) { browser.answerDialog(accepted: false) }
                }
                Button("确定") { browser.answerDialog(accepted: true) }
            } message: {
                Text(browser.dialog?.message ?? "")
            }
            .onDisappear { browser.shutdown() }
        }
    }

    private var dialogPresentation: Binding<Bool> {
        let presentedID = browser.dialog?.id
        return Binding(
            get: { presentedID != nil && browser.dialog?.id == presentedID },
            set: { if !$0 { browser.dismissDialog(id: presentedID) } }
        )
    }
}

/// Keep opener windows alive in the same view hierarchy while showing the newest popup.
/// Reusing only one WKWebView would break window.opener, postMessage and window.close.
private struct CourseWebContent: UIViewRepresentable {
    let pages: [WKWebView]
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ container: UIView, context: Context) {
        let identifiers = Set(pages.map(ObjectIdentifier.init))
        for child in container.subviews where !identifiers.contains(ObjectIdentifier(child)) {
            child.removeFromSuperview()
        }
        for page in pages {
            if page.superview !== container {
                page.frame = container.bounds
                page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(page)
            }
            page.isHidden = page !== pages.last
        }
    }
}

struct CourseWebDialog: Identifiable {
    enum Kind: Equatable { case alert, confirm, prompt }
    let id = UUID()
    let webViewID: ObjectIdentifier
    let kind: Kind
    let title: String
    let message: String
    let defaultText: String
    let completion: (Bool, String?) -> Void
}

@MainActor
final class CourseWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var address = ""
    @Published var error: String?
    @Published var isLoading = false
    @Published var isCapturing = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published private(set) var pages: [WKWebView]
    @Published private(set) var dialog: CourseWebDialog?
    @Published var promptText = ""
    var webView: WKWebView { pages.last! }
    private var queuedDialogs: [CourseWebDialog] = []
    private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var isShuttingDown = false
    private var isDismissingDialog = false
    private var displayedAddress = ""
    private var displayedURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // SSO sometimes opens its callback window after an asynchronous login request.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let root = WKWebView(frame: .zero, configuration: configuration)
        pages = [root]
        super.init()
        configure(root)
    }

    private func configure(_ page: WKWebView) {
        page.navigationDelegate = self
        page.uiDelegate = self
        page.allowsBackForwardNavigationGestures = true
        // JS history and opener-driven redirects may update URL/history without didFinish.
        observations[ObjectIdentifier(page)] = [
            page.observe(\.url, options: [.new]) { [weak self, weak page] _, _ in
                Task { @MainActor in self?.updateNavigation(ifActive: page) }
            },
            page.observe(\.isLoading, options: [.new]) { [weak self, weak page] _, _ in
                Task { @MainActor in self?.updateNavigation(ifActive: page) }
            },
            page.observe(\.canGoBack, options: [.new]) { [weak self, weak page] _, _ in
                Task { @MainActor in self?.updateNavigation(ifActive: page) }
            },
            page.observe(\.canGoForward, options: [.new]) { [weak self, weak page] _, _ in
                Task { @MainActor in self?.updateNavigation(ifActive: page) }
            }
        ]
    }

    func openAddress() {
        // The visible field omits SSO tickets, but re-opening that unchanged field must retain
        // the real URL's appID/redirectUrl/ticket parameters rather than break authentication.
        let target = address == displayedAddress ? displayedURL : CourseWebNavigationPolicy.addressURL(address)
        guard let url = target ?? CourseWebNavigationPolicy.addressURL(address) else {
            error = "请输入有效的 HTTPS 学校网址；北大旧版选课网 elective.pku.edu.cn 和门户 portal.pku.edu.cn 也支持 HTTP。"
            return
        }
        error = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
        else { closePopup() }
    }

    func closePopup() {
        guard pages.count > 1 else { return }
        removePopup(webView)
    }

    private func removePopup(_ page: WKWebView) {
        guard let index = pages.firstIndex(where: { $0 === page }), index > 0 else { return }
        let removed = Array(pages[index...])
        let identifiers = Set(removed.map(ObjectIdentifier.init))
        pages.removeSubrange(index...)
        cancelDialogs(for: identifiers)
        for child in removed {
            child.stopLoading()
            child.navigationDelegate = nil
            child.uiDelegate = nil
            observations.removeValue(forKey: ObjectIdentifier(child))
        }
        error = nil
        updateNavigation()
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        isCapturing = false
        isLoading = false
        cancelDialogs(for: Set(pages.map(ObjectIdentifier.init)))
        for page in pages {
            page.stopLoading()
            page.navigationDelegate = nil
            page.uiDelegate = nil
        }
        observations.removeAll()
        let store = pages[0].configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    func capture() async -> String? {
        guard !isShuttingDown else { return nil }
        let source = webView
        isCapturing = true
        error = nil
        defer { if !isShuttingDown { isCapturing = false } }
        do {
            // Strip inputs and scripts; credentials are never sent to the parser/server.
            let script = """
            (() => {
              const collect = (doc, depth) => {
                const root = doc.documentElement.cloneNode(true);
                root.querySelectorAll('script,style,noscript,input,textarea').forEach(e => e.remove());
                let result = root.outerHTML;
                if (depth < 3) {
                  doc.querySelectorAll('iframe,frame').forEach(frame => {
                    try {
                      if (frame.contentDocument && frame.contentDocument.documentElement) {
                        result += collect(frame.contentDocument, depth + 1);
                      }
                    } catch (_) { /* Cross-origin frames require opening their URL or a screenshot. */ }
                  });
                }
                return result;
              };
              return collect(document, 0);
            })()
            """
            guard let html = try await source.evaluateJavaScript(script) as? String, !html.isEmpty else {
                throw CourseCaptureError.message("当前页面没有可读取的内容，请先打开课程结果表。")
            }
            guard !isShuttingDown else { return nil }
            guard source === webView else {
                throw CourseCaptureError.message("网页窗口已切换，请重新识别当前页面。")
            }
            guard html.utf8.count <= 5 * 1024 * 1024 else {
                throw CourseCaptureError.message("网页内容过大，请打开仅包含课程结果的页面，或改用截图导入。")
            }
            if html.range(of: "<frame", options: .caseInsensitive) != nil ||
                html.range(of: "<iframe", options: .caseInsensitive) != nil {
                guard html.range(of: "<table", options: .caseInsensitive) != nil else {
                    throw CourseCaptureError.message("页面包含未能读取的内嵌课表。请直接打开课表所在网页，或改用截图导入。")
                }
            }
            return html
        } catch {
            guard !isShuttingDown else { return nil }
            if error is CourseCaptureError { self.error = error.localizedDescription }
            else { self.error = "读取页面失败，请等待课程页面加载完成后重试，或使用截图导入。" }
            return nil
        }
    }

    private func updateNavigation(ifActive page: WKWebView?) {
        guard let page, page === webView, !isShuttingDown else { return }
        updateNavigation()
    }

    private func updateNavigation() {
        canGoBack = webView.canGoBack || pages.count > 1
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        if let url = webView.url, let host = url.host, !host.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Callback queries can contain one-time SSO tickets; keep those out of displayed errors/screenshots.
            components.query = nil
            components.fragment = nil
            components.user = nil
            components.password = nil
            address = components.string ?? CourseWebNavigationPolicy.diagnosticTarget(url)
            displayedAddress = address
            displayedURL = url
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let requestedURL = navigationAction.request.url ??
            (navigationAction.targetFrame == nil ? URL(string: "about:blank") : nil)
        guard !isShuttingDown, let url = requestedURL else {
            decisionHandler(.cancel)
            return
        }
        // A newly created popup may first navigate its main frame to about:blank.
        let isPopupBlank = webView !== pages.first && ["about:blank", "about:srcdoc"].contains(url.absoluteString.lowercased())
        switch CourseWebNavigationPolicy.decision(for: url,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                isNewWindow: navigationAction.targetFrame == nil || isPopupBlank) {
        case .allow:
            // Let WKUIDelegate create real popup contexts. Loading into the opener breaks SSO callbacks.
            decisionHandler(.allow)
        case .block(let reason):
            error = reason
            decisionHandler(.cancel)
            updateNavigation(ifActive: webView)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !isShuttingDown else { return nil }
        let url = navigationAction.request.url ?? URL(string: "about:blank")!
        switch CourseWebNavigationPolicy.decision(for: url, isMainFrame: true, isNewWindow: true) {
        case .block(let reason): error = reason; return nil
        case .allow: break
        }
        guard pages.count < 6 else {
            error = "网页登录窗口过多，请返回上一窗口后重试。"
            return nil
        }
        // Use WebKit's supplied configuration unchanged. It preserves related-window opener,
        // process pool and the parent's ephemeral cookie store; a fresh config would break SSO.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        configure(popup)
        pages.append(popup)
        error = nil
        updateNavigation()
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) { removePopup(webView) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { error = nil; updateNavigation() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigation(ifActive: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error, in: webView)
    }

    private func showNavigationError(_ error: Error, in page: WKWebView) {
        updateNavigation(ifActive: page)
        let failure = error as NSError
        guard failure.code != NSURLErrorCancelled, !isShuttingDown else { return }
        let failingURL = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? page.url
        let target = failingURL.map(CourseWebNavigationPolicy.diagnosticTarget) ?? "学校网页"
        let description: String
        switch failure.code {
        case NSURLErrorNotConnectedToInternet: description = "当前没有网络连接"
        case NSURLErrorTimedOut: description = "连接超时，请检查校园网或稍后重试"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: description = "无法连接学校服务器"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid: description = "HTTPS 安全连接失败，请确认学校网址与系统日期"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection: description = "系统阻止了此 HTTP 连接，请使用学校的 HTTPS 入口"
        default: description = "网页加载失败（错误码 \(failure.code)），请重试或使用截图导入"
        }
        // NSError.localizedDescription can include full callback URLs, including tickets. Do not display it.
        self.error = "\(description)（\(target)）。"
    }

    private func enqueueDialog(in page: WKWebView, kind: CourseWebDialog.Kind, message: String,
                               defaultText: String = "", completion: @escaping (Bool, String?) -> Void) {
        guard !isShuttingDown, pages.contains(where: { $0 === page }) else {
            completion(false, nil)
            return
        }
        let origin = page.url.map(CourseWebNavigationPolicy.diagnosticTarget) ?? "学校网页"
        queuedDialogs.append(CourseWebDialog(webViewID: ObjectIdentifier(page), kind: kind,
            title: "网页提示 · \(origin)", message: String(message.prefix(2000)),
            defaultText: String(defaultText.prefix(2000)), completion: completion))
        showNextDialog()
    }

    private func showNextDialog() {
        guard dialog == nil, !queuedDialogs.isEmpty, !isShuttingDown, !isDismissingDialog else { return }
        let next = queuedDialogs.removeFirst()
        promptText = next.defaultText
        dialog = next
    }

    func answerDialog(accepted: Bool) {
        guard let current = dialog else { return }
        let text = promptText
        dialog = nil
        promptText = ""
        isDismissingDialog = true
        current.completion(accepted, accepted ? text : nil)
        resumeDialogsAfterDismissal()
    }

    func dismissDialog(id: UUID?) {
        guard let id else { return }
        // SwiftUI may reset an old presentation binding after its button action completed.
        // Defer and match the original ID so it cannot cancel the following queued dialog.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.dialog?.id == id else { return }
            self.answerDialog(accepted: false)
        }
    }

    private func resumeDialogsAfterDismissal() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !self.isShuttingDown else { return }
            self.isDismissingDialog = false
            self.showNextDialog()
        }
    }

    private func cancelDialogs(for identifiers: Set<ObjectIdentifier>) {
        var cancelled = queuedDialogs.filter { identifiers.contains($0.webViewID) }
        queuedDialogs.removeAll { identifiers.contains($0.webViewID) }
        if let current = dialog, identifiers.contains(current.webViewID) {
            dialog = nil
            promptText = ""
            isDismissingDialog = true
            cancelled.append(current)
            resumeDialogsAfterDismissal()
        }
        for item in cancelled { item.completion(false, nil) }
        showNextDialog()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        enqueueDialog(in: webView, kind: .alert, message: message) { _, _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        enqueueDialog(in: webView, kind: .confirm, message: message) { accepted, _ in completionHandler(accepted) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        enqueueDialog(in: webView, kind: .prompt, message: prompt, defaultText: defaultText ?? "") {
            accepted, text in completionHandler(accepted ? text : nil)
        }
    }
}
