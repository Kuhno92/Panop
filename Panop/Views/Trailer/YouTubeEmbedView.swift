#if !os(tvOS)
    import Network
    import PanopCore
    import SwiftUI
    import WebKit

    /// YouTube's own player, in a web view: the way YouTube permits a video to be played in an app. It loads from
    /// youtube-nocookie.com (the privacy-enhanced embed), identifies the app by its bundle identifier as the page's
    /// origin (YouTube
    /// refuses an embed with no origin, "error 153"), and tells the app when the video cannot be embedded so it can say
    /// so.
    final class YouTubeEmbedBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onFailure: () -> Void = {}

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }
            if text.hasPrefix("error") {
                DispatchQueue.main.async { self.onFailure() }
            }
        }

        /// Nothing but the player: a link in it (the logo, a suggested video) is left to the system's browser.
        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                #if os(iOS)
                    UIApplication.shared.open(url)
                #else
                    NSWorkspace.shared.open(url)
                #endif
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            DispatchQueue.main.async { self.onFailure() }
        }
    }

    enum YouTubeEmbed {
        /// The page's origin: the app's identifier as an address, which YouTube accepts as the identity of the app.
        static var origin: String {
            "https://" + (Bundle.main.bundleIdentifier ?? "com.panop.panop").lowercased()
        }

        static func page(videoID: String) -> String {
            """
            <!doctype html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <meta name="referrer" content="strict-origin-when-cross-origin">
            <style>
            html,body{margin:0;height:100%;background:#000;overflow:hidden}
            #player{position:absolute;inset:0;width:100%;height:100%}
            </style>
            </head><body><div id="player"></div>
            <script src="https://www.youtube.com/iframe_api"></script>
            <script>
            function post(message){ window.webkit.messageHandlers.trailer.postMessage(message); }
            function onYouTubeIframeAPIReady(){
              new YT.Player('player', {
                host: 'https://www.youtube-nocookie.com', videoId: '\(videoID)',
                playerVars: { playsinline: 1, autoplay: 1, rel: 0, modestbranding: 1, origin: '\(origin)' },
                events: {
                  onReady: function(e){ e.target.playVideo(); post('ready'); },
                  onError: function(e){ post('error:' + e.data); }
                }
              });
            }
            </script></body></html>
            """
        }

        /// - Parameter proxy: the app's VPN tunnel, when it is on. The page and the video then load through it, on a
        ///   store of their own that keeps nothing, and never fall back to a direct connection.
        static func makeWebView(videoID: String, bridge: YouTubeEmbedBridge, proxy: ProxyEndpoint? = nil) -> WKWebView {
            let configuration = WKWebViewConfiguration()
            if let proxy, let port = NWEndpoint.Port(rawValue: UInt16(proxy.socksPort)) {
                var route = ProxyConfiguration(socksv5Proxy: .hostPort(host: .init(proxy.host), port: port))
                route.applyCredential(username: proxy.username, password: proxy.password)
                route.allowFailover = false
                let store = WKWebsiteDataStore.nonPersistent()
                store.proxyConfigurations = [route]
                configuration.websiteDataStore = store
            }
            configuration.userContentController.add(bridge, name: "trailer")
            #if os(iOS)
                configuration.allowsInlineMediaPlayback = true
            #endif
            configuration.mediaTypesRequiringUserActionForPlayback = []
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = bridge
            #if os(iOS)
                view.isOpaque = false
                view.backgroundColor = .black
                view.scrollView.isScrollEnabled = false
                view.scrollView.backgroundColor = .black
            #endif
            view.loadHTMLString(page(videoID: videoID), baseURL: URL(string: origin))
            return view
        }
    }

    #if os(iOS)
        struct YouTubeEmbedView: UIViewRepresentable {
            let videoID: String
            var proxy: ProxyEndpoint?
            var onFailure: () -> Void

            func makeCoordinator() -> YouTubeEmbedBridge {
                YouTubeEmbedBridge()
            }

            func makeUIView(context: Context) -> WKWebView {
                TrailerAudio.activate()
                context.coordinator.onFailure = onFailure
                return YouTubeEmbed.makeWebView(videoID: videoID, bridge: context.coordinator, proxy: proxy)
            }

            func updateUIView(_ view: WKWebView, context: Context) {
                context.coordinator.onFailure = onFailure
            }

            static func dismantleUIView(_ view: WKWebView, coordinator: YouTubeEmbedBridge) {
                // Stops the sound when the sheet closes.
                view.configuration.userContentController.removeScriptMessageHandler(forName: "trailer")
                view.loadHTMLString("", baseURL: nil)
            }
        }
    #else
        struct YouTubeEmbedView: NSViewRepresentable {
            let videoID: String
            var proxy: ProxyEndpoint?
            var onFailure: () -> Void

            func makeCoordinator() -> YouTubeEmbedBridge {
                YouTubeEmbedBridge()
            }

            func makeNSView(context: Context) -> WKWebView {
                context.coordinator.onFailure = onFailure
                return YouTubeEmbed.makeWebView(videoID: videoID, bridge: context.coordinator, proxy: proxy)
            }

            func updateNSView(_ view: WKWebView, context: Context) {
                context.coordinator.onFailure = onFailure
            }

            static func dismantleNSView(_ view: WKWebView, coordinator: YouTubeEmbedBridge) {
                view.configuration.userContentController.removeScriptMessageHandler(forName: "trailer")
                view.loadHTMLString("", baseURL: nil)
            }
        }
    #endif
#endif
