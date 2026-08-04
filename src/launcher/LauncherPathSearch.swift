import Cocoa

// Filesystem tab-completion for path-mode queries (starting with / or ~).
enum LauncherPathSearch {
    private static let maxCandidates = 12

    static func isPathQuery(_ query: String) -> Bool {
        query.hasPrefix("/") || query.hasPrefix("~")
    }

    static func results(for query: String) -> [LauncherResult] {
        let (dirAsTyped, prefix) = split(query)
        let expandedDir = expand(dirAsTyped)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: expandedDir) else { return [] }
        return rank(names, prefix: prefix)
            .prefix(maxCandidates)
            .map { result(name: $0, dirAsTyped: dirAsTyped, expandedDir: expandedDir) }
    }

    // URL to open when Return is pressed on a raw path with no candidate selected.
    static func openURL(for query: String) -> URL? {
        let expanded = expand(query)
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    // Longest common completion across candidates, used for the first Tab press.
    static func longestCommonCompletion(_ results: [LauncherResult]) -> String? {
        let completions = results.compactMap { $0.completion }
        guard var lcp = completions.first else { return nil }
        for completion in completions.dropFirst() {
            lcp = lcp.commonPrefix(with: completion, options: [.caseInsensitive])
        }
        return lcp
    }

    // Splits into (directory-as-typed-including-trailing-slash, prefix-to-match).
    static func split(_ query: String) -> (dir: String, prefix: String) {
        if let slash = query.lastIndex(of: "/") {
            return (String(query[...slash]), String(query[query.index(after: slash)...]))
        }
        if query.hasPrefix("~") {
            return ("~/", String(query.dropFirst()))
        }
        return (query, "")
    }

    private static func expand(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.isEmpty ? "/" : expanded
    }

    private static func rank(_ names: [String], prefix: String) -> [String] {
        let showHidden = prefix.hasPrefix(".")
        let prefixLower = prefix.lowercased()
        let matches = names.filter { name in
            guard showHidden || !name.hasPrefix(".") else { return false }
            return prefix.isEmpty || name.lowercased().hasPrefix(prefixLower)
        }
        return matches.sorted { a, b in
            let aExact = a.hasPrefix(prefix), bExact = b.hasPrefix(prefix)
            guard aExact == bExact else { return aExact }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    private static func result(name: String, dirAsTyped: String, expandedDir: String) -> LauncherResult {
        let fullPath = (expandedDir as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
        // No trailing slash: Tab completes the name; the user types "/" to drill in.
        let completion = dirAsTyped + name
        return LauncherResult(
            id: fullPath,
            title: name,
            subtitle: isDir.boolValue ? "Folder" : fullPath,
            icon: NSWorkspace.shared.icon(forFile: fullPath),
            action: .openFile(url: URL(fileURLWithPath: fullPath)),
            completion: completion
        )
    }
}
