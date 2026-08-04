import Cocoa

class LauncherAppDiscovery {
    private(set) var apps = [LauncherAppEntry]()
    private var knownPaths = Set<String>()
    private var fsEventStream: FSEventStreamRef?
    private let watchedDirs: [String]
    private var onChange: (() -> Void)?

    static let searchDirectories: [String] = {
        var dirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        if let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path as String? {
            dirs.append(home)
        }
        return dirs
    }()

    init() {
        watchedDirs = Self.searchDirectories
    }

    func scan(onChange: @escaping () -> Void) {
        self.onChange = onChange
        rescan()
        startWatching()
    }

    func rescan() {
        knownPaths.removeAll()
        var entries = [LauncherAppEntry]()
        for dir in watchedDirs {
            scanDirectory(dir, &entries)
        }
        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        apps = entries
    }

    func loadAllIcons() {
        for i in apps.indices {
            apps[i].loadIconIfNeeded()
        }
    }

    private func scanDirectory(_ path: String, _ entries: inout [LauncherAppEntry]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
        for item in contents {
            guard item.hasSuffix(".app") else { continue }
            let fullPath = (path as NSString).appendingPathComponent(item)
            guard !knownPaths.contains(fullPath) else { continue }
            knownPaths.insert(fullPath)
            entries.append(LauncherAppEntry(URL(fileURLWithPath: fullPath)))
        }
    }

    private func startWatching() {
        guard fsEventStream == nil else { return }
        var dirs = watchedDirs as [CFString]
        let paths = dirs.withUnsafeMutableBufferPointer { buffer -> CFArray in
            CFArrayCreate(nil, UnsafeMutableRawPointer(buffer.baseAddress)!.assumingMemoryBound(to: UnsafeRawPointer?.self), buffer.count, nil)
        }
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, _, _, _, _) in
                guard let info else { return }
                let discovery = Unmanaged<LauncherAppDiscovery>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { discovery.handleFSEvent() }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }
        fsEventStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    private func handleFSEvent() {
        rescan()
        loadAllIcons()
        onChange?()
    }

    deinit {
        guard let stream = fsEventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
