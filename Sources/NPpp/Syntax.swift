import AppKit

/// Types de jetons colorés. La valeur brute sert d'index dans la palette et de classe CSS (tk-N).
enum TokenKind: UInt8 {
    case none = 0, keyword, string, comment, number, type, function, variable,
         constant, tag, attribute, meta, inserted, deleted
}

/// Règle : un motif regex (les groupes internes sont permis) et le type de jeton à peindre.
/// `inner` repeint l'intérieur du jeton (ex. les variables $X dans une chaîne Bash).
struct SyntaxRule {
    let pattern: String
    let kind: TokenKind
    var inner: [SyntaxRule] = []

    init(_ pattern: String, _ kind: TokenKind, inner: [SyntaxRule] = []) {
        self.pattern = pattern
        self.kind = kind
        self.inner = inner
    }
}

/// Une grammaire compilée en une seule regex d'alternatives : le texte est parcouru de gauche
/// à droite et la première alternative qui correspond gagne, ce qui évite de colorer un # dans
/// une chaîne ou un mot-clé dans un commentaire.
final class RuleSet {
    let regex: NSRegularExpression
    private let groups: [(index: Int, rule: SyntaxRule, inner: RuleSet?)]

    init(_ rules: [SyntaxRule], caseInsensitive: Bool) {
        var parts: [String] = []
        var groups: [(Int, SyntaxRule, RuleSet?)] = []
        var next = 1
        for r in rules {
            parts.append("(\(r.pattern))")
            let inner = r.inner.isEmpty ? nil : RuleSet(r.inner, caseInsensitive: caseInsensitive)
            groups.append((next, r, inner))
            let sub = (try? NSRegularExpression(pattern: r.pattern))?.numberOfCaptureGroups ?? 0
            next += 1 + sub
        }
        var opts: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { opts.insert(.caseInsensitive) }
        regex = try! NSRegularExpression(pattern: parts.joined(separator: "|"), options: opts)
        self.groups = groups
    }

    func paint(_ s: String, _ range: NSRange, into buf: inout [UInt8]) {
        regex.enumerateMatches(in: s, range: range) { m, _, _ in
            guard let m, m.range.length > 0 else { return }
            for g in groups where m.range(at: g.index).location != NSNotFound {
                let r = m.range
                buf.withUnsafeMutableBufferPointer { p in
                    for i in r.location..<NSMaxRange(r) { p[i] = g.rule.kind.rawValue }
                }
                g.inner?.paint(s, r, into: &buf)
                break
            }
        }
    }
}

/// Inclusion d'un autre langage dans une zone (JS dans <script>, code dans un bloc Markdown…).
struct SyntaxEmbed {
    let pattern: String
    let contentGroup: Int
    let languageGroup: Int?   // nom du langage lu dans le texte (bloc ```python)
    let languageID: String?   // ou langage fixe
}

final class SyntaxLanguage {
    let id: String
    let name: String
    let extensions: [String]
    let fileNames: [String]
    let shebangs: [String]
    let aliases: [String]
    private let ruleSpecs: [SyntaxRule]
    private let caseInsensitive: Bool
    let embeds: [SyntaxEmbed]

    private lazy var ruleSet = RuleSet(ruleSpecs, caseInsensitive: caseInsensitive)

    init(id: String, name: String, extensions: [String] = [], fileNames: [String] = [], shebangs: [String] = [],
         aliases: [String] = [], caseInsensitive: Bool = false, embeds: [SyntaxEmbed] = [], rules: [SyntaxRule]) {
        self.id = id
        self.name = name
        self.extensions = extensions
        self.fileNames = fileNames
        self.shebangs = shebangs
        self.aliases = aliases
        self.caseInsensitive = caseInsensitive
        self.embeds = embeds
        self.ruleSpecs = rules
    }

    /// Peint `range` de `s` dans `buf` (un octet TokenKind par unité UTF-16).
    func paint(_ s: String, _ range: NSRange, into buf: inout [UInt8]) {
        ruleSet.paint(s, range, into: &buf)
        for e in embeds {
            RX.re(e.pattern, [.anchorsMatchLines, .caseInsensitive]).enumerateMatches(in: s, range: range) { m, _, _ in
                guard let m else { return }
                let content = m.range(at: e.contentGroup)
                guard content.location != NSNotFound, content.length > 0 else { return }
                var lang: SyntaxLanguage?
                if let id = e.languageID { lang = Syntax.language(id: id) }
                if let g = e.languageGroup, m.range(at: g).location != NSNotFound {
                    lang = Syntax.language(named: (s as NSString).substring(with: m.range(at: g)))
                }
                guard let lang, lang !== self else { return }
                buf.withUnsafeMutableBufferPointer { p in
                    for i in content.location..<NSMaxRange(content) { p[i] = 0 }
                }
                lang.paint(s, content, into: &buf)
            }
        }
    }

    func paint(_ s: String) -> [UInt8] {
        let n = (s as NSString).length
        var buf = [UInt8](repeating: 0, count: n)
        paint(s, NSRange(location: 0, length: n), into: &buf)
        return buf
    }
}

// MARK: - Rendu (éditeur et aperçu)

enum Syntax {
    /// Parcourt les plages consécutives de même type.
    static func runs(_ buf: [UInt8], offset: Int = 0, _ body: (NSRange, TokenKind) -> Void) {
        var i = 0
        while i < buf.count {
            let k = buf[i]
            var j = i + 1
            while j < buf.count && buf[j] == k { j += 1 }
            if k != 0, let kind = TokenKind(rawValue: k) { body(NSRange(location: offset + i, length: j - i), kind) }
            i = j
        }
    }

    /// Colore `range` d'un NSTextStorage (les attributs de base doivent déjà être posés).
    static func apply(_ lang: SyntaxLanguage, to storage: NSTextStorage, range: NSRange, font: NSFont) {
        let s = storage.string
        var buf = [UInt8](repeating: 0, count: (s as NSString).length)
        lang.paint(s, range, into: &buf)
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        let slice = Array(buf[range.location..<NSMaxRange(range)])
        runs(slice, offset: range.location) { r, kind in
            storage.addAttribute(.foregroundColor, value: SyntaxTheme.color(kind), range: r)
            if kind == .comment { storage.addAttribute(.font, value: italic, range: r) }
        }
    }

    /// HTML coloré (pour l'aperçu).
    static func html(_ code: String, _ lang: SyntaxLanguage) -> String {
        let ns = code as NSString
        let buf = lang.paint(code)
        var out = ""
        var last = 0
        runs(buf) { r, kind in
            if r.location > last { out += esc(ns.substring(with: NSRange(location: last, length: r.location - last))) }
            out += "<span class=\"tk-\(kind.rawValue)\">\(esc(ns.substring(with: r)))</span>"
            last = NSMaxRange(r)
        }
        if last < ns.length { out += esc(ns.substring(from: last)) }
        return out
    }

    // MARK: Détection

    static let languages: [SyntaxLanguage] = SyntaxDefinitions.all

    static func language(id: String) -> SyntaxLanguage? { languages.first { $0.id == id } }

    /// Nom d'un bloc de code Markdown (```py, ```bash…).
    static func language(named raw: String) -> SyntaxLanguage? {
        let n = raw.lowercased()
        guard !n.isEmpty else { return nil }
        return languages.first { $0.id == n || $0.aliases.contains(n) || $0.extensions.contains(n) }
    }

    static func detect(url: URL?, firstLine: String) -> SyntaxLanguage? {
        if firstLine.hasPrefix("#!") {
            let words = firstLine.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "/" }).map(String.init)
            if let lang = languages.first(where: { l in words.contains { w in l.shebangs.contains { w.hasPrefix($0) } } }) {
                return lang
            }
        }
        guard let url else { return nil }
        let file = url.lastPathComponent.lowercased()
        if let lang = languages.first(where: { $0.fileNames.contains(file) }) { return lang }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return languages.first { $0.extensions.contains(ext) }
    }
}

/// Palette inspirée de Xcode, en clair et en sombre.
enum SyntaxTheme {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        func c(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                     blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? c(dark) : c(light)
        }
    }

    // [clair, sombre] par TokenKind ; réutilisé tel quel pour le CSS de l'aperçu.
    static let palette: [TokenKind: (UInt32, UInt32)] = [
        .keyword: (0x9B2393, 0xFC5FA3),
        .string: (0xC41A16, 0xFC6A5D),
        .comment: (0x6C7986, 0x7F8C98),
        .number: (0x1C00CF, 0xD0BF69),
        .type: (0x0B4F79, 0x5DD8FF),
        .function: (0x326D74, 0x67B7A4),
        .variable: (0x6C36A9, 0xA167E6),
        .constant: (0x9B2393, 0xFC5FA3),
        .tag: (0x0F68A0, 0x5DD8FF),
        .attribute: (0x815F03, 0xFD8F3F),
        .meta: (0x643820, 0xFD8F3F),
        .inserted: (0x1A7F37, 0x56D364),
        .deleted: (0xCF222E, 0xF85149),
    ]

    private static let colors: [UInt8: NSColor] = Dictionary(uniqueKeysWithValues:
        palette.map { ($0.key.rawValue, dyn($0.value.0, $0.value.1)) })

    static func color(_ k: TokenKind) -> NSColor { colors[k.rawValue] ?? .textColor }

    /// Règles CSS .tk-N pour l'aperçu.
    static var css: String {
        func hex(_ v: UInt32) -> String { String(format: "#%06X", v) }
        var light = "", dark = ""
        for (k, v) in palette.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let style = k == .comment ? "font-style:italic;" : ""
            light += ".tk-\(k.rawValue){color:\(hex(v.0));\(style)}\n"
            dark += ".tk-\(k.rawValue){color:\(hex(v.1))}\n"
        }
        return light + "@media (prefers-color-scheme: dark){\n\(dark)}\n"
    }
}
