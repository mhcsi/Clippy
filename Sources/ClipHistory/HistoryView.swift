import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var history: ClipboardHistory
    let onSelect: () -> Void

    private let calendar = Calendar.current
    private let rowHover = Color.primary.opacity(0.075)
    private let separator = Color.primary.opacity(0.08)

    private var groupedEntries: [(String, [ClipboardEntry])] {
        let filtered = history.entries.filter { entry in
            let query = history.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let selectedApp = history.selectedSourceAppBundleIdentifier,
               entry.sourceBundleIdentifier != selectedApp { return false }
            switch history.contentFilter {
            case .all:
                break
            case .photos:
                guard entry.isImage else { return false }
            case .texts:
                guard !entry.isImage, !isLink(entry.text) else { return false }
            case .links:
                guard !entry.isImage, isLink(entry.text) else { return false }
            }
            guard !query.isEmpty else { return true }
            return [entry.isImage ? "Image" : entry.text, entry.sourceAppName ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let groups = Dictionary(grouping: filtered) { dayLabel(for: $0.copiedAt) }
        let isNewestFirst = history.sortOrder == .lastCopy
        return groups.map { ($0.key, $0.value.sorted { isNewestFirst ? $0.copiedAt > $1.copiedAt : $0.copiedAt < $1.copiedAt }) }
            .sorted { isNewestFirst ? firstDate(for: $0.1) > firstDate(for: $1.1) : firstDate(for: $0.1) < firstDate(for: $1.1) }
    }

    private var hasSearch: Bool {
        !history.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            contentTypeFilters

            Rectangle()
                .fill(separator)
                .frame(height: 1)

            if groupedEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedEntries, id: \.0) { label, entries in
                            Text(label.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 15)
                                .padding(.bottom, 6)

                            ForEach(entries) { entry in
                                entryRow(entry)
                                Rectangle()
                                    .fill(separator)
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.visible)
                .background {
                    TransparentScrollViewBackground()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

        }
        .background {
            WindowBlurBackground()
                .allowsHitTesting(false)
        }
        .foregroundStyle(Color.primary.opacity(0.92))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(minWidth: 650, idealWidth: 880, maxWidth: .infinity,
               minHeight: 450, idealHeight: 620, maxHeight: .infinity)
        .onExitCommand(perform: onSelect)
    }

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)

            TextField("Type to search…", text: $history.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .accessibilityLabel("Search clipboard history")

            Spacer(minLength: 12)

            Menu {
                Menu {
                    Button {
                        history.sortOrder = .lastCopy
                    } label: {
                        menuChoice("Last Copy Time", selected: history.sortOrder == .lastCopy)
                    }
                    Button {
                        history.sortOrder = .firstCopy
                    } label: {
                        menuChoice("First Copy Time", selected: history.sortOrder == .firstCopy)
                    }
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }

                Menu {
                    Button {
                        history.selectedSourceAppBundleIdentifier = nil
                    } label: {
                        menuChoice("All Apps", selected: history.selectedSourceAppBundleIdentifier == nil)
                    }
                    if !history.sourceApplications.isEmpty {
                        Divider()
                        ForEach(history.sourceApplications) { app in
                            Button {
                                history.selectedSourceAppBundleIdentifier = app.bundleIdentifier
                            } label: {
                                HStack(spacing: 8) {
                                    if let icon = sourceApplicationImage(bundleIdentifier: app.bundleIdentifier) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    Text(app.name)
                                    if history.selectedSourceAppBundleIdentifier == app.bundleIdentifier {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label("Filter By App", systemImage: "line.3.horizontal.decrease")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort and filter clipboard history")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 54)
    }

    private var contentTypeFilters: some View {
        HStack(spacing: 7) {
            ForEach(ClipboardContentFilter.allCases) { filter in
                Button {
                    history.contentFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(history.contentFilter == filter ? 0.96 : 0.67))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Color.primary.opacity(history.contentFilter == filter ? 0.19 : 0.08))
                        }
                        .overlay {
                            Capsule()
                                .stroke(Color.primary.opacity(history.contentFilter == filter ? 0.20 : 0.09), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Show \(filter.title.lowercased()) in clipboard history")
                .accessibilityAddTraits(history.contentFilter == filter ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func menuChoice(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected { Image(systemName: "checkmark") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: hasSearch ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 3)
            Text(hasSearch ? "No matching entries" : (history.isPaused ? "Monitoring is paused" : "Nothing copied yet"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Text(hasSearch ? "Try a different keyword." : "Copied text and images will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entryRow(_ entry: ClipboardEntry) -> some View {
        let isHovered = history.hoveredEntryID == entry.id
        return Button { copy(entry) } label: {
            HStack(spacing: 11) {
                entryIcon(entry)

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.isImage ? "Image" : entry.text)
                        .font(.system(size: 14, weight: .regular))
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)

                    HStack(spacing: 5) {
                        if let sourceAppName = entry.sourceAppName {
                            Text(sourceAppName)
                                .lineLimit(1)
                            Text("·")
                        }
                        Text(entry.copiedAt, format: .dateTime.hour().minute())
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(isHovered ? 0.58 : 0))
                    .frame(width: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(isHovered ? rowHover : .clear, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 7)
        }
        .buttonStyle(.plain)
        .onHover { history.hoveredEntryID = $0 ? entry.id : nil }
        .accessibilityLabel(entry.isImage ? "Copy image from \(entry.copiedAt.formatted(date: .abbreviated, time: .shortened))" : "Copy \(entry.text)")
        .help("Copy this entry and close history")
    }

    @ViewBuilder
    private func entryIcon(_ entry: ClipboardEntry) -> some View {
        if entry.isImage,
           let data = history.thumbnailData(for: entry),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        } else if let appIcon = sourceApplicationImage(for: entry) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            Image(systemName: entry.isImage ? "photo" : "doc.text")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func sourceApplicationImage(for entry: ClipboardEntry) -> NSImage? {
        guard let bundleIdentifier = entry.sourceBundleIdentifier else { return nil }
        return sourceApplicationImage(bundleIdentifier: bundleIdentifier)
    }

    private func sourceApplicationImage(bundleIdentifier: String) -> NSImage? {
        if !bundleIdentifier.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }

    private func dayLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    private func copy(_ entry: ClipboardEntry) {
        history.recopy(entry)
        onSelect()
    }

    private func firstDate(for entries: [ClipboardEntry]) -> Date {
        entries.first?.copiedAt ?? .distantPast
    }

    private func isLink(_ text: String) -> Bool {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              !candidate.contains(where: \.isNewline),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
              match.range == NSRange(candidate.startIndex..., in: candidate),
              let scheme = match.url?.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp"].contains(scheme)
    }
}

private struct WindowBlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        return effectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

/// Prevents the native scroll view from painting an opaque track over the
/// translucent window material. Overlay scrollers leave the blurred material
/// visible behind the thumb in both Light and Dark appearances.
private struct TransparentScrollViewBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configureScrollView(for: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configureScrollView(for: nsView) }
    }

    private func configureScrollView(for view: NSView) {
        var ancestor: NSView? = view
        var root = view
        while let current = ancestor {
            root = current
            if let scrollView = current as? NSScrollView {
                applyTransparentStyle(to: scrollView)
                return
            }
            ancestor = current.superview
        }

        if let scrollView = firstScrollView(in: root) {
            applyTransparentStyle(to: scrollView)
        }
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstScrollView(in: child) { return scrollView }
        }
        return nil
    }

    private func applyTransparentStyle(to scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.alphaValue = 0.72
    }
}
