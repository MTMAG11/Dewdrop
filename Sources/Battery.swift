import SwiftUI
import Combine
import IOKit.ps
import Charts
import IOKit
import ServiceManagement
import UserNotifications

// MARK: - Battery reading

struct PDO: Identifiable {
    let id: Int
    let label: String       // "20 V · 3 A" or "PPS 3.3–21 V"
    let watts: Double
    let active: Bool
}

struct BatteryInfo {
    var percent = 0
    var isCharging = false
    var pluggedIn = false
    var fullyCharged = false
    var voltage = 0.0          // V
    var amperage = 0.0         // A (negative = discharging)
    var watts: Double { voltage * amperage }          // + in, - out
    var adapterWatts = 0
    var adapterIn = 0.0        // W drawn from the wall
    var systemLoad = 0.0       // W used by the Mac itself
    var batteryPower = 0.0     // W, + into battery, - out of battery
    var adapterVolts = 0.0
    var adapterLoss = 0.0       // W lost in conversion
    var wallMeasured = false    // adapterIn comes from the live SMC sensor
    var liveGauge = false       // voltage/current/power come from the live SMC gauge
    var pdos: [PDO] = []        // charger power profiles
    var systemPower: Double? = nil   // live PSTR
    var adapterContractV = 0.0  // negotiated PD voltage
    var adapterContractA = 0.0  // negotiated PD current
    var adapterAmps = 0.0
    var minutesRemaining: Int? = nil
    var cycles = 0
    var designCycles = 1000
    var designCapacity = 0     // mAh
    var maxCapacity = 0        // mAh
    var currentCapacity = 0    // mAh
    var temperature: Double? = nil   // °C
    var dailyMinSoc: Int? = nil
    var dailyMaxSoc: Int? = nil
    var lifeMinTemp: Int? = nil      // °C, gauge lifetime
    var lifeMaxTemp: Int? = nil
    var lifeMinPackV: Double? = nil  // V
    var lifeMaxPackV: Double? = nil
    var lifeMaxChargeA: Double? = nil
    var lifeMaxDischargeA: Double? = nil
    var serial = ""
    /// Plugged in but the battery is not taking or giving power (held at the charge limit): charge rate would read 0 W
    var holdingAtLimit: Bool { pluggedIn && abs(batteryPower) < 0.3 }
    /// The watts figure to headline: charge rate / battery draw normally, what the Mac itself is drawing while holding at the limit
    var displayWatts: Double {
        if holdingAtLimit { return systemLoad > 0.05 ? systemLoad : adapterIn }
        return abs(batteryPower)
    }
    var displayIsCharging: Bool { !holdingAtLimit && batteryPower >= 0 }
    var displayLabel: String { holdingAtLimit ? "System draw" : (batteryPower >= 0 ? "Charge rate" : "Power usage") }
    var health: Double { designCapacity > 0 ? Double(maxCapacity) / Double(designCapacity) * 100 : 0 }
    var hasBattery = false
}

func readBattery(ext: [String: Int] = [:]) -> BatteryInfo {
    var info = BatteryInfo()
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return info }
    defer { IOObjectRelease(svc) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let d = props?.takeRetainedValue() as? [String: Any] else { return info }

    func int(_ k: String) -> Int? { (d[k] as? NSNumber).map { Int(Int64(truncatingIfNeeded: $0.uint64Value)) } }
    func bool(_ k: String) -> Bool { (d[k] as? NSNumber)?.boolValue ?? false }

    info.hasBattery = bool("BatteryInstalled")
    info.percent = int("CurrentCapacity") ?? 0
    info.isCharging = bool("IsCharging")
    info.pluggedIn = bool("ExternalConnected")
    info.fullyCharged = bool("FullyCharged")
    info.voltage = Double(int("Voltage") ?? 0) / 1000
    info.amperage = Double(int("Amperage") ?? 0) / 1000
    info.cycles = int("CycleCount") ?? 0
    info.designCycles = int("DesignCycleCount9C") ?? 1000
    info.designCapacity = int("DesignCapacity") ?? 0
    info.maxCapacity = int("AppleRawMaxCapacity") ?? int("MaxCapacity") ?? 0
    info.currentCapacity = int("AppleRawCurrentCapacity") ?? 0
    info.serial = d["Serial"] as? String ?? ""
    let bd = d["BatteryData"] as? [String: Any] ?? [:]
    func bint(_ k: String) -> Int? { (bd[k] as? NSNumber).map { Int(Int64(truncatingIfNeeded: $0.uint64Value)) } }
    // Capacity fields live inside BatteryData on this macOS version
    info.designCapacity = int("DesignCapacity") ?? bint("DesignCapacity") ?? 0
    info.maxCapacity = int("AppleRawMaxCapacity") ?? bint("AppleRawMaxCapacity") ?? bint("FullChargeCapacity") ?? int("MaxCapacity") ?? 0
    info.currentCapacity = int("AppleRawCurrentCapacity") ?? bint("AppleRawCurrentCapacity") ?? bint("RemainingCapacity") ?? 0
    // Extended gauge fields (only visible through `ioreg -l`), refreshed in the background
    func e(_ k: String) -> Int? { ext[k] }
    if let t = e("Temperature"), t > 0 { info.temperature = Double(t) / 100 }
    info.dailyMinSoc = e("DailyMinSoc"); info.dailyMaxSoc = e("DailyMaxSoc")
    info.lifeMinTemp = e("MinimumTemperature"); info.lifeMaxTemp = e("MaximumTemperature")
    info.lifeMinPackV = e("MinimumPackVoltage").map { Double($0) / 1000 }
    info.lifeMaxPackV = e("MaximumPackVoltage").map { Double($0) / 1000 }
    info.lifeMaxChargeA = e("MaximumChargeCurrent").map { Double($0) / 1000 }
    info.lifeMaxDischargeA = e("MaximumDischargeCurrent").map { abs(Double($0)) / 1000 }
    if let a = d["AdapterDetails"] as? [String: Any] {
        if let w = a["Watts"] as? Int { info.adapterWatts = w }
        if let v = (a["AdapterVoltage"] as? NSNumber)?.doubleValue, v > 0 { info.adapterContractV = v / 1000 }
        if let c = (a["Current"] as? NSNumber)?.doubleValue, c > 0 { info.adapterContractA = c / 1000 }
    }
    if let t = d["PowerTelemetryData"] as? [String: Any] {
        func tw(_ k: String) -> Double? { (t[k] as? NSNumber).map { Double(Int64(truncatingIfNeeded: $0.uint64Value)) / 1000 } }
        info.adapterLoss = max(0, tw("AdapterEfficiencyLoss") ?? 0)
        info.systemLoad = max(0, tw("SystemLoad") ?? 0)
        info.batteryPower = tw("BatteryPower") ?? info.voltage * info.amperage
        info.adapterVolts = (tw("SystemVoltageIn") ?? 0)
        info.adapterAmps = (tw("SystemCurrentIn") ?? 0)
    } else { info.batteryPower = info.voltage * info.amperage }
    // Total drawn from the adapter = into battery + system + conversion loss
    info.adapterIn = info.pluggedIn ? max(0, info.batteryPower) + info.systemLoad + info.adapterLoss : 0
    // The IORegistry copy of voltage/current is only refreshed about once a minute. The SMC gauge keys update every second,
    // which is what makes the readings follow what you are doing.
    if let av = SMC.shared.intLE("B0AV", signed: false), av > 1000, let iv = SMC.shared.intLE("B0IV", signed: true) {
        info.voltage = av / 1000
        info.amperage = iv / 1000
        info.liveGauge = true
        if let ap = SMC.shared.intLE("B0AP", signed: true) { info.batteryPower = ap / 1000 } else { info.batteryPower = info.voltage * info.amperage }
        if let t = SMC.shared.float("TB0T"), t > 0, t < 100 { info.temperature = t }
    }
    info.systemPower = SMC.shared.float("PSTR")
    if info.pluggedIn, let ports = d["PortControllerInfo"] as? [[String: Any]] {
        for p in ports {
            guard let n = (p["PortControllerNPDOs"] as? NSNumber)?.intValue, n > 0, let raw = p["PortControllerPortPDO"] as? [NSNumber] else { continue }
            let rdo = UInt32(truncatingIfNeeded: (p["PortControllerActiveContractRdo"] as? NSNumber)?.uint64Value ?? 0)
            let activePos = Int((rdo >> 28) & 0xF)
            for (idx, num) in raw.prefix(n).enumerated() {
                let x = UInt32(truncatingIfNeeded: num.uint64Value)
                switch x >> 30 {
                case 0:   // fixed supply
                    let v = Double((x >> 10) & 0x3FF) * 0.05, a = Double(x & 0x3FF) * 0.01
                    info.pdos.append(PDO(id: idx, label: String(format: "%.0f V · %.1f A", v, a), watts: v * a, active: idx + 1 == activePos))
                case 3:   // programmable supply (PPS)
                    let minV = Double((x >> 8) & 0xFF) * 0.1, maxV = Double((x >> 17) & 0xFF) * 0.1, a = Double(x & 0x7F) * 0.05
                    info.pdos.append(PDO(id: idx, label: String(format: "PPS %.1f–%.1f V · %.1f A", minV, maxV, a), watts: maxV * a, active: idx + 1 == activePos))
                default: break
                }
            }
            break
        }
    }
    // The IORegistry telemetry only refreshes every ~10 s; the SMC sensors are live.
    if info.pluggedIn {
        if let w = SMC.shared.float("PDTR"), w > 0.5 { info.adapterIn = w; info.wallMeasured = true }
        if let sPow = SMC.shared.float("PSTR"), sPow > 0 { info.systemLoad = sPow }
    }
    if let m = int("TimeRemaining"), m > 0, m < 6000 { info.minutesRemaining = m }
    return info
}

func fmtTime(_ m: Int?) -> String {
    guard let m else { return "Calculating…" }
    return "\(m / 60)h \(String(format: "%02d", m % 60))m"
}

/// Pulls selected integer fields out of `ioreg -l` text for the battery
func readBatteryExtended() -> [String: Int] {
    let out = runCmd("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery", "-l", "-w0"], timeout: 10)
    var r: [String: Int] = [:]
    for k in ["Temperature", "DailyMinSoc", "DailyMaxSoc", "MinimumTemperature", "MaximumTemperature",
              "MinimumPackVoltage", "MaximumPackVoltage", "MaximumChargeCurrent", "MaximumDischargeCurrent"] {
        guard let range = out.range(of: "\"\(k)\"=") else { continue }
        let digits = out[range.upperBound...].prefix { $0.isNumber }
        if let u = UInt64(digits) { r[k] = Int(Int64(bitPattern: u)) }
    }
    return r
}

// MARK: - Per-app energy, devices, shell

func runCmd(_ path: String, _ args: [String], timeout: TimeInterval = 20, mergeErr: Bool = false) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe; p.standardError = mergeErr ? pipe : Pipe()
    guard (try? p.run()) != nil else { return "" }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

struct EnergyApp: Identifiable { let id = UUID(); let name: String; let impact: Double }
struct Device: Identifiable { let id = UUID(); let name: String; let levels: [(String, Int)] }

/// Activity Monitor's "Energy Impact" column, via `top` (no admin needed)
func readEnergy() -> [EnergyApp] {
    let out = runCmd("/usr/bin/top", ["-l", "2", "-n", "10", "-o", "power", "-stats", "pid,command,power"], timeout: 15)
    let lines = out.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    guard let hdr = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }
    var agg: [String: Double] = [:]
    for l in lines[(hdr + 1)...] {
        let t = l.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard t.count >= 3, Int(t[0]) != nil, let v = Double(t[t.count - 1]) else { continue }
        let name = t[1..<(t.count - 1)].joined(separator: " ")
        if name == "top" { continue }
        agg[name, default: 0] += v
    }
    return agg.filter { $0.value >= 1 }.sorted { $0.value > $1.value }.prefix(5).map { EnergyApp(name: $0.key, impact: $0.value) }
}

/// Connected Bluetooth devices that report a battery level
func readDevices() -> [Device] {
    let out = runCmd("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 25)
    guard let data = out.data(using: .utf8),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let arr = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
          let conn = arr["device_connected"] as? [[String: Any]] else { return [] }
    var res: [Device] = []
    for entry in conn {
        for (name, v) in entry {
            guard let props = v as? [String: Any] else { continue }
            var lv: [(String, Int)] = []
            for (k, label) in [("device_batteryLevelMain", "Battery"), ("device_batteryLevelLeft", "Left"),
                               ("device_batteryLevelRight", "Right"), ("device_batteryLevelCase", "Case")] {
                if let s = props[k] as? String, let n = Int(s.replacingOccurrences(of: "%", with: "")) { lv.append((label, n)) }
            }
            res.append(Device(name: name, levels: lv))
        }
    }
    return res
}

// MARK: - History

/// One reading per day of how much the battery can hold
struct HealthPoint: Codable, Identifiable {
    var id: Date { day }
    let day: Date
    var maxCapacity: Int      // mAh (average of the day's readings)
    var designCapacity: Int
    var cycles: Int
    var health: Double        // %
}

/// A stretch of charging, or a stretch on battery
struct ChargeSession: Codable, Identifiable {
    let id: UUID
    let kind: String          // "charge" or "discharge"
    let start: Date
    let end: Date
    let startPct: Int
    let endPct: Int
    let wh: Double            // energy into (charge) or out of (discharge) the battery
    let avgW: Double
    let peakW: Double
    var minutes: Double { end.timeIntervalSince(start) / 60 }
    var isCharge: Bool { kind == "charge" }
}

func fmtDuration(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
}

struct LiveSample: Identifiable {
    let id = UUID()
    let t: Date
    let battery: Double   // W, + charging / - discharging
    let system: Double    // W
    let wall: Double      // W
    let volts: Double
    let amps: Double
    let temp: Double?
    let pct: Int
}

struct Sample: Codable, Identifiable {
    var id: Date { t }
    let t: Date
    let pct: Int
    let watts: Double
    let charging: Bool
}

// MARK: - Monitor

final class Monitor: ObservableObject {
    @Published var info = BatteryInfo()
    @Published var history: [Sample] = []
    @Published var healthHistory: [HealthPoint] = []
    @Published var sessions: [ChargeSession] = []
    @Published var live: [LiveSample] = []   // ~1 Hz while a dropdown or the dashboard is open
    @Published var sessionStart = Date()
    @Published var energy: [EnergyApp] = []
    @Published var devices: [Device] = []
    @Published var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var open: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "openSections") ?? ["info", "energy"])
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var ext: [String: Int] = [:]
    var onEvent: ((BatteryEvent) -> Void)?
    private var prevPlugged: Bool?
    private var prevCharging = false
    private var fullFired = false
    private var alertsPrimed = false
    private var criticalFired: Set<Int> = []
    private var tickTimer: Timer?
    private var bag = Set<AnyCancellable>()
    private var lastStored = Date.distantPast
    private var highFired = false
    private var lowFired = false
    private let url: URL = {
        if let d = ProcessInfo.processInfo.environment["JB_DATADIR"] {     // diagnostics: keep test data away from the real history
            try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            return URL(fileURLWithPath: d).appendingPathComponent("history.json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Dewdrop", isDirectory: true)
        // earlier names: carry the history over
        for oldName in ["Cellwatch", "JuicyBattery"] {
            let old = base.appendingPathComponent(oldName, isDirectory: true)
            if FileManager.default.fileExists(atPath: old.path) && !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.moveItem(at: old, to: dir)
            }
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private var dataDir: URL { url.deletingLastPathComponent() }
    private var healthURL: URL { dataDir.appendingPathComponent("health.json") }
    private var sessionsURL: URL { dataDir.appendingPathComponent("sessions.json") }

    init() {
        let dec0 = JSONDecoder(); dec0.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: healthURL) { healthHistory = (try? dec0.decode([HealthPoint].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: sessionsURL) { sessions = (try? dec0.decode([ChargeSession].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            history = (try? dec.decode([Sample].self, from: d)) ?? []
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        tick()
        scheduleTick()
        Prefs.shared.$cfg.map(\.interval).removeDuplicates().sink { [weak self] _ in self?.scheduleTick() }.store(in: &bag)
        Activity.shared.$open.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.scheduleTick(); self?.openChanged() }.store(in: &bag)
        // macOS pushes a notification the instant power source changes (plug / unplug / charge state): no polling needed for that
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ c in
            guard let c else { return }
            Unmanaged<Monitor>.fromOpaque(c).takeUnretainedValue().tick()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
    }

    // MARK: charge / usage sessions

    private struct OpenSession {
        var kind: String
        var start: Date
        var startPct: Int
        var lastPct: Int
        var wh = 0.0
        var peak = 0.0
        mutating func add(_ i: BatteryInfo, dt: Double) {
            lastPct = i.percent
            let w = abs(i.batteryPower)
            wh += w * min(dt, 60) / 3600
            peak = max(peak, w)
        }
    }
    private var openSession: OpenSession?
    private var candidate: OpenSession?     // the new state, measured from the moment it began, during the grace period
    private var closeAt: Date?              // when the open session's state stopped matching
    private var lastTickAt: Date?

    /// Charging = "charge"; unplugged = "discharge"; plugged but not charging (held at limit / full) = no session.
    /// A change of state must last 90 s before the old session closes (so brief glitches don't split it),
    /// and the new session is counted from the moment the change began.
    func trackSessions(_ i: BatteryInfo, _ now: Date) {
        let dt = lastTickAt.map { now.timeIntervalSince($0) } ?? 0
        let prevTick = lastTickAt
        lastTickAt = now
        if dt > 120, let s = openSession, let prev = prevTick {          // the Mac was asleep: close at the last reading
            closeSession(s, at: closeAt ?? prev); openSession = nil; candidate = nil; closeAt = nil
        }
        let state: String? = i.isCharging ? "charge" : (!i.pluggedIn ? "discharge" : nil)
        if var s = openSession {
            if state == s.kind {
                s.add(i, dt: dt); openSession = s
                candidate = nil; closeAt = nil
            } else {
                if closeAt == nil { closeAt = now }
                if let st = state {
                    if candidate?.kind != st { candidate = OpenSession(kind: st, start: now, startPct: i.percent, lastPct: i.percent) }
                    candidate?.add(i, dt: dt)
                } else { candidate = nil }
                if now.timeIntervalSince(closeAt!) > 90 {                  // the change is real
                    closeSession(s, at: closeAt!)
                    openSession = candidate; candidate = nil; closeAt = nil
                }
            }
        } else if let st = state {
            openSession = OpenSession(kind: st, start: now, startPct: i.percent, lastPct: i.percent)
        }
    }

    private func closeSession(_ s: OpenSession, at end: Date) {
        let minutes = end.timeIntervalSince(s.start) / 60
        guard minutes >= 2, abs(s.lastPct - s.startPct) >= 1 || s.wh >= 0.5 else { return }
        let hours = max(minutes / 60, 0.001)
        sessions.append(ChargeSession(id: UUID(), kind: s.kind, start: s.start, end: end, startPct: s.startPct, endPct: s.lastPct,
                                      wh: s.wh, avgW: s.wh / hours, peakW: s.peak))
        if sessions.count > 400 { sessions.removeFirst(sessions.count - 400) }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(sessions) { try? d.write(to: sessionsURL, options: .atomic) }
    }

    /// Called when the app quits so the current stretch is not lost
    func flushSession() {
        if let s = openSession { closeSession(s, at: Date()); openSession = nil }
        saveHealth()
    }

    // MARK: daily health record

    private var healthSum = 0.0, healthCount = 0
    private var healthDay: Date?
    private var lastHealthSave = Date.distantPast

    private func trackHealth(_ i: BatteryInfo, _ now: Date) {
        guard i.designCapacity > 0, i.maxCapacity > 0 else { return }
        let day = Calendar.current.startOfDay(for: now)
        if healthDay != day { healthDay = day; healthSum = 0; healthCount = 0 }
        healthSum += Double(i.maxCapacity); healthCount += 1       // averaging smooths the gauge's small reading-to-reading wobble
        let avg = Int((healthSum / Double(healthCount)).rounded())
        let p = HealthPoint(day: day, maxCapacity: avg, designCapacity: i.designCapacity, cycles: i.cycles, health: Double(avg) / Double(i.designCapacity) * 100)
        if let last = healthHistory.last, last.day == day {
            healthHistory[healthHistory.count - 1] = p
        } else {
            healthHistory.append(p)
            saveHealth()
        }
        if now.timeIntervalSince(lastHealthSave) > 600 { saveHealth() }
    }

    private func saveHealth() {
        lastHealthSave = Date()
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(healthHistory) { try? d.write(to: healthURL, options: .atomic) }
    }

    func scheduleTick() {
        tickTimer?.invalidate()
        let iv = Activity.shared.interval
        let t = Timer(timeInterval: iv, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = iv * 0.35
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    /// Heavy lookups (per-app energy, Bluetooth devices, extended gauge data) only while a dropdown is open
    private var heavyTimers: [Timer] = []
    private var lastDevices = Date.distantPast
    private func openChanged() {
        heavyTimers.forEach { $0.invalidate() }; heavyTimers = []
        guard Activity.shared.open else { return }
        refreshEnergy(); refreshExt()
        if Date().timeIntervalSince(lastDevices) > 60 { lastDevices = Date(); refreshDevices() }
        func add(_ iv: TimeInterval, _ f: @escaping () -> Void) {
            let t = Timer(timeInterval: iv, repeats: true) { _ in f() }; t.tolerance = iv * 0.3
            RunLoop.main.add(t, forMode: .common); heavyTimers.append(t)
        }
        add(20) { [weak self] in self?.refreshEnergy() }
        add(30) { [weak self] in self?.refreshExt() }
        add(90) { [weak self] in self?.lastDevices = Date(); self?.refreshDevices() }
    }

    private func detectEvents(_ i: BatteryInfo) {
        defer { prevPlugged = i.pluggedIn; prevCharging = i.isCharging }
        guard let was = prevPlugged else { fullFired = i.pluggedIn && (i.fullyCharged || i.percent >= 100); return }
        if was != i.pluggedIn {
            if i.pluggedIn { onEvent?(.plugged(pct: i.percent, adapterW: i.adapterWatts, charging: i.isCharging)); criticalFired.removeAll() }
            else { onEvent?(.unplugged(pct: i.percent, minutes: i.minutesRemaining)); fullFired = false }
            return
        }
        // started charging a moment after plug-in
        if i.pluggedIn && !prevCharging && i.isCharging { onEvent?(.plugged(pct: i.percent, adapterW: i.adapterWatts, charging: true)) }
        if i.pluggedIn && (i.fullyCharged || i.percent >= 100) && !fullFired { fullFired = true; onEvent?(.full) }
        if i.percent < 97 { fullFired = false }
        if !i.pluggedIn {
            for level in [10, 5] where i.percent <= level && !criticalFired.contains(level) {
                criticalFired.insert(level)
                onEvent?(.critical(pct: i.percent, minutes: i.minutesRemaining))
                break
            }
        }
    }

    func toggle(_ id: String) {
        if open.contains(id) { open.remove(id) } else { open.insert(id) }
        UserDefaults.standard.set(Array(open), forKey: "openSections")
    }
    func refreshExt() {
        DispatchQueue.global(qos: .utility).async { let e = readBatteryExtended(); DispatchQueue.main.async { self.ext = e } }
    }
    func refreshEnergy() {
        DispatchQueue.global(qos: .utility).async { let e = readEnergy(); DispatchQueue.main.async { self.energy = e } }
    }
    func refreshDevices() {
        DispatchQueue.global(qos: .utility).async { let d = readDevices(); DispatchQueue.main.async { self.devices = d } }
    }
    /// Low Power Mode needs admin rights: macOS shows its own password prompt.
    func setLowPower(_ on: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script = "do shell script \"/usr/bin/pmset -a lowpowermode \(on ? 1 : 0)\" with administrator privileges"
            _ = runCmd("/usr/bin/osascript", ["-e", script], timeout: 120)
            DispatchQueue.main.async { self.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    func tick() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let i = Prof.time("readBattery") { readBattery(ext: ext) }
        info = i
        let now = Date()
        trackSessions(i, now)
        trackHealth(i, now)
        if Activity.shared.open {
            live.append(LiveSample(t: now, battery: i.batteryPower, system: i.pluggedIn ? i.systemLoad : abs(i.batteryPower),
                                   wall: i.adapterIn, volts: i.voltage, amps: i.amperage, temp: i.temperature, pct: i.percent))
            if live.count > 900 { live.removeFirst(live.count - 900) }
        }
        if now.timeIntervalSince(lastStored) >= 60 {
            lastStored = now
            history.append(Sample(t: now, pct: i.percent, watts: i.batteryPower, charging: i.isCharging))
            let cutoff = now.addingTimeInterval(-7 * 86400)
            history.removeAll { $0.t < cutoff }
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            if let d = try? enc.encode(history) { try? d.write(to: url, options: .atomic) }
        }
        Prof.time("detectEvents+alerts") { detectEvents(i); checkAlerts(i) }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func checkAlerts(_ i: BatteryInfo) {
        let ud = UserDefaults.standard
        let hi = ud.object(forKey: "highLimit") as? Int ?? 80
        let lo = ud.object(forKey: "lowLimit") as? Int ?? 20
        if !alertsPrimed {   // don't alert for a state that already existed when the app launched
            alertsPrimed = true
            highFired = i.pluggedIn && i.percent >= hi
            lowFired = !i.pluggedIn && i.percent <= lo
            for l in [10, 5] where !i.pluggedIn && i.percent <= l { criticalFired.insert(l) }
            return
        }
        if ud.object(forKey: "highAlert") as? Bool ?? true {
            if i.pluggedIn && i.percent >= hi && !highFired {
                highFired = true
                notify("Battery at \(i.percent)%", "Unplug to stay under your \(hi)% limit and slow battery wear.")
                onEvent?(.limit(pct: i.percent, limit: hi))
            }
            if i.percent < hi - 2 { highFired = false }
        }
        if ud.object(forKey: "lowAlert") as? Bool ?? true {
            if !i.pluggedIn && i.percent <= lo && !lowFired {
                lowFired = true
                notify("Battery low: \(i.percent)%", "Plug in soon. About \(fmtTime(i.minutesRemaining)) left.")
                onEvent?(.low(pct: i.percent, minutes: i.minutesRemaining))
            }
            if i.percent > lo + 2 { lowFired = false }
        }
    }

    /// Average discharge draw over this session's recent samples
    var avgDrain: Double? {
        let r = history.suffix(30).filter { !$0.charging && $0.watts < 0 }
        guard !r.isEmpty else { return nil }
        return -r.map(\.watts).reduce(0, +) / Double(r.count)
    }
}

