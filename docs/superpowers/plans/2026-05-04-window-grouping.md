# Window Grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in columnar grouped layout that splits "Name: value" window titles into groups navigable with arrow keys.

**Architecture:** New `WindowGrouper` produces grouped data from `Windows.list`. New `GroupedColumnsView` renders columns. `TilesPanel` conditionally switches between views. Preference toggle in AppearanceTab.

**Tech Stack:** Swift 5.8, AppKit (NSView, NSTextField, NSImageView), no new dependencies.

---

### Task 1: Add Preference

**Files:**
- Modify: `src/logic/Preferences.swift`
- Modify: `src/ui/settings-window/tabs/AppearanceTab.swift`

- [ ] **Step 1: Add default value and accessor**

In `src/logic/Preferences.swift`, add to the `defaultValues` dictionary (around line 50, before the shortcut loop):

```swift
"windowGroupingEnabled": "false",
```

Add accessor property (around line 146, near other Bool accessors like `hideColoredCircles`):

```swift
static var windowGroupingEnabled: Bool { CachedUserDefaults.bool("windowGroupingEnabled") }
```

- [ ] **Step 2: Add toggle to AppearanceTab**

In `src/ui/settings-window/tabs/AppearanceTab.swift`, inside the `makeView()` method, add a new row after the existing rows (find the pattern using `addRow(leftText:rightViews:)`):

```swift
table.addRow(leftText: NSLocalizedString("Group windows by title prefix", comment: ""),
    rightViews: [LabelAndControl.makeSwitch("windowGroupingEnabled")])
```

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild -workspace ztabby.xcworkspace -scheme Debug -configuration Debug -derivedDataPath ~/git/ztabby/DerivedData build 2>&1 | grep -E "BUILD|error:" | head -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add src/logic/Preferences.swift src/ui/settings-window/tabs/AppearanceTab.swift
git commit -m "feat: add windowGroupingEnabled preference and settings toggle"
```

---

### Task 2: Create WindowGrouper

**Files:**
- Create: `src/logic/WindowGrouper.swift`
- Modify: `src/logic/Windows.swift`
- Modify: `ztabby.xcodeproj/project.pbxproj` (add new file to Xcode project)

- [ ] **Step 1: Create WindowGrouper.swift**

Create `src/logic/WindowGrouper.swift`:

```swift
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
```

- [ ] **Step 2: Add groupedList to Windows.swift**

In `src/logic/Windows.swift`, add a static property near line 4 (after `static var list`):

```swift
static var groupedList = [WindowGroup]()
```

In the `updatesBeforeShowing()` method (around line 103, after the `sort()` call), add:

```swift
if Preferences.windowGroupingEnabled {
    groupedList = WindowGrouper.group(list.filter { shouldDisplay($0) })
}
```

- [ ] **Step 3: Add file to Xcode project**

Run the following to add the file to the project. Find the logic group PBXGroup and add a file reference:

```bash
# Use ruby script to add file to xcodeproj
ruby -e '
require "xcodeproj"
proj = Xcodeproj::Project.open("ztabby.xcodeproj")
target = proj.targets.find { |t| t.name == "ztabby" }
group = proj.main_group.find_subpath("src/logic", true)
ref = group.new_file("WindowGrouper.swift")
target.source_build_phase.add_file_reference(ref)
proj.save
' 2>&1 || echo "If xcodeproj gem not available, add file manually in Xcode"
```

If the ruby gem isn't available, open the project in Xcode and drag `src/logic/WindowGrouper.swift` into the `src/logic` group, ensuring "Add to target: ztabby" is checked.

- [ ] **Step 4: Build and verify**

Run:
```bash
xcodebuild -workspace ztabby.xcworkspace -scheme Debug -configuration Debug -derivedDataPath ~/git/ztabby/DerivedData build 2>&1 | grep -E "BUILD|error:" | head -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add src/logic/WindowGrouper.swift src/logic/Windows.swift ztabby.xcodeproj/project.pbxproj
git commit -m "feat: add WindowGrouper to split windows by title prefix"
```

---

### Task 3: Create GroupedColumnsView

**Files:**
- Create: `src/ui/main-window/GroupedColumnsView.swift`
- Modify: `ztabby.xcodeproj/project.pbxproj` (add new file)

- [ ] **Step 1: Create GroupedColumnsView.swift**

Create `src/ui/main-window/GroupedColumnsView.swift`:

```swift
import Cocoa

class GroupedColumnsView {
    static var contentView = NSView()
    static var scrollView = NSScrollView()
    private static var columnViews = [NSView]()
    private static var selectedGroupIndex = 0
    private static var selectedWindowIndex = 0
    private static var rowViews = [[NSView]]()

    private static let columnMinWidth: CGFloat = 200
    private static let headerHeight: CGFloat = 28
    private static let rowHeight: CGFloat = 24
    private static let iconSize: CGFloat = 16
    private static let padding: CGFloat = 8
    private static let dividerWidth: CGFloat = 1

    static func initialize() {
        scrollView.documentView = contentView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        contentView.wantsLayer = true
    }

    static func updateItemsAndLayout() {
        contentView.subviews.removeAll()
        columnViews.removeAll()
        rowViews.removeAll()
        let groups = Windows.groupedList
        guard !groups.isEmpty else { return }
        selectedGroupIndex = min(selectedGroupIndex, groups.count - 1)
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        let columnWidth = max(columnMinWidth, estimateColumnWidth(groups))
        var x: CGFloat = 0
        let maxRows = groups.map(\.windows.count).max() ?? 0
        let totalHeight = headerHeight + CGFloat(maxRows) * rowHeight + padding * 2
        for (groupIdx, group) in groups.enumerated() {
            if groupIdx > 0 {
                let divider = NSView(frame: NSRect(x: x, y: 0, width: dividerWidth, height: totalHeight))
                divider.wantsLayer = true
                divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
                contentView.addSubview(divider)
                x += dividerWidth
            }
            let column = NSView(frame: NSRect(x: x, y: 0, width: columnWidth, height: totalHeight))
            let header = NSTextField(labelWithString: group.name)
            header.font = .boldSystemFont(ofSize: 13)
            header.textColor = .labelColor
            header.frame = NSRect(x: padding, y: totalHeight - headerHeight, width: columnWidth - padding * 2, height: headerHeight)
            column.addSubview(header)
            var rows = [NSView]()
            for (winIdx, window) in group.windows.enumerated() {
                let rowY = totalHeight - headerHeight - CGFloat(winIdx + 1) * rowHeight
                let row = makeRow(group.displayLabels[winIdx], window, x: 0, y: rowY, width: columnWidth,
                                  isSelected: groupIdx == selectedGroupIndex && winIdx == selectedWindowIndex)
                column.addSubview(row)
                rows.append(row)
            }
            rowViews.append(rows)
            contentView.addSubview(column)
            columnViews.append(column)
            x += columnWidth
        }
        contentView.frame = NSRect(x: 0, y: 0, width: x, height: totalHeight)
    }

    private static func makeRow(_ label: String, _ window: Window, x: CGFloat, y: CGFloat, width: CGFloat, isSelected: Bool) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: y, width: width, height: rowHeight))
        row.wantsLayer = true
        if isSelected {
            row.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
            row.layer?.cornerRadius = 4
        }
        let icon = NSImageView(frame: NSRect(x: padding, y: (rowHeight - iconSize) / 2, width: iconSize, height: iconSize))
        icon.image = window.application.icon ?? window.application.runningApplication.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        row.addSubview(icon)
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12)
        text.textColor = isSelected ? .white : .labelColor
        text.lineBreakMode = .byTruncatingTail
        text.frame = NSRect(x: padding + iconSize + 4, y: 2, width: width - padding * 2 - iconSize - 4, height: rowHeight - 4)
        row.addSubview(text)
        return row
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
        updateItemsAndLayout()
    }

    static func navigateRight() {
        let groups = Windows.groupedList
        guard groups.count > 1 else { return }
        selectedGroupIndex = (selectedGroupIndex + 1) % groups.count
        selectedWindowIndex = min(selectedWindowIndex, groups[selectedGroupIndex].windows.count - 1)
        updateItemsAndLayout()
    }

    static func resetSelection() {
        selectedGroupIndex = 0
        selectedWindowIndex = 0
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Same approach as Task 2 Step 3, but for `src/ui/main-window/GroupedColumnsView.swift`. Either use the ruby script adapted for the new path, or drag the file into the `src/ui/main-window` group in Xcode with "Add to target" checked.

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild -workspace ztabby.xcworkspace -scheme Debug -configuration Debug -derivedDataPath ~/git/ztabby/DerivedData build 2>&1 | grep -E "BUILD|error:" | head -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add src/ui/main-window/GroupedColumnsView.swift ztabby.xcodeproj/project.pbxproj
git commit -m "feat: add GroupedColumnsView for columnar window grouping layout"
```

---

### Task 4: Integrate into TilesPanel and Keyboard Navigation

**Files:**
- Modify: `src/ui/main-window/TilesPanel.swift`
- Modify: `src/ui/main-window/TilesView.swift`
- Modify: `src/ui/App.swift`

- [ ] **Step 1: Update TilesPanel to conditionally use GroupedColumnsView**

In `src/ui/main-window/TilesPanel.swift`, find the `init()` or initialization code where `TilesView.initialize()` is called (around line 19-20). Add GroupedColumnsView initialization after it:

```swift
GroupedColumnsView.initialize()
```

Find `updateContents()` (around line 39-49). Replace the body with conditional logic:

```swift
func updateContents(_ preservedScrollOrigin: CGPoint?) {
    caTransaction {
        if Preferences.windowGroupingEnabled && !Windows.groupedList.isEmpty {
            contentView! = GroupedColumnsView.scrollView
            GroupedColumnsView.updateItemsAndLayout()
            guard App.appIsBeingUsed else { return }
            setContentSize(GroupedColumnsView.contentView.frame.size)
        } else {
            contentView! = TilesView.contentView
            TilesView.updateItemsAndLayout(preservedScrollOrigin)
            guard App.appIsBeingUsed else { return }
            setContentSize(TilesView.contentView.frame.size)
        }
        repositionOrFreeze()
    }
    TilesView.clearNeedsLayout()
}
```

- [ ] **Step 2: Route keyboard navigation for grouped mode**

In `src/ui/main-window/TilesView.swift`, find `handleSearchEditingKeyDown()` (around line 113-125). Add grouped mode handling before the existing arrow key code:

```swift
if Preferences.windowGroupingEnabled && !Windows.groupedList.isEmpty {
    if keyCode == UInt16(kVK_LeftArrow) { GroupedColumnsView.navigateLeft(); return .handled }
    if keyCode == UInt16(kVK_RightArrow) { GroupedColumnsView.navigateRight(); return .handled }
    if keyCode == UInt16(kVK_UpArrow) { GroupedColumnsView.navigateUp(); return .handled }
    if keyCode == UInt16(kVK_DownArrow) { GroupedColumnsView.navigateDown(); return .handled }
    if keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter) {
        if let window = GroupedColumnsView.selectedWindow() {
            Windows.focusSelectedWindow(window)
        }
        return .handled
    }
}
```

- [ ] **Step 3: Reset grouped selection on show**

In `src/ui/App.swift`, find `showUiOrCycleSelection()` (around line 298). Near the top of the first-show branch (where `Windows.sortByLevel()` is called), add:

```swift
GroupedColumnsView.resetSelection()
```

- [ ] **Step 4: Build and verify**

Run:
```bash
xcodebuild -workspace ztabby.xcworkspace -scheme Debug -configuration Debug -derivedDataPath ~/git/ztabby/DerivedData build 2>&1 | grep -E "BUILD|error:" | head -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add src/ui/main-window/TilesPanel.swift src/ui/main-window/TilesView.swift src/ui/App.swift
git commit -m "feat: integrate GroupedColumnsView into TilesPanel with keyboard navigation"
```

---

### Task 5: Manual Test and Fix

- [ ] **Step 1: Launch and enable grouping**

```bash
kill $(pgrep -f Ztabby-Debug) 2>/dev/null
open ~/git/ztabby/DerivedData/Build/Products/Debug/Ztabby-Debug.app
```

Open Ztabby-Debug settings, go to Appearance tab, enable "Group windows by title prefix".

- [ ] **Step 2: Test with windows that have colons in titles**

Open several windows with "Name: value" titles (e.g. multiple VS Code or terminal windows). Press the ztabby shortcut. Verify:
- Groups appear as columns
- Left/right switches groups
- Up/down moves within a group
- Enter focuses the selected window
- Ungrouped windows appear in "Other" at the end

- [ ] **Step 3: Fix any issues found during testing**

Address build errors, layout bugs, or navigation issues.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix: address issues found during manual testing of window grouping"
```
