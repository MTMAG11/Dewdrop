import SwiftUI
import Combine
import IOKit
import Darwin
import CoreWLAN
import UserNotifications

// MARK: - Small models

struct Proc: Identifiable { let id: Int; let name: String; let value: Double }
struct Vol: Identifiable { var id: String { path }; let path: String; let name: String; let total: Double; let free: Double }
struct SensorReading: Identifiable { var id: String { name }; let name: String; let value: Double }
struct FanReading: Identifiable { var id: Int; let rpm: Double; let min: Double; let max: Double }
struct WifiInfo { var rssi: Int; var rate: Double; var channel: Int?; var band: String? }

// MARK: - SMC (unprivileged reads only)

private struct SMCKeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
private struct SMCVers { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct SMCPLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var mem: UInt32 = 0 }
private struct SMCData {
    var key: UInt32 = 0
    var vers = SMCVers()
    var pLimit = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SMC {
    static let shared = SMC()
    private var conn: io_connect_t = 0
    private(set) var ok = false

    init() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if svc != 0 {
            ok = IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS
            IOObjectRelease(svc)
        }
    }

    private func fourcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private func call(_ i: inout SMCData) -> Bool {
        var o = SMCData()
        var sz = MemoryLayout<SMCData>.stride
        let r = IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<SMCData>.stride, &o, &sz)
        if r == KERN_SUCCESS { i = o; return true }
        return false
    }

    func read(_ key: String) -> (bytes: [UInt8], type: UInt32)? {
        guard ok else { return nil }
        var i = SMCData(); i.key = fourcc(key); i.data8 = 9
        guard call(&i), i.result == 0 else { return nil }
        let size = Int(i.keyInfo.dataSize), type = i.keyInfo.dataType
        var j = SMCData(); j.key = fourcc(key); j.keyInfo = i.keyInfo; j.data8 = 5
        guard call(&j), j.result == 0 else { return nil }
        return (withUnsafeBytes(of: j.bytes) { Array($0.prefix(size)) }, type)
    }

    func float(_ key: String) -> Double? {
        guard let r = read(key), r.type == fourcc("flt "), r.bytes.count == 4 else { return nil }
        return Double(r.bytes.withUnsafeBytes { $0.load(as: Float.self) })
    }

    /// Battery-gauge keys (B0AV, B0IV, B0AP…) are little-endian integers
    func intLE(_ key: String, signed: Bool) -> Double? {
        guard let r = read(key), !r.bytes.isEmpty, r.bytes.count <= 8 else { return nil }
        var v: UInt64 = 0
        for (i, x) in r.bytes.enumerated() { v |= UInt64(x) << (8 * UInt64(i)) }
        if signed { let sh = UInt64(64 - r.bytes.count * 8); return Double(Int64(bitPattern: v << sh) >> Int64(sh)) }
        return Double(v)
    }

    func int(_ key: String) -> Int? {
        guard let r = read(key), r.bytes.count == 1 else { return nil }
        return Int(r.bytes[0])
    }
}

// MARK: - GPU power via IOReport (the CPU/DRAM counters are not readable without root on this macOS)

final class GPUPower {
    private typealias CopyInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSub = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeRawPointer?
    private typealias CreateSamples = @convention(c) (UnsafeRawPointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias GetStr = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias IntVal = @convention(c) (CFDictionary, UnsafeMutablePointer<Int32>?) -> Int64
    private var sub: UnsafeRawPointer?
    private var subbed: Unmanaged<CFMutableDictionary>?
    private var samples: CreateSamples?
    private var name: GetStr?
    private var unit: GetStr?
    private var intVal: IntVal?
    private var last: (v: Double, t: Date)?
    private(set) var available = false

    init() {
        guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW),
              let a = dlsym(h, "IOReportCopyChannelsInGroup"), let b = dlsym(h, "IOReportCreateSubscription"),
              let c = dlsym(h, "IOReportCreateSamples"), let d = dlsym(h, "IOReportChannelGetChannelName"),
              let e = dlsym(h, "IOReportChannelGetUnitLabel"), let f = dlsym(h, "IOReportSimpleGetIntegerValue") else { return }
        let copy = unsafeBitCast(a, to: CopyInGroup.self)
        guard let chans = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return }
        sub = unsafeBitCast(b, to: CreateSub.self)(nil, chans, &subbed, 0, nil)
        samples = unsafeBitCast(c, to: CreateSamples.self)
        name = unsafeBitCast(d, to: GetStr.self); unit = unsafeBitCast(e, to: GetStr.self); intVal = unsafeBitCast(f, to: IntVal.self)
        available = sub != nil
    }

    /// Average GPU watts since the previous call
    func watts() -> Double? {
        guard available, let samples, let name, let unit, let intVal,
              let dict = samples(sub, subbed?.takeUnretainedValue(), nil)?.takeRetainedValue() as? [String: Any],
              let chans = dict["IOReportChannels"] as? [CFDictionary] else { return nil }
        for ch in chans where (name(ch)?.takeUnretainedValue() as String?) == "GPU Energy" {
            let u = unit(ch)?.takeUnretainedValue() as String? ?? "nJ"
            let scale: Double = u == "mJ" ? 1e-3 : (u == "uJ" ? 1e-6 : 1e-9)
            let v = Double(intVal(ch, nil)) * scale, now = Date()
            defer { last = (v, now) }
            guard let l = last, now.timeIntervalSince(l.t) > 0.2, v >= l.v else { return nil }
            return (v - l.v) / now.timeIntervalSince(l.t)
        }
        return nil
    }
}

// MARK: - HID temperature sensors (Apple Silicon, no admin needed)

@_silgen_name("IOHIDEventSystemClientCreate") private func hidCreate(_ a: CFAllocator?) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func hidSetMatching(_ c: CFTypeRef, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func hidCopyServices(_ c: CFTypeRef) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") private func hidCopyProperty(_ s: CFTypeRef, _ k: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func hidCopyEvent(_ s: CFTypeRef, _ t: Int64, _ o: Int32, _ x: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue") private func hidFloat(_ e: CFTypeRef, _ f: Int32) -> Double

final class HIDSensors {
    private var client: CFTypeRef?
    private var services: [CFTypeRef] = []
    private var names: [String] = []

    init() {
        guard let c = hidCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        client = c
        _ = hidSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        services = (hidCopyServices(c)?.takeRetainedValue() as? [CFTypeRef]) ?? []
        names = services.map { (hidCopyProperty($0, "Product" as CFString)?.takeRetainedValue() as? String) ?? "Sensor" }
    }

    func read() -> [SensorReading] {
        var out: [SensorReading] = []
        var seen: [String: Int] = [:]
        for (i, s) in services.enumerated() {
            guard let e = hidCopyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
            let v = hidFloat(e, 15 << 16)
            let base = names[i]
            if base.contains("tcal") || v < 0 || v > 150 { continue }   // calibration channels / invalid
            let n = (seen[base] ?? 0) + 1; seen[base] = n
            out.append(SensorReading(name: n > 1 ? "\(base) #\(n)" : base, value: v))
        }
        return out
    }
}

// MARK: - Readers

func perCoreTicks() -> [[UInt32]] {
    var numCPU: natural_t = 0
    var info: processor_info_array_t?
    var cnt: mach_msg_type_number_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &info, &cnt) == KERN_SUCCESS, let info else { return [] }
    var r: [[UInt32]] = []
    for i in 0..<Int(numCPU) {
        let b = Int(CPU_STATE_MAX) * i
        r.append([UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]), UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                  UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]), UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])])
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(cnt) * vm_size_t(MemoryLayout<integer_t>.size))
    return r
}

func sysctlInt(_ name: String) -> Int {
    var v: Int32 = 0; var sz = MemoryLayout<Int32>.size
    sysctlbyname(name, &v, &sz, nil, 0)
    return Int(v)
}

func sysctlStr(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return "" }
    var buf = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buf, &size, nil, 0)
    return String(cString: buf)
}

struct GPUStats { var util = 0.0, render = 0.0, tiler = 0.0, mem = 0.0 }

func readGPU() -> GPUStats? {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    var best: GPUStats?
    var e = IOIteratorNext(it)
    while e != 0 {
        if let ps = IORegistryEntryCreateCFProperty(e, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
            func d(_ k: String) -> Double { (ps[k] as? NSNumber)?.doubleValue ?? 0 }
            let g = GPUStats(util: d("Device Utilization %"), render: d("Renderer Utilization %"), tiler: d("Tiler Utilization %"), mem: d("In use system memory"))
            if best == nil || g.util > best!.util { best = g }
        }
        IOObjectRelease(e)
        e = IOIteratorNext(it)
    }
    return best
}

func readDiskIO() -> (read: Double, write: Double) {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return (0, 0) }
    defer { IOObjectRelease(it) }
    var r = 0.0, w = 0.0
    var e = IOIteratorNext(it)
    while e != 0 {
        if let st = IORegistryEntryCreateCFProperty(e, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
            r += (st["Bytes (Read)"] as? NSNumber)?.doubleValue ?? 0
            w += (st["Bytes (Write)"] as? NSNumber)?.doubleValue ?? 0
        }
        IOObjectRelease(e)
        e = IOIteratorNext(it)
    }
    return (r, w)
}

func readVolumes() -> [Vol] {
    let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap { u in
        guard let v = try? u.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { return nil }
        return Vol(path: u.path, name: v.volumeName ?? u.lastPathComponent, total: Double(total),
                   free: Double(v.volumeAvailableCapacityForImportantUsage ?? 0))
    }
}

func netCounters() -> (rx: UInt64, tx: UInt64, iface: String?) {
    var rx: UInt64 = 0, tx: UInt64 = 0
    var top: (String, UInt64)?
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0, nil) }
    defer { freeifaddrs(ifap) }
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let c = p {
        let name = String(cString: c.pointee.ifa_name)
        if name.hasPrefix("en"), let sa = c.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), let d = c.pointee.ifa_data {
            let nd = d.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(nd.ifi_ibytes); tx += UInt64(nd.ifi_obytes)
            let total = UInt64(nd.ifi_ibytes) + UInt64(nd.ifi_obytes)
            if top == nil || total > top!.1 { top = (name, total) }
        }
        p = c.pointee.ifa_next
    }
    return (rx, tx, top?.0)
}

func localIPAddress() -> String? {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
    defer { freeifaddrs(ifap) }
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let c = p {
        let name = String(cString: c.pointee.ifa_name)
        if name.hasPrefix("en"), let sa = c.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        p = c.pointee.ifa_next
    }
    return nil
}

func readWifi() -> WifiInfo? {
    guard let i = CWWiFiClient.shared().interface(), i.powerOn(), i.rssiValue() != 0 else { return nil }
    let band: String?
    switch i.wlanChannel()?.channelBand {
    case .band2GHz?: band = "2.4 GHz"
    case .band5GHz?: band = "5 GHz"
    case .band6GHz?: band = "6 GHz"
    default: band = nil
    }
    return WifiInfo(rssi: i.rssiValue(), rate: i.transmitRate(), channel: i.wlanChannel()?.channelNumber, band: band)
}

/// ps-based top lists (cpu or memory)
func readTopPS(memory: Bool) -> [Proc] {
    let out = runCmd("/bin/ps", ["-Aceo", memory ? "rss,pid,comm" : "pcpu,pid,comm", memory ? "-m" : "-r"], timeout: 5)
    var res: [Proc] = []
    for line in out.split(separator: "\n").dropFirst() {
        let t = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard t.count == 3, let v = Double(t[0]), let pid = Int(t[1]) else { continue }
        let name = String(t[2]).trimmingCharacters(in: .whitespaces)
        if name == "ps" { continue }
        res.append(Proc(id: pid, name: name, value: memory ? v * 1024 : v))
        if res.count >= 8 { break }
    }
    return res
}

/// Per-process disk I/O deltas (bytes/s) via libproc, same-user processes only
final class DiskProcSampler {
    private var last: [Int32: (r: UInt64, w: UInt64, name: String)] = [:]
    private var lastTime = Date()

    func sample() -> [Proc] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 32)
        let cnt = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        let now = Date(), dt = max(now.timeIntervalSince(lastTime), 0.5)
        var cur: [Int32: (r: UInt64, w: UInt64, name: String)] = [:]
        var res: [Proc] = []
        for pid in pids.prefix(Int(cnt)) where pid > 0 {
            var ru = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard ok == 0 else { continue }
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, 256)
            let name = String(cString: nameBuf)
            cur[pid] = (ru.ri_diskio_bytesread, ru.ri_diskio_byteswritten, name)
            if let p = last[pid] {
                let d = Double((ru.ri_diskio_bytesread &- p.r) &+ (ru.ri_diskio_byteswritten &- p.w)) / dt
                if d > 1024 { res.append(Proc(id: Int(pid), name: name, value: d)) }
            }
        }
        last = cur; lastTime = now
        return res.sorted { $0.value > $1.value }.prefix(8).map { $0 }
    }
}

/// Per-process network deltas (bytes/s) via nettop
final class NetProcSampler {
    private var last: [String: Double] = [:]
    private var lastTime = Date()

    func sample() -> [Proc] {
        let out = runCmd("/usr/bin/nettop", ["-P", "-L", "1", "-J", "bytes_in,bytes_out"], timeout: 8)
        let now = Date(), dt = max(now.timeIntervalSince(lastTime), 0.5)
        var cur: [String: Double] = [:]
        var res: [Proc] = []
        for line in out.split(separator: "\n").dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, let b1 = Double(f[1]), let b2 = Double(f[2]) else { continue }
            let key = f[0]
            cur[key] = b1 + b2
            if let p = last[key], b1 + b2 > p {
                let name = key.split(separator: ".").dropLast().joined(separator: ".")
                res.append(Proc(id: abs(key.hashValue), name: name.isEmpty ? key : name, value: (b1 + b2 - p) / dt))
            }
        }
        last = cur; lastTime = now
        return res.filter { $0.value > 256 }.sorted { $0.value > $1.value }.prefix(8).map { $0 }
    }
}

// MARK: - Formatting

func fmtBytes(_ b: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, b)), countStyle: .memory) }
func fmtFileBytes(_ b: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, b)), countStyle: .file) }
func fmtRate(_ b: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, b)), countStyle: .file) + "/s" }
func fmtRateShort(_ b: Double) -> String {
    let units = ["B", "K", "M", "G"]; var v = max(0, b); var i = 0
    while v >= 1000 && i < 3 { v /= 1000; i += 1 }
    return String(format: v >= 100 || i == 0 ? "%.0f %@/s" : "%.1f %@/s", v, units[i])
}

// MARK: - Store

final class SystemStore: ObservableObject {
    static let shared = SystemStore()
    @Published var tick = 0

    // CPU
    var cpuTotal = 0.0, cpuUser = 0.0, cpuSys = 0.0
    var cores: [Double] = []
    var load: (Double, Double, Double) = (0, 0, 0)
    var cpuHist: [Double] = []
    let coreCount = ProcessInfo.processInfo.processorCount
    let perfCores = sysctlInt("hw.perflevel0.logicalcpu")
    let effCores = sysctlInt("hw.perflevel1.logicalcpu")
    let chip = sysctlStr("machdep.cpu.brand_string")
    // GPU
    var gpu = GPUStats()
    var gpuHist: [Double] = []
    var gpuPower: Double?
    var gpuPowerHist: [Double] = []
    var core: CoreSensors?
    var coreAt = Date.distantPast
    var cpuPowerHist: [Double] = []
    var coreFresh: Bool { core != nil && Date().timeIntervalSince(coreAt) < 6 }
    /// GPU watts: the root sampler when available, otherwise the IOReport counter
    var gpuWatts: Double? { (coreFresh ? core?.gpuW : nil) ?? gpuPower }
    var socHist: [Double] = []
    var uptime = 0.0
    var procCount = 0, threadCount = 0
    var pageIns = 0.0, pageOuts = 0.0, swapIns = 0.0, swapOuts = 0.0
    // RAM
    var ramTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var ramUsed = 0.0, ramApp = 0.0, ramWired = 0.0, ramComp = 0.0, ramFree = 0.0, ramCache = 0.0
    var swapUsed = 0.0, swapTotal = 0.0
    var pressure = 1
    var ramHist: [Double] = []
    // Disk
    var volumes: [Vol] = []
    var diskRead = 0.0, diskWrite = 0.0
    var diskReadHist: [Double] = [], diskWriteHist: [Double] = []
    // Network
    var netDown = 0.0, netUp = 0.0
    var netDownHist: [Double] = [], netUpHist: [Double] = []
    var netTotalDown = 0.0, netTotalUp = 0.0
    var iface: String?
    var localIP: String?
    var publicIP: String?
    var wifi: WifiInfo?
    // Sensors
    var temps: [SensorReading] = []
    var systemPower: Double?
    var dcInPower: Double?
    var fans: [FanReading] = []
    var hasFans = false
    // Processes
    var topCPU: [Proc] = [], topMem: [Proc] = [], topDisk: [Proc] = [], topNet: [Proc] = []

    private var lastCores: [[UInt32]] = []
    private var lastDiskIO: (Double, Double)?
    private var lastNet: (UInt64, UInt64)?
    private var startNet: (UInt64, UInt64)?
    private var lastT = Date()
    private var timer: Timer?
    private var slowTimer: Timer?
    private let hid = HIDSensors()
    private let gpuMeter = GPUPower()
    private let diskProc = DiskProcSampler()
    private let netProc = NetProcSampler()
    private var cancellables = Set<AnyCancellable>()
    private var lastAlert: [String: Date] = [:]
    private var lastIPFetch = Date.distantPast
    private var slowBusy = false

    init() {
        lastCores = perCoreTicks()
        hasFans = (SMC.shared.int("FNum") ?? 0) > 0
        schedule()
        Prefs.shared.$cfg.map(\.interval).removeDuplicates().sink { [weak self] _ in self?.schedule() }.store(in: &cancellables)
        // $open publishes before the value changes, so hop to the next run loop turn before reading it
        Activity.shared.$open.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.schedule() }.store(in: &cancellables)
    }

    /// Only sample what is visible: an enabled menu bar module, an alert that needs it, or any open dropdown
    private func want(_ m: Mod) -> Bool {
        if Activity.shared.open { return true }
        let c = Prefs.shared.cfg
        if c.cfg(m).enabled { return true }
        switch m {
        case .cpu: return c.cpuAlertOn
        case .ram: return c.ramAlertOn
        case .disk: return c.diskAlertOn
        case .sensors: return c.tempAlertOn
        default: return false
        }
    }

    func schedule() {
        timer?.invalidate(); slowTimer?.invalidate(); slowTimer = nil
        let iv = Activity.shared.interval
        let t = Timer(timeInterval: iv, repeats: true) { [weak self] _ in self?.update() }
        t.tolerance = iv * 0.35            // lets macOS coalesce wake-ups with other work
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if Activity.shared.open {
            let st = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.updateSlow() }
            st.tolerance = 1.5
            RunLoop.main.add(st, forMode: .common)
            slowTimer = st
            updateSlow()
        }
        update()
    }

    private func push(_ a: inout [Double], _ v: Double, max n: Int = 300) { a.append(v); if a.count > n { a.removeFirst(a.count - n) } }

    func update() {
        Prof.time("sys.update") { updateBody() }
    }

    private func updateBody() {
        let now = Date(); let dt = max(now.timeIntervalSince(lastT), 0.1); lastT = now
        let cfg = Prefs.shared.cfg

        if want(.cpu) {
            let c = perCoreTicks()
            if c.count == lastCores.count, !c.isEmpty {
                var cs: [Double] = []; var tu = 0.0, ts = 0.0, tt = 0.0
                for i in 0..<c.count {
                    let du = Double(c[i][0] &- lastCores[i][0]), ds = Double(c[i][1] &- lastCores[i][1])
                    let di = Double(c[i][2] &- lastCores[i][2]), dn = Double(c[i][3] &- lastCores[i][3])
                    let t = du + ds + di + dn
                    cs.append(t > 0 ? (du + ds + dn) / t * 100 : 0)
                    tu += du + dn; ts += ds; tt += t
                }
                cores = cs
                if tt > 0 { cpuUser = tu / tt * 100; cpuSys = ts / tt * 100; cpuTotal = cpuUser + cpuSys }
            }
            lastCores = c
            var la = [Double](repeating: 0, count: 3); getloadavg(&la, 3); load = (la[0], la[1], la[2])
            push(&cpuHist, cpuTotal)
            if Activity.shared.open { uptime = ProcessInfo.processInfo.systemUptime; procCount = Int(proc_listallpids(nil, 0)) }
        } else { lastCores = [] }

        if want(.gpu) {
            if let g = readGPU() { gpu = g }
            push(&gpuHist, gpu.util)
            if let w = gpuMeter.watts() { gpuPower = w; push(&gpuPowerHist, w) }
        }

        if want(.ram) {
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
            var st = vm_statistics64()
            let r = withUnsafeMutablePointer(to: &st) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
            }
            if r == KERN_SUCCESS {
                let ps = Double(vm_kernel_page_size)
                ramApp = Double(st.internal_page_count &- st.purgeable_count) * ps
                ramWired = Double(st.wire_count) * ps
                ramComp = Double(st.compressor_page_count) * ps
                ramFree = Double(st.free_count) * ps
                ramCache = Double(st.external_page_count &+ st.purgeable_count) * ps
                ramUsed = ramApp + ramWired + ramComp
                pageIns = Double(st.pageins); pageOuts = Double(st.pageouts); swapIns = Double(st.swapins); swapOuts = Double(st.swapouts)
            }
            if Activity.shared.open {
                var sw = xsw_usage(); var sz = MemoryLayout<xsw_usage>.size
                if sysctlbyname("vm.swapusage", &sw, &sz, nil, 0) == 0 { swapUsed = Double(sw.xsu_used); swapTotal = Double(sw.xsu_total) }
                pressure = sysctlInt("kern.memorystatus_vm_pressure_level")
            }
            push(&ramHist, ramTotal > 0 ? ramUsed / ramTotal * 100 : 0)
        }

        if want(.disk) {
            if Activity.shared.open || volumes.isEmpty || Int(now.timeIntervalSince1970) % 30 < Int(Activity.shared.interval) + 1 { volumes = readVolumes() }
            let io = readDiskIO()
            if let l = lastDiskIO { diskRead = max(0, (io.read - l.0) / dt); diskWrite = max(0, (io.write - l.1) / dt) }
            lastDiskIO = io
            push(&diskReadHist, diskRead); push(&diskWriteHist, diskWrite)
        } else { lastDiskIO = nil }

        if want(.network) {
            let n = netCounters()
            if let l = lastNet { netDown = Double(n.rx &- l.0) / dt; netUp = Double(n.tx &- l.1) / dt }
            if startNet == nil { startNet = (n.rx, n.tx) }
            netTotalDown = Double(n.rx &- startNet!.0); netTotalUp = Double(n.tx &- startNet!.1)
            lastNet = (n.rx, n.tx); iface = n.iface
            push(&netDownHist, netDown); push(&netUpHist, netUp)
        } else { lastNet = nil }

        if want(.sensors) || want(.fans) {
            temps = hid.read()
            if let t = socTemp { push(&socHist, t) }
            if Activity.shared.open { systemPower = SMC.shared.float("PSTR"); dcInPower = SMC.shared.float("PDTR") }
        }
        if hasFans && want(.fans) {
            let nf = SMC.shared.int("FNum") ?? 0
            fans = (0..<nf).compactMap { i in
                guard let a = SMC.shared.float("F\(i)Ac") else { return nil }
                return FanReading(id: i, rpm: a, min: SMC.shared.float("F\(i)Mn") ?? 0, max: SMC.shared.float("F\(i)Mx") ?? 0)
            }
        }

        if Activity.shared.open && Helper.installed {
            Helper.touch()                                  // keeps the root sampler awake while we are looking
            if let (c, at) = Helper.read(), at != coreAt { core = c; coreAt = at; if let w = c.cpuW { push(&cpuPowerHist, w) } }
        }
        _ = cfg
        Prof.time("checkAlerts") { checkAlerts() }
        tick &+= 1
    }

    /// Heavier lookups: only while a dropdown is open
    func updateSlow() {
        guard Activity.shared.open else { return }
        let cfg = Prefs.shared.cfg
        localIP = localIPAddress()
        wifi = readWifi()
        guard !slowBusy else { return }
        slowBusy = true
        DispatchQueue.global(qos: .utility).async { [self] in
            let cpu = readTopPS(memory: false), mem = readTopPS(memory: true)
            DispatchQueue.main.async { self.topCPU = cpu; self.topMem = mem }
            let disk = diskProc.sample()
            DispatchQueue.main.async { self.topDisk = disk }
            let net = netProc.sample()           // nettop is the slow one
            DispatchQueue.main.async { self.topNet = net; self.slowBusy = false }
        }
        if cfg.publicIP, Date().timeIntervalSince(lastIPFetch) > 600 { fetchPublicIP() }
        if !cfg.publicIP { publicIP = nil }
    }

    private func fetchPublicIP() {
        lastIPFetch = Date()
        guard let u = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: u) { d, _, _ in
            let s = d.flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async { self.publicIP = s }
        }.resume()
    }

    // SoC die temperature summary
    var dieTemps: [Double] { temps.filter { $0.name.contains("tdie") }.map(\.value) }
    var socTemp: Double? { dieTemps.isEmpty ? nil : dieTemps.reduce(0, +) / Double(dieTemps.count) }
    var socMax: Double? { dieTemps.max() }
    var nandTemp: Double? { let t = temps.filter { $0.name.contains("NAND") }.map(\.value); return t.isEmpty ? nil : t.max() }
    var battTemp: Double? { let t = temps.filter { $0.name.contains("gas gauge") }.map(\.value); return t.isEmpty ? nil : t.reduce(0, +) / Double(t.count) }

    private func alert(_ key: String, _ title: String, _ body: String) {
        if let t = lastAlert[key], Date().timeIntervalSince(t) < 600 { return }
        lastAlert[key] = Date()
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func checkAlerts() {
        let c = Prefs.shared.cfg
        if c.cpuAlertOn, cpuTotal >= Double(c.cpuAlertAt) { alert("cpu", "CPU at \(Int(cpuTotal))%", "Usage is above your \(c.cpuAlertAt)% threshold.") }
        if c.ramAlertOn, ramTotal > 0, ramUsed / ramTotal * 100 >= Double(c.ramAlertAt) { alert("ram", "Memory at \(Int(ramUsed / ramTotal * 100))%", "Usage is above your \(c.ramAlertAt)% threshold.") }
        if c.diskAlertOn, let v = volumes.first(where: { $0.path == "/" }) ?? volumes.first, v.free / 1e9 < Double(c.diskAlertGB) {
            alert("disk", "Low disk space", "Only \(fmtFileBytes(v.free)) free on \(v.name).")
        }
        if c.tempAlertOn, let t = socMax, t >= Double(c.tempAlertAt) { alert("temp", "SoC at \(Int(t))°C", "Above your \(c.tempAlertAt)°C threshold.") }
    }
}
