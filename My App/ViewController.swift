//
//  ViewController.swift
//  STR Express
//
//  Created by Muhammad on 7/7/23.
//

import UIKit
import WebKit
import OneSignalFramework

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, OSPushSubscriptionObserver {

    let reachability = try! Reachability()
    var hasLoadedInitialPage = false

    lazy var webview: WKWebView = {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = prefs

        // CRITICAL FOR QR SCANNER: Allows the camera feed to play inside the webview
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Native bridge for opening external links from JS (window.webkit.messageHandlers.openExternal)
        let contentController = WKUserContentController()
        contentController.add(self, name: "openExternal")
        configuration.userContentController = contentController

        let webVew = WKWebView(frame: .zero, configuration: configuration)
        webVew.translatesAutoresizingMaskIntoConstraints = false
        webVew.scrollView.contentInsetAdjustmentBehavior = .never

        // Append our Native App signature to the User-Agent (passes Strict Native App Lock & allows OAuth)
        webVew.evaluateJavaScript("navigator.userAgent") { (result, _) in
            if let defaultUA = result as? String {
                webVew.customUserAgent = defaultUA + " MyAppNativeWebView/1.0"
            } else {
                webVew.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 MyAppNativeWebView/1.0"
            }
        }

        return webVew
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        view.addSubview(webview)

        webview.navigationDelegate = self
        webview.uiDelegate = self

        // --- SAFE AREA LAYOUT FIX ---
        NSLayoutConstraint.activate([
            webview.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webview.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webview.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Listen for OneSignal subscription changes so first-time installs register their Player ID immediately
        OneSignal.User.pushSubscription.addObserver(self)

        // 1. Get OneSignal Player ID
        let userId = OneSignal.User.pushSubscription.id ?? "0000"

        // 2. Get App Version Name (CFBundleShortVersionString) & Build Number (CFBundleVersion)
        let versionName = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let versionCode = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        // 3. Build URL with version parameters (matches your Android app parameters!)
        let baseUrl = "https://haivglobal.com/myapp/app/"
        let urlString = "\(baseUrl)?app=yes&ios=yes&playerid=\(userId)&versionname=\(versionName)&versioncode=\(versionCode)"

        guard let url = URL(string: urlString) else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("ios_android_app", forHTTPHeaderField: "X-MyApp-Client")

        reachability.whenReachable = { [weak self] _ in
            guard let self = self else { return }
            if !self.hasLoadedInitialPage {
                self.hasLoadedInitialPage = true
                self.webview.load(request)
            }
        }

        reachability.whenUnreachable = { [weak self] _ in
            guard let self = self else { return }
            if let networkVC = self.storyboard?.instantiateViewController(withIdentifier: "NetworkErrorViewController") as? NetworkErrorViewController {
                self.present(networkVC, animated: true)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(internetChanged), name: Notification.Name.reachabilityChanged, object: reachability)

        do {
            try reachability.startNotifier()
        } catch {
            print("Could not start notifier")
        }
    }

    // Automatically push OneSignal Player ID into WebView as soon as iOS generates it
    func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        if let newPlayerId = state.current.id, !newPlayerId.isEmpty {
            DispatchQueue.main.async {
                self.webview.evaluateJavaScript("if(window.setOneSignalPlayerId){ window.setOneSignalPlayerId('\(newPlayerId)'); }", completionHandler: nil)
            }
        }
    }

    // Re-inject Player ID when page finishes loading
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let currentPid = OneSignal.User.pushSubscription.id, !currentPid.isEmpty {
            webView.evaluateJavaScript("if(window.setOneSignalPlayerId){ window.setOneSignalPlayerId('\(currentPid)'); }", completionHandler: nil)
        }
    }

    // Handle JS message handler: window.webkit.messageHandlers.openExternal.postMessage(url)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "openExternal", let urlStr = message.body as? String, let url = URL(string: urlStr) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // Intercept external links (?u=username, open_external=1, social links, FIB, tel:) and open in Safari / Native Apps
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let urlStr = url.absoluteString

        // 1. Open Public Storefront links (?u=username) in external Safari
        if urlStr.contains("open_external=1") || urlStr.contains("?u=") || urlStr.contains("&u=") || urlStr.contains("/myapp/u/") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        // 2. Keep Facebook OAuth login dialogs inside WebView
        if urlStr.contains("facebook.com/v") || urlStr.contains("facebook.com/login") || urlStr.contains("facebook.com/dialog/oauth") {
            decisionHandler(.allow)
            return
        }

        // 3. Open Social Media, WhatsApp, and FIB links externally
        if urlStr.contains("tiktok.com") || urlStr.contains("snapchat.com") ||
           urlStr.contains("instagram.com") || urlStr.contains("wa.me") ||
           urlStr.contains("whatsapp.com") || urlStr.contains("fib.iq") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        // 4. Handle tel:, mailto:, and custom schemes
        if let scheme = url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    // Automatically grant Camera permission inside WKWebView (iOS 15+)
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    @objc func internetChanged(note: Notification) {
        // Handled by reachability closures
    }
}
