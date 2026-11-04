import Foundation

/// État d'un onglet, tel qu'il est mémorisé entre deux lancements.
struct TabState: Codable {
    var path: String?
    var language: String? = nil  // langage forcé via le menu
    var name: String?            // nom des onglets « Sans titre »
    var text: String?            // présent si modifications non enregistrées ou onglet sans fichier
    var mode: ViewMode
    var selection: Int
    var fileDate: Double?
    var lineEnding: LineEnding?
    var encoding: TextEncoding?
}

struct SessionData: Codable {
    var tabs: [TabState]
    var active: Int
    var frame: String?
}

enum SessionStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NPpp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var file: URL { directory.appendingPathComponent("session.json") }

    static func load() -> SessionData? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SessionData.self, from: data)
    }

    static func save(_ session: SessionData) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// Historique des fichiers récents, du plus récent au plus ancien.
enum RecentStore {
    static let limit = 20
    private static var file: URL { SessionStore.directory.appendingPathComponent("recent.json") }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func save(_ paths: [String]) {
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// Versions précédentes : copie du fichier sur le disque avant de l'écraser.
/// L'arborescence d'origine est reproduite sous versions/ ; rien n'est purgé.
enum VersionStore {
    static var directory: URL { SessionStore.directory.appendingPathComponent("versions", isDirectory: true) }

    static func folder(for url: URL) -> URL {
        directory.appendingPathComponent(url.deletingLastPathComponent().path, isDirectory: true)
    }

    /// Vrai si la copie existe, ou s'il n'y a rien à copier.
    static func backup(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return true }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let dest = folder(for: url).appendingPathComponent("\(url.lastPathComponent).\(stamp.string(from: Date())).bak")
        if fm.fileExists(atPath: dest.path) { return true }
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: dest)
            return true
        } catch {
            return false
        }
    }
}
