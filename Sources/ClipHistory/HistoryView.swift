import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var history: ClipboardHistory
    let onSelect: () -> Void

    private let calendar = Calendar.current
    private let rowHover = Color.white.opacity(0.075)
    private let separator = Color.white.opacity(0.08)

    private var groupedEntries: [(String, [ClipboardEntry])] {
        let filtered = history.entries.filter { entry in
            let query = history.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let selectedApp = history.selectedSourceAppBundleIdentifier,
               entry.sourceBundleIdentifier != selectedApp { return false }
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
                                .foregroundStyle(.white.opacity(0.45))
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
            }

        }
        .background {
            WindowBlurBackground()
                .overlay(Color.black.opacity(0.24))
                .allowsHitTesting(false)
        }
        .foregroundStyle(.white.opacity(0.92))
        .preferredColorScheme(.dark)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
                .foregroundStyle(.white.opacity(0.52))

            TextField("Type to search…", text: $history.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.92))
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
                    .foregroundStyle(.white.opacity(0.72))
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
                .foregroundStyle(.white.opacity(0.34))
                .padding(.bottom, 3)
            Text(hasSearch ? "No matching entries" : (history.isPaused ? "Monitoring is paused" : "Nothing copied yet"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
            Text(hasSearch ? "Try a different keyword." : "Copied text and images will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.46))
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
                        .foregroundStyle(.white.opacity(0.88))

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
                    .foregroundStyle(.white.opacity(0.42))
                }

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 0.58 : 0))
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
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.10), lineWidth: 1))
        } else if let appIcon = sourceApplicationImage(for: entry) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            Image(systemName: entry.isImage ? "photo" : "doc.text")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
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
