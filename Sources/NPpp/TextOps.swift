import AppKit

/// Opérations sur le texte inspirées de Notepad++ : lignes, paragraphes, espaces, casse, Markdown.
extension EditorController {

    private var ns: NSString { text as NSString }
    private var selection: NSRange { textView.selectedRange() }

    /// Lignes entières couvertes par la sélection (ou ligne du curseur).
    private var selectedLinesRange: NSRange { ns.lineRange(for: selection) }

    /// Plage visée par une opération globale : la sélection si elle existe, sinon tout le document.
    private var targetRange: NSRange {
        selection.length > 0 ? selectedLinesRange : NSRange(location: 0, length: ns.length)
    }

    /// Applique `transform` aux lignes de la plage visée, en conservant le \n final.
    private func transformLines(_ transform: ([String]) -> [String]) {
        let range = targetRange
        var block = ns.substring(with: range)
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { block.removeLast() }
        var result = transform(block.components(separatedBy: "\n")).joined(separator: "\n")
        if trailingNewline { result += "\n" }
        guard result != ns.substring(with: range) else { return }
        replace(range, with: result,
                select: selection.length > 0 ? NSRange(location: range.location, length: (result as NSString).length) : selection)
    }

    private func transformText(_ transform: (String) -> String) {
        let range = targetRange
        let old = ns.substring(with: range)
        let result = transform(old)
        guard result != old else { return }
        replace(range, with: result,
                select: selection.length > 0 ? NSRange(location: range.location, length: (result as NSString).length)
                                             : NSRange(location: min(selection.location, ns.length - range.length + (result as NSString).length), length: 0))
    }

    // MARK: Lignes

    @objc func duplicateLine(_ sender: Any?) {
        let sel = selection
        if sel.length > 0 {
            let s = ns.substring(with: sel)
            replace(NSRange(location: NSMaxRange(sel), length: 0), with: s,
                    select: NSRange(location: NSMaxRange(sel), length: sel.length))
            return
        }
        let lr = selectedLinesRange
        var line = ns.substring(with: lr)
        if !line.hasSuffix("\n") { line = "\n" + line.trimmingCharacters(in: .newlines) }
        let insertAt = NSMaxRange(lr)
        replace(NSRange(location: insertAt, length: 0), with: line,
                select: NSRange(location: sel.location + (line as NSString).length, length: 0))
    }

    @objc func moveLineUp(_ sender: Any?) {
        let sel = selection
        let lr = selectedLinesRange
        guard lr.location > 0 else { return }
        let prev = ns.lineRange(for: NSRange(location: lr.location - 1, length: 0))
        var a = ns.substring(with: prev)
        var b = ns.substring(with: lr)
        if !b.hasSuffix("\n") { b += "\n"; a.removeLast() }
        replace(NSUnionRange(prev, lr), with: b + a,
                select: NSRange(location: prev.location + (sel.location - lr.location), length: sel.length))
    }

    @objc func moveLineDown(_ sender: Any?) {
        let sel = selection
        let lr = selectedLinesRange
        guard NSMaxRange(lr) < ns.length else { return }
        let next = ns.lineRange(for: NSRange(location: NSMaxRange(lr), length: 0))
        var a = ns.substring(with: lr)
        var b = ns.substring(with: next)
        if !b.hasSuffix("\n") { b += "\n"; a.removeLast() }
        replace(NSUnionRange(lr, next), with: b + a,
                select: NSRange(location: lr.location + (b as NSString).length + (sel.location - lr.location), length: sel.length))
    }

    @objc func deleteLine(_ sender: Any?) {
        let lr = selectedLinesRange
        replace(lr, with: "", select: NSRange(location: lr.location, length: 0))
    }

    @objc func sortLinesAscending(_ sender: Any?) {
        transformLines { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    }

    @objc func sortLinesDescending(_ sender: Any?) {
        transformLines { $0.sorted { $0.localizedStandardCompare($1) == .orderedDescending } }
    }

    @objc func reverseLines(_ sender: Any?) { transformLines { $0.reversed() } }

    @objc func removeDuplicateLines(_ sender: Any?) {
        transformLines { lines in
            var seen = Set<String>()
            return lines.filter { seen.insert($0).inserted }
        }
    }

    // MARK: Paragraphes

    /// Joint les lignes sélectionnées en une seule (comme Ctrl+J dans Notepad++).
    @objc func joinLines(_ sender: Any?) {
        let sel = selection
        if sel.length == 0 {
            // Joint la ligne courante avec la suivante.
            let lr = selectedLinesRange
            guard NSMaxRange(lr) < ns.length else { return }
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(lr), length: 0))
            let range = NSUnionRange(lr, next)
            var parts = ns.substring(with: range).components(separatedBy: "\n")
            let trailing = parts.last == "" ? "\n" : ""
            if trailing == "\n" { parts.removeLast() }
            let joined = Self.join(parts) + trailing
            replace(range, with: joined, select: NSRange(location: lr.location + (Self.trimEnd(parts[0]) as NSString).length, length: 0))
            return
        }
        transformText { block in
            let trailing = block.hasSuffix("\n") ? "\n" : ""
            let lines = block.dropLast(trailing.count).components(separatedBy: "\n")
            return Self.join(lines) + trailing
        }
    }

    /// Supprime les retours à la ligne internes des paragraphes (texte copié d'un PDF, d'un mail…),
    /// en gardant les lignes vides qui séparent les paragraphes.
    @objc func unwrapParagraphs(_ sender: Any?) {
        transformText { block in
            let trailing = block.hasSuffix("\n") ? "\n" : ""
            var out: [String] = []
            var para: [String] = []
            func flush() { if !para.isEmpty { out.append(Self.join(para)); para = [] } }
            for line in block.dropLast(trailing.count).components(separatedBy: "\n") {
                let t = line.trimmed
                // On ne fusionne pas les lignes Markdown structurantes.
                let structural = t.hasPrefix("#") || t.hasPrefix(">") || t.hasPrefix("|") || t.hasPrefix("```")
                    || MarkdownRenderer.listMarker(line) != nil || MarkdownRenderer.isHR(t)
                if t.isEmpty { flush(); out.append(line); continue }
                if structural { flush(); para = [line]; continue }
                para.append(line)
            }
            flush()
            return out.joined(separator: "\n") + trailing
        }
    }

    /// Sépare les paragraphes par une ligne vide (chaque ligne devient un paragraphe).
    @objc func separateParagraphs(_ sender: Any?) {
        transformLines { lines in
            var out: [String] = []
            for (i, l) in lines.enumerated() {
                out.append(l)
                if !l.isBlank, i + 1 < lines.count, !lines[i + 1].isBlank { out.append("") }
            }
            return out
        }
    }

    @objc func removeBlankLines(_ sender: Any?) {
        transformLines { $0.filter { !$0.isBlank } }
    }

    @objc func collapseBlankLines(_ sender: Any?) {
        transformLines { lines in
            var out: [String] = []
            for l in lines where !(l.isBlank && out.last?.isBlank == true) { out.append(l.isBlank ? "" : l) }
            return out
        }
    }

    private static func trimEnd(_ s: String) -> String {
        String(s.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
    }

    private static func join(_ lines: [String]) -> String {
        guard let first = lines.first else { return "" }
        return lines.dropFirst().reduce(trimEnd(first)) { acc, l in
            let t = l.trimmed
            if t.isEmpty { return acc }
            if acc.isEmpty { return t }
            // Mot coupé par un trait d'union en fin de ligne : on recolle.
            if acc.hasSuffix("-"), let c = t.first, c.isLowercase { return String(acc.dropLast()) + t }
            return acc + " " + t
        }
    }

    // MARK: Espaces

    @objc func trimTrailingWhitespace(_ sender: Any?) {
        transformLines { $0.map(Self.trimEnd) }
    }

    @objc func tabsToSpaces(_ sender: Any?) {
        transformLines { lines in
            lines.map { line in
                var out = ""
                for c in line {
                    if c == "\t" { out += String(repeating: " ", count: 4 - out.count % 4) } else { out.append(c) }
                }
                return out
            }
        }
    }

    @objc func leadingSpacesToTabs(_ sender: Any?) {
        transformLines { lines in
            lines.map { line in
                let n = line.leadingSpaces
                return String(repeating: "\t", count: n / 4) + String(repeating: " ", count: n % 4) + line.dropFirst(n)
            }
        }
    }

    // MARK: Casse

    private func transformSelection(_ f: (String) -> String) {
        var sel = selection
        if sel.length == 0 {
            // Sans sélection : le mot sous le curseur.
            sel = textView.selectionRange(forProposedRange: sel, granularity: .selectByWord)
            guard sel.length > 0 else { return }
        }
        let s = f(ns.substring(with: sel))
        replace(sel, with: s, select: NSRange(location: sel.location, length: (s as NSString).length))
    }

    @objc func makeUppercase(_ sender: Any?) { transformSelection { $0.uppercased() } }
    @objc func makeLowercase(_ sender: Any?) { transformSelection { $0.lowercased() } }
    @objc func makeTitlecase(_ sender: Any?) { transformSelection { $0.capitalized } }
    @objc func makeSentencecase(_ sender: Any?) {
        transformSelection { s in
            let lower = s.lowercased()
            return rxReplace(lower, #"(^|[.!?]\s+|\n)(\p{Ll})"#) { g in g[1] + g[2].uppercased() }
        }
    }

    // MARK: Markdown

    private func wrapSelection(_ prefix: String, _ suffix: String) {
        let sel = selection
        let p = (prefix as NSString).length, s = (suffix as NSString).length
        // Déjà entouré : on retire.
        if sel.location >= p, NSMaxRange(sel) + s <= ns.length,
           ns.substring(with: NSRange(location: sel.location - p, length: p)) == prefix,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: s)) == suffix {
            let inner = ns.substring(with: sel)
            replace(NSRange(location: sel.location - p, length: sel.length + p + s), with: inner,
                    select: NSRange(location: sel.location - p, length: sel.length))
            return
        }
        let inner = ns.substring(with: sel)
        replace(sel, with: prefix + inner + suffix, select: NSRange(location: sel.location + p, length: sel.length))
    }

    @objc func toggleBold(_ sender: Any?) { wrapSelection("**", "**") }
    @objc func toggleItalic(_ sender: Any?) { wrapSelection("*", "*") }
    @objc func toggleCode(_ sender: Any?) { wrapSelection("`", "`") }
    @objc func toggleStrike(_ sender: Any?) { wrapSelection("~~", "~~") }

    @objc func insertLink(_ sender: Any?) {
        let sel = selection
        let inner = ns.substring(with: sel)
        if inner.hasPrefix("http") {
            replace(sel, with: "[](\(inner))", select: NSRange(location: sel.location + 1, length: 0))
        } else {
            let s = "[\(inner)]()"
            replace(sel, with: s, select: NSRange(location: sel.location + (s as NSString).length - 1, length: 0))
        }
    }

    /// Cycle des titres sur la ligne courante : rien → # → ## → ### → rien.
    @objc func cycleHeading(_ sender: Any?) {
        let lr = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = ns.substring(with: lr)
        let nl = line.hasSuffix("\n") ? "\n" : ""
        if !nl.isEmpty { line.removeLast() }
        let level = line.prefix(while: { $0 == "#" }).count
        let body = line.dropFirst(level).drop(while: { $0 == " " })
        let newLevel = level >= 3 ? 0 : level + 1
        let new = (newLevel > 0 ? String(repeating: "#", count: newLevel) + " " : "") + body
        replace(lr, with: new + nl, select: NSRange(location: lr.location + (new as NSString).length, length: 0))
    }

    /// Coche / décoche une case « - [ ] » sur les lignes sélectionnées, ou en crée une.
    @objc func toggleTask(_ sender: Any?) {
        transformLinesInSelection { line in
            if let m = rxMatch(line, #"^(\s*[-*+] )\[( |x|X)\] (.*)$"#) {
                return m[1] + (m[2] == " " ? "[x] " : "[ ] ") + m[3]
            }
            if let m = rxMatch(line, #"^(\s*)[-*+] (.*)$"#) { return m[1] + "- [ ] " + m[2] }
            return line.isBlank ? line : "- [ ] " + line
        }
    }

    private func transformLinesInSelection(_ f: (String) -> String) {
        let lr = selectedLinesRange
        var block = ns.substring(with: lr)
        let nl = block.hasSuffix("\n")
        if nl { block.removeLast() }
        let out = block.components(separatedBy: "\n").map(f).joined(separator: "\n") + (nl ? "\n" : "")
        let delta = (out as NSString).length - lr.length
        let sel = selection
        replace(lr, with: out,
                select: sel.length > 0 ? NSRange(location: lr.location, length: (out as NSString).length - (nl ? 1 : 0))
                                       : NSRange(location: max(lr.location, sel.location + delta), length: 0))
    }
}
