// In-app web browser for Nexus Mods. Logging in here is remembered (WebKit's
// default persistent data store), "Mod Manager Download" nxm:// links are
// caught before they leave the app, and archives downloaded directly
// ("Manual download") are installed automatically.

import AppKit
import ModManagerCore
import SwiftUI
import WebKit

struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @State private var browser = BrowserController()

    var body: some View {
        VStack(spacing: 0) {
            if let current = model.browserQueue.first {
                queueBanner(current)
                Divider()
            }
            WebViewHost(webView: browser.webView)
                .overlay(alignment: .top) {
                    if browser.isLoading {
                        ProgressView(value: browser.progress)
                            .progressViewStyle(.linear)
                            .controlSize(.mini)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let active = model.downloads.first(where: { !$0.isFinished }) {
                        DownloadToast(item: active)
                            .padding()
                    }
                }
        }
        .navigationTitle(browser.title.isEmpty ? "Nexus Mods" : browser.title)
        .navigationSubtitle(browser.url?.host() ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { browser.webView.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!browser.canGoBack)
                Button { browser.webView.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!browser.canGoForward)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if browser.isLoading {
                    Button { browser.webView.stopLoading() } label: { Label("Stop", systemImage: "xmark") }
                } else {
                    Button { browser.webView.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                }
                Button {
                    browser.webView.load(URLRequest(url: URL(string: "https://www.nexusmods.com/stardewvalley")!))
                } label: {
                    Label("Stardew Valley on Nexus", systemImage: "house")
                }
                .help("Stardew Valley mods on Nexus")
                Button {
                    if let url = browser.url { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Open in Default Browser", systemImage: "safari")
                }
                .help("Open this page in your default browser")
                .disabled(browser.url == nil)
            }
        }
        .onAppear {
            browser.onNXMLink = { model.browserDidReceiveNXM($0) }
            browser.onArchiveDownloaded = { model.installBrowserDownload($0) }
            browser.onDownloadFailed = { model.show("Download Failed", $0) }
            if let request = model.browserRequest {
                browser.load(request.url)
            } else {
                // Reopened by window restoration with nothing to show.
                browser.load(URL(string: "https://www.nexusmods.com/\(NexusClient.gameDomain)")!)
            }
        }
        .onChange(of: model.browserRequest) { _, request in
            if let request { browser.load(request.url) }
        }
    }

    private func queueBanner(_ current: BrowserQueueItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(current.title) — \(model.browserQueue.count) left")
                    .font(.headline)
                Text("Click **Slow download** below. The next mod opens automatically after each download starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Skip") { model.advanceBrowserQueue() }
            Button("Stop", role: .cancel) { model.cancelBrowserQueue() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct DownloadToast: View {
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: item.state == .downloading ? item.progress : nil)
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text(item.state == .installing ? "Installing \(item.title)…" : "Downloading \(item.title)…")
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
@Observable
final class BrowserController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0

    @ObservationIgnored var onNXMLink: (URL) -> Void = { _ in }
    @ObservationIgnored var onArchiveDownloaded: (URL) -> Void = { _ in }
    @ObservationIgnored var onDownloadFailed: (String) -> Void = { _ in }
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()  // keeps the Nexus login
        webView = WKWebView(frame: .zero, configuration: configuration)
        // Present as Safari so sign-in pages don't reject an "embedded browser".
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observations = [
            webView.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.title = view.title ?? "" } },
            webView.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.url = view.url } },
            webView.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } },
            webView.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] view, _ in MainActor.assumeIsolated { self?.progress = view.estimatedProgress } },
        ]
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    // MARK: Navigation

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        switch url.scheme?.lowercased() {
        case "nxm":
            onNXMLink(url)
            decisionHandler(.cancel)
        case "http", "https", "about", "blob", "data":
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        default:
            // mailto:, steam:// etc. go to their usual apps.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    /// Links that open a new window (target="_blank") load in this one.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: Downloads

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "sdv_browser_\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            completionHandler(nil)
            return
        }
        let destination = folder.appending(path: suggestedFilename.isEmpty ? "download.zip" : suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if ModManager.archiveExtensions.contains(file.pathExtension.lowercased()) {
            onArchiveDownloaded(file)
        } else {
            // Not a mod archive: hand it to the user in Downloads instead.
            let target = URL.downloadsDirectory.appending(path: file.lastPathComponent)
            try? FileManager.default.moveItem(at: file, to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        onDownloadFailed(error.localizedDescription)
    }
}
