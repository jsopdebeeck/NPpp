import AppKit

/// Coloration légère du Markdown en mode texte (police à chasse fixe conservée).
enum MarkdownHighlighter {
    static func apply(to s: NSTextStorage, base: [NSAttributedString.Key: Any]) {
        guard let font = base[.font] as? NSFont else { return }
        let str = s.string
        let full = NSRange(location: 0, length: s.length)
        let fm = NSFontManager.shared
        let bold = fm.convert(font, toHaveTrait: .boldFontMask)
        let italic = fm.convert(font, toHaveTrait: .italicFontMask)
        let muted = NSColor.tertiaryLabelColor

        func each(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines],
                  _ body: (NSTextCheckingResult) -> Void) {
            RX.re(pattern, options).enumerateMatches(in: str, range: full) { m, _, _ in
                if let m { body(m) }
            }
        }

        s.beginEditing()
        s.setAttributes(base, range: full)

        each(#"^#{1,6}[ \t].*$"#) { m in
            s.addAttributes([.font: bold, .foregroundColor: NSColor.systemBlue], range: m.range)
        }
        each(#"^ {0,3}>.*$"#) { m in
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
        }
        each(#"^[ \t]*(?:[-*+]|\d+[.)])(?=[ \t])"#) { m in
            s.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: m.range)
        }
        each(#"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+(\[[ xX]\])"#) { m in
            s.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: m.range(at: 1))
        }
        each(#"(\*\*|__)(?=\S)[^\n]+?(?<=\S)\1"#) { m in
            s.addAttribute(.font, value: bold, range: m.range)
        }
        each(#"(?<![\w*])\*(?=[^\s*])[^\n*]*?[^\s*]?\*(?![\w*])|(?<![\w_])_(?=[^\s_])[^\n_]*?[^\s_]?_(?![\w_])"#) { m in
            s.addAttribute(.font, value: italic, range: m.range)
        }
        each(#"~~[^\n]+?~~"#) { m in
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range)
        }
        each(#"==[^\n=]+?=="#) { m in
            s.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.3), range: m.range)
        }
        each(#"!?\[[^\]\n]*\]\(([^)\n]*)\)"#) { m in
            s.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range)
            s.addAttribute(.foregroundColor, value: muted, range: m.range(at: 1))
        }
        each(#"\[\[[^\]\n]+\]\]"#) { m in
            s.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range)
        }
        each(#"^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$"#) { m in
            s.addAttribute(.foregroundColor, value: muted, range: m.range)
        }
        each(#"^(\|.*\|)[ \t]*$"#) { m in
            s.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: m.range(at: 1))
        }
        // Le code passe en dernier : rien n'est stylé à l'intérieur.
        each(#"`[^`\n]+`"#) { m in
            s.addAttributes([.font: font, .foregroundColor: NSColor.systemPink], range: m.range)
            s.removeAttribute(.strikethroughStyle, range: m.range)
        }
        each(#"^ {0,3}(```|~~~)[ \t]*([\w+#.-]*)[^\n]*\n?([\s\S]*?)(?:^ {0,3}\1[ \t]*$|\z)"#) { m in
            s.addAttributes([.font: font, .foregroundColor: NSColor.systemTeal], range: m.range)
            s.removeAttribute(.strikethroughStyle, range: m.range)
            s.removeAttribute(.backgroundColor, range: m.range)
            // Bloc ```python, ```bash… : coloration du langage à l'intérieur.
            let content = m.range(at: 3)
            if m.range(at: 2).length > 0, content.length > 0,
               let lang = Syntax.language(named: (str as NSString).substring(with: m.range(at: 2))) {
                s.addAttribute(.foregroundColor, value: NSColor.textColor, range: content)
                Syntax.apply(lang, to: s, range: content, font: font)
            }
        }
        each(#"\A---\n[\s\S]*?\n---$"#) { m in
            s.addAttributes([.font: font, .foregroundColor: NSColor.secondaryLabelColor], range: m.range)
        }
        s.endEditing()
    }
}

/// Gestionnaire de mise en page qui dessine les caractères invisibles
/// (espaces ·, tabulations →, fins de ligne LF / CRLF / CR), à la manière de Notepad++.
final class EditorLayoutManager: NSLayoutManager {
    var showInvisibles = false
    var lineEnding: LineEnding = .lf

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showInvisibles, let storage = textStorage, storage.length > 0 else { return }

        let ns = storage.string as NSString
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let baseFont = (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let color = NSColor.tertiaryLabelColor
        let symAttrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: color]
        let eolFont = NSFont.systemFont(ofSize: max(7, baseFont.pointSize * 0.55), weight: .semibold)
        let eolAttrs: [NSAttributedString.Key: Any] = [.font: eolFont, .foregroundColor: NSColor.controlBackgroundColor]

        for i in chars.location..<NSMaxRange(chars) {
            let c = ns.character(at: i)
            let symbol: String
            switch c {
            case 0x20: symbol = "·"
            case 0x09: symbol = "→"
            case 0xA0: symbol = "°"
            case 0x0A: symbol = lineEnding.rawValue
            default: continue
            }
            let g = glyphIndexForCharacter(at: i)
            let line = lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let loc = location(forGlyphAt: g)
            let x = origin.x + line.minX + loc.x
            let baseline = origin.y + line.minY + loc.y

            if c == 0x0A {
                // Petite étiquette arrondie, comme les fins de ligne affichées par Notepad++.
                let label = symbol as NSString
                let size = label.size(withAttributes: eolAttrs)
                let h = baseFont.ascender * 0.95
                let box = NSRect(x: x + 2, y: baseline - h, width: size.width + 6, height: h)
                color.setFill()
                NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5).fill()
                label.draw(at: NSPoint(x: box.minX + 3, y: box.midY - size.height / 2), withAttributes: eolAttrs)
            } else {
                (symbol as NSString).draw(at: NSPoint(x: x, y: baseline - baseFont.ascender), withAttributes: symAttrs)
            }
        }
    }
}
