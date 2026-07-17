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
    private(set) var mode: LauncherMode = .apps

    private let maxResults = 8
    private let discovery: LauncherAppDiscovery
    private let frecency: LauncherFrecency
    // While cycling path candidates with Tab/arrows we preview the selection in the
    // field without re-listing, so the sibling set stays put. suppressUpdate guards that.
    private var suppressUpdate = false
    private var pathCycle: [LauncherResult]?

    init(discovery: LauncherAppDiscovery, frecency: LauncherFrecency) {
        self.discovery = discovery
        self.frecency = frecency
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

    func launchSelected() {
        guard let result = selectedResult else {
            launchRawPath()
            return
        }
        perform(result.action)
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
        case .apps: return LauncherSearch.rank(discovery.apps, query: query, frecency: frecency).map(LauncherResult.init(app:))
        case .path: return LauncherPathSearch.results(for: query)
        case .url: return urlResults()
        }
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

    private func launchRawPath() {
        guard mode == .path, let url = LauncherPathSearch.openURL(for: query) else { return }
        NSWorkspace.shared.open(url)
    }

    private func perform(_ action: LauncherAction) {
        switch action {
        case .launchApp(let url, let bundleIdentifier):
            if let bundleIdentifier { frecency.recordLaunch(bundleIdentifier) }
            NSWorkspace.shared.open(url)
        case .openFile(let url), .openURL(let url):
            NSWorkspace.shared.open(url)
        }
    }
}
