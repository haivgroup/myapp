//
//  ViewController.swift
//  STR Express
//
//  Created by Muhammad on 7/7/23.
//

import UIKit
import WebKit
import OneSignalFramework

class ViewController: UIViewController {

    let reachability = try! Reachability()

    let webview: WKWebView = {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = prefs
        
        // CRITICAL FOR QR SCANNER: Allows the camera feed to play inside the webview
        configuration.allowsInlineMediaPlayback = true
        
        let webVew = WKWebView(frame: .zero, configuration: configuration)
        // Disable automatic translation to use Auto Layout constraints
        webVew.translatesAutoresizingMaskIntoConstraints = false
        
        // Optional: Stops iOS from automatically adding weird gaps to your scroll view
        webVew.scrollView.contentInsetAdjustmentBehavior = .never
        
        return webVew
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Optional: Set background color to match your app's header/footer
        view.backgroundColor = .white

        view.addSubview(webview)
        
        // --- SAFE AREA LAYOUT FIX ---
        // This pins the web view specifically to the safe boundaries (avoiding notch/home bar)
        NSLayoutConstraint.activate([
            webview.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webview.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webview.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        var userId: String!
        
        // This gets the unique ID for this specific device's push subscription
        userId = OneSignal.User.pushSubscription.id
        if (userId == nil) {
            userId = "0000"
        }

        guard let url = URL(string: "http://www.strexpress20.com/application/index.php?app=yes&playerid=" + userId) else {
            return
        }

        reachability.whenReachable = { _  in
            //connected
            self.webview.load(URLRequest(url: url))
        }
            
        reachability.whenUnreachable = { _ in
            //not connected
            if let networkVC = self.storyboard?.instantiateViewController(withIdentifier: "NetworkErrorViewController") as? NetworkErrorViewController {
                self.present(networkVC, animated: true)
            }
        }
            
        NotificationCenter.default.addObserver(self, selector: #selector(internetChanged), name: Notification.Name.reachabilityChanged , object: reachability)
        
        do {
            try reachability.startNotifier()
        } catch {
            print("Could not start notifier")
        }
    }

    @objc
    func internetChanged(note: Notification) {
        //do something
    }
    
    // NOTE: viewDidLayoutSubviews() was completely removed because we are using Auto Layout now.
}
