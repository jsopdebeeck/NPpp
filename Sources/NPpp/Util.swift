import Foundation

/// Cache de regex compilées (le rendu Markdown les réutilise à chaque frappe).
enum RX {
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func re(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        let key = "\(options.rawValue)|\(pattern)"
        if let r = cache[key] { return r }
        let r = try! NSRegularExpression(pattern: pattern, options: options)
        cache[key] = r
        return r
    }
}

/// Remplace chaque correspondance par le résultat de `transform(groupes)`.
/// Les groupes absents valent "".
func rxReplace(_ s: String, _ pattern: String, _ options: NSRegularExpression.Options = [],
               _ transform: ([String]) -> String) -> String {
    let ns = s as NSString
    let matches = RX.re(pattern, options).matches(in: s, range: NSRange(location: 0, length: ns.length))
    if matches.isEmpty { return s }
    var out = ""
    var last = 0
    for m in matches {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        var groups: [String] = []
        for g in 0..<m.numberOfRanges {
            let r = m.range(at: g)
            groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        out += transform(groups)
        last = m.range.location + m.range.length
    }
    out += ns.substring(from: last)
    return out
}

/// Groupes de la première correspondance, ou nil.
func rxMatch(_ s: String, _ pattern: String, _ options: NSRegularExpression.Options = []) -> [String]? {
    let ns = s as NSString
    guard let m = RX.re(pattern, options).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
}

/// Échappement HTML pour du texte.
func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// Échappement HTML pour une valeur d'attribut.
func attr(_ s: String) -> String {
    esc(s).replacingOccurrences(of: "\"", with: "&quot;")
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
    var isBlank: Bool { allSatisfy { $0 == " " || $0 == "\t" } }
    var leadingSpaces: Int { prefix(while: { $0 == " " }).count }
}
