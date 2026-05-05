import Cocoa

struct WindowGroup {
    let name: String
    let windows: [Window]
    let displayLabels: [String]
}

class WindowGrouper {
    static func group(_ windows: [Window]) -> [WindowGroup] {
        var grouped = [(name: String, entries: [(window: Window, label: String)])]()
        var ungrouped = [(window: Window, label: String)]()
        var groupIndex = [String: Int]()
        for window in windows {
            if let range = window.title.range(of: ": ") {
                let name = String(window.title[..<range.lowerBound])
                let label = String(window.title[range.upperBound...])
                if let idx = groupIndex[name] {
                    grouped[idx].entries.append((window, label))
                } else {
                    groupIndex[name] = grouped.count
                    grouped.append((name, [(window, label)]))
                }
            } else {
                ungrouped.append((window, window.title))
            }
        }
        grouped.sort { bestFocus($0.entries) < bestFocus($1.entries) }
        for i in grouped.indices {
            grouped[i].entries.sort { $0.window.lastFocusOrder < $1.window.lastFocusOrder }
        }
        var result = grouped.map { WindowGroup(name: $0.name, windows: $0.entries.map(\.window), displayLabels: $0.entries.map(\.label)) }
        if !ungrouped.isEmpty {
            ungrouped.sort { $0.window.lastFocusOrder < $1.window.lastFocusOrder }
            result.append(WindowGroup(name: NSLocalizedString("Other", comment: ""), windows: ungrouped.map(\.window), displayLabels: ungrouped.map(\.label)))
        }
        return result
    }

    private static func bestFocus(_ entries: [(window: Window, label: String)]) -> Int {
        entries.map(\.window.lastFocusOrder).min() ?? Int.max
    }
}
