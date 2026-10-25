import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    static let defaultFontSize: CGFloat = 14

    private(set) var controllers: [EditorController] = []
    private var closedTabs: [TabState] = []
    private(set) var isTerminating = false
    private var saveWork: DispatchWorkItem?
    private var pendingURLs: [URL] = []
    private var launched = false
    private var savedFrame: NSRect?

    // MARK: Préférences

    private let defaults = UserDefaults.standard

    var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: "fontSize")) }
        set { defaults.set(Double(min(40, max(9, newValue))), forKey: "fontSize") }
    }
    var editorFont: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var wraps: Bool { defaults.bool(forKey: "wraps") }
    var showInvisibles: Bool { defaults.bool(forKey: "showInvisibles") }
    var markdownMode: ViewMode { ViewMode(rawValue: defaults.string(forKey: "markdownMode") ?? "") ?? .preview }

    // MARK: Cycle de vie

    func applicationWillFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["fontSize": Double(Self.defaultFontSize), "wraps": true, "showInvisibles": false])
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.build()
        PreviewTemplate.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreSession()
        launched = true
        pendingURLs.forEach { open(url: $0) }
        pendingURLs = []
        // Fichiers passés en ligne de commande : NPpp fichier.md
        for arg in CommandLine.arguments.dropFirst() where !arg.hasPrefix("-") {
            let url = URL(fileURLWithPath: arg)
            if FileManager.default.fileExists(atPath: url.path) { open(url: url) }
        }
        if controllers.isEmpty { newTab(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard launched else { pendingURLs += urls; return }
        urls.forEach { open(url: $0) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let c = controllers.last { c.window?.makeKeyAndOrderFront(nil) } else { newTab(nil) }
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        currentController?.checkDisk()
    }

    /// Pas de question à la fermeture : tout (y compris le non-enregistré) est conservé dans la session.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveSessionNow()
        isTerminating = true
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Onglets

    var currentController: EditorController? {
        if let c = NSApp.keyWindow?.windowController as? EditorController { return c }
        if let c = NSApp.mainWindow?.windowController as? EditorController { return c }
        return controllers.last
    }

    private func nextUntitledName() -> String {
        let used = Set(controllers.map(\.untitledName))
        var n = 1
        while used.contains(n == 1 ? "Sans titre" : "Sans titre \(n)") { n += 1 }
        return n == 1 ? "Sans titre" : "Sans titre \(n)"
    }

    private func show(_ c: EditorController, after host: EditorController? = nil) {
        controllers.append(c)
        guard let w = c.window else { return }
        if let hostWindow = (host ?? currentController)?.window, hostWindow !== w, hostWindow.isVisible {
            let anchor = hostWindow.tabbedWindows?.last ?? hostWindow
            anchor.addTabbedWindow(w, ordered: .above)
        } else {
            if let f = savedFrame { w.setFrame(f, display: false) } else { w.center() }
            w.makeKeyAndOrderFront(nil)
            if let g = w.tabGroup, !g.isTabBarVisible { w.toggleTabBar(nil) }
        }
        w.makeKeyAndOrderFront(nil)
        c.didShow()
        scheduleSave()
    }

    @objc func newTab(_ sender: Any?) {
        show(EditorController.blank(name: nextUntitledName()))
    }

    /// Bouton « + » de la barre d'onglets.
    @objc func newWindowForTab(_ sender: Any?) { newTab(sender) }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = currentController?.fileURL?.deletingLastPathComponent()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { open(url: $0) }
    }

    func open(url: URL) {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = controllers.first(where: { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let isMarkdown = EditorController.markdownExtensions.contains(url.pathExtension.lowercased())
        let c: EditorController
        do {
            c = try EditorController.open(url, mode: isMarkdown ? markdownMode : .text)
        } catch {
            let a = NSAlert()
            a.messageText = "Impossible d'ouvrir « \(url.lastPathComponent) »."
            a.informativeText = FileManager.default.fileExists(atPath: url.path) ? error.localizedDescription : "Le fichier n'existe pas."
            a.runModal()
            return
        }
        // Remplace l'onglet vide « Sans titre » s'il est seul et intact.
        let blank = currentController.flatMap { $0.isPristineBlank ? $0 : nil }
        show(c, after: blank)
        if let blank {
            controllers.removeAll { $0 === blank }
            blank.window?.close()
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func controllerClosed(_ c: EditorController) {
        controllers.removeAll { $0 === c }
        if !c.isPristineBlank {
            closedTabs.append(c.state())
            if closedTabs.count > 30 { closedTabs.removeFirst() }
        }
        scheduleSave()
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        while let t = closedTabs.popLast() {
            if let path = t.path, let existing = controllers.first(where: { $0.fileURL?.path == path }) {
                existing.window?.makeKeyAndOrderFront(nil)
                return
            }
            if let c = EditorController.restore(t, untitledName: nextUntitledName()) {
                show(c)
                return
            }
        }
        NSSound.beep()
    }

    // MARK: Session

    private func orderedControllers() -> [EditorController] {
        var result: [EditorController] = []
        var seen = Set<ObjectIdentifier>()
        for c in controllers {
            let group = c.window?.tabbedWindows ?? [c.window].compactMap { $0 }
            for w in group {
                guard let ec = w.windowController as? EditorController,
                      controllers.contains(where: { $0 === ec }),
                      seen.insert(ObjectIdentifier(ec)).inserted else { continue }
                result.append(ec)
            }
        }
        return result
    }

    func scheduleSave() {
        guard !isTerminating else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSessionNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveSessionNow() {
        guard !isTerminating else { return }
        let ordered = orderedControllers()
        let active = currentController.flatMap { c in ordered.firstIndex(where: { $0 === c }) } ?? 0
        let frame = (currentController?.window?.frame).map { NSStringFromRect($0) }
        SessionStore.save(SessionData(tabs: ordered.map { $0.state() }, active: active, frame: frame))
    }

    private func restoreSession() {
        guard let session = SessionStore.load() else { return }
        savedFrame = session.frame.map(NSRectFromString)
        var restored: [(Int, EditorController)] = []
        for (i, t) in session.tabs.enumerated() {
            if let c = EditorController.restore(t, untitledName: nextUntitledName()) { restored.append((i, c)) }
        }
        var previous: EditorController?
        for (_, c) in restored {
            show(c, after: previous)
            previous = c
        }
        let active = restored.last(where: { $0.0 <= session.active })?.1 ?? restored.first?.1
        active?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Préférences d'affichage

    private func refreshAll() { controllers.forEach { $0.applyAppearance() } }

    @objc func biggerFont(_ sender: Any?) { fontSize += 1; refreshAll() }
    @objc func smallerFont(_ sender: Any?) { fontSize -= 1; refreshAll() }
    @objc func resetFont(_ sender: Any?) { fontSize = Self.defaultFontSize; refreshAll() }
    @objc func toggleWrap(_ sender: Any?) { defaults.set(!wraps, forKey: "wraps"); refreshAll() }
    @objc func toggleInvisibles(_ sender: Any?) { defaults.set(!showInvisibles, forKey: "showInvisibles"); refreshAll() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleWrap(_:)): item.state = wraps ? .on : .off
        case #selector(toggleInvisibles(_:)): item.state = showInvisibles ? .on : .off
        case #selector(reopenClosedTab(_:)): return !closedTabs.isEmpty
        default: break
        }
        return true
    }
}
