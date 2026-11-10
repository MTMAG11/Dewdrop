import AppKit
import SwiftUI
import Combine

// MARK: - Popup content

struct PopupRoot: View {
    let mods: [Mod]
    @ObservedObject var batt: Monitor
    @ObservedObject var sys: SystemStore
    var snapshot = false

    var maxH: CGFloat { (NSScreen.main?.visibleFrame.height ?? 800) - 100 }

    @ViewBuilder func module(_ m: Mod) -> some View {
        switch m {
        case .battery: BatteryContent(m: batt)
        case .cpu: CPUContent(sys: sys)
        case .gpu: GPUContent(sys: sys)
        case .ram: RAMContent(sys: sys)
        case .disk: DiskContent(sys: sys)
        case .network: NetContent(sys: sys)
        case .sensors: SensorsContent(sys: sys)
        case .fans: FansContent(sys: sys)
        case .bluetooth: BluetoothContent(batt: batt)
        case .clock: ClockContent(sys: sys)
        }
    }

    var inner: some View {
        VStack(spacing: 10) {
            if mods.count == 1 {
                module(mods[0])
            } else {
                ForEach(mods) { m in
                    Group {
                        if m == .battery { module(m) }
                        else { Collapsible(id: "mod.\(m.rawValue)", title: m.title, icon: m.icon, color: m.color) { module(m) } }
                    }.modifier(SectionDrag(id: "mod.\(m.rawValue)"))
                }
            }
            PopupFooter(m: batt, showBattery: mods.contains(.battery), page: mods.first.map(Page.forMod) ?? .overview)
        }
        .padding(12)
    }

    var body: some View {
        Group {
            if snapshot { inner } else { ScrollView(.vertical, showsIndicators: false) { inner } }
        }
        .frame(width: 366)
        .background(jbg)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.16)))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Borderless popup panel under a status item

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PopupController: NSObject {
    let panel: PopupPanel
    let hc: NSHostingController<AnyView>
    let measure: AnyView
    private let root: AnyView
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var resignObs: NSObjectProtocol?
    private var fitTimer: Timer?
    private var closedAt = Date.distantPast
    private var topY: CGFloat = 0
    static var autoClose = true

    init(root: AnyView, measure: AnyView) {
        self.measure = measure
        self.root = root
        hc = NSHostingController(rootView: AnyView(Color.clear))   // content is only mounted while open (no idle re-rendering)
        hc.sizingOptions = []
        panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 366, height: 400),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.contentView = hc.view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
    }

    var isOpen: Bool { panel.isVisible }

    /// Exact content height, measured by rendering the non-scrolling variant; capped to the screen
    var idealSize: NSSize {
        let h: CGFloat = MainActor.assumeIsolated {
            let r = ImageRenderer(content: measure.frame(width: 366).fixedSize(horizontal: false, vertical: true))
            r.scale = 1
            return r.nsImage?.size.height ?? 420
        }
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 60
        return NSSize(width: 366, height: min(max(h, 120), maxH))
    }

    func toggle(from button: NSStatusBarButton) {
        if isOpen { close(); return }
        if Date().timeIntervalSince(closedAt) < 0.25 { return }
        guard let win = button.window else { return }
        let bf = win.convertToScreen(button.convert(button.bounds, to: nil))
        Activity.shared.popup = true
        hc.rootView = root
        let size = idealSize
        let screen = win.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = bf.midX - size.width / 2
        x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)
        topY = bf.minY - 6
        panel.setFrame(NSRect(x: x, y: topY - size.height, width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in self?.close() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.close(); return nil }
            return e
        }
        if PopupController.autoClose {
            resignObs = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.close() }
        }
        let ft = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in self?.fit() }
        ft.tolerance = 0.2
        RunLoop.main.add(ft, forMode: .common)
        fitTimer = ft
    }

    private func fit() {
        let s = idealSize
        guard panel.isVisible, abs(s.height - panel.frame.height) > 1 else { return }
        panel.setFrame(NSRect(x: panel.frame.minX, y: topY - s.height, width: 366, height: s.height), display: true)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        hc.rootView = AnyView(Color.clear)
        Activity.shared.popup = false
        closedAt = Date()
        fitTimer?.invalidate(); fitTimer = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let o = resignObs { NotificationCenter.default.removeObserver(o); resignObs = nil }
    }
}

// MARK: - Settings window

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    var batt: Monitor?
    private var window: NSWindow?

    func show() {
        guard let batt else { return }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Settings"
            w.contentViewController = NSHostingController(rootView: SettingsView(batt: batt))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        HelperState.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

func openSettingsWindow() { SettingsWindowController.shared.show() }

// MARK: - Dashboard window (the full app)

final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()
    var batt: Monitor?
    private var window: NSWindow?

    func show(_ page: Page? = nil) {
        guard let batt else { return }
        if let page { NavModel.shared.page = page }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Dewdrop"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.minSize = NSSize(width: 900, height: 600)
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor(white: 0.105, alpha: 1)
            w.appearance = NSAppearance(named: .darkAqua)
            let hc = NSHostingController(rootView: DashboardView(sys: SystemStore.shared, batt: batt))
            hc.sizingOptions = []
            w.contentViewController = hc
            w.setContentSize(NSSize(width: 1120, height: 780))
            w.delegate = self
            w.setFrameAutosaveName("DewdropDashboard")
            if !w.setFrameUsingName("DewdropDashboard") { w.center() }
            window = w
        }
        NSApp.setActivationPolicy(.regular)       // Dock icon + app menu while the window is open
        Activity.shared.window = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Activity.shared.window = false
        NSApp.setActivationPolicy(.accessory)     // back to menu-bar only
    }
}

func openDashboard(_ page: Page? = nil) { DispatchQueue.main.async { DashboardWindowController.shared.show(page) } }

// MARK: - Status items

final class StatusController: NSObject {
    let sys = SystemStore.shared
    let batt: Monitor
    let prefs = Prefs.shared
    private var items: [String: (item: NSStatusItem, popup: PopupController, mods: [Mod])] = [:]
    private var signature = ""
    private var lastSig: [String: String] = [:]
    private var bag = Set<AnyCancellable>()

    init(batt: Monitor) {
        self.batt = batt
        super.init()
        rebuild()
        prefs.$cfg.receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }.store(in: &bag)
        sys.$tick.receive(on: RunLoop.main).sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &bag)
        batt.$info.receive(on: RunLoop.main).sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &bag)
    }

    /// Menu bar items to show, left-to-right: each module alone, merged modules grouped at the first merged position
    private func plan() -> [(key: String, mods: [Mod])] {
        let c = prefs.cfg
        let enabled = c.orderedMods.filter { c.cfg($0).enabled }
        var res: [(String, [Mod])] = []
        var placed = false
        let merged = enabled.filter { c.cfg($0).combined }
        for m in enabled {
            if c.cfg(m).combined {
                if !placed { res.append(("combined", merged)); placed = true }
            } else { res.append((m.rawValue, [m])) }
        }
        return res
    }

    private func rebuild() {
        let p = plan()
        let sig = p.map { "\($0.key):" + $0.mods.map(\.rawValue).joined(separator: ",") }.joined(separator: "|")
        if sig == signature { refresh(); return }
        signature = sig
        lastSig.removeAll()
        for (_, v) in items { v.popup.close(); NSStatusBar.system.removeStatusItem(v.item) }
        items.removeAll()
        // items stack leftwards in creation order, so create the rightmost first
        for (key, mods) in p.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "Dewdrop." + key   // remembers where you Cmd-drag it in the menu bar
            item.button?.identifier = NSUserInterfaceItemIdentifier(key)
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.imagePosition = .imageOnly
            let popup = PopupController(root: AnyView(PopupRoot(mods: mods, batt: batt, sys: sys)),
                                        measure: AnyView(PopupRoot(mods: mods, batt: batt, sys: sys, snapshot: true)))
            items[key] = (item, popup, mods)
        }
        refresh()
    }

    /// Merge the battery and system ticks into one menu bar update (each update makes macOS redraw the icon)
    private var refreshPending = false
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }

    func refresh() {
        let cfg = prefs.cfg
        for (key, v) in items {
            guard let b = v.item.button else { continue }
            let dark = b.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            // Only re-render the menu bar image when something visible changed
            let sig = (dark ? "d" : "l") + v.mods.map { m -> String in
                let d = widgetData(m, sys, batt, cfg), c = cfg.cfg(m)
                return "\(m.rawValue)|\(c.widget.rawValue)|\(c.label)|\(c.colored)|\(d.value)|\(d.line1)|\(d.line2)|\(d.pct)|\(d.charging)|" + (c.widget == .graph ? "\(d.hist.count)/\(d.hist.last ?? 0)" : "")
            }.joined(separator: ";")
            if lastSig[key] == sig, b.image != nil { continue }
            lastSig[key] = sig
            if let img = Prof.time("renderStrip", { renderStrip(mods: v.mods, dark: dark, sys: sys, batt: batt, cfg: prefs.cfg) }) {
                img.isTemplate = false
                b.image = img
            }
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let (key, v) = items.first(where: { $0.value.item.button === sender }) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Dashboard", action: #selector(openDash), keyEquivalent: "d").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            let prev = NSMenuItem(title: "Preview On-Screen Alerts", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, sel) in [("Plugged in", #selector(prevPlug)), ("Unplugged", #selector(prevUnplug)), ("Low battery", #selector(prevLow)),
                                 ("Critical battery", #selector(prevCritical)), ("Fully charged", #selector(prevFull)), ("Charge limit", #selector(prevLimit))] {
                sub.addItem(withTitle: title, action: sel, keyEquivalent: "").target = self
            }
            prev.submenu = sub
            menu.addItem(prev)
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
            v.item.menu = menu
            sender.performClick(nil)
            v.item.menu = nil
            return
        }
        for (k, o) in items where k != key { o.popup.close() }
        v.popup.toggle(from: sender)
    }

    func selfTest() {
        PopupController.autoClose = false
        let dir = ProcessInfo.processInfo.environment["JB_SELFTEST"] ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let (key, v) = self.items.first(where: { $0.key == "battery" }) ?? self.items.first, let b = v.item.button else { return }
            FileHandle.standardError.write("selftest: ideal=\(v.popup.idealSize)\n".data(using: .utf8)!)
            v.popup.toggle(from: b)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let view = v.popup.hc.view
                FileHandle.standardError.write("selftest[\(key)] open=\(v.popup.isOpen) frame=\(v.popup.panel.frame) ideal=\(v.popup.idealSize)\n".data(using: .utf8)!)
                _ = view
                FileHandle.standardError.write("selftest: window=\(v.popup.panel.windowNumber)\n".data(using: .utf8)!)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { exit(0) }
        }
    }

    @objc private func openSettings() { openSettingsWindow() }
    @objc private func openDash() { openDashboard() }
    @objc private func prevPlug() { HUDController.shared.show(.plugged(pct: batt.info.percent, adapterW: batt.info.adapterWatts, charging: true), force: true) }
    @objc private func prevUnplug() { HUDController.shared.show(.unplugged(pct: batt.info.percent, minutes: batt.info.minutesRemaining), force: true) }
    @objc private func prevLow() { HUDController.shared.show(.low(pct: 20, minutes: batt.info.minutesRemaining), force: true) }
    @objc private func prevCritical() { HUDController.shared.show(.critical(pct: 5, minutes: batt.info.minutesRemaining), force: true) }
    @objc private func prevFull() { HUDController.shared.show(.full, force: true) }
    @objc private func prevLimit() { HUDController.shared.show(.limit(pct: 80, limit: 80), force: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Launch

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: StatusController?
    let batt = Monitor()
    func applicationWillTerminate(_ notification: Notification) { batt.flushSession() }

    @objc func openSettingsAction() { openSettingsWindow() }
    @objc func openDashboardAction() { openDashboard() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openDashboard(); return true }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dewdrop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Open Dashboard", action: #selector(openDashboardAction), keyEquivalent: "d").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Dewdrop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Dewdrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu
        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
    }

    private var launchedAsLoginItem: Bool {
        guard let e = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return e.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        DashboardWindowController.shared.batt = batt
        SettingsWindowController.shared.batt = batt
        batt.onEvent = { HUDController.shared.show($0) }
        status = StatusController(batt: batt)
        let env = ProcessInfo.processInfo.environment
        let testing = env["JB_SESSIONTEST"] != nil || env["JB_SELFTEST"] != nil || env["JB_HUDTEST"] != nil || env["JB_LIVETEST"] != nil || env["JB_DASHTEST"] != nil
        if let path = env["JB_PARSETEST"], let d = FileManager.default.contents(atPath: path),
           let root = (try? PropertyListSerialization.propertyList(from: d, options: [], format: nil)) as? [String: Any] {
            let c = Helper.parse(root)
            print("parsed cpu=\(String(describing: c.cpuW)) gpu=\(String(describing: c.gpuW)) ane=\(String(describing: c.aneW)) pkg=\(String(describing: c.packageW)) clusters=\(c.clusters) gpuMHz=\(String(describing: c.gpuMHz)) thermal=\(String(describing: c.thermal))")
            print("install script:\n" + (Helper.installScript() ?? "nil"))
            exit(0)
        }
        if env["JB_SESSIONTEST"] != nil {
            let m = batt
            let base = Date(timeIntervalSince1970: 1_800_000_000)
            func feed(_ t0: Double, _ t1: Double, plugged: Bool, charging: Bool, watts: Double, pct0: Int, pct1: Int) {
                var t = t0
                while t < t1 {
                    var i = BatteryInfo()
                    i.pluggedIn = plugged; i.isCharging = charging; i.batteryPower = watts
                    i.percent = pct0 + Int(Double(pct1 - pct0) * (t - t0) / max(t1 - t0, 1))
                    m.trackSessions(i, base.addingTimeInterval(t))
                    t += 5
                }
            }
            feed(0, 600, plugged: false, charging: false, watts: -6, pct0: 80, pct1: 77)        // 10 min on battery
            feed(600, 1200, plugged: true, charging: true, watts: 30, pct0: 77, pct1: 81)       // charging
            feed(1200, 1220, plugged: true, charging: false, watts: 0, pct0: 81, pct1: 81)      // 20 s glitch: must NOT split the session
            feed(1220, 1800, plugged: true, charging: true, watts: 30, pct0: 81, pct1: 85)      // charging again
            feed(1800, 2000, plugged: true, charging: false, watts: 0, pct0: 85, pct1: 85)      // held at the limit: charge session closes after 90 s
            feed(2000, 2300, plugged: false, charging: false, watts: -8, pct0: 85, pct1: 83)    // on battery 5 min
            var wake = BatteryInfo(); wake.pluggedIn = false; wake.batteryPower = -8; wake.percent = 70
            m.trackSessions(wake, base.addingTimeInterval(9000))                                 // woke after a long sleep: closes at the last reading
            for s in m.sessions {
                print(String(format: "session %@  %@ -> %@  %d%% -> %d%%  %.1f min  %.2f Wh  avg %.1f W  peak %.1f W", s.kind, "\(Int(s.start.timeIntervalSince(base)))s", "\(Int(s.end.timeIntervalSince(base)))s", s.startPct, s.endPct, s.minutes, s.wh, s.avgW, s.peakW))
            }
            print("total sessions: \(m.sessions.count)")
            exit(0)
        }
        if env["JB_DASHTEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { openDashboard(.battery) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                let w = NSApp.windows.first { $0.title == "Dewdrop" }
                FileHandle.standardError.write("dashtest: visible=\(w?.isVisible ?? false) frame=\(String(describing: w?.frame)) policy=\(NSApp.activationPolicy().rawValue) interval=\(Activity.shared.interval) open=\(Activity.shared.open) topCPU=\(SystemStore.shared.topCPU.count) energy=\(self.batt.energy.count)\n".data(using: .utf8)!)
                exit(0)
            }
        }
        if !testing && !launchedAsLoginItem { openDashboard() }
        if ProcessInfo.processInfo.environment["JB_SELFTEST"] != nil { status?.selfTest() }
        if ProcessInfo.processInfo.environment["JB_LIVETEST"] != nil {
            var n = 0
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                n += 1
                if n == 4 { let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", "for i in 1 2 3 4 5 6 7 8 9 10; do (timeout 5 yes > /dev/null &) ; done; sleep 6"]; try? p.run() }
                let i = readBattery()
                let g = SystemStore.shared.gpuPower.map { String(format: "%.2f", $0) } ?? "-"
                FileHandle.standardError.write(String(format: "live t=%2d  %@  V=%.3f  I=%7.0f mA  battery=%6.2f W  system=%5.2f W  wall=%5.2f W  temp=%@  gpuW=%@\n", n, i.liveGauge ? "SMC " : "IORG", i.voltage, i.amperage * 1000, i.batteryPower, i.systemPower ?? -1, i.adapterIn, i.temperature.map { String(format: "%.1f", $0) } ?? "-", g).data(using: .utf8)!)
                if n >= 12 { exit(0) }
            }
        }
        if ProcessInfo.processInfo.environment["JB_HUDTEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { HUDController.shared.show(.plugged(pct: 78, adapterW: 60, charging: true), force: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { HUDController.shared.show(.critical(pct: 5, minutes: 11), force: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13) { FileHandle.standardError.write("hudtest ok\n".data(using: .utf8)!); exit(0) }
        }
    }
}

/// One-time: bring settings over from the app's previous name
func migrateFromOldName() {
    let ud = UserDefaults.standard
    guard !ud.bool(forKey: "migratedFromOldName") else { return }
    let keys = ["config.v1", "openSections2", "range", "highAlert", "highLimit", "lowAlert", "lowLimit", "perfV2", "perfV3"]
    var copied = Set<String>()
    for suite in ["com.rishaan.cellwatch", "com.rishaan.juicybattery"] {      // newest earlier name first
        guard let old = UserDefaults(suiteName: suite) else { continue }
        for (k, v) in old.dictionaryRepresentation() where keys.contains(k) && !copied.contains(k) { ud.set(v, forKey: k); copied.insert(k) }
    }
    ud.set(true, forKey: "migratedFromOldName")
}
migrateFromOldName()

/// Only one copy may own the menu bar: a newly launched copy replaces any older one (no duplicate icons after an update)
func replaceOlderInstances() {
    guard let id = Bundle.main.bundleIdentifier else { return }
    let me = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != me }
    for o in others { o.terminate() }
    let deadline = Date().addingTimeInterval(2)
    while others.contains(where: { !$0.isTerminated }) && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    for o in others where !o.isTerminated { o.forceTerminate() }
}
let isDiagnosticRun = CommandLine.arguments.contains("--snapshot") || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("JB_") }
if !isDiagnosticRun { replaceOlderInstances() }

let app = NSApplication.shared

// Debug: `Dewdrop --snapshot <dir>` renders the widgets and popups to PNG files and exits.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
    let dir = CommandLine.arguments[i + 1]
    let batt = Monitor()
    let sys = SystemStore.shared
    if ProcessInfo.processInfo.environment["JB_DEMODATA"] != nil {      // diagnostics only: fabricated rows to check the layout, never saved
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        batt.healthHistory = (0..<42).map { n in
            let day = cal.date(byAdding: .day, value: -(41 - n), to: today)!
            let h = 100.4 - Double(n) * 0.012 + sin(Double(n)) * 0.05
            return HealthPoint(day: day, maxCapacity: Int(4629 * h / 100), designCapacity: 4629, cycles: n / 3, health: h)
        }
        var demo: [ChargeSession] = []
        for n in 0..<14 {
            let start = Date(timeIntervalSinceNow: -Double(14 - n) * 11 * 3600)
            let charge = n % 2 == 1
            let mins = charge ? 55 + Double(n * 3) : 240 + Double(n * 7)
            demo.append(ChargeSession(id: UUID(), kind: charge ? "charge" : "discharge", start: start, end: start.addingTimeInterval(mins * 60),
                                      startPct: charge ? 22 + n : 96 - n, endPct: charge ? 80 : 30 + n, wh: charge ? 31 + Double(n) : 38 + Double(n) * 1.5,
                                      avgW: charge ? 34 : 9.5 + Double(n % 4), peakW: charge ? 52 : 21))
        }
        batt.sessions = demo
    }
    Activity.shared.popup = true          // sample at 1 Hz so charts have data
    RunLoop.main.run(until: Date().addingTimeInterval(14))
    // clean screenshots: hide processes whose name contains the text in JB_SCRUB
    if let hide = ProcessInfo.processInfo.environment["JB_SCRUB"]?.lowercased(), !hide.isEmpty {
        batt.energy.removeAll { $0.name.lowercased().contains(hide) }
        sys.topCPU.removeAll { $0.name.lowercased().contains(hide) }
        sys.topMem.removeAll { $0.name.lowercased().contains(hide) }
        sys.topDisk.removeAll { $0.name.lowercased().contains(hide) }
        sys.topNet.removeAll { $0.name.lowercased().contains(hide) }
    }
    MainActor.assumeIsolated {
        func save(_ img: NSImage?, _ name: String) {
            guard let img, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
        }
        var cfg = Prefs.shared.cfg
        for m in Mod.allCases { cfg.set(m) { $0.enabled = true } }
        for dark in [true, false] {
            let fg: Color = dark ? .white : .black
            let strip = MenuBarStrip(mods: Mod.allCases, sys: sys, batt: batt, cfg: cfg, fg: fg)
                .padding(6).background(Color(white: dark ? 0.12 : 0.92)).environment(\.colorScheme, dark ? .dark : .light)
            let r = ImageRenderer(content: strip); r.scale = 2
            save(r.nsImage, "strip-" + (dark ? "dark" : "light"))
        }
        let events: [(String, BatteryEvent)] = [("plugged", .plugged(pct: 64, adapterW: 60, charging: true)), ("unplugged", .unplugged(pct: 64, minutes: 612)),
            ("low", .low(pct: 20, minutes: 74)), ("critical", .critical(pct: 5, minutes: 11)), ("full", .full), ("limit", .limit(pct: 80, limit: 80))]
        for (name, e) in events {
            let r = ImageRenderer(content: HUDCard(event: e, t: 1.4).padding(30).background(Color(white: 0.35))); r.scale = 2
            save(r.nsImage, "hud-" + name)
        }
        for p in Page.allCases {
            let content = PageContent(page: p, sys: sys, batt: batt).padding(24).frame(width: 900, alignment: .topLeading).background(jbg).environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: content); r.scale = 1
            save(r.nsImage, "page-" + p.rawValue)
        }
        for m in Mod.allCases {
            let r = ImageRenderer(content: PopupRoot(mods: [m], batt: batt, sys: sys, snapshot: true).frame(width: 366, alignment: .top).background(Color(white: 0.3)))
            r.scale = 1.2
            save(r.nsImage, "popup-" + m.rawValue)
        }
    }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
