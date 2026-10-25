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
