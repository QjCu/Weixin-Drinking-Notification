import SwiftUI
import PhotosUI
import Vision
import ImageIO
import WebKit

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
                    TextField("学校教务网站 HTTPS 地址", text: $browser.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { browser.openAddress() }
                    Button("前往") { browser.openAddress() }
                }
                .padding()
                Text("登录后打开选课结果页面，再点“识别当前页面”。登录和识别均在本机进行，网页会话不保存到磁盘。")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.bottom, 8)
                if let error = browser.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .padding(.horizontal).padding(.bottom, 8)
                }
                if browser.isLoading { ProgressView().frame(maxWidth: .infinity).padding(.bottom, 4) }
                CourseWebContent(webView: browser.webView)
                HStack(spacing: 28) {
                    Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
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
        }
    }
}

private struct CourseWebContent: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
private final class CourseWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var address = ""
    @Published var error: String?
    @Published var isLoading = false
    @Published var isCapturing = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func openAddress() {
        let entered = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = entered.contains("://") ? entered : "https://\(entered)"
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            error = "请输入有效的 HTTPS 学校网页地址。"
            return
        }
        error = nil
        webView.load(URLRequest(url: url))
    }

    func capture() async -> String? {
        isCapturing = true
        error = nil
        defer { isCapturing = false }
        do {
            // Strip input values and scripts. Only course page structure is needed by the parser.
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
            guard let html = try await webView.evaluateJavaScript(script) as? String,
                  !html.isEmpty else {
                throw CourseCaptureError.message("当前页面没有可读取的内容，请先打开课程结果表。")
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
            if error is CourseCaptureError {
                self.error = error.localizedDescription
            } else {
                self.error = "读取页面失败：\(error.localizedDescription) 如页面使用内嵌框架，可直接打开课表所在页面或改用截图。"
            }
            return nil
        }
    }

    private func updateNavigation() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let url = webView.url { address = url.absoluteString }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Some sign-in pages build a blank child frame before filling it locally.
        if navigationAction.request.url?.absoluteString == "about:blank",
           navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url,
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else {
            error = "此导入窗口仅支持 HTTPS 网页；也可以使用截图或粘贴内容导入。"
            isLoading = false
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            webView.load(navigationAction.request)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        error = nil
        updateNavigation()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateNavigation()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error)
    }

    private func showNavigationError(_ error: Error) {
        isLoading = false
        updateNavigation()
        if (error as NSError).code != NSURLErrorCancelled {
            self.error = "无法打开网页：\(error.localizedDescription)"
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        // Preserve useful school login validation messages instead of silently discarding alerts.
        error = message
        completionHandler()
    }
}
