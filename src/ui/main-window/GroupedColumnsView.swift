import Cocoa

class GroupedColumnsView {
    static var contentView: EffectView!
    private static var innerView = NSView()
    private static var clipView = NSView()
    private static var selectedGroupIndex = 0
    private static var selectedWindowIndex = 0

    private static let columnMinWidth: CGFloat = 200
    private static let headerHeight: CGFloat = 28
    private static let rowHeight: CGFloat = 24
    private static let iconSize: CGFloat = 16
    private static let padding: CGFloat = 16
    private static let dividerWidth: CGFloat = 1

    private static var columnOffsets = [CGFloat]()
    private static var columnWidths = [CGFloat]()

    static func initialize() {
        contentView = makeAppropriateEffectView()
        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        clipView.addSubview(innerView)
        contentView.addSubview(clipView)
    }

    static func updateItemsAndLayout(animated: Bool = false) {
        innerView.subviews.removeAll()
        let groups = Windows.groupedList
        guard !groups.isEmpty else { return }
        selectedGroupIndex = min(selectedGroupIndex, groups.count - 1)
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        let columnWidth = max(columnMinWidth, estimateColumnWidth(groups))
        let maxRows = groups.map(\.windows.count).max() ?? 0
        let totalHeight = padding + headerHeight + CGFloat(maxRows) * rowHeight + padding

        columnOffsets.removeAll()
        columnWidths.removeAll()

        var x: CGFloat = padding
        for (groupIdx, group) in groups.enumerated() {
            if groupIdx > 0 {
                addDivider(x: x, height: totalHeight)
                x += dividerWidth
            }
            columnOffsets.append(x)
            columnWidths.append(columnWidth)
            addColumn(group, groupIdx: groupIdx, x: x, width: columnWidth, totalHeight: totalHeight)
            x += columnWidth
        }
        x += padding

        let innerWidth = x
        let innerSize = NSSize(width: innerWidth, height: totalHeight)
        innerView.frame.size = innerSize

        let screen = NSScreen.preferred
        let maxViewWidth = screen.frame.width * Appearance.maxWidthOnScreen
        let viewWidth = min(innerWidth, maxViewWidth)
        let viewSize = NSSize(width: viewWidth, height: totalHeight)
        clipView.frame = NSRect(origin: .zero, size: viewSize)
        contentView.frame = NSRect(origin: .zero, size: viewSize)
        contentView.updateAppearance()

        centerOnSelectedColumn(animated: animated)
    }

    private static func centerOnSelectedColumn(animated: Bool) {
        guard selectedGroupIndex < columnOffsets.count else { return }
        let colX = columnOffsets[selectedGroupIndex]
        let colW = columnWidths[selectedGroupIndex]
        let colCenter = colX + colW * 0.5
        let viewWidth = clipView.frame.width
        let innerWidth = innerView.frame.width
        var targetX = colCenter - viewWidth * 0.5
        targetX = max(0, min(targetX, innerWidth - viewWidth))
        let newOrigin = NSPoint(x: -targetX, y: 0)
        guard animated else {
            innerView.frame.origin = newOrigin
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            innerView.animator().frame.origin = newOrigin
        }
    }

    private static func addDivider(x: CGFloat, height: CGFloat) {
        let divider = NSView(frame: NSRect(x: x, y: 0, width: dividerWidth, height: height))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        innerView.addSubview(divider)
    }

    private static func addColumn(_ group: WindowGroup, groupIdx: Int, x: CGFloat, width: CGFloat, totalHeight: CGFloat) {
        let column = NSView(frame: NSRect(x: x, y: 0, width: width, height: totalHeight))
        let header = NSTextField(labelWithString: group.name)
        header.font = .boldSystemFont(ofSize: 13)
        header.textColor = .labelColor
        header.frame = NSRect(x: padding, y: totalHeight - padding - headerHeight, width: width - padding * 2, height: headerHeight)
        column.addSubview(header)
        for (winIdx, window) in group.windows.enumerated() {
            let rowY = totalHeight - padding - headerHeight - CGFloat(winIdx + 1) * rowHeight
            let isSelected = groupIdx == selectedGroupIndex && winIdx == selectedWindowIndex
            addRow(to: column, label: group.displayLabels[winIdx], window: window, y: rowY, width: width, isSelected: isSelected)
        }
        innerView.addSubview(column)
    }

    private static func addRow(to parent: NSView, label: String, window: Window, y: CGFloat, width: CGFloat, isSelected: Bool) {
        let row = NSView(frame: NSRect(x: 0, y: y, width: width, height: rowHeight))
        row.wantsLayer = true
        if isSelected {
            row.layer?.backgroundColor = NSColor.systemAccentColor.cgColor
            row.layer?.cornerRadius = 4
        }
        let iconView = NSImageView(frame: NSRect(x: padding, y: (rowHeight - iconSize) / 2, width: iconSize, height: iconSize))
        iconView.image = iconForWindow(window)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        row.addSubview(iconView)
        if window.isBusy {
            let busySize = iconSize + 4
            let busyView = NSView(frame: NSRect(x: padding - 2, y: (rowHeight - busySize) / 2, width: busySize, height: busySize))
            busyView.wantsLayer = true
            busyView.layer?.masksToBounds = false
            let busy = BusyIndicatorLayer()
            busy.frame = CGRect(x: 0, y: 0, width: busySize, height: busySize)
            busy.update(busy: true, size: busySize)
            busyView.layer?.addSublayer(busy)
            row.addSubview(busyView)
        }
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12)
        text.textColor = isSelected ? .white : .labelColor
        text.lineBreakMode = .byTruncatingTail
        text.frame = NSRect(x: padding + iconSize + 4, y: 2, width: width - padding * 2 - iconSize - 4, height: rowHeight - 4)
        row.addSubview(text)
        parent.addSubview(row)
    }

    private static func iconForWindow(_ window: Window) -> NSImage? {
        if let cgImage = window.application.icon {
            return NSImage(cgImage: cgImage, size: NSSize(width: iconSize, height: iconSize))
        }
        return window.application.runningApplication.icon
    }

    private static func estimateColumnWidth(_ groups: [WindowGroup]) -> CGFloat {
        var maxWidth: CGFloat = columnMinWidth
        for group in groups {
            for label in group.displayLabels {
                let size = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
                maxWidth = max(maxWidth, size.width + padding * 2 + iconSize + 12)
            }
            let headerSize = (group.name as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            maxWidth = max(maxWidth, headerSize.width + padding * 2 + 8)
        }
        return min(maxWidth, 300)
    }

    static func selectedWindow() -> Window? {
        let groups = Windows.groupedList
        guard selectedGroupIndex < groups.count else { return nil }
        let group = groups[selectedGroupIndex]
        guard selectedWindowIndex < group.windows.count else { return nil }
        return group.windows[selectedWindowIndex]
    }

    static func navigateUp() {
        let groups = Windows.groupedList
        guard selectedGroupIndex < groups.count else { return }
        let count = groups[selectedGroupIndex].windows.count
        selectedWindowIndex = (selectedWindowIndex - 1 + count) % count
        updateItemsAndLayout()
    }

    static func navigateDown() {
        let groups = Windows.groupedList
        guard selectedGroupIndex < groups.count else { return }
        let count = groups[selectedGroupIndex].windows.count
        selectedWindowIndex = (selectedWindowIndex + 1) % count
        updateItemsAndLayout()
    }

    static func navigateLeft() {
        let groups = Windows.groupedList
        guard groups.count > 1 else { return }
        selectedGroupIndex = (selectedGroupIndex - 1 + groups.count) % groups.count
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        updateItemsAndLayout(animated: true)
    }

    static func navigateRight() {
        let groups = Windows.groupedList
        guard groups.count > 1 else { return }
        selectedGroupIndex = (selectedGroupIndex + 1) % groups.count
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        updateItemsAndLayout(animated: true)
    }

    static func resetSelection() {
        let groups = Windows.groupedList
        guard let previousWindow = Windows.list.first(where: { $0.lastFocusOrder == 1 }) else {
            selectedGroupIndex = 0
            selectedWindowIndex = 0
            return
        }
        for (gi, group) in groups.enumerated() {
            if let wi = group.windows.firstIndex(where: { $0.id == previousWindow.id }) {
                selectedGroupIndex = gi
                selectedWindowIndex = wi
                return
            }
        }
        selectedGroupIndex = 0
        selectedWindowIndex = 0
    }
}
