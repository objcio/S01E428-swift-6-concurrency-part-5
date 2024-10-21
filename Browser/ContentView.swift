import SwiftUI
import Observation
import WebKit

struct Page: Identifiable, Hashable {
    var id = UUID()
    var url: URL
    var title: String = "No title"
    var fullText: String?
    var lastUpdated: Date = .now
    var snapshot: Data?
}


@Observable
class Store {
    var pages: [Page] = [
        .init(url: .init(string: "https://www.objc.io")!),
        .init(url: .init(string: "https://www.apple.com")!)
    ]

    func submit(_ url: URL) {
        pages.append(Page(url: url))
    }
}

class Box<A> {
    var value: A
    init(_ value: A) {
        self.value = value
    }
}

struct NoWebViewError: Error {}

struct WebViewProxy {
    var box: Box<WKWebView?> = Box(nil)

    @MainActor
    func takeSnapshot() async throws -> NSImage {
        guard let w = box.value else { throw NoWebViewError() }
        return try await w.takeSnapshot(configuration: nil)
    }
}

extension EnvironmentValues {
    @Entry var webViewBox: Box<WKWebView?>?
}

struct WebViewReader<Content: View>: View {
    @State private var proxy = WebViewProxy()
    @ViewBuilder var content: (WebViewProxy) -> Content
    var body: some View {
        content(proxy)
            .environment(\.webViewBox, proxy.box)
    }
}

struct WebView: NSViewRepresentable {
    var url: URL

    class Coordinator: NSObject, WKNavigationDelegate {
    }

    func makeCoordinator() -> Coordinator {
        .init()
    }

    func makeNSView(context: Context) -> WKWebView {
        let result = WKWebView()
        result.navigationDelegate = context.coordinator
        return result
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.environment.webViewBox?.value = nsView
        if nsView.url != url {
            let request = URLRequest(url: url)
            nsView.load(request)
        }
    }
}

struct ContentView: View {
    @State var store = Store()
    @State var currentURLString: String = "https://www.objc.io"
    @State var selectedPage: Page.ID?
    @State var image: NSImage?

    var body: some View {
        WebViewReader { proxy in
            NavigationSplitView(sidebar: {
                List(selection: $selectedPage) {
                    ForEach(store.pages) { page in
                        Text(page.url.absoluteString)
                    }
                }
            }, detail: {
                if let s = selectedPage, let page = store.pages.first(where: { $0.id == s }) {
                    WebView(url: page.url)
                        .overlay {
                            if let i = image {
                                Image(nsImage: i)
                                    .scaleEffect(0.5)
                                    .border(Color.red)
                            }
                        }
                } else {
                    ContentUnavailableView("No page selected", systemImage: "globe")
                }
            })
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TextField("URL", text: $currentURLString)
                        .onSubmit {
                            if let u = URL(string: currentURLString) {
                                currentURLString = ""
                                store.submit(u)
                            }
                        }
                }
            }
            .toolbar {
                Button("Snapshot Alt") {
                    Task {
                        image = try await proxy.takeSnapshot()
                    }
                }
            }
            .onAppear {
                test()
            }
        }
    }
}

#Preview {
    ContentView()
}
