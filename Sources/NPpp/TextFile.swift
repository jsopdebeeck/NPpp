import Foundation

/// Fins de ligne. Dans l'éditeur, le texte est toujours normalisé en "\n" ;
/// la fin de ligne d'origine est réappliquée à l'enregistrement.
enum LineEnding: String, Codable, CaseIterable {
    case lf = "LF", crlf = "CRLF", cr = "CR"

    var chars: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    var menuTitle: String {
        switch self {
        case .crlf: return "Windows (CRLF)"
        case .lf: return "Unix / macOS (LF)"
        case .cr: return "Ancien Mac (CR)"
        }
    }

    /// Fin de ligne majoritaire du texte brut.
    static func detect(_ s: String) -> LineEnding {
        var crlf = 0, lf = 0, cr = 0
        var prevCR = false
        for u in s.utf16 {
            if u == 10 {
                if prevCR { crlf += 1; cr -= 1 } else { lf += 1 }
                prevCR = false
            } else if u == 13 {
                cr += 1
                prevCR = true
            } else {
                prevCR = false
            }
        }
        if crlf >= lf && crlf >= cr && crlf > 0 { return .crlf }
        if cr > lf { return .cr }
        return .lf
    }

    static func normalize(_ s: String) -> String {
        guard s.contains("\r") else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

/// Encodage d'un fichier texte (avec ou sans BOM pour l'UTF-8).
struct TextEncoding: Codable, Equatable {
    var raw: UInt
    var bom: Bool

    var encoding: String.Encoding { String.Encoding(rawValue: raw) }

    static let utf8 = TextEncoding(raw: String.Encoding.utf8.rawValue, bom: false)
    static let utf8BOM = TextEncoding(raw: String.Encoding.utf8.rawValue, bom: true)
    static let utf16 = TextEncoding(raw: String.Encoding.utf16.rawValue, bom: true)
    static let latin1 = TextEncoding(raw: String.Encoding.isoLatin1.rawValue, bom: false)
    static let cp1252 = TextEncoding(raw: String.Encoding.windowsCP1252.rawValue, bom: false)
    static let macRoman = TextEncoding(raw: String.Encoding.macOSRoman.rawValue, bom: false)

    static let all: [TextEncoding] = [.utf8, .utf8BOM, .utf16, .latin1, .cp1252, .macRoman]

    var name: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8BOM: return "UTF-8 avec BOM"
        case .utf16: return "UTF-16"
        case .latin1: return "ISO-8859-1"
        case .cp1252: return "Windows-1252"
        case .macRoman: return "Mac Roman"
        default: return String.localizedName(of: encoding)
        }
    }
}

struct TextFile {
    var text: String          // normalisé en "\n"
    var lineEnding: LineEnding
    var encoding: TextEncoding

    /// Lit un fichier en détectant BOM, UTF-8 ou à défaut Windows-1252 / Latin-1.
    static func read(_ url: URL, forcing forced: TextEncoding? = nil) throws -> TextFile {
        let data = try Data(contentsOf: url)
        let (raw, enc) = try decode(data, forcing: forced)
        return TextFile(text: LineEnding.normalize(raw), lineEnding: LineEnding.detect(raw), encoding: enc)
    }

    static func decode(_ data: Data, forcing forced: TextEncoding?) throws -> (String, TextEncoding) {
        if let forced {
            var d = data
            if forced.raw == String.Encoding.utf8.rawValue, d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
            guard let s = String(data: d, encoding: forced.encoding) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return (s, forced)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) {
            return (s, .utf8BOM)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) {
            return (s, .utf16)
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
        if let s = String(data: data, encoding: .windowsCP1252) { return (s, .cp1252) }
        if let s = String(data: data, encoding: .isoLatin1) { return (s, .latin1) }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// Données à écrire sur disque, ou nil si l'encodage ne peut pas représenter le texte.
    func encoded() -> Data? {
        let raw = lineEnding == .lf ? text : text.replacingOccurrences(of: "\n", with: lineEnding.chars)
        guard var data = raw.data(using: encoding.encoding, allowLossyConversion: false) else { return nil }
        if encoding.bom && encoding.raw == String.Encoding.utf8.rawValue {
            data = Data([0xEF, 0xBB, 0xBF]) + data
        }
        return data
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
