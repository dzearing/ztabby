import Cocoa

// Recently opened files, folders, and URLs (the non-app launcher targets). Scored by
// frecency with the same half-life as LauncherFrecency so the most-used recents surface
// at the top of the empty query alongside frequently launched apps.
@available(macOS 26.0, *)
class LauncherRecents {
    private struct Entry: Codable {
        var title: String
        var isURL: Bool
        var timestamps: [Double]
    }

    private static let key = "LauncherRecents.entries"
    private static let maxEntries = 40
    private static let maxTimestamps = 20
    private static let halfLifeSeconds: Double = 3 * 24 * 3600

    private let defaults = UserDefaults.standard
    private var entries: [String: Entry] = [:]

    init() { load() }

    // Record an opened file/folder (key = filesystem path) or URL (key = absolute string).
    func record(key: String, title: String, isURL: Bool) {
        var entry = entries[key] ?? Entry(title: title, isURL: isURL, timestamps: [])
        entry.title = title
        entry.isURL = isURL
        entry.timestamps.append(Date().timeIntervalSince1970)
        if entry.timestamps.count > Self.maxTimestamps {
            entry.timestamps = Array(entry.timestamps.suffix(Self.maxTimestamps))
        }
        entries[key] = entry
        prune()
        save()
    }

    // Recent results with their frecency scores, most-used first. Files that no longer
    // exist are skipped so a stale recent never shows up only to fail on open.
    func scoredResults() -> [(result: LauncherResult, score: Double)] {
        entries.compactMap { key, entry -> (result: LauncherResult, score: Double)? in
            let score = Self.score(entry.timestamps)
            guard score > 0 else { return nil }
            if !entry.isURL, !FileManager.default.fileExists(atPath: key) { return nil }
            return (makeResult(key: key, entry: entry), score)
        }
        .sorted { $0.score > $1.score }
    }

    private func makeResult(key: String, entry: Entry) -> LauncherResult {
        if entry.isURL, let url = URL(string: key) {
            return LauncherResult(
                id: key,
                title: entry.title,
                subtitle: key,
                icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
                action: .openURL(url: url)
            )
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: key, isDirectory: &isDir)
        return LauncherResult(
            id: key,
            title: entry.title,
            subtitle: isDir.boolValue ? "Folder" : key,
            icon: NSWorkspace.shared.icon(forFile: key),
            action: .openFile(url: URL(fileURLWithPath: key))
        )
    }

    private static func score(_ timestamps: [Double]) -> Double {
        let now = Date().timeIntervalSince1970
        return timestamps.reduce(0.0) { $0 + pow(2.0, -(now - $1) / Self.halfLifeSeconds) }
    }

    private func prune() {
        let cutoff = Date().timeIntervalSince1970 - Self.halfLifeSeconds * 10
        for (key, entry) in entries {
            let recent = entry.timestamps.filter { $0 >= cutoff }
            if recent.isEmpty {
                entries.removeValue(forKey: key)
            } else if recent.count != entry.timestamps.count {
                var updated = entry
                updated.timestamps = recent
                entries[key] = updated
            }
        }
        if entries.count > Self.maxEntries {
            let kept = entries.sorted { Self.score($0.value.timestamps) > Self.score($1.value.timestamps) }
                .prefix(Self.maxEntries)
            entries = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
