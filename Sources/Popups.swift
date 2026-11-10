import SwiftUI
import Charts

// MARK: - CPU

struct CPUContent: View {
    @ObservedObject var sys: SystemStore
    var body: some View { VStack(spacing: 10) { SectionList(mod: .cpu) { AnyView(section($0)) } } }
    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header":
            ModHeader(big: String(format: "%.0f", sys.cpuTotal), caption: "CPU Usage", icon: "cpu",
                      right: [("LOAD 1m", String(format: "%.2f", sys.load.0))], frac: sys.cpuTotal / 100, color: Mod.cpu.color)
        case "cpu.hist":
            Collapsible(id: "cpu.hist", title: "Usage History", icon: "chart.xyaxis.line", color: Mod.cpu.color) {
                HistChart(values: sys.cpuHist, color: Mod.cpu.color, maxY: 100)
                LineRow(label: "User", value: String(format: "%.1f%%", sys.cpuUser), color: Mod.cpu.color)
                LineRow(label: "System", value: String(format: "%.1f%%", sys.cpuSys), color: .red)
                LineRow(label: "Idle", value: String(format: "%.1f%%", max(0, 100 - sys.cpuTotal)))
            }
        case "cpu.power":
            Collapsible(id: "cpu.power", title: "Power & Frequency", icon: "bolt.fill", color: .yellow) {
                if sys.coreFresh, let c = sys.core {
                    if let w = c.cpuW { LineRow(label: "CPU power", value: String(format: "%.2f W", w), color: .yellow) }
                    if let w = c.gpuW { LineRow(label: "GPU power", value: String(format: "%.2f W", w), color: .purple) }
                    if let w = c.aneW { LineRow(label: "Neural Engine", value: String(format: "%.2f W", w), color: .pink) }
                    if let w = c.packageW { LineRow(label: "Package total", value: String(format: "%.2f W", w), color: .orange) }
                    ForEach(Array(c.clusters.enumerated()), id: \.offset) { _, cl in LineRow(label: cl.name + " frequency", value: String(format: "%.0f MHz", cl.mhz), color: .cyan) }
                    if let t = c.thermal { LineRow(label: "Thermal pressure", value: t.capitalized, color: t.lowercased() == "nominal" ? jgreen : .orange) }
                    HistChart(values: sys.cpuPowerHist, color: .yellow, height: 60)
                } else if Helper.installed {
                    Text("Waiting for the first sample…").font(.system(size: 13)).foregroundStyle(.secondary)
                } else { CoreSensorsHint() }
            }
        case "cpu.cores":
            Collapsible(id: "cpu.cores", title: "Cores", icon: "square.grid.3x3.fill", color: .indigo) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(sys.cores.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12)).frame(height: 56)
                                RoundedRectangle(cornerRadius: 3).fill(loadColor(v)).frame(height: max(2, 56 * v / 100))
                            }
                            Text("\(i + 1)").font(mono(9, .regular)).foregroundStyle(.secondary)
                        }
                    }
                }
                if sys.perfCores > 0 { LineRow(label: "Performance cores", value: "\(sys.perfCores)") }
                if sys.effCores > 0 { LineRow(label: "Efficiency cores", value: "\(sys.effCores)") }
            }
        case "cpu.load":
            Collapsible(id: "cpu.load", title: "Load Average", icon: "gauge.with.dots.needle.50percent", color: .yellow) {
                LineRow(label: "1 minute", value: String(format: "%.2f", sys.load.0), color: .yellow)
                LineRow(label: "5 minutes", value: String(format: "%.2f", sys.load.1))
                LineRow(label: "15 minutes", value: String(format: "%.2f", sys.load.2))
            }
        case "cpu.top":
            Collapsible(id: "cpu.top", title: "Top Processes", icon: "list.number", color: .orange) {
                ProcRows(procs: sys.topCPU, color: .orange) { String(format: "%.1f%%", $0) }
            }
        case "cpu.info":
            Collapsible(id: "cpu.info", title: "Processor", icon: "info.circle.fill", color: .cyan) {
                LineRow(label: "Chip", value: sys.chip)
                LineRow(label: "Logical cores", value: "\(sys.coreCount)")
                LineRow(label: "Model", value: sysctlStr("hw.model"))
                LineRow(label: "Uptime", value: fmtUptimeLong(sys.uptime))
                LineRow(label: "Processes", value: "\(sys.procCount)")
                if let t = sys.socTemp { LineRow(label: "SoC temperature", value: String(format: "%.1f °C", t), color: tempColor(t)) }
            }
        default: EmptyView()
        }
    }
}

// MARK: - GPU

struct GPUContent: View {
    @ObservedObject var sys: SystemStore
    var body: some View { VStack(spacing: 10) { SectionList(mod: .gpu) { AnyView(section($0)) } } }
    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header":
            ModHeader(big: String(format: "%.0f", sys.gpu.util), caption: "GPU Utilization", icon: "display",
                      right: [("MEMORY", fmtBytes(sys.gpu.mem))], frac: sys.gpu.util / 100, color: Mod.gpu.color)
        case "gpu.hist":
            Collapsible(id: "gpu.hist", title: "Usage History", icon: "chart.xyaxis.line", color: Mod.gpu.color) {
                HistChart(values: sys.gpuHist, color: Mod.gpu.color, maxY: 100)
            }
        case "gpu.det":
            Collapsible(id: "gpu.det", title: "Details", icon: "info.circle.fill", color: .cyan) {
                LineRow(label: "Device utilization", value: String(format: "%.0f%%", sys.gpu.util), color: Mod.gpu.color)
                LineRow(label: "Renderer", value: String(format: "%.0f%%", sys.gpu.render))
                LineRow(label: "Tiler", value: String(format: "%.0f%%", sys.gpu.tiler))
                LineRow(label: "System memory in use", value: fmtBytes(sys.gpu.mem))
                LineRow(label: "GPU power", value: sys.gpuWatts.map { String(format: "%.2f W", $0) } ?? "—", color: .yellow)
                if sys.coreFresh, let f = sys.core?.gpuMHz { LineRow(label: "GPU frequency", value: String(format: "%.0f MHz", f), color: .cyan) }
                LineRow(label: "Chip", value: sys.chip)
            }
        default: EmptyView()
        }
    }
}

// MARK: - Memory

struct RAMContent: View {
    @ObservedObject var sys: SystemStore
    var pct: Double { sys.ramTotal > 0 ? sys.ramUsed / sys.ramTotal * 100 : 0 }
    var pressureText: (String, Color) {
        switch sys.pressure { case 2: return ("Warning", .yellow); case 4: return ("Critical", .red); default: return ("Normal", jgreen) }
    }
    var body: some View { VStack(spacing: 10) { SectionList(mod: .ram) { AnyView(section($0)) } } }
    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header":
            ModHeader(big: String(format: "%.0f", pct), caption: "\(fmtBytes(sys.ramUsed)) of \(fmtBytes(sys.ramTotal))", icon: "memorychip",
                      right: [("PRESSURE", pressureText.0)], frac: pct / 100, color: Mod.ram.color)
        case "ram.hist":
            Collapsible(id: "ram.hist", title: "Usage History", icon: "chart.xyaxis.line", color: Mod.ram.color) {
                HistChart(values: sys.ramHist, color: Mod.ram.color, maxY: 100)
            }
        case "ram.break":
            Collapsible(id: "ram.break", title: "Breakdown", icon: "chart.pie.fill", color: .purple) {
                LineRow(label: "App memory", value: fmtBytes(sys.ramApp), color: Mod.ram.color)
                LineRow(label: "Wired", value: fmtBytes(sys.ramWired), color: .red)
                LineRow(label: "Compressed", value: fmtBytes(sys.ramComp), color: .yellow)
                LineRow(label: "Cached files", value: fmtBytes(sys.ramCache), color: .cyan)
                LineRow(label: "Free", value: fmtBytes(sys.ramFree), color: jgreen)
                Divide()
                LineRow(label: "Swap used", value: "\(fmtBytes(sys.swapUsed)) of \(fmtBytes(sys.swapTotal))")
                LineRow(label: "Memory pressure", value: pressureText.0, color: pressureText.1)
            }
        case "ram.top":
            Collapsible(id: "ram.top", title: "Top Processes", icon: "list.number", color: .orange) {
                ProcRows(procs: sys.topMem, color: Mod.ram.color) { fmtBytes($0) }
            }
        default: EmptyView()
        }
    }
}

// MARK: - Disk

struct DiskContent: View {
    @ObservedObject var sys: SystemStore
    var boot: Vol? { sys.volumes.first(where: { $0.path == "/" }) ?? sys.volumes.first }
    var used: Double { boot.map { ($0.total - $0.free) / $0.total * 100 } ?? 0 }
    var body: some View { VStack(spacing: 10) { SectionList(mod: .disk) { AnyView(section($0)) } } }
    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header":
            ModHeader(big: String(format: "%.0f", used), caption: boot.map { "\($0.name)" } ?? "Disk", icon: "internaldrive",
                      right: [("FREE", boot.map { fmtFileBytes($0.free) } ?? "—")], frac: used / 100, color: Mod.disk.color)
        case "disk.vols":
            Collapsible(id: "disk.vols", title: "Volumes", icon: "externaldrive.fill", color: Mod.disk.color) {
                ForEach(sys.volumes) { v in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(v.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Text("\(fmtFileBytes(v.free)) free of \(fmtFileBytes(v.total))").font(mono(11, .regular)).foregroundStyle(.secondary)
                        }
                        FillBar(frac: (v.total - v.free) / v.total, color: loadColor((v.total - v.free) / v.total * 100), height: 6)
                    }
                }
            }
        case "disk.act":
            Collapsible(id: "disk.act", title: "Activity", icon: "arrow.up.arrow.down", color: .orange) {
                DualChart(a: sys.diskReadHist, b: sys.diskWriteHist, ca: .cyan, cb: .orange)
                LineRow(label: "Read", value: fmtRate(sys.diskRead), color: .cyan)
                LineRow(label: "Write", value: fmtRate(sys.diskWrite), color: .orange)
            }
        case "disk.top":
            Collapsible(id: "disk.top", title: "Top Processes (I/O)", icon: "list.number", color: .orange) {
                ProcRows(procs: sys.topDisk, color: Mod.disk.color) { fmtRate($0) }
            }
        default: EmptyView()
        }
    }
}

// MARK: - Network

struct NetContent: View {
    @ObservedObject var sys: SystemStore
    @ObservedObject var prefs = Prefs.shared
    var body: some View { VStack(spacing: 10) { SectionList(mod: .network) { AnyView(section($0)) } } }
    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header":
            CardBox {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("DOWNLOAD", systemImage: "arrow.down.circle.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.mint)
                        Text(fmtRate(sys.netDown)).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.mint).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("UPLOAD", systemImage: "arrow.up.circle.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.orange)
                        Text(fmtRate(sys.netUp)).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.orange).monospacedDigit()
                    }
                }.padding(16)
            }
        case "net.speed":
            Collapsible(id: "net.speed", title: "Speed History", icon: "chart.xyaxis.line", color: .mint) {
                DualChart(a: sys.netDownHist, b: sys.netUpHist, ca: .mint, cb: .orange)
                LineRow(label: "Downloaded since launch", value: fmtFileBytes(sys.netTotalDown), color: .mint)
                LineRow(label: "Uploaded since launch", value: fmtFileBytes(sys.netTotalUp), color: .orange)
            }
        case "net.conn":
            Collapsible(id: "net.conn", title: "Connection", icon: "network", color: .cyan) {
                LineRow(label: "Interface", value: sys.iface ?? "—")
                LineRow(label: "Local IP", value: sys.localIP ?? "—")
                if prefs.cfg.publicIP { LineRow(label: "Public IP", value: sys.publicIP ?? "Fetching…") }
                else { Text("Public IP is off. Enable it in Settings → General (it asks api.ipify.org).").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        case "net.wifi":
            if let w = sys.wifi {
                Collapsible(id: "net.wifi", title: "Wi-Fi", icon: "wifi", color: .blue) {
                    LineRow(label: "Signal", value: "\(w.rssi) dBm", color: w.rssi > -60 ? jgreen : (w.rssi > -75 ? .yellow : .red))
                    LineRow(label: "Link speed", value: String(format: "%.0f Mbps", w.rate))
                    if let c = w.channel { LineRow(label: "Channel", value: "\(c)") }
                    if let b = w.band { LineRow(label: "Band", value: b) }
                }
            }
        case "net.top":
            Collapsible(id: "net.top", title: "Top Processes", icon: "list.number", color: .orange) {
                ProcRows(procs: sys.topNet, color: .mint) { fmtRate($0) }
            }
        default: EmptyView()
        }
    }
}

// MARK: - Sensors

struct SensorsContent: View {
    @ObservedObject var sys: SystemStore
    var body: some View { VStack(spacing: 10) { SectionList(mod: .sensors) { AnyView(section($0)) } } }
    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header":
            ModHeader(big: sys.socTemp.map { String(format: "%.0f", $0) } ?? "—", unit: "°C", caption: "SoC Temperature", icon: "thermometer.medium",
                      right: sys.socMax.map { [("HOTTEST DIE", String(format: "%.0f°C", $0))] } ?? [],
                      frac: (sys.socTemp ?? 0) / 110, color: sys.socTemp.map(tempColor) ?? .gray)
        case "sens.temp":
            Collapsible(id: "sens.temp", title: "Temperatures", icon: "thermometer.medium", color: .red) {
                if let t = sys.socTemp { LineRow(label: "SoC (die average)", value: String(format: "%.1f °C", t), color: tempColor(t)) }
                if let t = sys.socMax { LineRow(label: "SoC (hottest die)", value: String(format: "%.1f °C", t), color: tempColor(t)) }
                if let t = sys.nandTemp { LineRow(label: "Storage (NAND)", value: String(format: "%.1f °C", t), color: tempColor(t)) }
                if let t = sys.battTemp { LineRow(label: "Battery", value: String(format: "%.1f °C", t), color: tempColor(t)) }
                if sys.temps.isEmpty { Text("Reading sensors…").font(.system(size: 13)).foregroundStyle(.secondary) }
            }
        case "sens.pow":
            if sys.systemPower != nil || sys.dcInPower != nil {
                Collapsible(id: "sens.pow", title: "Power", icon: "bolt.fill", color: .yellow) {
                    if let p = sys.systemPower { LineRow(label: "System total", value: String(format: "%.1f W", p), color: .yellow) }
                    if let p = sys.dcInPower { LineRow(label: "DC input", value: String(format: "%.1f W", p), color: .orange) }
                    if let p = sys.gpuPower { LineRow(label: "GPU", value: String(format: "%.2f W", p), color: .purple) }
                }
            }
        case "sens.all":
            Collapsible(id: "sens.all", title: "All Sensors (\(sys.temps.count))", icon: "list.bullet", color: .gray) {
                ForEach(sys.temps) { s in LineRow(label: s.name, value: String(format: "%.1f °C", s.value), color: tempColor(s.value)) }
            }
        default: EmptyView()
        }
    }
}

// MARK: - Fans

struct FansContent: View {
    @ObservedObject var sys: SystemStore
    var body: some View {
        VStack(spacing: 10) {
            if sys.fans.isEmpty {
                CardBox {
                    VStack(spacing: 8) {
                        Image(systemName: "fan").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("No fans on this Mac").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text("Fanless Macs cool passively, so there is no fan speed to report.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(20)
                }
            } else {
                ForEach(sys.fans) { f in
                    Collapsible(id: "fan.\(f.id)", title: "Fan \(f.id + 1)", icon: "fan.fill", color: .teal) {
                        LineRow(label: "Speed", value: String(format: "%.0f rpm", f.rpm), color: .teal)
                        if f.max > f.min { FillBar(frac: (f.rpm - f.min) / (f.max - f.min), color: .teal, height: 6) }
                        LineRow(label: "Min / Max", value: String(format: "%.0f / %.0f rpm", f.min, f.max))
                    }
                }
            }
        }
    }
}

// MARK: - Bluetooth

struct BluetoothContent: View {
    @ObservedObject var batt: Monitor
    var body: some View { VStack(spacing: 10) { SectionList(mod: .bluetooth) { AnyView(section($0)) } } }
    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header":
            ModHeader(big: "\(batt.devices.count)", unit: "", caption: "Connected Devices", icon: "airpodspro", color: Mod.bluetooth.color)
        case "bt.dev":
            Collapsible(id: "bt.dev", title: "Devices", icon: "dot.radiowaves.left.and.right", color: Mod.bluetooth.color) {
                if batt.devices.isEmpty { Text("No Bluetooth devices connected.").font(.system(size: 13)).foregroundStyle(.secondary) }
                ForEach(batt.devices) { d in DeviceRow(d: d) }
            }
        default: EmptyView()
        }
    }
}

struct DeviceRow: View {
    let d: Device
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "iphone").foregroundStyle(.white).frame(width: 20)
                Text(d.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                if d.levels.count == 1 { Text("\(d.levels[0].1)%").font(mono(13, .bold)).foregroundStyle(jgreen) }
                else if d.levels.isEmpty { Text("No battery info").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            if d.levels.count == 1 { FillBar(frac: Double(d.levels[0].1) / 100, color: jgreen, height: 4) }
            else {
                ForEach(d.levels, id: \.0) { l in
                    HStack(spacing: 8) {
                        Text(l.0).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                        FillBar(frac: Double(l.1) / 100, color: jgreen, height: 4)
                        Text("\(l.1)%").font(mono(11, .bold)).foregroundStyle(jgreen)
                    }
                }
            }
        }
    }
}

// MARK: - Clock

struct ClockContent: View {
    @ObservedObject var sys: SystemStore
    @ObservedObject var prefs = Prefs.shared
    func fmt(_ id: String, _ pattern: String) -> String {
        let f = DateFormatter(); f.dateFormat = pattern
        if let tz = TimeZone(identifier: id) { f.timeZone = tz }
        return f.string(from: Date())
    }
    var body: some View {
        let c = prefs.cfg
        let tp = c.clock24 ? (c.clockSeconds ? "HH:mm:ss" : "HH:mm") : (c.clockSeconds ? "h:mm:ss a" : "h:mm a")
        VStack(spacing: 10) { SectionList(mod: .clock) { id in AnyView(section(id, c, tp)) } }
    }
    @ViewBuilder func section(_ id: String, _ c: Config, _ tp: String) -> some View {
        switch id {
        case "header":
            if let first = c.timeZones.first {
                ModHeader(big: fmt(first, c.clock24 ? "HH:mm" : "h:mm"), unit: c.clock24 ? "" : fmt(first, "a"),
                          caption: fmt(first, "EEEE, MMM d"), icon: "clock", color: Mod.clock.color)
            }
        case "clock.zones":
            Collapsible(id: "clock.zones", title: "Time Zones", icon: "globe", color: Mod.clock.color) {
                ForEach(c.timeZones, id: \.self) { id in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(id.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? id)
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Text(fmt(id, "EEE, MMM d") + " · " + fmt(id, "zzz")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(fmt(id, tp)).font(mono(16, .bold)).foregroundStyle(Mod.clock.color)
                    }
                }
            }
        default: EmptyView()
        }
    }
}
