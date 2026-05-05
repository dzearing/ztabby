# Window Grouping by Title Prefix

## Overview

Add an opt-in feature that groups windows whose titles match the pattern "Name: value" into columns by their prefix. When enabled, the ztabby UI switches from the default tile grid to a columnar grouped list layout.

## Data Model: WindowGrouper

A new class `WindowGrouper` in `src/logic/`.

**Input:** `Windows.list` (the current flat array of `Window` objects).

**Grouping logic:**
- Split each window's `title` on the first occurrence of `": "` (colon + space).
- Left side = group key. Right side = display label for that window within the group.
- Windows whose title does not contain `": "` are collected into an "Ungrouped" bucket.

**Sorting:**
- Groups are sorted by the `lastFocusOrder` of their most recently focused window (lowest = most recent = first).
- Within each group, windows are sorted by `lastFocusOrder` (most recent first).
- The "Ungrouped" bucket always appears last, regardless of recency.

**Output:** `[(groupName: String, windows: [Window])]` — an ordered array of groups, each containing an ordered array of windows.

**Integration point:** Called inside `Windows.updatesBeforeShowing()` when `Preferences.windowGroupingEnabled` is true. The grouped result is stored as a static property (e.g., `Windows.groupedList`) for the view to consume.

## View: GroupedColumnsView

A new `NSView` subclass in `src/ui/main-window/`.

### Layout

- Each group renders as a vertical column.
- Columns are laid out horizontally, left to right, in group sort order.
- Each column has:
  - A **header label** showing the group name, styled as a bold section title.
  - **Rows** underneath, one per window. Each row contains: small app icon + the display label (the "value" part after the colon; full title for ungrouped windows).
- Columns have equal width. Vertical divider lines separate columns.
- The panel resizes to fit content, same as TilesView.

### Selection State

- Two indices: `selectedGroupIndex` and `selectedWindowIndex` (within that group).
- The selected row gets a highlight background matching the current tile selection style.

### Keyboard Navigation

- **Up/Down:** Move within the current group. Wrap at edges (top wraps to bottom and vice versa).
- **Left/Right:** Switch to the adjacent group. Preserve the row index, clamped if the new group is shorter.
- **Enter/Return:** Focus the selected window (feeds into existing `Windows.focusSelectedWindow()` flow).
- **Escape:** Dismiss the panel.

### Integration with TilesPanel

- `TilesPanel` conditionally creates either `TilesView` or `GroupedColumnsView` based on `Preferences.windowGroupingEnabled`.
- When grouping is enabled, `TilesPanel.updateContents()` calls `GroupedColumnsView.updateItemsAndLayout()` instead of `TilesView.updateItemsAndLayout()`.
- The selected window from `GroupedColumnsView` feeds back into the same window-focus flow used by `TilesView`.

## Settings

- **Key:** `windowGroupingEnabled` — `Bool`, default `false`.
- **Location:** AppearanceTab in the settings window.
- **UI:** A switch labeled "Group windows by title prefix" with subtitle text "Groups windows with 'Name: value' titles into columns by name".
- **Behavior:** Takes effect on the next shortcut press. No app restart required.
- **Accessor:** `Preferences.windowGroupingEnabled` via `CachedUserDefaults.bool()`.

## Files to Create

- `src/logic/WindowGrouper.swift` — grouping and sorting logic
- `src/ui/main-window/GroupedColumnsView.swift` — columnar grouped layout view

## Files to Modify

- `src/logic/Windows.swift` — call `WindowGrouper` during `updatesBeforeShowing()`, store result
- `src/logic/Preferences.swift` — add `windowGroupingEnabled` default and accessor
- `src/ui/main-window/TilesPanel.swift` — conditionally use `GroupedColumnsView`
- `src/ui/settings-window/tabs/AppearanceTab.swift` — add grouping toggle
- `src/logic/events/KeyboardEvents.swift` — route arrow keys to grouped navigation when active

## Out of Scope

- Configurable delimiter (hardcoded to `": "`).
- Collapsible groups.
- Thumbnail previews in grouped mode (compact text rows only).
- Mouse interaction within grouped view (keyboard-only for initial implementation).
