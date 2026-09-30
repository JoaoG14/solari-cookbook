import SwiftUI
import WebKit

struct ConnectorLogo: View {
    let connector: MobileConnector
    private static let cache = NSCache<NSURL, UIImage>()
    @State private var loadedURL: URL?
    @State private var bitmap: UIImage?
    @State private var svg: Data?

    var body: some View {
        Group {
            if let bitmap {
                Image(uiImage: bitmap).resizable().scaledToFit()
            } else if let svg {
                ConnectorSVG(data: svg) { image in
                    bitmap = image
                    if let loadedURL { Self.cache.setObject(image, forKey: loadedURL as NSURL) }
                }
            } else {
                Text(String(connector.name.prefix(1))).font(.headline).foregroundStyle(.black)
            }
        }
        .padding(4).frame(width: 34, height: 34)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.12)))
        .accessibilityHidden(true)
        .task(id: connector.logoUrl) {
            bitmap = nil
            svg = nil
            let fallback = URL(string: "https://logos.composio.dev/api/\(connector.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")!
            let urls = connector.logoUrl.map { $0 == fallback ? [$0] : [$0, fallback] } ?? [fallback]
            for url in urls where url.scheme == "https" {
                if let cached = Self.cache.object(forKey: url as NSURL) {
                    bitmap = cached
                    return
                }
                do {
                    var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                    request.timeoutInterval = 15
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try Task.checkCancellation()
                    guard let response = response as? HTTPURLResponse,
                          response.statusCode == 200, data.count <= 1_000_000 else { continue }
                    if let image = UIImage(data: data) {
                        bitmap = image
                        Self.cache.setObject(image, forKey: url as NSURL)
                        return
                    }
                    if response.mimeType == "image/svg+xml" {
                        loadedURL = url
                        svg = data
                        return
                    }
                } catch {
                    if Task.isCancelled { return }
                }
            }
        }
    }
}

// Composio's logo CDN serves SVG. Render it as a non-interactive image, with scripts
// and network access disabled inside the document, rather than loading a webpage.
private struct ConnectorSVG: UIViewRepresentable {
    let data: Data
    let loaded: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(loaded: loaded) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let loaded: (UIImage) -> Void
        init(loaded: @escaping (UIImage) -> Void) { self.loaded = loaded }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait for image decoding and painting before caching a native snapshot.
            webView.callAsyncJavaScript("""
                await document.images[0].decode();
                await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
                """, arguments: [:], in: nil, in: .defaultClient) { [weak self, weak webView] result in
                guard case .success = result, let webView else { return }
                webView.takeSnapshot(with: nil) { image, _ in
                    if let image { self?.loaded(image) }
                }
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.loadHTMLString("""
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
            <style>html,body{margin:0;width:100%;height:100%;overflow:hidden}img{width:100%;height:100%;object-fit:contain}</style>
            </head><body><img alt="" src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
            """, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
