import Foundation

enum Recents {
    private static let key = "recentSites"
    private static let maxCount = 10

    /// Recent site paths, most recent first; missing folders are dropped.
    static func load() -> [String] {
        let all = UserDefaults.standard.stringArray(forKey: key) ?? []
        let existing = all.filter { FileManager.default.fileExists(atPath: $0) }
        if existing.count != all.count { UserDefaults.standard.set(existing, forKey: key) }
        return existing
    }

    static func add(_ path: String) {
        var list = load().filter { $0 != path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(maxCount)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum SiteCheck {
    static func isJekyllSite(_ path: String) -> Bool {
        ["_config.yml", "_config.yaml", "_config.toml"].contains {
            FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent($0))
        }
    }
}

func logErr(_ message: String) {
    FileHandle.standardError.write(Data(("[JekyllCanvas] " + message + "\n").utf8))
}
