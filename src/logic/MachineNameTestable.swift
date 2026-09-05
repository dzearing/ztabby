import Foundation

/// Ghoztty publishes an `AXGhosttyMachine` value per terminal window. Windows that run on this Mac
/// can report it under several names ("Local", "localhost", "127.0.0.1", this Mac's hostname, ...)
/// depending on how their session was opened, so we fold those aliases into one name instead of
/// showing a card per alias.
class MachineNameTestable {
    static let localMachineName = "Local"

    static func normalize(_ machine: String?) -> String? {
        guard let machine else { return nil }
        return isLocal(machine) ? localMachineName : machine
    }

    static func isLocal(_ machine: String) -> Bool {
        isLocal(machine, localAliases)
    }

    static func isLocal(_ machine: String, _ aliases: Set<String>) -> Bool {
        let cleaned = clean(machine)
        guard !cleaned.isEmpty else { return false }
        return aliases.contains(cleaned) || aliases.contains(withoutLocalSuffix(cleaned))
    }

    static func aliases(_ hostNames: [String?]) -> Set<String> {
        var result = loopbackAliases
        for name in hostNames.compactMap({ $0 }).map(clean) where !name.isEmpty {
            result.insert(name)
            result.insert(withoutLocalSuffix(name))
        }
        return result
    }

    static let loopbackAliases: Set<String> = ["local", "local machine", "localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]

    /// this Mac's own names; resolved once, and without `Host.current().names` as that one can block on DNS
    private static let localAliases = aliases([ProcessInfo.processInfo.hostName, Host.current().localizedName])

    private static func clean(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func withoutLocalSuffix(_ name: String) -> String {
        name.hasSuffix(".local") ? String(name.dropLast(".local".count)) : name
    }
}
