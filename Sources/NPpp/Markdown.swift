import Foundation

/// Convertisseur Markdown → HTML, sans dépendance.
/// Couvre l'usage courant : titres, paragraphes, listes imbriquées et cases à cocher,
/// citations et callouts, blocs de code, tableaux, liens (y compris [[wikilinks]]),
/// images, emphase, barré, surlignage, front matter YAML.
final class MarkdownRenderer {
    private var slugCounts: [String: Int] = [:]
    private var refs: [String: (url: String, title: String)] = [:]

    static func html(_ text: String) -> String { MarkdownRenderer().render(text) }

    func render(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n").map(Self.expandLeadingTabs)
        var out = ""
        if lines.first == "---", let end = lines.indices.dropFirst().first(where: { lines[$0] == "---" || lines[$0] == "..." }) {
            let fm = lines[1..<end].joined(separator: "\n")
            out += "<pre class=\"frontmatter\"><code>\(esc(fm))</code></pre>\n"
            lines = Array(lines[(end + 1)...])
        }
        lines = extractReferences(lines)
        out += blocks(lines)
        return out
    }

    // MARK: - Blocs

    private func blocks(_ lines: [String], tight: Bool = false) -> String {
        var out = ""
        var para: [String] = []
        var i = 0

        func flush() {
            guard !para.isEmpty else { return }
            let text = para.map { String($0.drop(while: { $0 == " " })) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespaces)
            out += tight ? inline(text) + "\n" : "<p>\(inline(text))</p>\n"
            para = []
        }

        while i < lines.count {
            let line = lines[i]
            if line.isBlank { flush(); i += 1; continue }
            let indent = line.leadingSpaces
            let t = line.trimmed

            // Bloc de code délimité
            if indent < 4, let fence = rxMatch(t, #"^(`{3,}|~{3,})\s*([^`]*)$"#) {
                flush()
                let marker = fence[1]
                let lang = fence[2].trimmed.split(separator: " ").first.map(String.init) ?? ""
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmed
                    if l.hasPrefix(marker), l.allSatisfy({ $0 == marker.first }) { break }
                    code.append(String(lines[i].dropFirst(min(indent, lines[i].leadingSpaces))))
                    i += 1
                }
                i += 1
                let cls = lang.isEmpty ? "" : " class=\"language-\(attr(lang))\""
                let source = code.joined(separator: "\n")
                let body = Syntax.language(named: lang).map { Syntax.html(source, $0) } ?? esc(source)
                out += "<pre><code\(cls)>\(body)</code></pre>\n"
                continue
            }

            // Code indenté (hors paragraphe)
            if indent >= 4 && para.isEmpty {
                var code: [String] = []
                while i < lines.count, lines[i].isBlank || lines[i].leadingSpaces >= 4 {
                    code.append(String(lines[i].dropFirst(min(4, lines[i].leadingSpaces))))
                    i += 1
                }
                while code.last?.isBlank == true { code.removeLast() }
                out += "<pre><code>\(esc(code.joined(separator: "\n")))</code></pre>\n"
                continue
            }

            // Titre ATX
            if indent < 4, let h = rxMatch(t, #"^(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$"#) {
                flush()
                let level = h[1].count
                out += "<h\(level) id=\"\(attr(slug(h[2])))\">\(inline(h[2]))</h\(level)>\n"
                i += 1
                continue
            }

            // Titre Setext (soulignement === ou ---)
            if !para.isEmpty, indent < 4, rxMatch(t, #"^(=+|-+)$"#) != nil {
                let text = para.map(\.trimmed).joined(separator: "\n")
                let level = t.hasPrefix("=") ? 1 : 2
                para = []
                out += "<h\(level) id=\"\(attr(slug(text)))\">\(inline(text))</h\(level)>\n"
                i += 1
                continue
            }

            // Ligne horizontale
            if indent < 4, Self.isHR(t) {
                flush()
                out += "<hr>\n"
                i += 1
                continue
            }

            // Citation / callout
            if indent < 4, t.hasPrefix(">") {
                flush()
                var q: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmed
                    if l.hasPrefix(">") {
                        var s = String(l.dropFirst())
                        if s.hasPrefix(" ") { s.removeFirst() }
                        q.append(s)
                    } else if !lines[i].isBlank, let last = q.last, !last.isBlank,
                              Self.listMarker(lines[i]) == nil, !l.hasPrefix("#"), !l.hasPrefix("```") {
                        q.append(l) // continuation paresseuse
                    } else { break }
                    i += 1
                }
                if let first = q.first, let c = rxMatch(first, #"^\[!(\w+)\][+-]?\s*(.*)$"#) {
                    let kind = c[1].lowercased()
                    let title = c[2].isEmpty ? c[1].capitalized : c[2]
                    out += "<div class=\"callout callout-\(attr(kind))\"><div class=\"callout-title\">\(inline(title))</div>\(blocks(Array(q.dropFirst())))</div>\n"
                } else {
                    out += "<blockquote>\n\(blocks(q))</blockquote>\n"
                }
                continue
            }

            // Tableau
            if line.contains("|"), i + 1 < lines.count, Self.isTableSeparator(lines[i + 1]) {
                flush()
                out += table(lines, &i)
                continue
            }

            // Liste
            if indent < 4, Self.listMarker(line) != nil {
                flush()
                out += list(lines, &i)
                continue
            }

            // Bloc HTML brut
            if indent < 4, rxMatch(t, #"^(?:<!--|</?(?:address|article|aside|blockquote|center|details|summary|div|dl|dt|dd|fieldset|figure|figcaption|footer|form|h[1-6]|header|hr|iframe|main|nav|ol|ul|li|p|pre|section|table|thead|tbody|tr|td|th|img|br|video|audio|picture|source|style)\b)"#, [.caseInsensitive]) != nil {
                flush()
                var html: [String] = []
                while i < lines.count, !lines[i].isBlank { html.append(lines[i]); i += 1 }
                out += html.joined(separator: "\n") + "\n"
                continue
            }

            para.append(line)
            i += 1
        }
        flush()
        return out
    }

    // MARK: - Listes

    struct ListMarker {
        var indent: Int
        var ordered: Bool
        var bullet: Character
        var start: Int
        var contentOffset: Int
    }

    static func listMarker(_ line: String) -> ListMarker? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " { i += 1 }
        let indent = i
        guard i < chars.count else { return nil }

        var ordered = false
        var bullet: Character = chars[i]
        var start = 1
        if "-*+".contains(chars[i]) {
            i += 1
        } else {
            var digits = ""
            while i < chars.count, chars[i].isASCII, chars[i].isNumber, digits.count < 9 { digits.append(chars[i]); i += 1 }
            guard !digits.isEmpty, i < chars.count, chars[i] == "." || chars[i] == ")" else { return nil }
            ordered = true
            bullet = chars[i]
            start = Int(digits) ?? 1
            i += 1
        }
        if i == chars.count { return ListMarker(indent: indent, ordered: ordered, bullet: bullet, start: start, contentOffset: i) }
        guard chars[i] == " " else { return nil }
        let markerEnd = i
        while i < chars.count, chars[i] == " ", i - markerEnd < 4 { i += 1 }
        if i == chars.count { i = markerEnd + 1 }
        return ListMarker(indent: indent, ordered: ordered, bullet: bullet, start: start, contentOffset: i)
    }

    private func list(_ lines: [String], _ i: inout Int) -> String {
        let first = Self.listMarker(lines[i])!
        var items: [[String]] = []
        var current: [String] = []
        var marker = first
        var loose = false
        var pendingBlank = false
        var begun = false

        while i < lines.count {
            let line = lines[i]
            if line.isBlank {
                pendingBlank = true
                if begun { current.append("") }
                i += 1
                continue
            }
            let indent = line.leadingSpaces
            if let m = Self.listMarker(line), indent < marker.contentOffset, !Self.isHR(line.trimmed) {
                guard m.ordered == first.ordered, first.ordered || m.bullet == first.bullet else { break }
                if begun {
                    items.append(current)
                    if pendingBlank { loose = true }
                }
                marker = m
                current = [line.count > m.contentOffset ? String(line.dropFirst(m.contentOffset)) : ""]
                begun = true
                pendingBlank = false
                i += 1
                continue
            }
            if indent >= marker.contentOffset {
                if pendingBlank { loose = true }
                current.append(String(line.dropFirst(marker.contentOffset)))
                pendingBlank = false
                i += 1
                continue
            }
            if !pendingBlank {
                current.append(line.trimmed) // continuation paresseuse
                i += 1
                continue
            }
            break
        }
        if begun { items.append(current) }

        var html = first.ordered ? (first.start != 1 ? "<ol start=\"\(first.start)\">\n" : "<ol>\n") : "<ul>\n"
        for var item in items {
            while item.last?.isBlank == true { item.removeLast() }
            var cls = ""
            var box = ""
            if let f = item.first, let task = rxMatch(f, #"^\[([ xX])\](?: +|$)"#) {
                let checked = task[1] != " "
                box = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                item[0] = String(f.dropFirst(task[0].count))
                cls = checked ? " class=\"task done\"" : " class=\"task\""
            }
            html += "<li\(cls)>\(box)\(blocks(item, tight: !loose))</li>\n"
        }
        html += first.ordered ? "</ol>\n" : "</ul>\n"
        return html
    }

    // MARK: - Tableaux

    static func isTableSeparator(_ line: String) -> Bool {
        line.contains("|") && line.contains("-")
            && rxMatch(line.trimmed, #"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$"#) != nil
    }

    private static func splitRow(_ line: String) -> [String] {
        var t = line.trimmed
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var cell = ""
        var inCode = false
        var prev: Character = " "
        for c in t {
            if c == "`" { inCode.toggle() }
            if c == "|" && !inCode && prev != "\\" {
                cells.append(cell.trimmed)
                cell = ""
            } else {
                cell.append(c)
            }
            prev = c
        }
        cells.append(cell.trimmed)
        return cells
    }

    private func table(_ lines: [String], _ i: inout Int) -> String {
        let header = Self.splitRow(lines[i])
        let aligns = Self.splitRow(lines[i + 1]).map { c -> String in
            let l = c.hasPrefix(":"), r = c.hasSuffix(":")
            return l && r ? "center" : r ? "right" : l ? "left" : ""
        }
        i += 2
        func cell(_ tag: String, _ text: String, _ col: Int) -> String {
            let a = col < aligns.count && !aligns[col].isEmpty ? " style=\"text-align:\(aligns[col])\"" : ""
            return "<\(tag)\(a)>\(inline(text))</\(tag)>"
        }
        var html = "<div class=\"table\"><table>\n<thead><tr>"
        for (c, h) in header.enumerated() { html += cell("th", h, c) }
        html += "</tr></thead>\n<tbody>\n"
        while i < lines.count, !lines[i].isBlank, lines[i].contains("|") {
            let row = Self.splitRow(lines[i])
            html += "<tr>"
            for c in 0..<header.count { html += cell("td", c < row.count ? row[c] : "", c) }
            html += "</tr>\n"
            i += 1
        }
        return html + "</tbody></table></div>\n"
    }

    // MARK: - Références

    private func extractReferences(_ lines: [String]) -> [String] {
        var kept: [String] = []
        var inFence = false
        for line in lines {
            let t = line.trimmed
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle() }
            if !inFence, let m = rxMatch(line, #"^ {0,3}\[([^\]^][^\]]*)\]:\s*<?([^\s>]+)>?(?:\s+["'(](.*)["')])?\s*$"#) {
                refs[Self.refKey(m[1])] = (m[2], m[3])
                continue
            }
            kept.append(line)
        }
        return kept
    }

    private static func refKey(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Inline

    private func inline(_ s: String) -> String {
        var tokens: [String] = []
        func stash(_ html: String) -> String {
            tokens.append(html)
            return "\u{E000}\(tokens.count - 1)\u{E001}"
        }
        func linkOpen(_ href: String, _ title: String = "", _ cls: String = "") -> String {
            let t = title.isEmpty ? "" : " title=\"\(attr(title))\""
            let c = cls.isEmpty ? "" : " class=\"\(cls)\""
            return stash("<a href=\"\(attr(href))\"\(t)\(c)>")
        }

        var t = s

        // Code inline
        t = rxReplace(t, #"(`+)([\s\S]+?)(?<!`)\1(?!`)"#) { g in
            var c = g[2].replacingOccurrences(of: "\n", with: " ")
            if c.count > 2, c.hasPrefix(" "), c.hasSuffix(" ") { c = String(c.dropFirst().dropLast()) }
            return stash("<code>\(esc(c))</code>")
        }
        // Retours à la ligne forcés (deux espaces ou \ en fin de ligne)
        t = rxReplace(t, #"(?: {2,}|\\)\n"#) { _ in stash("<br>\n") }
        // Échappements
        t = rxReplace(t, ##"\\([!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])"##) { g in stash(esc(g[1])) }
        // Liens automatiques <https://…>
        t = rxReplace(t, #"<((?:https?|mailto|file):[^\s>]+)>"#) { g in
            stash("<a href=\"\(attr(g[1]))\">\(esc(g[1]))</a>")
        }
        // HTML inline autorisé
        t = rxReplace(t, #"</?(?:br|kbd|sub|sup|mark|u|ins|del|s|small|span|abbr|b|i|em|strong|img|a)\b[^<>]*>"#, [.caseInsensitive]) { g in
            stash(g[0])
        }
        // Images
        t = rxReplace(t, #"!\[([^\]]*)\]\(\s*<?([^\s)>]*)>?(?:\s+["'](.*?)["'])?\s*\)"#) { g in
            let title = g[3].isEmpty ? "" : " title=\"\(attr(g[3]))\""
            return stash("<img src=\"\(attr(g[2]))\" alt=\"\(attr(g[1]))\"\(title)>")
        }
        // Wikilinks [[Note]], [[Note|alias]], ![[image.png]]
        t = rxReplace(t, #"(!?)\[\[([^\]|#]+)(#[^\]|]*)?(?:\|([^\]]+))?\]\]"#) { g in
            let target = g[2].trimmed
            let isImage = rxMatch(target, #"\.(png|jpe?g|gif|svg|webp|heic)$"#, [.caseInsensitive]) != nil
            let file = (target as NSString).pathExtension.isEmpty ? target + ".md" : target
            let href = (file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file) + g[3]
            if g[1] == "!" && isImage { return stash("<img src=\"\(attr(href))\" alt=\"\(attr(target))\">") }
            return linkOpen(href, "", "wikilink") + (g[4].isEmpty ? target : g[4]) + stash("</a>")
        }
        // Liens [texte](url "titre")
        t = rxReplace(t, #"\[((?:[^\[\]]|\[[^\[\]]*\])*)\]\(\s*<?([^\s)>]*(?:\([^\s)]*\)[^\s)>]*)?)>?(?:\s+["'](.*?)["'])?\s*\)"#) { g in
            linkOpen(g[2], g[3]) + g[1] + stash("</a>")
        }
        // Liens par référence [texte][ref], [texte][], [ref]
        if !refs.isEmpty {
            t = rxReplace(t, #"\[((?:[^\[\]]|\[[^\[\]]*\])*)\](?:\[([^\]]*)\])?"#) { g in
                guard let r = refs[Self.refKey(g[2].isEmpty ? g[1] : g[2])] else { return g[0] }
                return linkOpen(r.url, r.title) + g[1] + stash("</a>")
            }
        }

        t = esc(t)

        // URL nues
        t = rxReplace(t, #"(?<![\w/"'=])(https?://[^\s<\x{E000}]+[^\s<\x{E000}.,:;!?'")\]])"#) { g in
            stash("<a href=\"\(g[1].replacingOccurrences(of: "\"", with: "%22"))\">\(g[1])</a>")
        }
        // Emphase
        t = rxReplace(t, #"(\*\*\*|___)(?=\S)([\s\S]+?)(?<=\S)\1"#) { g in "<strong><em>\(g[2])</em></strong>" }
        t = rxReplace(t, #"\*\*(?=\S)([\s\S]+?)(?<=\S)\*\*"#) { g in "<strong>\(g[1])</strong>" }
        t = rxReplace(t, #"(?<![\w_])__(?=\S)([\s\S]+?)(?<=\S)__(?![\w_])"#) { g in "<strong>\(g[1])</strong>" }
        t = rxReplace(t, #"(?<![\w*])\*(?=[^\s*])([\s\S]*?[^\s*])?\*(?![\w*])"#) { g in "<em>\(g[0].dropFirst().dropLast())</em>" }
        t = rxReplace(t, #"(?<![\w_])_(?=[^\s_])([\s\S]*?[^\s_])?_(?![\w_])"#) { g in "<em>\(g[0].dropFirst().dropLast())</em>" }
        t = rxReplace(t, #"~~(?=\S)([\s\S]+?)(?<=\S)~~"#) { g in "<del>\(g[1])</del>" }
        t = rxReplace(t, #"==(?=\S)([\s\S]+?)(?<=\S)=="#) { g in "<mark>\(g[1])</mark>" }

        // Restauration des fragments protégés
        for _ in 0..<4 where t.contains("\u{E000}") {
            t = rxReplace(t, "\u{E000}(\\d+)\u{E001}") { g in tokens[Int(g[1])!] }
        }
        return t
    }

    // MARK: - Utilitaires

    static func isHR(_ t: String) -> Bool {
        rxMatch(t, #"^(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$"#) != nil
    }

    private static func expandLeadingTabs(_ line: String) -> String {
        guard line.hasPrefix("\t") || line.hasPrefix(" ") else { return line }
        var out = ""
        var rest = Substring(line)
        while let c = rest.first, c == " " || c == "\t" {
            out += c == "\t" ? String(repeating: " ", count: 4 - out.count % 4) : " "
            rest = rest.dropFirst()
        }
        return out + rest
    }

    private func slug(_ text: String) -> String {
        let plain = text.lowercased().replacingOccurrences(of: #"[`*_~\[\]()#!<>]"#, with: "", options: .regularExpression)
        var s = String(plain.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-"
        }.map(Character.init))
        s = s.trimmed.replacingOccurrences(of: " ", with: "-")
        if s.isEmpty { s = "section" }
        let n = slugCounts[s, default: 0]
        slugCounts[s] = n + 1
        return n == 0 ? s : "\(s)-\(n)"
    }
}
