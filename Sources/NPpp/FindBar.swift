import AppKit

/// Options de recherche partagées par tous les onglets (comme dans Notepad++).
struct FindOptions {
    var matchCase = false
    var wholeWord = false
    var regex = false
    var extended = false     // \n \t \r \\ interprétés en mode normal
    var inSelection = false
}

enum FindShared {
    nonisolated(unsafe) static var find = ""
    nonisolated(unsafe) static var replace = ""
    nonisolated(unsafe) static var options = FindOptions()
}

enum FindEngine {
    /// Interprète \n \t \r \\ (mode étendu).
    static func unescapeExtended(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.append(c); continue }
            switch n {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": break // le texte est normalisé en \n
            case "0": out.append("\0")
            case "\\": out.append("\\")
            default: out.append("\\"); out.append(n)
            }
        }
        return out
    }

    static func regex(for find: String, _ o: FindOptions) -> NSRegularExpression? {
        guard !find.isEmpty else { return nil }
        var pattern: String
        if o.regex {
            // Le texte interne n'utilise que \n : on rend \r\n et \r? inoffensifs.
            pattern = find.replacingOccurrences(of: "\\r\\n", with: "\\n")
                .replacingOccurrences(of: "\\r?", with: "")
                .replacingOccurrences(of: "\\r", with: "")
        } else {
            let literal = o.extended ? unescapeExtended(find) : find
            if literal.isEmpty { return nil }
            pattern = NSRegularExpression.escapedPattern(for: literal)
        }
        if o.wholeWord { pattern = "\\b(?:\(pattern))\\b" }
        var opts: NSRegularExpression.Options = [.anchorsMatchLines]
        if !o.matchCase { opts.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: opts)
    }

    /// Modèle de remplacement : en regex, accepte \1 comme $1 et \n, \t.
    static func template(for replace: String, _ o: FindOptions) -> String {
        if o.regex {
            var out = ""
            var it = replace.makeIterator()
            while let c = it.next() {
                if c == "$" { out += "$"; continue }
                guard c == "\\", let n = it.next() else { out.append(c); continue }
                switch n {
                case "n": out += "\n"
                case "t": out += "\t"
                case "r": break
                case "1"..."9": out += "$\(n)"
                case "\\": out += "\\\\"
                default: out += NSRegularExpression.escapedTemplate(for: String(n))
                }
            }
            return out
        }
        let literal = o.extended ? unescapeExtended(replace) : replace
        return NSRegularExpression.escapedTemplate(for: literal)
    }
}

protocol FindBarDelegate: AnyObject {
    func findBarChanged(_ bar: FindBar)
    func findBarNext(_ bar: FindBar, backwards: Bool)
    func findBarReplace(_ bar: FindBar)
    func findBarReplaceAll(_ bar: FindBar)
    func findBarClose(_ bar: FindBar)
}

/// Barre Rechercher / Remplacer affichée en haut de l'éditeur.
final class FindBar: NSView, NSSearchFieldDelegate {
    weak var delegate: FindBarDelegate?

    let findField = NSSearchField()
    let replaceField = NSTextField()
    let countLabel = NSTextField(labelWithString: "")
    private let caseBtn = FindBar.toggle("Aa", "Respecter la casse")
    private let wordBtn = FindBar.toggle("Mot", "Mot entier uniquement")
    private let regexBtn = FindBar.toggle(".*", "Expression régulière (\\1 ou $1 dans le remplacement)")
    private let extBtn = FindBar.toggle("\\n", "Mode étendu : \\n, \\t, \\\\ (hors regex)")
    private let selBtn = FindBar.toggle("Sél.", "Remplacer dans la sélection seulement")
    private var replaceRow: NSStackView!

    var showsReplace: Bool {
        get { !replaceRow.isHidden }
        set { replaceRow.isHidden = !newValue }
    }

    var options: FindOptions {
        FindOptions(matchCase: caseBtn.state == .on, wholeWord: wordBtn.state == .on,
                    regex: regexBtn.state == .on, extended: extBtn.state == .on,
                    inSelection: selBtn.state == .on)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        findField.placeholderString = "Rechercher"
        findField.sendsSearchStringImmediately = true
        findField.sendsWholeSearchString = false
        findField.delegate = self
        (findField.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        replaceField.placeholderString = "Remplacer par"
        replaceField.delegate = self
        replaceField.bezelStyle = .roundedBezel
        for f in [findField, replaceField] as [NSTextField] {
            f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            f.controlSize = .regular
            f.lineBreakMode = .byClipping
            f.cell?.isScrollable = true
            f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.widthAnchor.constraint(equalToConstant: 118).isActive = true

        for b in [caseBtn, wordBtn, regexBtn, extBtn, selBtn] { b.target = self; b.action = #selector(optionChanged) }

        let prev = FindBar.button("chevron.up", "Précédent (⇧⌘G)", #selector(prevTapped), self)
        let next = FindBar.button("chevron.down", "Suivant (⌘G)", #selector(nextTapped), self)
        let close = FindBar.button("xmark", "Fermer (Échap)", #selector(closeTapped), self)
        close.bezelStyle = .inline
        close.isBordered = false

        let replaceBtn = NSButton(title: "Remplacer", target: self, action: #selector(replaceTapped))
        let replaceAllBtn = NSButton(title: "Tout remplacer", target: self, action: #selector(replaceAllTapped))
        for b in [replaceBtn, replaceAllBtn] { b.bezelStyle = .rounded; b.controlSize = .small; b.font = .systemFont(ofSize: 11) }

        let findRow = NSStackView(views: [findField, countLabel, prev, next, caseBtn, wordBtn, regexBtn, extBtn, close])
        replaceRow = NSStackView(views: [replaceField, replaceBtn, replaceAllBtn, selBtn])
        for row in [findRow, replaceRow!] {
            row.orientation = .horizontal
            row.spacing = 6
            row.alignment = .centerY
        }
        let stack = NSStackView(views: [findRow, replaceRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            findRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -8),
            // Champ « Remplacer » aussi large que « Rechercher ».
            replaceField.widthAnchor.constraint(equalTo: findField.widthAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        loadShared()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    /// Reprend la recherche et les options communes à tous les onglets.
    func loadShared() {
        findField.stringValue = FindShared.find
        replaceField.stringValue = FindShared.replace
        let o = FindShared.options
        caseBtn.state = o.matchCase ? .on : .off
        wordBtn.state = o.wholeWord ? .on : .off
        regexBtn.state = o.regex ? .on : .off
        extBtn.state = o.extended ? .on : .off
        selBtn.state = o.inSelection ? .on : .off
    }

    private func storeShared() {
        FindShared.find = findField.stringValue
        FindShared.replace = replaceField.stringValue
        FindShared.options = options
    }

    func setStatus(_ text: String, error: Bool = false) {
        countLabel.stringValue = text
        countLabel.textColor = error ? .systemRed : .secondaryLabelColor
    }

    // MARK: Actions

    @objc private func optionChanged() { storeShared(); delegate?.findBarChanged(self) }
    @objc private func prevTapped() { storeShared(); delegate?.findBarNext(self, backwards: true) }
    @objc private func nextTapped() { storeShared(); delegate?.findBarNext(self, backwards: false) }
    @objc private func replaceTapped() { storeShared(); delegate?.findBarReplace(self) }
    @objc private func replaceAllTapped() { storeShared(); delegate?.findBarReplaceAll(self) }
    @objc private func closeTapped() { delegate?.findBarClose(self) }

    func controlTextDidChange(_ obj: Notification) {
        storeShared()
        if (obj.object as AnyObject) === findField { delegate?.findBarChanged(self) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            storeShared()
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if control === replaceField { delegate?.findBarReplace(self) }
            else { delegate?.findBarNext(self, backwards: shift) }
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            // ⌥↩ insère un vrai retour à la ligne dans le champ.
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.findBarClose(self)
            return true
        default:
            return false
        }
    }

    // MARK: Fabrique

    private static func toggle(_ title: String, _ tip: String) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.setButtonType(.pushOnPushOff)
        b.bezelStyle = .recessed
        b.controlSize = .small
        b.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        b.toolTip = tip
        return b
    }

    private static func button(_ symbol: String, _ tip: String, _ action: Selector, _ target: AnyObject) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let b = NSButton(image: img, target: target, action: action)
        b.bezelStyle = .recessed
        b.controlSize = .small
        b.toolTip = tip
        return b
    }
}
