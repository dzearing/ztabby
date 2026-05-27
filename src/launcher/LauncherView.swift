import SwiftUI
import AppKit

@available(macOS 26.0, *)
struct LauncherView: View {
    @Bindable var viewModel: LauncherViewModel
    var onDismiss: () -> Void
    var onLaunch: () -> Void

    private let maxResults = 5
    private let visibleRows = 3

    var body: some View {
        GlassEffectContainer {
            SwiftUI.VStack(spacing: 0) {
                searchField
                if !viewModel.results.isEmpty {
                    SwiftUI.Divider().opacity(0.3)
                    resultsList
                }
            }
        }
        .frame(width: 680)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var searchField: some View {
        SwiftUI.HStack(spacing: 12) {
            SwiftUI.Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                ghostTextOverlay
                LauncherTextField(
                    text: $viewModel.query,
                    onEscape: onDismiss,
                    onReturn: onLaunch,
                    onArrowUp: { viewModel.moveSelection(-1) },
                    onArrowDown: { viewModel.moveSelection(1) },
                    onTab: { viewModel.acceptCompletion() }
                )
                .font(.system(size: 24, weight: .regular))
            }
            if !viewModel.query.isEmpty {
                SwiftUI.Button {
                    viewModel.query = ""
                } label: {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            topResultIcon
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var ghostTextOverlay: some View {
        if let ghost = viewModel.ghostCompletion, !viewModel.query.isEmpty {
            SwiftUI.HStack(spacing: 0) {
                SwiftUI.Text(viewModel.query)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.clear)
                SwiftUI.Text(ghost)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineLimit(1)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var topResultIcon: some View {
        if let icon = viewModel.topResult?.icon, !viewModel.query.isEmpty {
            SwiftUI.Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
        }
    }

    private var resultsList: some View {
        let visibleCount: Int = min(viewModel.results.count, visibleRows)
        let listHeight: Double = Double(visibleCount) * 56.0 + 12.0
        let entries: [LauncherAppEntry] = Array(viewModel.results.prefix(maxResults))
        let selected: Int = viewModel.selectedIndex
        return resultsScrollView(entries: entries, selected: selected, listHeight: listHeight)
    }

    private func resultsScrollView(entries: [LauncherAppEntry], selected: Int, listHeight: Double) -> some View {
        SwiftUI.ScrollViewReader { proxy in
            SwiftUI.ScrollView(.vertical) {
                resultsVStack(entries: entries, selected: selected)
            }
            .frame(maxHeight: listHeight)
            .onChange(of: viewModel.selectedIndex) { _, newValue in
                guard entries.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(entries[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func resultsVStack(entries: [LauncherAppEntry], selected: Int) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                resultRow(entry, isSelected: index == selected)
                    .id(entry.id)
                    .onTapGesture {
                        viewModel.selectedIndex = index
                        onLaunch()
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func resultRow(_ entry: LauncherAppEntry, isSelected: Bool) -> some View {
        SwiftUI.HStack(spacing: 12) {
            if let icon = entry.icon {
                SwiftUI.Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 40, height: 40)
            }
            SwiftUI.VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Text(entry.name)
                    .font(.system(size: 15, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                SwiftUI.Text(entry.kind.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            SwiftUI.Spacer()
            if isSelected {
                SwiftUI.Text("\u{21a9}")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.12))
                : nil
        )
    }
}

@available(macOS 26.0, *)
struct LauncherTextField: NSViewRepresentable {
    @Binding var text: String
    var onEscape: () -> Void
    var onReturn: () -> Void
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onTab: () -> Void

    func makeNSView(context: Context) -> LauncherNSTextField {
        let field = LauncherNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 24, weight: .regular)
        field.placeholderString = "Search apps\u{2026}"
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.usesSingleLineMode = true
        field.onEscape = onEscape
        field.onReturn = onReturn
        field.onArrowUp = onArrowUp
        field.onArrowDown = onArrowDown
        field.onTab = onTab
        return field
    }

    func updateNSView(_ nsView: LauncherNSTextField, context: Context) {
        guard nsView.stringValue != text else { return }
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherTextField
        init(_ parent: LauncherTextField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

class LauncherNSTextField: NSTextField {
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onTab: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        switch Int(event.keyCode) {
        case 53: onEscape?(); return true
        case 36, 76: onReturn?(); return true
        case 126: onArrowUp?(); return true
        case 125: onArrowDown?(); return true
        case 48: onTab?(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
