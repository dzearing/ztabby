import Cocoa
import SwiftUI

@available(macOS 26.0, *)
@Observable
class LauncherViewModel {
    var query = "" {
        didSet { updateResults() }
    }
    var results = [LauncherAppEntry]()
    var selectedIndex = 0

    private let discovery: LauncherAppDiscovery
    private let frecency: LauncherFrecency

    init(discovery: LauncherAppDiscovery, frecency: LauncherFrecency) {
        self.discovery = discovery
        self.frecency = frecency
        updateResults()
    }

    var topResult: LauncherAppEntry? {
        results.first
    }

    var ghostCompletion: String? {
        guard !query.isEmpty, let top = topResult else { return nil }
        let nameLower = top.name.lowercased()
        let queryLower = query.lowercased()
        guard nameLower.hasPrefix(queryLower) else { return "\u{2009}\u{2014} " + top.name }
        let remaining = String(top.name.dropFirst(query.count))
        guard !remaining.isEmpty else { return nil }
        return remaining
    }

    func acceptCompletion() {
        guard let top = topResult else { return }
        let nameLower = top.name.lowercased()
        let queryLower = query.lowercased()
        if nameLower.hasPrefix(queryLower) {
            query = top.name
        }
    }

    func updateResults() {
        results = LauncherSearch.rank(discovery.apps, query: query, frecency: frecency)
        selectedIndex = 0
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    func launchSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let entry = results[selectedIndex]
        if let bid = entry.bundleIdentifier {
            frecency.recordLaunch(bid)
        }
        NSWorkspace.shared.open(entry.bundleURL)
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }
}
