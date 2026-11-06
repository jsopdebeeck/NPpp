import AppKit
import WebKit

/// Impression et export PDF. Le document est rendu dans une vue web hors écran,
/// avec la même page que l'aperçu, en apparence claire, puis paginé par WebKit.
@MainActor
final class PrintJob: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let body: String
    private let base: String
    private let title: String
    private let destination: URL?   // nil : panneau d'impression ; sinon : PDF écrit sans panneau
    private weak var window: NSWindow?
    private var completion: ((Bool) -> Void)?
    private var keepAlive: PrintJob?

    private init(body: String, base: String, title: String, destination: URL?, window: NSWindow) {
        let info = NSPrintInfo.shared
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: info.paperSize.width, height: info.paperSize.height),
                            configuration: WKWebViewConfiguration())
        webView.appearance = NSAppearance(named: .aqua) // papier blanc, couleurs claires
        self.body = body
        self.base = base
        self.title = title
        self.destination = destination
        self.window = window
        super.init()
        webView.navigationDelegate = self
    }

    /// Lance l'impression (destination nil) ou l'export PDF vers `destination`.
    static func run(body: String, base: String, title: String, destination: URL?, window: NSWindow,
                    completion: @escaping (Bool) -> Void) {
        let job = PrintJob(body: body, base: base, title: title, destination: destination, window: window)
        job.keepAlive = job
        job.completion = completion
        job.webView.loadFileURL(PreviewTemplate.fileURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Contenu, titre, puis attente des images avant de paginer.
        let script = """
        setContent(body, base);
        document.title = title;
        await Promise.all([...document.images].map(i => i.complete ? 0 :
            new Promise(r => { i.onload = i.onerror = r; })));
        return 1;
        """
        webView.callAsyncJavaScript(script, arguments: ["body": body, "base": base, "title": title],
                                    in: nil, in: .page) { [weak self] _ in
            self?.startOperation()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

    private func startOperation() {
        guard let window else { finish(false); return }
        let info = (NSPrintInfo.shared.copy() as! NSPrintInfo)
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if let destination {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        }
        let op = webView.printOperation(with: info)
        op.jobTitle = title
        op.showsPrintPanel = destination == nil
        op.showsProgressPanel = true
        op.view?.frame = webView.bounds
        // En feuille sur la fenêtre : avec runModal() seul, WebKit produit des pages blanches.
        op.runModal(for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish(success)
    }

    private func finish(_ success: Bool) {
        completion?(success)
        completion = nil
        keepAlive = nil
    }
}
