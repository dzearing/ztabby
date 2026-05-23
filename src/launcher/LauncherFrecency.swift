import Foundation

class LauncherFrecency {
    private static let suiteName = "\(App.bundleIdentifier).launcher"
    private static let maxEvents = 100
    private static let halfLifeSeconds: Double = 3 * 24 * 3600

    private var defaults: UserDefaults
    private var cache = [String: [Double]]()

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        loadCache()
    }

    func recordLaunch(_ bundleIdentifier: String) {
        var timestamps = cache[bundleIdentifier] ?? []
        timestamps.append(Date().timeIntervalSince1970)
        if timestamps.count > Self.maxEvents {
            timestamps = Array(timestamps.suffix(Self.maxEvents))
        }
        cache[bundleIdentifier] = timestamps
        defaults.set(timestamps, forKey: bundleIdentifier)
    }

    func score(_ bundleIdentifier: String?) -> Double {
        guard let bundleIdentifier, let timestamps = cache[bundleIdentifier], !timestamps.isEmpty else { return 0 }
        let now = Date().timeIntervalSince1970
        return timestamps.reduce(0.0) { sum, ts in
            let age = now - ts
            return sum + pow(2.0, -age / Self.halfLifeSeconds)
        }
    }

    private func loadCache() {
        guard let dict = defaults.persistentDomain(forName: Self.suiteName) else { return }
        for (key, value) in dict {
            guard let timestamps = value as? [Double] else { continue }
            cache[key] = timestamps
        }
    }

    func prune() {
        let cutoff = Date().timeIntervalSince1970 - Self.halfLifeSeconds * 10
        for (key, timestamps) in cache {
            let pruned = timestamps.filter { $0 >= cutoff }
            if pruned.isEmpty {
                cache.removeValue(forKey: key)
                defaults.removeObject(forKey: key)
            } else if pruned.count != timestamps.count {
                cache[key] = pruned
                defaults.set(pruned, forKey: key)
            }
        }
    }
}
