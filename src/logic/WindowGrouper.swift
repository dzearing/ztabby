import Cocoa

struct WindowGroup {
    let name: String
    let windows: [Window]
    let displayLabels: [String]
}

/// One card per machine; `columns` is the existing title-prefix grouping applied within that machine.
struct MachineCard {
    let name: String
    let columns: [WindowGroup]
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

    private static func bestFocus(_ windows: [Window]) -> Int {
        windows.map(\.lastFocusOrder).min() ?? Int.max
    }

    /// Groups windows into one card per machine, keyed on the Ghoztty `AXGhosttyMachine` attribute.
    /// Non-Ghoztty windows are treated as running on the local machine ("Local"), as are the windows
    /// Ghoztty reports under an alias of this Mac (localhost, 127.0.0.1, this Mac's hostname, ...).
    /// Within each machine card we reuse the existing title-prefix grouping, so headers are preserved
    /// per machine. Returns nil unless the Ghoztty windows span at least two distinct machines, so
    /// this only activates when there is genuinely more than one machine to disambiguate.
    static func machineGroups(_ windows: [Window]) -> [MachineCard]? {
        guard Set(windows.compactMap { MachineNameTestable.normalize($0.ghosttyMachine) }).count >= 2 else { return nil }
        var order = [String]()
        var byMachine = [String: [Window]]()
        for window in windows {
            let machine = MachineNameTestable.normalize(window.ghosttyMachine) ?? localMachineName
            if byMachine[machine] == nil { order.append(machine) }
            byMachine[machine, default: []].append(window)
        }
        let sorted = order.sorted { bestFocus(byMachine[$0]!) < bestFocus(byMachine[$1]!) }
        return sorted.map { MachineCard(name: $0, columns: group(byMachine[$0]!)) }
    }

    static let localMachineName = MachineNameTestable.localMachineName
}
