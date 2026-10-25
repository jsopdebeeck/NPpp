import AppKit
import WebKit

enum ViewMode: String, Codable { case text, split, preview }

/// Un onglet = une fenêtre (onglets natifs macOS) contenant un éditeur et un aperçu.
final class EditorController: NSWindowController, NSWindowDelegate, NSTextViewDelegate,
                              WKNavigationDelegate, NSToolbarDelegate, FindBarDelegate {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx"]

    private(set) var url: URL?
    var untitledName: String
    var lineEnding: LineEnding { didSet { layoutManager.lineEnding = lineEnding; textView.needsDisplay = true; refreshChrome() } }
    var encoding: TextEncoding { didSet { refreshChrome() } }
    private var savedText: String
    private var savedLineEnding: LineEnding
    private var savedEncoding: TextEncoding
    private var fileDate: Date?
    private(set) var mode: ViewMode = .text

    let textStorage = NSTextStorage()
    let layoutManager = EditorLayoutManager()
    let textView: NSTextView
    let scrollView = NSScrollView()
    private let splitView = NSSplitView()
    private let findBar = FindBar()
    private let statusLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl()
    private var webView: WKWebView?
    private var previewLoaded = false
    private var refreshWork: DispatchWorkItem?
    private var findWork: DispatchWorkItem?
    private var wordCount = 0
    private var lastDirty: Bool?
    private var pendingSelection = 0

    var app: AppDelegate { NSApp.delegate as! AppDelegate }
    var text: String { textView.string }
    var isDirty: Bool { text != savedText || lineEnding != savedLineEnding || encoding != savedEncoding }
    var isMarkdown: Bool { if case .markdown = kind { return true } else { return false } }

    /// Langage choisi à la main (menu Langage) : "plain", "markdown" ou l'identifiant d'un langage.
    var languageOverride: String? { didSet { highlight(force: true); pushPreview(); updateStatus(); app.scheduleSave() } }

    enum DocKind {
        case markdown, code(SyntaxLanguage), plain
        var id: String {
            switch self {
            case .markdown: return "markdown"
            case .plain: return "plain"
            case .code(let l): return l.id
            }
        }
        var name: String {
            switch self {
            case .markdown: return "Markdown"
            case .plain: return "Texte brut"
            case .code(let l): return l.name
            }
        }
    }

    /// Nature du document : choix manuel, sinon extension, nom de fichier ou ligne #!.
    var kind: DocKind {
        if let o = languageOverride {
            if o == "markdown" { return .markdown }
            if let l = Syntax.language(id: o) { return .code(l) }
            return .plain
        }
        let ns = text as NSString
        let firstLine = ns.length == 0 ? "" : ns.substring(to: min(ns.length, 200)).components(separatedBy: "\n")[0]
        if let url, Self.markdownExtensions.contains(url.pathExtension.lowercased()) { return .markdown }
        if let lang = Syntax.detect(url: url, firstLine: firstLine) { return .code(lang) }
        return url == nil ? .markdown : .plain
    }
    private var lastKindID = ""
    var displayName: String { url?.lastPathComponent ?? untitledName }
    var isPristineBlank: Bool { url == nil && text.isEmpty }
    var fileURL: URL? { url }

    // MARK: - Création

    init(url: URL?, file: TextFile, savedText: String? = nil, savedLineEnding: LineEnding? = nil,
         savedEncoding: TextEncoding? = nil, fileDate: Date?, mode: ViewMode, untitledName: String) {
        self.url = url
        self.untitledName = untitledName
        self.lineEnding = file.lineEnding
        self.encoding = file.encoding
        self.savedText = savedText ?? file.text
        self.savedLineEnding = savedLineEnding ?? file.lineEnding
        self.savedEncoding = savedEncoding ?? file.encoding
        self.fileDate = fileDate

        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        layoutManager.lineEnding = file.lineEnding

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "NPpp"
        window.isRestorable = false
        window.minSize = NSSize(width: 480, height: 300)
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self

        buildViews()
        buildToolbar()
        textView.string = file.text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        applyAppearance()
        setMode(mode, persist: false)
        refreshChrome()
        updateStatus(countWords: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func blank(name: String) -> EditorController {
        EditorController(url: nil, file: TextFile(text: "", lineEnding: .lf, encoding: .utf8),
                         fileDate: nil, mode: .text, untitledName: name)
    }

    static func open(_ url: URL, mode: ViewMode) throws -> EditorController {
        let file = try TextFile.read(url)
        return EditorController(url: url, file: file, fileDate: TextFile.modificationDate(url), mode: mode, untitledName: "")
    }

    /// Recrée un onglet depuis la session. Les modifications non enregistrées sont restaurées telles quelles.
    static func restore(_ t: TabState, untitledName: String) -> EditorController? {
        if let path = t.path {
            let url = URL(fileURLWithPath: path)
            let disk = try? TextFile.read(url)
            let date = t.fileDate.map { Date(timeIntervalSince1970: $0) }
            let c: EditorController
            if let buffer = t.text {
                let file = TextFile(text: buffer, lineEnding: t.lineEnding ?? disk?.lineEnding ?? .lf,
                                    encoding: t.encoding ?? disk?.encoding ?? .utf8)
                c = EditorController(url: url, file: file, savedText: disk?.text ?? "",
                                     savedLineEnding: disk?.lineEnding, savedEncoding: disk?.encoding,
                                     fileDate: date ?? TextFile.modificationDate(url), mode: t.mode, untitledName: "")
            } else {
                guard let disk else { return nil } // fichier disparu, rien à restaurer
                c = EditorController(url: url, file: disk, fileDate: TextFile.modificationDate(url), mode: t.mode, untitledName: "")
            }
            c.pendingSelection = t.selection
            c.languageOverride = t.language
            return c
        }
        let file = TextFile(text: t.text ?? "", lineEnding: t.lineEnding ?? .lf, encoding: t.encoding ?? .utf8)
        let c = EditorController(url: nil, file: file, savedText: "", savedLineEnding: file.lineEnding,
                                 savedEncoding: file.encoding, fileDate: nil, mode: t.mode,
                                 untitledName: t.name ?? untitledName)
        c.pendingSelection = t.selection
        c.languageOverride = t.language
        return c
    }

    func state() -> TabState {
        TabState(path: url?.path,
                 language: languageOverride,
                 name: url == nil ? untitledName : nil,
                 text: (url == nil || isDirty) ? text : nil,
                 mode: mode,
                 selection: textView.selectedRange().location,
                 fileDate: fileDate?.timeIntervalSince1970,
                 lineEnding: lineEnding,
                 encoding: encoding)
    }

    /// Appelé une fois la fenêtre affichée : restaure la position du curseur.
    func didShow() {
        let loc = min(pendingSelection, (text as NSString).length)
        guard loc > 0 else { return }
        DispatchQueue.main.async {
            self.textView.setSelectedRange(NSRange(location: loc, length: 0))
            self.textView.scrollRangeToVisible(NSRange(location: loc, length: 0))
        }
    }

    // MARK: - Vues

    private func buildViews() {
        let content = NSView()
        window!.contentView = content

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(textScrolled),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(scrollView)

        findBar.delegate = self
        findBar.isHidden = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        let statusBar = NSView()
        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [findBar, splitView, separator, statusBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBar.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])
        splitView.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        splitView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        for v in [statusBar, separator, findBar] as [NSView] {
            v.setContentHuggingPriority(.required, for: .vertical)
        }
        for v in [findBar, splitView, separator, statusBar] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeWebView() -> WKWebView {
        if let webView { return webView }
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.navigationDelegate = self
        w.setValue(false, forKey: "drawsBackground")
        w.pageZoom = app.fontSize / AppDelegate.defaultFontSize
        splitView.addArrangedSubview(w)
        webView = w
        previewLoaded = false
        w.loadFileURL(PreviewTemplate.fileURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return w
    }

    // MARK: - Barre d'outils

    private static let modeItem = NSToolbarItem.Identifier("mode")

    private func buildToolbar() {
        let tb = NSToolbar(identifier: "NPppToolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        window!.toolbar = tb
        window!.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.modeItem] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.modeItem] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.modeItem else { return nil }
        modeControl.segmentCount = 3
        let segments = [("text.alignleft", "Texte (⌘1)"), ("rectangle.split.2x1", "Côte à côte (⌘2)"), ("eye", "Aperçu (⌘3)")]
        for (i, s) in segments.enumerated() {
            modeControl.setImage(NSImage(systemSymbolName: s.0, accessibilityDescription: s.1), forSegment: i)
            modeControl.setToolTip(s.1, forSegment: i)
            modeControl.setWidth(34, forSegment: i)
        }
        modeControl.trackingMode = .selectOne
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged)
        modeControl.selectedSegment = [.text: 0, .split: 1, .preview: 2][mode]!
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = modeControl
        item.label = "Affichage"
        return item
    }

    @objc private func modeControlChanged() {
        setMode([ViewMode.text, .split, .preview][modeControl.selectedSegment])
    }

    // MARK: - Modes d'affichage

    @objc func setTextMode(_ sender: Any?) { setMode(.text) }
    @objc func setSplitMode(_ sender: Any?) { setMode(.split) }
    @objc func setPreviewMode(_ sender: Any?) { setMode(.preview) }

    func setMode(_ m: ViewMode, persist: Bool = true) {
        mode = m
        modeControl.selectedSegment = [.text: 0, .split: 1, .preview: 2][m]!
        if m != .text { _ = makeWebView() }
        scrollView.isHidden = (m == .preview)
        webView?.isHidden = (m == .text)
        splitView.adjustSubviews()
        if m == .split {
            DispatchQueue.main.async {
                self.splitView.setPosition(self.splitView.bounds.width / 2, ofDividerAt: 0)
                self.syncScroll()
            }
        }
        pushPreview()
        if let w = window, w.isVisible {
            w.makeFirstResponder(m == .preview ? webView : textView)
        }
        if persist {
            if isMarkdown { UserDefaults.standard.set(m.rawValue, forKey: "markdownMode") }
            app.scheduleSave()
        }
    }

    private func pushPreview() {
        guard mode != .text, let webView, previewLoaded else { return }
        let body: String
        switch kind {
        case .markdown: body = MarkdownRenderer.html(text)
        case .code(let lang): body = "<pre class=\"code\"><code>\(Syntax.html(text, lang))</code></pre>"
        case .plain: body = "<pre class=\"plain\">\(esc(text))</pre>"
        }
        let base = url?.deletingLastPathComponent().absoluteString ?? ""
        guard let data = try? JSONSerialization.data(withJSONObject: [body, base]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("setContent.apply(null, \(json))") { [weak self] _, _ in
            if self?.mode == .split { self?.syncScroll() }
        }
    }

    @objc private func textScrolled() {
        if mode == .split { syncScroll() }
    }

    private func syncScroll() {
        guard let webView, previewLoaded else { return }
        let clip = scrollView.contentView
        let maxY = textView.frame.height - clip.bounds.height
        let f = maxY > 0 ? min(1, max(0, clip.bounds.origin.y / maxY)) : 0
        webView.evaluateJavaScript("setScrollFraction(\(f))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        previewLoaded = true
        pushPreview()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let target = action.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if target.isFileURL {
            let ext = target.pathExtension.lowercased()
            if Self.markdownExtensions.contains(ext) || ext == "txt" {
                app.open(url: target)
            } else {
                NSWorkspace.shared.open(target)
            }
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    // MARK: - Apparence

    /// Police, interligne, retour à la ligne, invisibles : réglages communs à tous les onglets.
    func applyAppearance() {
        let font = app.editorFont
        let charWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.15
        para.defaultTabInterval = charWidth * 4
        para.tabStops = []
        baseAttributes = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: para]
        textView.typingAttributes = baseAttributes
        textView.defaultParagraphStyle = para
        layoutManager.showInvisibles = app.showInvisibles
        applyWrap(app.wraps)
        highlight(force: true)
        webView?.pageZoom = app.fontSize / AppDelegate.defaultFontSize
        textView.needsDisplay = true
    }

    private var baseAttributes: [NSAttributedString.Key: Any] = [:]

    private func applyWrap(_ wraps: Bool) {
        guard let container = textView.textContainer else { return }
        if wraps {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            textView.frame.size.width = scrollView.contentSize.width
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
    }

    private func highlight(force: Bool = false) {
        guard !textView.hasMarkedText() else { return } // ne pas casser la saisie des accents (^, ¨)
        let full = NSRange(location: 0, length: textStorage.length)
        let k = kind
        let changed = k.id != lastKindID
        lastKindID = k.id
        let tooBig = textStorage.length > 400_000
        switch k {
        case .markdown where !tooBig:
            MarkdownHighlighter.apply(to: textStorage, base: baseAttributes)
        case .code(let lang) where !tooBig:
            textStorage.beginEditing()
            textStorage.setAttributes(baseAttributes, range: full)
            if let font = baseAttributes[.font] as? NSFont {
                Syntax.apply(lang, to: textStorage, range: full, font: font)
            }
            textStorage.endEditing()
        default:
            if force || changed { textStorage.setAttributes(baseAttributes, range: full) }
        }
        if changed { updateStatus() }
    }

    /// Titre, onglet, barre d'état.
    func refreshChrome() {
        guard let w = window else { return }
        let dirty = isDirty
        w.title = displayName
        w.representedURL = url
        w.isDocumentEdited = dirty
        w.tab.title = (dirty ? "● " : "") + displayName
        w.tab.toolTip = url?.path
        lastDirty = dirty
        updateStatus()
    }

    func updateStatus(countWords: Bool = false) {
        let ns = text as NSString
        let sel = textView.selectedRange()
        let loc = min(sel.location, ns.length)
        var line = 1
        let head = ns.substring(to: loc)
        for u in head.utf16 where u == 10 { line += 1 }
        let col = loc - ns.lineRange(for: NSRange(location: loc, length: 0)).location + 1
        if countWords {
            var n = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
            wordCount = n
        }
        var parts = ["Ln \(line), Col \(col)" + (sel.length > 0 ? "  (\(sel.length) sél.)" : "")]
        parts.append("\(wordCount) mots")
        parts.append(kind.name)
        parts.append(lineEnding.rawValue)
        parts.append(encoding.name)
        statusLabel.stringValue = parts.joined(separator: "     ")
    }

    // MARK: - Édition

    func textDidChange(_ notification: Notification) {
        highlight()
        if isDirty != lastDirty { refreshChrome() } else { updateStatus() }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pushPreview()
            self?.updateStatus(countWords: true)
            if self?.findBar.isHidden == false { self?.runFind(select: false) }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        app.scheduleSave()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatus()
    }

    /// Remplacement programmatique, annulable avec ⌘Z.
    func replace(_ range: NSRange, with string: String, select: NSRange? = nil) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textStorage.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        if let select {
            let len = (text as NSString).length
            let loc = min(select.location, len)
            textView.setSelectedRange(NSRange(location: loc, length: min(select.length, len - loc)))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }

    // MARK: - Fichier

    @objc func saveDocument(_ sender: Any?) { save() }
    @objc func saveDocumentAs(_ sender: Any?) { saveAs() }

    @discardableResult
    func save() -> Bool {
        guard let url else { return saveAs() }
        return write(to: url)
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url?.lastPathComponent ?? untitledName + ".md"
        panel.directoryURL = url?.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let dest = panel.url else { return false }
        guard write(to: dest) else { return false }
        url = dest
        highlight(force: true)
        pushPreview()
        refreshChrome()
        app.scheduleSave()
        return true
    }

    private func write(to dest: URL) -> Bool {
        let file = TextFile(text: text, lineEnding: lineEnding, encoding: encoding)
        guard let data = file.encoded() else {
            let a = NSAlert()
            a.messageText = "Le texte contient des caractères impossibles à enregistrer en \(encoding.name)."
            a.informativeText = "Enregistrer en UTF-8 à la place ?"
            a.addButton(withTitle: "Enregistrer en UTF-8")
            a.addButton(withTitle: "Annuler")
            guard a.runModal() == .alertFirstButtonReturn else { return false }
            encoding = .utf8
            return write(to: dest)
        }
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
        savedText = text
        savedLineEnding = lineEnding
        savedEncoding = encoding
        fileDate = TextFile.modificationDate(dest)
        refreshChrome()
        app.scheduleSave()
        return true
    }

    /// Recharge si le fichier a changé sur le disque (Dropbox, autre éditeur…).
    func checkDisk() {
        guard let url, let date = TextFile.modificationDate(url) else { return }
        guard let known = fileDate else { fileDate = date; return }
        guard date.timeIntervalSince(known) > 0.5 else { return }
        fileDate = date
        guard let disk = try? TextFile.read(url) else { return }
        if disk.text == text {
            savedText = disk.text
            refreshChrome()
            return
        }
        if isDirty {
            let a = NSAlert()
            a.messageText = "« \(displayName) » a été modifié par une autre application."
            a.informativeText = "Vous avez aussi des modifications non enregistrées dans NPpp."
            a.addButton(withTitle: "Garder ma version")
            a.addButton(withTitle: "Recharger depuis le disque")
            guard a.runModal() == .alertSecondButtonReturn else { return }
        }
        load(disk)
    }

    private func load(_ file: TextFile) {
        let sel = textView.selectedRange()
        textView.string = file.text
        textView.undoManager?.removeAllActions()
        savedText = file.text
        savedLineEnding = file.lineEnding
        savedEncoding = file.encoding
        lineEnding = file.lineEnding
        encoding = file.encoding
        highlight(force: true)
        let len = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        pushPreview()
        refreshChrome()
        updateStatus(countWords: true)
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Fins de ligne et encodage

    @objc func setLineEnding(_ sender: NSMenuItem) {
        guard let le = sender.representedObject as? String, let new = LineEnding(rawValue: le) else { return }
        lineEnding = new
        app.scheduleSave()
    }

    @objc func setEncoding(_ sender: NSMenuItem) {
        guard let i = sender.representedObject as? Int else { return }
        encoding = TextEncoding.all[i]
        app.scheduleSave()
    }

    /// Relit le fichier en forçant un encodage (accents mal décodés).
    @objc func reopenWithEncoding(_ sender: NSMenuItem) {
        guard let url, let i = sender.representedObject as? Int else { return }
        if isDirty {
            let a = NSAlert()
            a.messageText = "Relire le fichier fera perdre les modifications non enregistrées."
            a.addButton(withTitle: "Relire")
            a.addButton(withTitle: "Annuler")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        do { load(try TextFile.read(url, forcing: TextEncoding.all[i])) }
        catch { NSAlert(error: error).runModal() }
    }

    // MARK: - Langage

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        languageOverride = id == "auto" ? nil : id
    }

    // MARK: - Fenêtre

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if app.isTerminating || !isDirty { return true }
        let a = NSAlert()
        a.messageText = "Enregistrer les modifications de « \(displayName) » ?"
        a.informativeText = "Sinon, elles seront abandonnées. ⇧⌘T rouvre l'onglet fermé."
        a.addButton(withTitle: "Enregistrer")
        a.addButton(withTitle: "Ne pas enregistrer")
        a.addButton(withTitle: "Annuler")
        switch a.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if !app.isTerminating { app.controllerClosed(self) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        checkDisk()
        if !findBar.isHidden { findBar.loadShared(); runFind(select: false) }
        app.scheduleSave()
    }

    func windowDidResize(_ notification: Notification) {
        if mode == .split { syncScroll() }
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setTextMode(_:)): item.state = mode == .text ? .on : .off
        case #selector(setSplitMode(_:)): item.state = mode == .split ? .on : .off
        case #selector(setPreviewMode(_:)): item.state = mode == .preview ? .on : .off
        case #selector(setLineEnding(_:)):
            item.state = (item.representedObject as? String) == lineEnding.rawValue ? .on : .off
        case #selector(setEncoding(_:)):
            item.state = (item.representedObject as? Int).map { TextEncoding.all[$0] == encoding } == true ? .on : .off
        case #selector(setLanguage(_:)):
            let id = item.representedObject as? String
            item.state = id == "auto" ? (languageOverride == nil ? .on : .off) : (id == kind.id ? .on : .off)
        case #selector(reopenWithEncoding(_:)), #selector(revealInFinder(_:)):
            return url != nil
        default: break
        }
        return true
    }

    // MARK: - Rechercher / Remplacer

    @objc func showFind(_ sender: Any?) { openFindBar(replace: false) }
    @objc func showReplace(_ sender: Any?) { openFindBar(replace: true) }
    @objc func findNext(_ sender: Any?) { findBarNext(findBar, backwards: false) }
    @objc func findPrevious(_ sender: Any?) { findBarNext(findBar, backwards: true) }

    @objc func useSelectionForFind(_ sender: Any?) {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { return }
        FindShared.find = (text as NSString).substring(with: sel)
        findBar.loadShared()
        if !findBar.isHidden { runFind(select: false) }
    }

    private func openFindBar(replace: Bool) {
        if mode == .preview && replace { setMode(.split) }
        let sel = textView.selectedRange()
        if sel.length > 0, sel.length < 200 {
            let s = (text as NSString).substring(with: sel)
            if !s.contains("\n") { FindShared.find = s }
        }
        findBar.loadShared()
        findBar.showsReplace = replace || (!findBar.isHidden && findBar.showsReplace)
        findBar.isHidden = false
        window?.makeFirstResponder(replace && !FindShared.find.isEmpty ? findBar.replaceField : findBar.findField)
        (window?.firstResponder as? NSTextView)?.selectAll(nil)
        runFind(select: false)
    }

    /// Compte et surligne toutes les occurrences.
    @discardableResult
    private func runFind(select: Bool) -> [NSRange] {
        let full = NSRange(location: 0, length: textStorage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        let find = FindShared.find
        guard !find.isEmpty else { findBar.setStatus(""); return [] }
        guard let re = FindEngine.regex(for: find, FindShared.options) else {
            findBar.setStatus("Regex invalide", error: true)
            return []
        }
        let matches = re.matches(in: text, range: full).map(\.range).filter { $0.length > 0 }
        let color = NSColor.systemYellow.withAlphaComponent(0.35)
        for r in matches.prefix(20_000) {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r)
        }
        if mode == .preview, let webView {
            if #available(macOS 13.0, *) {
                let cfg = WKFindConfiguration()
                cfg.caseSensitive = FindShared.options.matchCase
                webView.find(find, configuration: cfg) { _ in }
            }
        }
        updateFindStatus(matches)
        return matches
    }

    private func updateFindStatus(_ matches: [NSRange]) {
        if matches.isEmpty { findBar.setStatus("Aucun résultat", error: true); return }
        let sel = textView.selectedRange()
        if let i = matches.firstIndex(of: sel) {
            findBar.setStatus("\(i + 1) sur \(matches.count)")
        } else {
            findBar.setStatus("\(matches.count) résultat\(matches.count > 1 ? "s" : "")")
        }
    }

    func findBarChanged(_ bar: FindBar) {
        findWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let matches = self.runFind(select: false)
            // Recherche incrémentale : saute à la première occurrence après le curseur.
            let start = self.textView.selectedRange().location
            if let m = matches.first(where: { $0.location >= start }) ?? matches.first {
                self.select(m)
                self.updateFindStatus(matches)
            }
        }
        findWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func findBarNext(_ bar: FindBar, backwards: Bool) {
        if mode == .preview, let webView {
            if #available(macOS 13.0, *) {
                let cfg = WKFindConfiguration()
                cfg.backwards = backwards
                cfg.caseSensitive = FindShared.options.matchCase
                webView.find(FindShared.find, configuration: cfg) { _ in }
            }
            return
        }
        let matches = runFind(select: false)
        guard !matches.isEmpty else { NSSound.beep(); return }
        let sel = textView.selectedRange()
        let target: NSRange
        if backwards {
            target = matches.last(where: { $0.location < sel.location }) ?? matches.last!
        } else {
            let after = sel.location + sel.length
            target = matches.first(where: { $0.location >= after && $0 != sel }) ?? matches.first!
        }
        select(target)
        updateFindStatus(matches)
    }

    func findBarReplace(_ bar: FindBar) {
        let o = FindShared.options
        guard let re = FindEngine.regex(for: FindShared.find, o) else { return }
        let sel = textView.selectedRange()
        let ns = text as NSString
        if sel.length > 0, let m = re.firstMatch(in: text, options: [.anchored], range: sel), m.range == sel {
            let replacement = re.replacementString(for: m, in: ns as String, offset: 0,
                                                   template: FindEngine.template(for: FindShared.replace, o))
            replace(sel, with: replacement,
                    select: NSRange(location: sel.location + (replacement as NSString).length, length: 0))
        }
        findBarNext(bar, backwards: false)
    }

    func findBarReplaceAll(_ bar: FindBar) {
        let o = FindShared.options
        guard let re = FindEngine.regex(for: FindShared.find, o) else { return }
        let sel = textView.selectedRange()
        let range = (o.inSelection && sel.length > 0) ? sel : NSRange(location: 0, length: textStorage.length)
        let ns = text as NSString
        let count = re.numberOfMatches(in: text, range: range)
        guard count > 0 else { findBar.setStatus("Aucun résultat", error: true); return }
        let segment = ns.substring(with: range)
        let replaced = re.stringByReplacingMatches(in: segment, range: NSRange(location: 0, length: (segment as NSString).length),
                                                   withTemplate: FindEngine.template(for: FindShared.replace, o))
        replace(range, with: replaced,
                select: o.inSelection ? NSRange(location: range.location, length: (replaced as NSString).length)
                                      : NSRange(location: min(sel.location, (replaced as NSString).length), length: 0))
        runFind(select: false)
        findBar.setStatus("\(count) remplacé\(count > 1 ? "s" : "")")
    }

    func findBarClose(_ bar: FindBar) {
        findBar.isHidden = true
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: textStorage.length))
        window?.makeFirstResponder(mode == .preview ? webView : textView)
    }

    private func select(_ r: NSRange) {
        textView.setSelectedRange(r)
        textView.scrollRangeToVisible(r)
        textView.showFindIndicator(for: r)
    }
}
