import Foundation

class LauncherSearch {
    static func rank(_ apps: [LauncherAppEntry], query: String, frecency: LauncherFrecency) -> [LauncherAppEntry] {
        guard !query.isEmpty else {
            return apps.sorted { frecency.score($0.bundleIdentifier) > frecency.score($1.bundleIdentifier) }
        }
        let queryLower = query.lowercased()
        var scored = [(entry: LauncherAppEntry, score: Double)]()
        for app in apps {
            let matchScore = matchScore(app, queryLower)
            guard matchScore > 0 else { continue }
            let frecencyScore = frecency.score(app.bundleIdentifier)
            let combined = matchScore + frecencyScore * 0.3
            scored.append((app, combined))
        }
        scored.sort { $0.score > $1.score }
        return scored.map { $0.entry }
    }

    private static func matchScore(_ app: LauncherAppEntry, _ queryLower: String) -> Double {
        let name = app.nameLowercased
        if name == queryLower { return 10.0 }
        if name.hasPrefix(queryLower) { return 8.0 + (Double(queryLower.count) / Double(max(name.count, 1))) }
        if let range = name.range(of: queryLower) {
            let position = name.distance(from: name.startIndex, to: range.lowerBound)
            return 5.0 - Double(position) * 0.1
        }
        let acronym = acronymMatch(name, queryLower)
        if acronym > 0 { return 4.0 + acronym }
        let subsequence = subsequenceMatch(name, queryLower)
        if subsequence > 0 { return subsequence }
        return 0
    }

    private static func acronymMatch(_ name: String, _ query: String) -> Double {
        var initials = [Character]()
        var prevWasSpace = true
        for ch in name {
            if prevWasSpace && !ch.isWhitespace {
                initials.append(ch)
            }
            prevWasSpace = ch.isWhitespace || ch == "-" || ch == "_"
        }
        guard initials.count >= query.count else { return 0 }
        let acronym = String(initials).lowercased()
        guard acronym.hasPrefix(query) else { return 0 }
        return Double(query.count) / Double(max(initials.count, 1))
    }

    private static func subsequenceMatch(_ name: String, _ query: String) -> Double {
        var nameIdx = name.startIndex
        var matched = 0
        var gaps = 0
        var prevMatched = false
        for qChar in query {
            var found = false
            while nameIdx < name.endIndex {
                let nChar = name[nameIdx]
                nameIdx = name.index(after: nameIdx)
                if nChar == qChar {
                    matched += 1
                    if !prevMatched && matched > 1 { gaps += 1 }
                    prevMatched = true
                    found = true
                    break
                }
                prevMatched = false
            }
            guard found else { return 0 }
        }
        guard matched == query.count else { return 0 }
        let ratio = Double(matched) / Double(max(name.count, 1))
        let penalty = Double(gaps) * 0.15
        return max(0.1, 2.0 * ratio - penalty)
    }
}
