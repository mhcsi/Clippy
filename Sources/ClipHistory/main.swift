import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@main
@MainActor
enum ClippyApplication {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = ClipboardHistory()
    private var panel: ClippyPanel!
    private var statusItem: NSStatusItem!
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var hotKeyHandler: EventHandlerRef?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.rememberExternalApplication(application) }
        }
        history.startMonitoring()
        createPanel()
        createStatusItem()
        registerHotKey()
        togglePanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        history.stopMonitoring()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !panel.isVisible { togglePanel() }
        else { panel.makeKeyAndOrderFront(nil) }
        return true
    }

    private func createPanel() {
        let content = HistoryView(history: history) { [weak self] in self?.hidePanel() }
        panel = ClippyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        // Leave the panel appearance unset so AppKit and SwiftUI follow macOS Light/Dark mode.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 650, height: 450)
        panel.contentView = NSHostingView(rootView: content)
        panel.center()
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let logoURL = Bundle.main.url(forResource: "ClippyMenuBar", withExtension: "pdf"),
           let logo = NSImage(contentsOf: logoURL) {
            logo.size = NSSize(width: 18, height: 18)
            logo.isTemplate = true
            statusItem.button?.image = logo
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clippy")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Clippy", action: #selector(showFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clippy", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let parameterStatus = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard parameterStatus == noErr else { return noErr }
            let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in app.handleHotKey(id: hotKeyID.id) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard installStatus == noErr else { return }

        registerHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), id: 1)
        let historyShortcuts: [(keyCode: UInt32, position: UInt32)] = [
            (UInt32(kVK_ANSI_2), 2),
            (UInt32(kVK_ANSI_3), 3),
            (UInt32(kVK_ANSI_4), 4),
            (UInt32(kVK_ANSI_5), 5),
            (UInt32(kVK_ANSI_6), 6),
            (UInt32(kVK_ANSI_7), 7),
            (UInt32(kVK_ANSI_8), 8),
            (UInt32(kVK_ANSI_9), 9)
        ]
        for shortcut in historyShortcuts {
            registerHotKey(keyCode: shortcut.keyCode, modifiers: UInt32(cmdKey | optionKey), id: shortcut.position)
        }
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference { hotKeyRefs.append(reference) }
    }

    private func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            togglePanel()
        case 2...9:
            pasteHistoryEntry(at: Int(id - 1))
        default:
            break
        }
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier,
              !application.isTerminated else { return }
        lastExternalApplication = application
    }

    private func pasteHistoryEntry(at index: Int) {
        guard history.entries.indices.contains(index) else { return }
        history.recopy(history.entries[index])
        hidePanel()

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            let alert = NSAlert()
            alert.messageText = "Allow Clippy to paste"
            alert.informativeText = "The selected item is on your clipboard. To paste it into the app you were using, allow Clippy under System Settings → Privacy & Security → Accessibility."
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        guard let target = lastExternalApplication, !target.isTerminated else { return }
        target.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard !target.isTerminated,
                  let source = CGEventSource(stateID: .combinedSessionState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.postToPid(target.processIdentifier)
            keyUp.postToPid(target.processIdentifier)
        }
    }

    private func togglePanel() {
        if panel.isVisible { hidePanel() }
        else {
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
    }

    @objc private func showFromMenu() { togglePanel() }
    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This permanently removes all saved entries."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { history.clear() }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

@MainActor
private final class ClippyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
