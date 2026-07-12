@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import ServiceManagement

enum HealthLog {
    static let url: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Switcher.log")
    }()

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let data = Data(line.utf8)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

struct SwitchItem {
    let app: NSRunningApplication
    let title: String
    let icon: NSImage
    let thumbnail: CGImage?
}

final class SwitcherView: NSView {
    var items: [SwitchItem] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    var query = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.47).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()

        let tileWidth: CGFloat = 180
        let tileHeight: CGFloat = 142
        let gap: CGFloat = 6
        for (index, item) in items.enumerated() {
            let column = index % 6
            let row = index / 6
            let rect = NSRect(x: 18 + CGFloat(column) * (tileWidth + gap), y: 18 + CGFloat(row) * (tileHeight + gap), width: tileWidth, height: tileHeight)
            (index == selected ? NSColor.controlAccentColor.withAlphaComponent(0.32) : NSColor.black.withAlphaComponent(0.12)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()

            let preview = NSRect(x: rect.minX + 6, y: rect.minY + 6, width: rect.width - 12, height: 124)
            if let cgImage = item.thumbnail {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: preview, xRadius: 5, yRadius: 5).addClip()
                NSImage(cgImage: cgImage, size: preview.size).draw(in: preview, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                item.icon.draw(in: NSRect(x: preview.midX - 54, y: preview.midY - 54, width: 108, height: 108))
            }

            if index == selected {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingMiddle
                paragraph.alignment = .center
                NSColor.windowBackgroundColor.withAlphaComponent(0.62).setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 8, y: rect.maxY - 31, width: rect.width - 16, height: 24), xRadius: 6, yRadius: 6).fill()
                item.title.draw(in: NSRect(x: rect.minX + 13, y: rect.maxY - 29, width: rect.width - 26, height: 21), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
                ])
            }
        }

        if !query.isEmpty {
            ("Search: " + query).draw(at: NSPoint(x: 20, y: bounds.maxY - 28), withAttributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
    }
}

final class SwitcherController: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var switcherView: SwitcherView!
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var items: [SwitchItem] = []
    private var activationOrder: [pid_t] = []
    private var searchMode = false
    private var query = ""
    private var displayWork: DispatchWorkItem?
    private var isVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        HealthLog.write("launched pid=\(ProcessInfo.processInfo.processIdentifier)")
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        observeActivations()
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.async {
                self.rebuildItems()
                self.showPanel()
            }
            return
        }
        requestAccessibility()
        registerLoginItem()
        startPermissionMonitor()
    }

    private func makePanel() {
        switcherView = SwitcherView(frame: .zero)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 178),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = switcherView
    }

    private func observeActivations() {
        if let current = NSWorkspace.shared.frontmostApplication { activationOrder.append(current.processIdentifier) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.activationOrder.removeAll { $0 == app.processIdentifier }
            self?.activationOrder.insert(app.processIdentifier, at: 0)
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        HealthLog.write("Accessibility trusted=\(trusted)")
    }

    private func registerLoginItem() {
        do {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            HealthLog.write("login item status=\(SMAppService.mainApp.status.rawValue)")
        } catch {
            HealthLog.write("login item registration failed: \(error.localizedDescription)")
        }
    }

    private func startPermissionMonitor() {
        checkPermissionAndInstallTap()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkPermissionAndInstallTap()
        }
    }

    private func checkPermissionAndInstallTap() {
        guard eventTap == nil else { permissionTimer?.invalidate(); permissionTimer = nil; return }
        guard AXIsProcessTrusted() else { return }
        installEventTap()
    }

    private func installEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                     options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                     callback: { _, type, event, refcon in
            let controller = Unmanaged<SwitcherController>.fromOpaque(refcon!).takeUnretainedValue()
            return controller.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: pointer)
        guard let eventTap else {
            HealthLog.write("event tap creation failed; will retry")
            return
        }
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        HealthLog.write("event tap installed; Switcher is ready")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            HealthLog.write("event tap was disabled and has been re-enabled")
            return false
        }
        let flags = event.flags
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged, isVisible, !flags.contains(.maskCommand) {
            DispatchQueue.main.async { self.commitSelection() }
            return true
        }
        guard type == .keyDown else { return false }
        if flags.contains(.maskCommand), key == 48 {
            HealthLog.write("received Command-Tab")
            DispatchQueue.main.async { self.advance(backward: flags.contains(.maskShift)) }
            return true
        }
        guard isVisible else { return false }
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        let text = String(utf16CodeUnits: buffer, count: length)
        DispatchQueue.main.async { self.handleVisibleKey(key, flags: flags, text: text) }
        return true
    }

    private func advance(backward: Bool) {
        if !isVisible {
            rebuildItems()
            guard !items.isEmpty else { return }
            switcherView.selected = items.count > 1 ? (backward ? items.count - 1 : 1) : 0
            displayWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.showPanel() }
            displayWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
        } else {
            switcherView.selected = SwitcherModel.movedIndex(switcherView.selected, by: backward ? -1 : 1, count: items.count)
        }
    }

    private func rebuildItems() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID && !$0.isTerminated && !$0.isHidden && $0.activationPolicy == .regular &&
            !SwitcherModel.excludedBundleIdentifiers.contains($0.bundleIdentifier ?? "")
        }
        items = apps.sorted { rank($0) < rank($1) }.compactMap { app in
            guard let titleAndWindow = mainWindow(for: app) else { return nil }
            return SwitchItem(app: app, title: titleAndWindow.title ?? app.localizedName ?? "Unknown",
                              icon: app.icon ?? NSImage(), thumbnail: titleAndWindow.image)
        }
        if !query.isEmpty { items = items.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.app.localizedName ?? "").localizedCaseInsensitiveContains(query) } }
        switcherView.items = items
        switcherView.selected = min(switcherView.selected, max(0, items.count - 1))
    }

    private func rank(_ app: NSRunningApplication) -> Int {
        activationOrder.firstIndex(of: app.processIdentifier) ?? (10_000 + Int(app.processIdentifier))
    }

    private func mainWindow(for app: NSRunningApplication) -> (title: String?, image: CGImage?)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = list.filter({ ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 })
                    .max(by: { area($0) < area($1) }),
              let number = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
        let image = CGWindowListCreateImage(.null, .optionIncludingWindow, number, [.boundsIgnoreFraming, .bestResolution])
        return (info[kCGWindowName as String] as? String, image)
    }

    private func area(_ info: [String: Any]) -> CGFloat {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict) else { return 0 }
        return rect.width * rect.height
    }

    private func showPanel() {
        guard !items.isEmpty else { return }
        isVisible = true
        let columns = min(items.count, 6)
        let rows = Int(ceil(Double(items.count) / 6.0))
        let width = CGFloat(columns) * 186 + 24
        let height = CGFloat(rows) * 154 + (query.isEmpty ? 24 : 56)
        panel.setContentSize(NSSize(width: width, height: height))
        switcherView.frame = NSRect(origin: .zero, size: panel.frame.size)
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: screen.midX - width / 2, y: screen.midY - height / 2))
        panel.orderFrontRegardless()
        HealthLog.write("showing \(items.count) apps")
    }

    private func hidePanel() {
        displayWork?.cancel()
        panel.orderOut(nil)
        isVisible = false
        searchMode = false
        query = ""
        switcherView.query = ""
    }

    private func commitSelection() {
        guard isVisible, items.indices.contains(switcherView.selected) else { hidePanel(); return }
        let app = items[switcherView.selected].app
        HealthLog.write("focusing \(app.localizedName ?? app.bundleIdentifier ?? "unknown")")
        hidePanel()
        app.unhide()
        app.activate(options: [.activateAllWindows])
    }

    private func handleVisibleKey(_ key: Int64, flags: CGEventFlags, text: String) {
        if searchMode {
            if key == 53 { query = ""; searchMode = false; rebuildItems(); switcherView.query = ""; return }
            if key == 36 { commitSelection(); return }
            if key == 51 { if !query.isEmpty { query.removeLast() }; rebuildItems(); switcherView.query = query; return }
            if text.count == 1, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                query += text
                rebuildItems()
                switcherView.query = query
            }
            return
        }
        switch key {
        case 53: hidePanel()
        case 36: commitSelection()
        case 123: switcherView.selected = SwitcherModel.movedIndex(switcherView.selected, by: -1, count: items.count)
        case 124: switcherView.selected = SwitcherModel.movedIndex(switcherView.selected, by: 1, count: items.count)
        case 1: searchMode = true; query = ""; switcherView.query = "Type to search"
        case 13: performWindowAction(kAXCloseButtonAttribute)
        case 46: toggleMinimized()
        case 3: toggleFullscreen()
        case 12: selectedApp()?.terminate(); hidePanel()
        case 4: toggleHidden()
        case 7: toggleMinimized()
        default: break
        }
    }

    private func selectedApp() -> NSRunningApplication? {
        items.indices.contains(switcherView.selected) ? items[switcherView.selected].app : nil
    }

    private func focusedWindow() -> AXUIElement? {
        guard let app = selectedApp() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) != .success {
            guard AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &value) == .success else { return nil }
        }
        return (value as! AXUIElement)
    }

    private func performWindowAction(_ buttonAttribute: String) {
        guard let window = focusedWindow() else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, buttonAttribute as CFString, &value) == .success else { return }
        AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString)
        rebuildItems()
    }

    private func toggleFullscreen() {
        guard let window = focusedWindow() else { return }
        var value: CFTypeRef?
        let key = "AXFullScreen" as CFString
        AXUIElementCopyAttributeValue(window, key, &value)
        AXUIElementSetAttributeValue(window, key, (!(value as? Bool ?? false)) as CFBoolean)
    }

    private func toggleMinimized() {
        guard let window = focusedWindow() else { return }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, (!(value as? Bool ?? false)) as CFBoolean)
        rebuildItems()
    }

    private func toggleHidden() {
        guard let app = selectedApp() else { return }
        if app.isHidden { app.unhide() } else { app.hide() }
        rebuildItems()
    }
}

let app = NSApplication.shared
let delegate = SwitcherController()
app.delegate = delegate
app.run()
