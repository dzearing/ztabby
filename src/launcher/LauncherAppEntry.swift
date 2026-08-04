import Cocoa

struct LauncherAppEntry: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL
    let kind: LauncherAppKind
    var icon: NSImage?
    var nameLowercased: String

    init(_ bundleURL: URL) {
        self.bundleURL = bundleURL
        let bundle = Bundle(url: bundleURL)
        self.name = bundle?.infoDictionary?["CFBundleName"] as? String
            ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
        self.bundleIdentifier = bundle?.bundleIdentifier
        self.id = bundleIdentifier ?? bundleURL.absoluteString
        self.nameLowercased = name.lowercased()
        self.kind = Self.classifyPath(bundleURL)
        self.icon = nil
    }

    mutating func loadIconIfNeeded() {
        guard icon == nil else { return }
        icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
    }

    private static func classifyPath(_ url: URL) -> LauncherAppKind {
        let path = url.path
        if path.hasPrefix("/System/Applications/Utilities") { return .utility }
        if path.hasPrefix("/System/Applications") { return .system }
        return .application
    }
}

enum LauncherAppKind: String {
    case application = "Application"
    case system = "System"
    case utility = "Utility"
}
