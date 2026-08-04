import Cocoa

class GroupedColumnsView {
    static var contentView: EffectView!
    private static var innerView = NSView()
    private static var clipView = NSView()
    private static var selectedGroupIndex = 0
    private static var selectedWindowIndex = 0

    // machine mode selection: a card (machine), a column (title-group within it), a row (window within the column)
    private static var selectedMachineIndex = 0
    private static var selectedColumnIndex = 0
    private static var selectedRowIndex = 0

    private static let columnMinWidth: CGFloat = 200
    private static let headerHeight: CGFloat = 28
    private static let rowHeight: CGFloat = 24
    private static let iconSize: CGFloat = 16
    private static let padding: CGFloat = 16
    private static let dividerWidth: CGFloat = 1

    // machine-grouping mode (one card per machine, stacked vertically, name rotated on the left edge)
    private static let machineStripWidth: CGFloat = 32
    private static let cardGap: CGFloat = 12
    private static let cardCornerRadius: CGFloat = 8
    private static let maxCardRows = 15

    private static var columnOffsets = [CGFloat]()
    private static var columnWidths = [CGFloat]()
    private static var cardOffsetsY = [CGFloat]()
    private static var cardHeights = [CGFloat]()

    static func initialize() {
        contentView = makeAppropriateEffectView()
        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        clipView.addSubview(innerView)
        contentView.addSubview(clipView)
    }

    static func updateItemsAndLayout(animated: Bool = false) {
        if Windows.groupingMode == .machine {
            updateMachineLayout(animated: animated)
            return
        }
        innerView.subviews.removeAll()
        let groups = Windows.groupedList
        guard !groups.isEmpty else { return }
        selectedGroupIndex = min(selectedGroupIndex, groups.count - 1)
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        let columnWidth = max(columnMinWidth, estimateColumnWidth(groups))
        let maxRows = min(groups.map(\.windows.count).max() ?? 0, maxCardRows)
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

    // MARK: - machine grouping (one card per machine; existing title-groups nested inside)

    private static func updateMachineLayout(animated: Bool) {
        innerView.subviews.removeAll()
        let cards = Windows.machineCards
        guard !cards.isEmpty else { return }
        clampMachineSelection()

        let columnWidth = max(columnMinWidth, estimateColumnWidthInCards(cards))
        let cardContentWidths = cards.map { machineContentWidth($0, columnWidth) }
        let maxContentWidth = cardContentWidths.max() ?? columnWidth
        let cardWidth = machineStripWidth + padding + maxContentWidth + padding

        let heights = cards.map { machineCardHeight($0) }
        let innerHeight = padding * 2 + heights.reduce(0, +) + cardGap * CGFloat(max(0, cards.count - 1))
        let innerWidth = padding + cardWidth + padding

        cardOffsetsY.removeAll()
        cardHeights.removeAll()
        var cursorTop = innerHeight - padding
        for (machineIdx, card) in cards.enumerated() {
            let height = heights[machineIdx]
            let cardY = cursorTop - height
            cardOffsetsY.append(cardY)
            cardHeights.append(height)
            addMachineCard(card, machineIdx: machineIdx, x: padding, y: cardY, width: cardWidth, height: height, columnWidth: columnWidth)
            cursorTop = cardY - cardGap
        }

        innerView.frame.size = NSSize(width: innerWidth, height: innerHeight)
        let screen = NSScreen.preferred
        let viewWidth = min(innerWidth, screen.frame.width * Appearance.maxWidthOnScreen)
        let viewHeight = min(innerHeight, screen.frame.height * Appearance.maxHeightOnScreen)
        let viewSize = NSSize(width: viewWidth, height: viewHeight)
        clipView.frame = NSRect(origin: .zero, size: viewSize)
        contentView.frame = NSRect(origin: .zero, size: viewSize)
        contentView.updateAppearance()

        centerOnSelectedCard(animated: animated)
    }

    private static func machineColumnRows(_ card: MachineCard) -> Int {
        card.columns.map(\.windows.count).max() ?? 0
    }

    private static func machineContentWidth(_ card: MachineCard, _ columnWidth: CGFloat) -> CGFloat {
        let count = card.columns.count
        return CGFloat(count) * columnWidth + CGFloat(max(0, count - 1)) * dividerWidth
    }

    /// rows shown before the card caps its height and scrolls internally
    private static func visibleCardRows(_ card: MachineCard) -> Int {
        min(machineColumnRows(card), maxCardRows)
    }

    /// card height fits the visible (capped) title-group rows AND is tall enough to render the full rotated
    /// machine name (the name label needs `cardHeight - padding`, so leave slack for the text field's insets)
    private static func machineCardHeight(_ card: MachineCard) -> CGFloat {
        let contentHeight = headerHeight + CGFloat(visibleCardRows(card)) * rowHeight
        let nameMinHeight = machineNameLength(card.name) + padding * 2
        return max(padding + contentHeight + padding, nameMinHeight)
    }

    private static func machineNameLength(_ name: String) -> CGFloat {
        // + buffer so the rotated NSTextField (which has small internal insets) never truncates the name
        (name as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 11)]).width + 8
    }

    private static func centerOnSelectedCard(animated: Bool) {
        guard selectedMachineIndex < cardOffsetsY.count else { return }
        let cardCenterY = cardOffsetsY[selectedMachineIndex] + cardHeights[selectedMachineIndex] * 0.5
        let viewHeight = clipView.frame.height
        let innerHeight = innerView.frame.height
        var originY = viewHeight * 0.5 - cardCenterY
        originY = max(viewHeight - innerHeight, min(0, originY))
        let newOrigin = NSPoint(x: 0, y: originY)
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

    private static func addMachineCard(_ card: MachineCard, machineIdx: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, columnWidth: CGFloat) {
        let isSelectedCard = machineIdx == selectedMachineIndex
        let tint = MachinePalette.color(for: card.name)
        let cardView = NSView(frame: NSRect(x: x, y: y, width: width, height: height))
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = cardCornerRadius
        cardView.layer?.backgroundColor = tint.withAlphaComponent(isSelectedCard ? 0.22 : 0.10).cgColor
        cardView.layer?.borderWidth = isSelectedCard ? 2 : 1
        cardView.layer?.borderColor = tint.withAlphaComponent(isSelectedCard ? 1 : 0.5).cgColor
        addMachineNameLabel(to: cardView, name: card.name, height: height, tint: tint)

        let contentTop = height - padding
        let rowsAreaHeight = CGFloat(visibleCardRows(card)) * rowHeight
        var cx = machineStripWidth + padding
        for (colIdx, column) in card.columns.enumerated() {
            if colIdx > 0 {
                addCardDivider(to: cardView, x: cx, top: contentTop, height: headerHeight + rowsAreaHeight)
                cx += dividerWidth
            }
            let isColumnSelected = isSelectedCard && colIdx == selectedColumnIndex
            addCappedColumn(to: cardView, column: column, x: cx, width: columnWidth, contentTop: contentTop, isColumnSelected: isColumnSelected, selectedRow: selectedRowIndex, highlight: tint)
            cx += columnWidth
        }
        innerView.addSubview(cardView)
    }

    /// renders a title-group column with a fixed header and a height-capped, internally-scrollable rows area.
    /// Any column with more than `maxCardRows` windows is clipped and shows a top/bottom fade; the selected
    /// column scrolls to keep its selected row visible (and clear of the fade).
    private static func addCappedColumn(to parent: NSView, column: WindowGroup, x: CGFloat, width: CGFloat, contentTop: CGFloat, isColumnSelected: Bool, selectedRow: Int, highlight: NSColor) {
        addCardHeader(to: parent, name: column.name, x: x, width: width, contentTop: contentTop)
        let totalRows = column.windows.count
        let visibleRows = min(totalRows, maxCardRows)
        let areaHeight = CGFloat(visibleRows) * rowHeight
        let fullHeight = CGFloat(totalRows) * rowHeight
        let overflow = totalRows > maxCardRows
        let clip = NSView(frame: NSRect(x: x, y: contentTop - headerHeight - areaHeight, width: width, height: areaHeight))
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        parent.addSubview(clip)
        let scrollY = (overflow && isColumnSelected) ? scrollOffsetFor(selectedRow, fullRowsHeight: fullHeight, areaHeight: areaHeight) : 0
        let inner = NSView(frame: NSRect(x: 0, y: areaHeight - fullHeight + scrollY, width: width, height: fullHeight))
        clip.addSubview(inner)
        for (winIdx, window) in column.windows.enumerated() {
            let rowY = fullHeight - CGFloat(winIdx + 1) * rowHeight
            let isSelected = isColumnSelected && winIdx == selectedRow
            addRow(to: inner, label: column.displayLabels[winIdx], window: window, x: 0, y: rowY, width: width, isSelected: isSelected, highlight: highlight)
        }
        if overflow {
            applyFadeMask(to: clip, areaHeight: areaHeight, fadeTop: scrollY > 0, fadeBottom: scrollY < fullHeight - areaHeight)
        }
    }

    /// vertical offset (measured from the top of the column) needed to keep the selected row inside the clip,
    /// clear of the fade region at the top/bottom edges (except at the very ends, where the fade is disabled)
    private static func scrollOffsetFor(_ rowIndex: Int, fullRowsHeight: CGFloat, areaHeight: CGFloat) -> CGFloat {
        let maxScroll = max(0, fullRowsHeight - areaHeight)
        let margin = rowHeight
        let selTop = CGFloat(rowIndex) * rowHeight
        let selBottom = selTop + rowHeight
        var scrollY: CGFloat = 0
        if selBottom > areaHeight - margin { scrollY = selBottom - (areaHeight - margin) }
        if selTop - margin < scrollY { scrollY = selTop - margin }
        return min(max(0, scrollY), maxScroll)
    }

    private static func applyFadeMask(to view: NSView, areaHeight: CGFloat, fadeTop: Bool, fadeBottom: Bool) {
        guard let layer = view.layer else { return }
        let mask = CAGradientLayer()
        mask.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: areaHeight)
        mask.startPoint = CGPoint(x: 0.5, y: 1)
        mask.endPoint = CGPoint(x: 0.5, y: 0)
        let opaque = NSColor.white.cgColor
        let clear = NSColor.white.withAlphaComponent(0).cgColor
        let fade = min(rowHeight, areaHeight * 0.25) / areaHeight
        mask.colors = [fadeTop ? clear : opaque, opaque, opaque, fadeBottom ? clear : opaque]
        mask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        layer.mask = mask
    }

    private static func addCardHeader(to card: NSView, name: String, x: CGFloat, width: CGFloat, contentTop: CGFloat) {
        let header = NSTextField(labelWithString: name)
        header.font = .boldSystemFont(ofSize: 13)
        header.textColor = .labelColor
        header.lineBreakMode = .byTruncatingTail
        header.frame = NSRect(x: x + padding, y: contentTop - headerHeight, width: width - padding * 2, height: headerHeight)
        card.addSubview(header)
    }

    private static func addMachineNameLabel(to card: NSView, name: String, height: CGFloat, tint: NSColor) {
        let label = NSTextField(labelWithString: name)
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = tint
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        let length = height - padding
        label.frame = NSRect(x: machineStripWidth * 0.5 - length * 0.5, y: height * 0.5 - 8, width: length, height: 16)
        label.frameCenterRotation = 90
        card.addSubview(label)
    }

    private static func addCardDivider(to card: NSView, x: CGFloat, top: CGFloat, height: CGFloat) {
        let divider = NSView(frame: NSRect(x: x, y: top - height, width: dividerWidth, height: height))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        card.addSubview(divider)
    }

    private static func addDivider(x: CGFloat, height: CGFloat) {
        let divider = NSView(frame: NSRect(x: x, y: 0, width: dividerWidth, height: height))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        innerView.addSubview(divider)
    }

    private static func addColumn(_ group: WindowGroup, groupIdx: Int, x: CGFloat, width: CGFloat, totalHeight: CGFloat) {
        addCappedColumn(to: innerView, column: group, x: x, width: width, contentTop: totalHeight - padding, isColumnSelected: groupIdx == selectedGroupIndex, selectedRow: selectedWindowIndex, highlight: .systemAccentColor)
    }

    private static func addRow(to parent: NSView, label: String, window: Window, x: CGFloat, y: CGFloat, width: CGFloat, isSelected: Bool, highlight: NSColor = .systemAccentColor) {
        let row = NSView(frame: NSRect(x: x, y: y, width: width, height: rowHeight))
        row.wantsLayer = true
        if isSelected {
            row.layer?.backgroundColor = highlight.cgColor
            row.layer?.cornerRadius = 4
        }
        let iconView = NSImageView(frame: NSRect(x: padding, y: (rowHeight - iconSize) / 2, width: iconSize, height: iconSize))
        iconView.image = iconForWindow(window)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        row.addSubview(iconView)
        addActivityIndicator(ActivityIndicator.make(window.activityState), to: row)
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12)
        text.textColor = isSelected ? .white : .labelColor
        text.lineBreakMode = .byTruncatingTail
        text.frame = NSRect(x: padding + iconSize + 4, y: 2, width: width - padding * 2 - iconSize - 4, height: rowHeight - 4)
        row.addSubview(text)
        parent.addSubview(row)
    }

    /// Overlays the row's app icon; a sibling view so it draws above the icon image.
    private static func addActivityIndicator(_ indicator: ActivityIndicator?, to row: NSView) {
        guard let indicator else { return }
        let size = iconSize + 4
        let view = NSView(frame: NSRect(x: padding - 2, y: (rowHeight - size) / 2, width: size, height: size))
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        let activityLayer = ActivityIndicatorLayer()
        activityLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        activityLayer.update(indicator, size: size)
        view.layer?.addSublayer(activityLayer)
        row.addSubview(view)
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

    private static func estimateColumnWidthInCards(_ cards: [MachineCard]) -> CGFloat {
        estimateColumnWidth(cards.flatMap(\.columns))
    }

    static func selectedWindow() -> Window? {
        if Windows.groupingMode == .machine {
            guard let column = selectedMachineColumn() else { return nil }
            guard selectedRowIndex < column.windows.count else { return nil }
            return column.windows[selectedRowIndex]
        }
        let groups = Windows.groupedList
        guard selectedGroupIndex < groups.count else { return nil }
        let group = groups[selectedGroupIndex]
        guard selectedWindowIndex < group.windows.count else { return nil }
        return group.windows[selectedWindowIndex]
    }

    private static func selectedMachineColumn() -> WindowGroup? {
        let cards = Windows.machineCards
        guard selectedMachineIndex < cards.count else { return nil }
        let columns = cards[selectedMachineIndex].columns
        guard selectedColumnIndex < columns.count else { return nil }
        return columns[selectedColumnIndex]
    }

    static func navigateUp() {
        if Windows.groupingMode == .machine { machineMoveRow(-1); return }
        let groups = Windows.groupedList
        guard selectedGroupIndex < groups.count else { return }
        let count = groups[selectedGroupIndex].windows.count
        selectedWindowIndex = (selectedWindowIndex - 1 + count) % count
        updateItemsAndLayout()
    }

    static func navigateDown() {
        if Windows.groupingMode == .machine { machineMoveRow(1); return }
        let groups = Windows.groupedList
        guard selectedGroupIndex < groups.count else { return }
        let count = groups[selectedGroupIndex].windows.count
        selectedWindowIndex = (selectedWindowIndex + 1) % count
        updateItemsAndLayout()
    }

    static func navigateLeft() {
        if Windows.groupingMode == .machine { machineMoveColumn(-1); return }
        let groups = Windows.groupedList
        guard groups.count > 1 else { return }
        selectedGroupIndex = (selectedGroupIndex - 1 + groups.count) % groups.count
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        updateItemsAndLayout(animated: true)
    }

    static func navigateRight() {
        if Windows.groupingMode == .machine { machineMoveColumn(1); return }
        let groups = Windows.groupedList
        guard groups.count > 1 else { return }
        selectedGroupIndex = (selectedGroupIndex + 1) % groups.count
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        updateItemsAndLayout(animated: true)
    }

    /// machine mode: move between title-group columns inside the focused card; clamps at the card's edges (never crosses cards)
    private static func machineMoveColumn(_ delta: Int) {
        let cards = Windows.machineCards
        guard selectedMachineIndex < cards.count else { return }
        let columns = cards[selectedMachineIndex].columns
        let newColumn = selectedColumnIndex + delta
        guard newColumn >= 0, newColumn < columns.count else { return }
        selectedColumnIndex = newColumn
        selectedRowIndex = min(selectedRowIndex, max(0, columns[newColumn].windows.count - 1))
        updateItemsAndLayout()
    }

    /// machine mode: move between window rows inside the focused column; only when stepping past the
    /// top/bottom edge do we glide to the previous/next machine card (recentering it)
    private static func machineMoveRow(_ delta: Int) {
        let cards = Windows.machineCards
        guard let column = selectedMachineColumn() else { return }
        let newRow = selectedRowIndex + delta
        if newRow >= 0, newRow < column.windows.count {
            selectedRowIndex = newRow
            updateItemsAndLayout()
            return
        }
        let newMachine = selectedMachineIndex + delta
        guard newMachine >= 0, newMachine < cards.count else { return }
        selectedMachineIndex = newMachine
        let newColumns = cards[newMachine].columns
        selectedColumnIndex = min(selectedColumnIndex, max(0, newColumns.count - 1))
        let count = newColumns.isEmpty ? 0 : newColumns[selectedColumnIndex].windows.count
        selectedRowIndex = delta < 0 ? max(0, count - 1) : 0
        updateItemsAndLayout(animated: true)
    }

    private static func clampMachineSelection() {
        let cards = Windows.machineCards
        guard !cards.isEmpty else { return }
        selectedMachineIndex = min(max(0, selectedMachineIndex), cards.count - 1)
        let columns = cards[selectedMachineIndex].columns
        guard !columns.isEmpty else { selectedColumnIndex = 0; selectedRowIndex = 0; return }
        selectedColumnIndex = min(max(0, selectedColumnIndex), columns.count - 1)
        let count = columns[selectedColumnIndex].windows.count
        selectedRowIndex = min(max(0, selectedRowIndex), max(0, count - 1))
    }

    static func resetSelection() {
        if Windows.groupingMode == .machine { resetMachineSelection(); return }
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

    private static func resetMachineSelection() {
        selectedMachineIndex = 0
        selectedColumnIndex = 0
        selectedRowIndex = 0
        guard let previousWindow = Windows.list.first(where: { $0.lastFocusOrder == 1 }) else { return }
        for (mi, card) in Windows.machineCards.enumerated() {
            for (ci, column) in card.columns.enumerated() {
                if let ri = column.windows.firstIndex(where: { $0.id == previousWindow.id }) {
                    selectedMachineIndex = mi
                    selectedColumnIndex = ci
                    selectedRowIndex = ri
                    return
                }
            }
        }
    }
}

/// Maps a machine name to a stable color from a fixed palette, so each machine card is visually distinct
/// and the same machine always gets the same color across launches.
enum MachinePalette {
    // hand-picked calm, cool tones only — no red/orange/amber "danger" colors
    private static let palette: [NSColor] = [
        NSColor(srgbRed: 0.27, green: 0.56, blue: 0.91, alpha: 1), // blue
        NSColor(srgbRed: 0.20, green: 0.69, blue: 0.73, alpha: 1), // teal
        NSColor(srgbRed: 0.33, green: 0.71, blue: 0.51, alpha: 1), // green
        NSColor(srgbRed: 0.46, green: 0.51, blue: 0.93, alpha: 1), // indigo
        NSColor(srgbRed: 0.61, green: 0.47, blue: 0.86, alpha: 1), // purple
        NSColor(srgbRed: 0.28, green: 0.64, blue: 0.85, alpha: 1), // cyan
        NSColor(srgbRed: 0.27, green: 0.64, blue: 0.58, alpha: 1), // sea green
        NSColor(srgbRed: 0.44, green: 0.56, blue: 0.78, alpha: 1), // slate blue
    ]

    static func color(for machine: String) -> NSColor {
        palette[Int(stableHash(machine) % UInt64(palette.count))]
    }

    /// deterministic FNV-1a hash so colors are stable across runs (Swift's String.hashValue is randomized per launch)
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hash
    }
}
