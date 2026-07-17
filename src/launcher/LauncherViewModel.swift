import Cocoa
import SwiftUI

@available(macOS 26.0, *)
@Observable
class LauncherViewModel {
    var query = "" {
        didSet { if !suppressUpdate { updateResults() } }
    }
    var results = [LauncherResult]()
    var selectedIndex = 0
    // Set when a launch is rejected (e.g. a path that no longer exists); shown as a banner.
    var errorMessage: String?
    private(set) var mode: LauncherMode = .apps

    private let maxResults = 8
    private let discovery: LauncherAppDiscovery
    private let frecency: LauncherFrecency
    private let recents: LauncherRecents
    // While cycling path candidates with Tab/arrows we preview the selection in the
    // field without re-listing, so the sibling set stays put. suppressUpdate guards that.
    private var suppressUpdate = false
    private var pathCycle: [LauncherResult]?

    init(discovery: LauncherAppDiscovery, frecency: LauncherFrecency, recents: LauncherRecents) {
        self.discovery = discovery
        self.frecency = frecency
        self.recents = recents
        updateResults()
    }

    var topResult: LauncherResult? { results.first }

    var selectedResult: LauncherResult? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : results.first
    }

    var ghostCompletion: String? {
        guard !query.isEmpty, let selected = selectedResult else { return nil }
        switch mode {
        case .apps: return appGhost(selected)
        case .path: return pathGhost(selected)
        case .url: return nil
        }
    }

    func updateResults() {
        errorMessage = nil
        mode = Self.detectMode(query)
        pathCycle = nil
        results = Array(makeResults().prefix(maxResults))
        selectedIndex = 0
    }

    func acceptCompletion() {
        switch mode {
        case .apps: acceptAppCompletion()
        case .path: acceptPathCompletion()
        case .url: break
        }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let next = max(0, min(results.count - 1, selectedIndex + delta))
        guard pathCycle != nil else { selectedIndex = next; return }
        previewPathCandidate(at: next)
    }

    // Returns true if something was launched (or there was nothing to launch) and the
    // window should close; false if the launch was rejected and an error banner is showing.
    @discardableResult
    func launchSelected() -> Bool {
        errorMessage = nil
        guard let result = selectedResult else {
            // No concrete result. In path mode, try opening the raw typed path; otherwise
            // (e.g. an app search with no match) there is nothing to do — just dismiss.
            return mode == .path ? launchRawPath() : true
        }
        return perform(result.action)
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }

    private static func detectMode(_ query: String) -> LauncherMode {
        if LauncherPathSearch.isPathQuery(query) { return .path }
        if LauncherURL.url(for: query) != nil { return .url }
        return .apps
    }

    private func makeResults() -> [LauncherResult] {
        switch mode {
        case .apps:
            let ranked = LauncherSearch.rank(discovery.apps, query: query, frecency: frecency).map(LauncherResult.init(app:))
            // On the empty query, blend recently opened files/folders/URLs in with the apps.
            return query.isEmpty ? mergedWithRecents(ranked) : ranked
        case .path: return LauncherPathSearch.results(for: query)
        case .url: return urlResults()
        }
    }

    // Merge recent files/folders/URLs with the frecency-ranked apps by score, so the most-used
    // recents rise to the top. Ties favor recents, then the app list's existing order.
    private func mergedWithRecents(_ apps: [LauncherResult]) -> [LauncherResult] {
        let recentScored = recents.scoredResults()
        guard !recentScored.isEmpty else { return apps }
        var scored = [(result: LauncherResult, score: Double, order: Int)]()
        var order = 0
        for item in recentScored {
            scored.append((item.result, item.score, order)); order += 1
        }
        for app in apps {
            scored.append((app, appScore(app), order)); order += 1
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.map { $0.result }
    }

    private func appScore(_ result: LauncherResult) -> Double {
        if case .launchApp(_, let bundleIdentifier) = result.action { return frecency.score(bundleIdentifier) }
        return 0
    }

    private func urlResults() -> [LauncherResult] {
        guard let url = LauncherURL.url(for: query) else { return [] }
        return [LauncherResult(
            id: "url",
            title: url.absoluteString,
            subtitle: "Open in browser",
            icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
            action: .openURL(url: url)
        )]
    }

    private func appGhost(_ selected: LauncherResult) -> String? {
        let nameLower = selected.title.lowercased()
        guard nameLower.hasPrefix(query.lowercased()) else { return "\u{2009}\u{2014} " + selected.title }
        let remaining = String(selected.title.dropFirst(query.count))
        return remaining.isEmpty ? nil : remaining
    }

    private func pathGhost(_ selected: LauncherResult) -> String? {
        guard let completion = selected.completion, completion.hasPrefix(query), completion.count > query.count else { return nil }
        return String(completion.dropFirst(query.count))
    }

    private func acceptAppCompletion() {
        guard let top = results.first, top.title.lowercased().hasPrefix(query.lowercased()) else { return }
        query = top.title
    }

    private func acceptPathCompletion() {
        if let candidates = pathCycle {
            previewPathCandidate(at: (selectedIndex + 1) % candidates.count)
            return
        }
        guard !results.isEmpty else { return }
        // First Tab: extend to the longest common completion when it strictly grows the query.
        if results.count > 1, let lcp = LauncherPathSearch.longestCommonCompletion(results), lcp.count > query.count {
            query = lcp
            return
        }
        // Otherwise start cycling: anchor the current candidates and preview the selected one.
        pathCycle = results
        let alreadyShown = selectedResult?.completion == query
        previewPathCandidate(at: alreadyShown ? (selectedIndex + 1) % results.count : selectedIndex)
    }

    // Show a path candidate's completion in the field without re-listing its siblings.
    private func previewPathCandidate(at index: Int) {
        guard let candidates = pathCycle, candidates.indices.contains(index),
              let completion = candidates[index].completion else { return }
        suppressUpdate = true
        query = completion
        suppressUpdate = false
        results = candidates
        selectedIndex = index
    }

    @discardableResult
    private func launchRawPath() -> Bool {
        guard let url = LauncherPathSearch.openURL(for: query) else {
            errorMessage = "No such file or folder: \(query)"
            return false
        }
        recordRecentFile(url)
        NSWorkspace.shared.open(url)
        return true
    }

    @discardableResult
    private func perform(_ action: LauncherAction) -> Bool {
        switch action {
        case .launchApp(let url, let bundleIdentifier):
            if let bundleIdentifier { frecency.recordLaunch(bundleIdentifier) }
            NSWorkspace.shared.open(url)
            return true
        case .openFile(let url):
            // The candidate may have been deleted since it was listed — recheck before opening.
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = "No such file or folder: \(url.path)"
                return false
            }
            recordRecentFile(url)
            NSWorkspace.shared.open(url)
            return true
        case .openURL(let url):
            recents.record(key: url.absoluteString, title: url.absoluteString, isURL: true)
            NSWorkspace.shared.open(url)
            return true
        }
    }

    private func recordRecentFile(_ url: URL) {
        recents.record(key: url.path, title: url.lastPathComponent, isURL: false)
    }
}
