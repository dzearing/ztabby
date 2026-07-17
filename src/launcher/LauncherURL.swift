import Foundation

// Detects when a query is a web address and normalizes it to a URL.
enum LauncherURL {
    static func url(for query: String) -> URL? {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return URL(string: text)
        }
        guard looksLikeHost(text) else { return nil }
        return URL(string: "https://" + text)
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        let host = String(text.split(separator: "/", maxSplits: 1).first ?? "")
        guard !host.isEmpty else { return false }
        if host == "localhost" || host.hasPrefix("localhost:") { return true }
        let hostname = String(host.split(separator: ":", maxSplits: 1).first ?? "")
        return isDomain(hostname)
    }

    private static func isDomain(_ hostname: String) -> Bool {
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else { return false }
        return true
    }
}
