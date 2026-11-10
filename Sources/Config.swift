import SwiftUI
import Combine

enum Mod: String, CaseIterable, Codable, Identifiable {
    case battery, cpu, gpu, ram, disk, network, sensors, fans, bluetooth, clock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .battery: return "Battery"; case .cpu: return "CPU"; case .gpu: return "GPU"; case .ram: return "Memory"
        case .disk: return "Disk"; case .network: return "Network"; case .sensors: return "Sensors"; case .fans: return "Fans"
        case .bluetooth: return "Bluetooth"; case .clock: return "Clock"
        }
    }
    var short: String {
        switch self {
        case .battery: return "BAT"; case .cpu: return "CPU"; case .gpu: return "GPU"; case .ram: return "RAM"
        case .disk: return "SSD"; case .network: return "NET"; case .sensors: return "TEMP"; case .fans: return "FAN"
        case .bluetooth: return "BT"; case .clock: return "CLK"
        }
    }
    var icon: String {
        switch self {
        case .battery: return "battery.100percent"; case .cpu: return "cpu"; case .gpu: return "display"; case .ram: return "memorychip"
        case .disk: return "internaldrive"; case .network: return "network"; case .sensors: return "thermometer.medium"
        case .fans: return "fan"; case .bluetooth: return "airpodspro"; case .clock: return "clock"
        }
    }
    var color: Color {
        switch self {
        case .battery: return Color(red: 0.19, green: 0.82, blue: 0.35); case .cpu: return .blue; case .gpu: return .purple
        case .ram: return .orange; case .disk: return .cyan; case .network: return .mint; case .sensors: return .red
        case .fans: return .teal; case .bluetooth: return .indigo; case .clock: return .pink
        }
    }
    var kinds: [WidgetKind] {
        switch self {
        case .battery: return [.pill, .battery, .text, .stacked, .pie]
        case .cpu, .gpu, .ram, .disk: return [.stacked, .text, .bar, .graph, .pie]
        case .network: return [.speeds, .text, .graph]
        case .sensors, .fans, .clock: return [.text, .stacked]
        case .bluetooth: return [.icon]
        }
    }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case stacked, text, bar, graph, pie, battery, speeds, icon, pill
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stacked: return "Label over value"; case .text: return "Text"; case .bar: return "Bar"; case .graph: return "Line graph"
        case .pie: return "Ring"; case .pill: return "Pill with number"; case .battery: return "Battery icon + text"; case .speeds: return "Up / down speeds"; case .icon: return "Icon only"
        }
    }
}

struct ModuleCfg: Codable, Equatable {
    var enabled: Bool
    var widget: WidgetKind
    var combined = false
    var label = true
    var colored = true
}

struct Config: Codable, Equatable {
    var interval = 2.0
    var mods: [String: ModuleCfg] = [:]
    var order: [String] = Mod.allCases.map(\.rawValue)
    var timeZones: [String] = [TimeZone.current.identifier]
    var clock24 = false
    var clockSeconds = false
    var publicIP = false
    var descriptiveLabels = true
    var batteryWatts = true
    var batteryText = true
    var layout: [String: [String]] = [:]
    var hidden: [String] = []
    var hudEnabled = true
    var hudPlug = true, hudLow = true, hudFull = true
    var cpuAlertOn = false, cpuAlertAt = 90
    var ramAlertOn = false, ramAlertAt = 90
    var diskAlertOn = false, diskAlertGB = 20
    var tempAlertOn = false, tempAlertAt = 90

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        interval = d(.interval, 2.0); mods = d(.mods, [:]); order = d(.order, Mod.allCases.map(\.rawValue))
        timeZones = d(.timeZones, [TimeZone.current.identifier]); clock24 = d(.clock24, false); clockSeconds = d(.clockSeconds, false)
        publicIP = d(.publicIP, false); descriptiveLabels = d(.descriptiveLabels, true); batteryWatts = d(.batteryWatts, true)
        batteryText = d(.batteryText, true)
        layout = d(.layout, [:]); hidden = d(.hidden, [])
        hudEnabled = d(.hudEnabled, true); hudPlug = d(.hudPlug, true); hudLow = d(.hudLow, true); hudFull = d(.hudFull, true)
        cpuAlertOn = d(.cpuAlertOn, false); cpuAlertAt = d(.cpuAlertAt, 90); ramAlertOn = d(.ramAlertOn, false); ramAlertAt = d(.ramAlertAt, 90)
        diskAlertOn = d(.diskAlertOn, false); diskAlertGB = d(.diskAlertGB, 20); tempAlertOn = d(.tempAlertOn, false); tempAlertAt = d(.tempAlertAt, 90)
    }

    func cfg(_ m: Mod) -> ModuleCfg {
        mods[m.rawValue] ?? ModuleCfg(enabled: [.battery, .cpu, .ram, .gpu].contains(m), widget: m.kinds[0])
    }
    mutating func set(_ m: Mod, _ f: (inout ModuleCfg) -> Void) {
        var c = cfg(m); f(&c); mods[m.rawValue] = c
    }
    var orderedMods: [Mod] {
        var r = order.compactMap(Mod.init(rawValue:))
        for m in Mod.allCases where !r.contains(m) { r.append(m) }
        return r
    }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()
    @Published var cfg: Config {
        didSet {
            if let d = try? JSONEncoder().encode(cfg) { UserDefaults.standard.set(d, forKey: "config.v1") }
        }
    }
    init() {
        if let d = UserDefaults.standard.data(forKey: "config.v1"), let c = try? JSONDecoder().decode(Config.self, from: d) { cfg = c }
        else { cfg = Config() }
        // one-time migration to the battery-friendly default
        if !UserDefaults.standard.bool(forKey: "perfV2") {
            UserDefaults.standard.set(true, forKey: "perfV2")
            if cfg.interval < 5 { cfg.interval = 5 }
        }
        // live battery data is cheap now, so default back to a responsive 2 s
        if !UserDefaults.standard.bool(forKey: "perfV3") {
            UserDefaults.standard.set(true, forKey: "perfV3")
            cfg.interval = 2
        }
    }
    // MARK: popup layout (order + visibility of sections)

    func sections(_ m: Mod) -> [String] {
        let d = defaultSections(m)
        let saved = (cfg.layout[m.rawValue] ?? []).filter { d.contains($0) }
        return saved + d.filter { !saved.contains($0) }
    }
    private func module(of id: String) -> Mod? { Mod.allCases.first { defaultSections($0).contains(id) } }

    func moveSection(_ id: String, to index: Int) {
        if id.hasPrefix("mod.") {
            var o = cfg.orderedMods.map(\.rawValue)
            let raw = String(id.dropFirst(4))
            guard let from = o.firstIndex(of: raw) else { return }
            o.remove(at: from); o.insert(raw, at: max(0, min(index, o.count))); cfg.order = o
            return
        }
        guard let m = module(of: id) else { return }
        var s = sections(m)
        guard let from = s.firstIndex(of: id) else { return }
        s.remove(at: from); s.insert(id, at: max(0, min(index, s.count)))
        cfg.layout[m.rawValue] = s
    }
    func list(of id: String) -> [String] {
        if id.hasPrefix("mod.") { return cfg.orderedMods.map { "mod.\($0.rawValue)" } }
        return module(of: id).map { sections($0) } ?? []
    }
    func moveToTop(_ id: String) { moveSection(id, to: 0) }
    func move(_ id: String, by d: Int) { if let i = list(of: id).firstIndex(of: id) { moveSection(id, to: i + d) } }
    func move(_ id: String, before target: String) {
        guard id != target else { return }
        let l = list(of: id)
        guard l.contains(target), let ti = l.firstIndex(of: target), let fi = l.firstIndex(of: id) else { return }
        moveSection(id, to: fi < ti ? ti : ti)
    }
    func setHidden(_ id: String, _ hide: Bool) {
        cfg.hidden.removeAll { $0 == id }
        if hide { cfg.hidden.append(id) }
    }
    func resetLayout() { cfg.layout = [:]; cfg.hidden = [] }

    func binding<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { self.cfg[keyPath: kp] }, set: { self.cfg[keyPath: kp] = $0 })
    }
    func binding<T>(_ m: Mod, _ kp: WritableKeyPath<ModuleCfg, T>) -> Binding<T> {
        Binding(get: { self.cfg.cfg(m)[keyPath: kp] }, set: { v in self.cfg.set(m) { $0[keyPath: kp] = v } })
    }
}

func defaultSections(_ m: Mod) -> [String] {
    switch m {
    case .battery: return ["header", "info", "energy", "devices", "sessions", "history"]
    case .cpu: return ["header", "cpu.hist", "cpu.power", "cpu.cores", "cpu.load", "cpu.top", "cpu.info"]
    case .gpu: return ["header", "gpu.hist", "gpu.det"]
    case .ram: return ["header", "ram.hist", "ram.break", "ram.top"]
    case .disk: return ["header", "disk.vols", "disk.act", "disk.top"]
    case .network: return ["header", "net.speed", "net.conn", "net.wifi", "net.top"]
    case .sensors: return ["header", "sens.temp", "sens.pow", "sens.all"]
    case .fans: return []
    case .bluetooth: return ["header", "bt.dev"]
    case .clock: return ["header", "clock.zones"]
    }
}

func sectionTitle(_ id: String) -> String {
    let t: [String: String] = [
        "header": "Summary card", "info": "Battery Information", "energy": "Apps Using Significant Energy", "devices": "Connected Devices", "sessions": "Charge History", "history": "History",
        "cpu.hist": "Usage History", "cpu.power": "Power & Frequency", "cpu.cores": "Cores", "cpu.load": "Load Average", "cpu.top": "Top Processes", "cpu.info": "Processor",
        "gpu.hist": "Usage History", "gpu.det": "Details",
        "ram.hist": "Usage History", "ram.break": "Breakdown", "ram.top": "Top Processes",
        "disk.vols": "Volumes", "disk.act": "Activity", "disk.top": "Top Processes (I/O)",
        "net.speed": "Speed History", "net.conn": "Connection", "net.wifi": "Wi-Fi", "net.top": "Top Processes",
        "sens.temp": "Temperatures", "sens.pow": "Power", "sens.all": "All Sensors",
        "bt.dev": "Devices", "clock.zones": "Time Zones",
    ]
    return t[id] ?? id
}

/// Which sections are expanded (shared by every popup)
final class OpenState: ObservableObject {
    static let shared = OpenState()
    @Published var open: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "openSections2") ?? ["info", "energy", "cpu.hist", "ram.break", "net.speed", "disk.vols", "sens.temp", "gpu.hist", "clock.zones", "bt.dev"])
    func toggle(_ id: String) {
        if open.contains(id) { open.remove(id) } else { open.insert(id) }
        UserDefaults.standard.set(Array(open), forKey: "openSections2")
    }
}


/// True while a dropdown or the dashboard window is open. Heavy sampling only runs then.
final class Activity: ObservableObject {
    static let shared = Activity()
    @Published private(set) var open = false
    var popup = false { didSet { open = popup || window } }
    var window = false { didSet { open = popup || window } }
    var interval: Double { open ? 1 : max(2, Prefs.shared.cfg.interval) }
}

/// Debug: set JB_PROFILE=1 to log how much wall time each recurring job takes
enum Prof {
    static let on = ProcessInfo.processInfo.environment["JB_PROFILE"] != nil
    static var acc: [String: (n: Int, t: Double)] = [:]
    static var last = Date()
    @inline(__always) static func time<T>(_ name: String, _ f: () -> T) -> T {
        guard on else { return f() }
        let s = DispatchTime.now().uptimeNanoseconds
        let r = f()
        let d = Double(DispatchTime.now().uptimeNanoseconds - s) / 1e6
        var e = acc[name] ?? (0, 0); e.n += 1; e.t += d; acc[name] = e
        if Date().timeIntervalSince(last) > 20 {
            last = Date()
            let line = acc.sorted { $0.value.t > $1.value.t }.map { String(format: "%@ n=%d total=%.0fms avg=%.1fms", $0.key, $0.value.n, $0.value.t, $0.value.t / Double($0.value.n)) }.joined(separator: "\n  ")
            FileHandle.standardError.write(("PROFILE (20s):\n  " + line + "\n").data(using: .utf8)!)
            acc = [:]
        }
        return r
    }
}
