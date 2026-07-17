import Cocoa

enum LauncherMode {
    case apps
    case path
    case url
}

enum LauncherAction {
    case launchApp(url: URL, bundleIdentifier: String?)
    case openFile(url: URL)
    case openURL(url: URL)
}

struct LauncherResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    var icon: NSImage?
    let action: LauncherAction
    // When set (path mode), the text Tab completes the query to.
    let completion: String?

    init(id: String, title: String, subtitle: String, icon: NSImage?, action: LauncherAction, completion: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
        self.completion = completion
    }

    init(app: LauncherAppEntry) {
        self.init(
            id: app.id,
            title: app.name,
            subtitle: app.kind.rawValue,
            icon: app.icon,
            action: .launchApp(url: app.bundleURL, bundleIdentifier: app.bundleIdentifier)
        )
    }
}
