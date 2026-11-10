import SwiftUI
import Charts

// MARK: - Navigation

enum Page: String, CaseIterable, Identifiable {
    case overview, battery, cpu, gpu, memory, disk, network, sensors
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"; case .battery: return "Battery"; case .cpu: return "CPU"; case .gpu: return "GPU"
        case .memory: return "Memory"; case .disk: return "Disk"; case .network: return "Network"; case .sensors: return "Sensors"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"; case .battery: return "battery.100percent"; case .cpu: return "cpu"; case .gpu: return "display"
        case .memory: return "memorychip"; case .disk: return "internaldrive"; case .network: return "network"; case .sensors: return "thermometer.medium"
        }
    }
    var color: Color {
        switch self {
        case .overview: return .white; case .battery: return jgreen; case .cpu: return Mod.cpu.color; case .gpu: return Mod.gpu.color
        case .memory: return Mod.ram.color; case .disk: return Mod.disk.color; case .network: return Mod.network.color; case .sensors: return Mod.sensors.color
        }
    }
    static func forMod(_ m: Mod) -> Page {
        switch m {
        case .battery, .bluetooth: return .battery; case .cpu: return .cpu; case .gpu: return .gpu; case .ram: return .memory
        case .disk: return .disk; case .network: return .network; case .sensors, .fans: return .sensors; case .clock: return .overview
        }
    }
}

final class NavModel: ObservableObject {
    static let shared = NavModel()
    @Published var page: Page = .overview
}

// MARK: - Building blocks

struct Panel<C: View>: View {
    let title: String, icon: String, color: Color
    var trailing: String? = nil
    @ViewBuilder let content: C
    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                content
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Big: View {
    let label: String, value: String
    var unit = ""
    var color: Color = .white
    var caption: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(color).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(color.opacity(0.85)) }
            }
            if let caption { Text(caption).font(.system(size: 11)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Series: Identifiable {
    let id = UUID()
    let name: String
    let values: [Double]
    let color: Color
}

struct BigChart: View {
    let series: [Series]
    var unit = ""
    var height: CGFloat = 170
    var minY: Double? = nil
    var maxY: Double? = nil
    var area = true
    var body: some View {
        let all = series.flatMap(\.values)
        let lo = minY ?? min(0, all.min() ?? 0)
        let hi = maxY ?? max((all.max() ?? 1) * 1.12, lo + 1)
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(series) { s in
                    ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                        if area && series.count == 1 {
                            AreaMark(x: .value("t", i), yStart: .value("base", lo), yEnd: .value("v", v))
                                .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.45), s.color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                        }
                        LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", s.name))
                            .foregroundStyle(s.color).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.monotone)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: abs(d) >= 100 ? "%.0f" : "%.1f", d) + unit).font(.system(size: 10)).foregroundStyle(.secondary) } }
                }
            }
            .chartYScale(domain: lo...hi)
            .frame(height: height)
            if series.count > 1 || !(series.first?.name.isEmpty ?? true) {
                HStack(spacing: 14) {
                    ForEach(series) { s in
                        HStack(spacing: 5) { Circle().fill(s.color).frame(width: 7, height: 7); Text(s.name).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text("last \(series.map { $0.values.count }.max() ?? 0) readings").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

func minAvgMax(_ v: [Double], _ fmt: String = "%.1f") -> String {
    guard !v.isEmpty else { return "—" }
    return "min " + String(format: fmt, v.min()!) + "  ·  avg " + String(format: fmt, v.reduce(0, +) / Double(v.count)) + "  ·  max " + String(format: fmt, v.max()!)
}

struct Grid2<A: View, B: View>: View {
    let a: A
    let b: B
    var body: some View { HStack(alignment: .top, spacing: 14) { a.frame(maxWidth: .infinity); b.frame(maxWidth: .infinity) } }
}

struct KV: View {
    let k: String, v: String
    var color: Color = .white
    var body: some View {
        HStack { Text(k).font(.system(size: 13)).foregroundStyle(.secondary); Spacer(); Text(v).font(mono(13, .bold)).foregroundStyle(color) }
    }
}

// MARK: - Dashboard root

struct DashboardView: View {
    @ObservedObject var sys: SystemStore
    @ObservedObject var batt: Monitor
    @ObservedObject var nav = NavModel.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 214)
            Rectangle().fill(jline).frame(width: 1)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: nav.page.icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(nav.page.color)
                        Text(nav.page.title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Text("Live · updates every second").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    pageBody
                }.padding(24)
            }
        }
        .background(jbg)
        .environment(\.colorScheme, .dark)
    }

    func summary(_ p: Page) -> String {
        switch p {
        case .overview: return ""
        case .battery: return "\(batt.info.percent)%  \(String(format: "%.1f", abs(batt.info.batteryPower))) W"
        case .cpu: return String(format: "%.0f%%", sys.cpuTotal)
        case .gpu: return String(format: "%.0f%%", sys.gpu.util)
        case .memory: return sys.ramTotal > 0 ? String(format: "%.0f%%", sys.ramUsed / sys.ramTotal * 100) : ""
        case .disk: return (sys.volumes.first(where: { $0.path == "/" }) ?? sys.volumes.first).map { fmtFileBytes($0.free) + " free" } ?? ""
        case .network: return "↓ " + fmtRateShort(sys.netDown)
        case .sensors: return sys.socTemp.map { String(format: "%.0f°C", $0) } ?? ""
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.batteryblock.fill").font(.system(size: 20)).foregroundStyle(jgreen)
                Text("Dewdrop").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }.padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 14)
            ForEach(Page.allCases) { p in
                Button { nav.page = p } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.color).frame(width: 20)
                        Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text(summary(p)).font(mono(10, .regular)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(nav.page == p ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 8)
            }
            Spacer()
            Button { openSettingsWindow() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill").foregroundStyle(.secondary).frame(width: 20)
                    Text("Settings…").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 8).padding(.bottom, 14)
        }
        .background(Color.black.opacity(0.35))
    }

    var pageBody: some View { PageContent(page: nav.page, sys: sys, batt: batt) }
}

struct PageContent: View {
    let page: Page
    @ObservedObject var sys: SystemStore
    @ObservedObject var batt: Monitor
    var body: some View {
        switch page {
        case .overview: OverviewPage(sys: sys, batt: batt)
        case .battery: BatteryPage(batt: batt)
        case .cpu: CPUPage(sys: sys)
        case .gpu: GPUPage(sys: sys)
        case .memory: MemoryPage(sys: sys)
        case .disk: DiskPage(sys: sys)
        case .network: NetworkPage(sys: sys)
        case .sensors: SensorsPage(sys: sys)
        }
    }
}

// MARK: - Overview

struct OverviewPage: View {
    @ObservedObject var sys: SystemStore
    @ObservedObject var batt: Monitor
    var i: BatteryInfo { batt.info }

    func tile(_ p: Page, _ big: String, _ unit: String, _ caption: String, _ hist: [Double], _ maxY: Double?) -> some View {
        Button { NavModel.shared.page = p } label: {
            CardBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: p.icon).foregroundStyle(p.color)
                        Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Big(label: caption, value: big, unit: unit, color: p.color)
                    if !hist.isEmpty { HistChart(values: hist, color: p.color, maxY: maxY, height: 54) }
                }.padding(14)
            }
        }.buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "Power right now", icon: "bolt.fill", color: .yellow, trailing: i.liveGauge ? "live battery gauge" : "") {
                HStack(alignment: .top) {
                    Big(label: i.holdingAtLimit ? "System draw" : (i.batteryPower >= 0 ? "Charging" : "Battery draw"), value: String(format: "%.2f", i.displayWatts), unit: "W", color: i.holdingAtLimit ? .cyan : (i.batteryPower >= 0 ? jgreen : .orange))
                    if i.pluggedIn { Big(label: "From wall", value: String(format: "%.1f", i.adapterIn), unit: "W", color: .yellow) }
                    Big(label: "System", value: String(format: "%.1f", i.pluggedIn ? i.systemLoad : abs(i.batteryPower)), unit: "W", color: .cyan)
                    Big(label: "Battery", value: "\(i.percent)", unit: "%", color: jgreen)
                }
                if i.pluggedIn {
                    BigChart(series: [Series(name: "Battery", values: batt.live.map(\.battery), color: .orange),
                                      Series(name: "System", values: batt.live.map(\.system), color: .cyan),
                                      Series(name: "Wall", values: batt.live.map(\.wall), color: .yellow)], unit: " W", height: 150)
                } else {
                    BigChart(series: [Series(name: "Power draw", values: batt.live.map { abs($0.battery) }, color: .orange)], unit: " W", height: 150, minY: 0)
                }
            }
            HStack(spacing: 14) {
                tile(.cpu, String(format: "%.0f", sys.cpuTotal), "%", "Usage", sys.cpuHist, 100)
                tile(.gpu, String(format: "%.0f", sys.gpu.util), "%", "Utilization", sys.gpuHist, 100)
            }
            HStack(spacing: 14) {
                tile(.memory, sys.ramTotal > 0 ? String(format: "%.0f", sys.ramUsed / sys.ramTotal * 100) : "—", "%", "\(fmtBytes(sys.ramUsed)) of \(fmtBytes(sys.ramTotal))", sys.ramHist, 100)
                tile(.network, fmtRateShort(sys.netDown), "", "Download · ↑ \(fmtRateShort(sys.netUp))", sys.netDownHist, nil)
            }
            HStack(spacing: 14) {
                tile(.disk, (sys.volumes.first(where: { $0.path == "/" }) ?? sys.volumes.first).map { fmtFileBytes($0.free) } ?? "—", "", "Free", [], nil)
                tile(.sensors, sys.socTemp.map { String(format: "%.0f", $0) } ?? "—", "°C", "SoC temperature", sys.socHist, nil)
            }
        }
    }
}

// MARK: - Battery

struct BatteryPage: View {
    @ObservedObject var batt: Monitor
    @AppStorage("sessFilter") var sessFilter = 0
    var i: BatteryInfo { batt.info }
    var live: [LiveSample] { batt.live }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                CardBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(i.percent)").font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(jgreen).monospacedDigit()
                            Text("%").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(jgreen.opacity(0.85))
                        }
                        Text(i.isCharging ? "Charging" : (i.pluggedIn ? "Plugged in" : "On battery")).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        FillBar(frac: Double(i.percent) / 100, color: jgreen, height: 8, ticks: true)
                        Text((i.isCharging ? "Until full  " : "Time left  ") + ((i.pluggedIn && !i.isCharging) ? "—" : fmtTime(i.minutesRemaining))).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(18)
                }.frame(maxWidth: 330)
                Panel(title: "Live readings", icon: "waveform.path.ecg", color: .orange, trailing: i.liveGauge ? "SMC battery gauge · 1 Hz" : "slow system registry") {
                    HStack(alignment: .top) {
                        Big(label: i.holdingAtLimit ? "System draw" : (i.batteryPower >= 0 ? "Charge rate" : "Power draw"), value: String(format: "%.2f", i.displayWatts), unit: "W", color: i.holdingAtLimit ? .cyan : (i.batteryPower >= 0 ? jgreen : .orange))
                        Big(label: "Voltage", value: String(format: "%.3f", i.voltage), unit: "V", color: .yellow)
                    }
                    HStack(alignment: .top) {
                        Big(label: i.amperage >= 0 ? "Current in" : "Current out", value: String(format: "%.0f", abs(i.amperage) * 1000), unit: "mA", color: .cyan)
                        if let t = i.temperature { Big(label: "Temperature", value: String(format: "%.1f", t), unit: "°C", color: tempColor(t)) }
                    }
                }
            }
            Panel(title: "Power over time", icon: "chart.xyaxis.line", color: .orange, trailing: minAvgMax(live.map { abs($0.battery) }, "%.1f") + " W") {
                if i.pluggedIn {
                    BigChart(series: [Series(name: "Into battery (+) / out (−)", values: live.map(\.battery), color: .orange),
                                      Series(name: "System", values: live.map(\.system), color: .cyan),
                                      Series(name: "From wall", values: live.map(\.wall), color: .yellow)], unit: " W", height: 200)
                } else {
                    BigChart(series: [Series(name: "Power draw", values: live.map { abs($0.battery) }, color: .orange)], unit: " W", height: 200, minY: 0)
                }
            }
            Grid2(a: Panel(title: "Voltage", icon: "bolt.fill", color: .yellow, trailing: minAvgMax(live.map(\.volts), "%.2f")) {
                BigChart(series: [Series(name: "", values: live.map(\.volts), color: .yellow)], unit: " V", height: 120, minY: (live.map(\.volts).min() ?? 11) - 0.2)
            }, b: Panel(title: "Current", icon: "waveform.path.ecg", color: .cyan, trailing: "mA") {
                BigChart(series: [Series(name: "", values: live.map { $0.amps * 1000 }, color: .cyan)], unit: "", height: 120)
            })
            powerFlow
            charger
            Grid2(a: health, b: lifetime)
            energy
            healthTrend
            sessionsPanel
            longTerm
        }
    }

    // MARK: health over time

    var healthTrend: some View {
        let h = batt.healthHistory
        return Panel(title: "Battery health over time", icon: "heart.text.square", color: jgreen, trailing: "\(h.count) day\(h.count == 1 ? "" : "s") recorded") {
            if h.count < 2 {
                Text("One reading is saved per day, so the trend line appears after the second day. Recorded so far:").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                let lo = (h.map(\.health).min() ?? 90) - 0.4, hi = (h.map(\.health).max() ?? 100) + 0.4
                Chart(h) { p in
                    LineMark(x: .value("Day", p.day), y: .value("Health", p.health)).foregroundStyle(jgreen).interpolationMethod(.monotone)
                    PointMark(x: .value("Day", p.day), y: .value("Health", p.health)).foregroundStyle(jgreen)
                }
                .chartYScale(domain: lo...hi)
                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.1f%%", d)).font(.system(size: 10)).foregroundStyle(.secondary) } } } }
                .frame(height: 170)
                if let f = h.first, let l = h.last {
                    HStack(alignment: .top) {
                        Big(label: "First recorded", value: String(format: "%.1f", f.health), unit: "%", color: .white, caption: f.day.formatted(.dateTime.day().month(.abbreviated).year()))
                        Big(label: "Now", value: String(format: "%.1f", l.health), unit: "%", color: jgreen, caption: "\(l.maxCapacity) mAh")
                        Big(label: "Change", value: String(format: "%+.1f", l.health - f.health), unit: "pts", color: l.health - f.health < -0.05 ? .orange : jgreen)
                        Big(label: "Cycles added", value: "\(l.cycles - f.cycles)", color: .purple, caption: "now \(l.cycles)")
                    }
                }
            }
            Divide()
            HStack {
                Text("DAY").frame(width: 160, alignment: .leading); Text("HEALTH").frame(width: 80, alignment: .trailing)
                Text("CAPACITY").frame(width: 100, alignment: .trailing); Text("CYCLES").frame(maxWidth: .infinity, alignment: .trailing)
            }.font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
            ForEach(Array(h.suffix(10).reversed())) { p in
                HStack {
                    Text(p.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())).frame(width: 160, alignment: .leading).foregroundStyle(.white)
                    Text(String(format: "%.1f%%", p.health)).frame(width: 80, alignment: .trailing).foregroundStyle(jgreen)
                    Text("\(p.maxCapacity) mAh").frame(width: 100, alignment: .trailing).foregroundStyle(.cyan)
                    Text("\(p.cycles)").frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(.purple)
                }.font(mono(12, .regular))
            }
        }
    }

    // MARK: charge + usage sessions

    var sessionsPanel: some View {
        let all = Array(batt.sessions.reversed())
        let shown = all.filter { sessFilter == 0 || (sessFilter == 1 && $0.isCharge) || (sessFilter == 2 && !$0.isCharge) }
        let week = batt.sessions.filter { $0.start > Date(timeIntervalSinceNow: -7 * 86400) }
        let charges = week.filter(\.isCharge), runs = week.filter { !$0.isCharge }
        let chargeWh = charges.map(\.wh).reduce(0, +)
        let avgCharge = charges.isEmpty ? 0 : charges.map(\.avgW).reduce(0, +) / Double(charges.count)
        let avgDraw = runs.isEmpty ? 0 : runs.map(\.avgW).reduce(0, +) / Double(runs.count)
        let longest = runs.map(\.minutes).max() ?? 0
        return Panel(title: "Charge & usage sessions", icon: "bolt.badge.clock", color: .yellow, trailing: "\(batt.sessions.count) recorded") {
            HStack(alignment: .top) {
                Big(label: "Charges (7 days)", value: "\(charges.count)", color: jgreen, caption: String(format: "%.1f Wh added", chargeWh))
                Big(label: "Avg charge speed", value: charges.isEmpty ? "—" : String(format: "%.1f", avgCharge), unit: charges.isEmpty ? "" : "W", color: .yellow)
                Big(label: "Avg draw on battery", value: runs.isEmpty ? "—" : String(format: "%.1f", avgDraw), unit: runs.isEmpty ? "" : "W", color: .orange)
                Big(label: "Longest run", value: runs.isEmpty ? "—" : fmtDuration(longest), color: .cyan)
            }
            Picker("", selection: $sessFilter) { Text("All").tag(0); Text("Charging").tag(1); Text("On battery").tag(2) }.pickerStyle(.segmented).labelsHidden()
            if shown.isEmpty {
                Text("Nothing recorded yet. Sessions are logged automatically as you charge and unplug (stretches of at least 2 minutes).").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(Array(shown.prefix(40))) { s in
                SessionRowView(s: s)
                Divide()
            }
            Button("Export sessions as CSV…") { exportSessionsCSV(batt.sessions) }
        }
    }

    var powerFlow: some View {
        Panel(title: "Power flow", icon: "arrow.triangle.branch", color: .mint) {
            HStack(spacing: 10) {
                flowBox(i.pluggedIn ? "powerplug.fill" : "battery.50percent", i.pluggedIn ? "Wall" : "Battery", i.pluggedIn ? i.adapterIn : abs(i.batteryPower), .yellow)
                Image(systemName: "chevron.right.2").foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    if i.pluggedIn { flowBox(i.batteryPower >= 0 ? "battery.100percent.bolt" : "battery.50percent", i.batteryPower >= 0 ? "Into battery" : "From battery", abs(i.batteryPower), i.batteryPower >= 0 ? jgreen : .orange) }
                    flowBox("laptopcomputer", "System", i.pluggedIn ? i.systemLoad : abs(i.batteryPower), .cyan)
                }
            }
            if i.pluggedIn {
                let loss = max(0, i.adapterIn - max(0, i.batteryPower) - i.systemLoad)
                KV(k: "Conversion / other losses", v: String(format: "%.1f W", loss), color: .secondary)
            }
        }
    }

    func flowBox(_ icon: String, _ label: String, _ w: Double, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(String(format: "%.2f W", w)).font(mono(20, .bold)).foregroundStyle(.white)
            }
            Spacer()
        }.padding(14).frame(maxWidth: .infinity).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder var charger: some View {
        if i.pluggedIn {
            Panel(title: "Charger", icon: "powerplug.fill", color: .yellow) {
                HStack(alignment: .top) {
                    Big(label: "Adapter", value: i.adapterWatts > 0 ? "\(i.adapterWatts)" : "—", unit: "W", color: .yellow)
                    Big(label: "Negotiated", value: i.adapterContractV > 0 ? String(format: "%.0f V · %.1f A", i.adapterContractV, i.adapterContractA) : "—", color: .white)
                    Big(label: "Wall draw now", value: String(format: "%.1f", i.adapterIn), unit: "W", color: .orange, caption: i.wallMeasured ? "measured" : "estimated")
                }
                if !i.pdos.isEmpty {
                    Divide()
                    Text("CHARGER POWER PROFILES").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                    ForEach(i.pdos) { p in
                        HStack {
                            Image(systemName: p.active ? "checkmark.circle.fill" : "circle").foregroundStyle(p.active ? jgreen : .secondary)
                            Text(p.label).font(.system(size: 13)).foregroundStyle(.white)
                            Spacer()
                            Text(String(format: "%.0f W", p.watts)).font(mono(13, .bold)).foregroundStyle(p.active ? jgreen : .white)
                            if p.active { Text("in use").font(.system(size: 11)).foregroundStyle(jgreen) }
                        }
                    }
                }
            }
        }
    }

    var health: some View {
        Panel(title: "Health & capacity", icon: "heart.fill", color: i.health >= 80 ? jgreen : .yellow) {
            HStack(alignment: .top) {
                Big(label: "Max capacity", value: String(format: "%.1f", i.health), unit: "%", color: i.health >= 80 ? jgreen : .yellow)
                Big(label: "Cycles", value: "\(i.cycles)", unit: "/ \(i.designCycles)", color: .purple)
            }
            FillBar(frac: i.health / 100, color: i.health >= 80 ? jgreen : .yellow, height: 8)
            KV(k: "Remaining", v: "\(i.currentCapacity) mAh", color: jgreen)
            KV(k: "Current full", v: "\(i.maxCapacity) mAh", color: .cyan)
            KV(k: "Design capacity", v: "\(i.designCapacity) mAh")
            if let lo = i.dailyMinSoc, let hi = i.dailyMaxSoc, hi > 0 { KV(k: "Today's charge range", v: "\(lo)% – \(hi)%", color: .purple) }
        }
    }

    var lifetime: some View {
        Panel(title: "Lifetime (battery gauge)", icon: "clock.arrow.circlepath", color: .pink) {
            if let lo = i.lifeMinTemp, let hi = i.lifeMaxTemp { KV(k: "Temperature range", v: "\(lo)°C – \(hi)°C", color: .orange) }
            if let lo = i.lifeMinPackV, let hi = i.lifeMaxPackV { KV(k: "Pack voltage range", v: String(format: "%.2f – %.2f V", lo, hi), color: .yellow) }
            if let c = i.lifeMaxChargeA { KV(k: "Max charge current", v: String(format: "%.2f A", c), color: jgreen) }
            if let c = i.lifeMaxDischargeA { KV(k: "Max discharge current", v: String(format: "%.2f A", c), color: .orange) }
            if i.lifeMaxTemp == nil { Text("Loading…").font(.system(size: 13)).foregroundStyle(.secondary) }
        }
    }

    var energy: some View {
        Panel(title: "Apps using significant energy", icon: "bolt.circle", color: .orange, trailing: "Energy Impact") {
            if batt.energy.isEmpty { Text("Nothing using significant energy right now.").font(.system(size: 13)).foregroundStyle(.secondary) }
            ProcRowsE(apps: batt.energy)
        }
    }

    var longTerm: some View {
        let h = batt.history
        return Panel(title: "Charge history", icon: "chart.xyaxis.line", color: jgreen, trailing: "\(h.count) minutes recorded") {
            Chart(h) { LineMark(x: .value("t", $0.t), y: .value("%", $0.pct)).foregroundStyle(jgreen).interpolationMethod(.monotone) }
                .chartYScale(domain: 0...100).frame(height: 140)
            Chart(h) { AreaMark(x: .value("t", $0.t), y: .value("W", $0.watts)).foregroundStyle(LinearGradient(colors: [.orange, .orange.opacity(0.05)], startPoint: .top, endPoint: .bottom)) }
                .frame(height: 120)
            Text("Top: charge level. Bottom: battery power (+ charging / − draining), recorded once a minute while the app runs.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - CPU

struct CPUPage: View {
    @ObservedObject var sys: SystemStore
    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "Usage", icon: "cpu", color: Mod.cpu.color, trailing: minAvgMax(sys.cpuHist, "%.0f") + " %") {
                HStack(alignment: .top) {
                    Big(label: "Total", value: String(format: "%.0f", sys.cpuTotal), unit: "%", color: Mod.cpu.color)
                    Big(label: "User", value: String(format: "%.1f", sys.cpuUser), unit: "%", color: .blue)
                    Big(label: "System", value: String(format: "%.1f", sys.cpuSys), unit: "%", color: .red)
                    Big(label: "Idle", value: String(format: "%.1f", max(0, 100 - sys.cpuTotal)), unit: "%", color: .white)
                }
                BigChart(series: [Series(name: "", values: sys.cpuHist, color: Mod.cpu.color)], unit: "%", height: 190, minY: 0, maxY: 100)
            }
            Panel(title: "Power & frequency", icon: "bolt.fill", color: .yellow, trailing: sys.coreFresh ? "core sensors · root sampler" : "needs core sensors") {
                if sys.coreFresh, let c = sys.core {
                    HStack(alignment: .top) {
                        Big(label: "CPU", value: c.cpuW.map { String(format: "%.2f", $0) } ?? "—", unit: "W", color: .yellow)
                        Big(label: "GPU", value: c.gpuW.map { String(format: "%.2f", $0) } ?? "—", unit: "W", color: .purple)
                        Big(label: "Neural Engine", value: c.aneW.map { String(format: "%.2f", $0) } ?? "—", unit: "W", color: .pink)
                        Big(label: "Package", value: c.packageW.map { String(format: "%.2f", $0) } ?? "—", unit: "W", color: .orange)
                    }
                    BigChart(series: [Series(name: "CPU power", values: sys.cpuPowerHist, color: .yellow)], unit: " W", height: 130, minY: 0)
                    HStack(alignment: .top) {
                        ForEach(Array(c.clusters.enumerated()), id: \.offset) { _, cl in Big(label: cl.name, value: String(format: "%.0f", cl.mhz), unit: "MHz", color: .cyan) }
                        if let t = c.thermal { Big(label: "Thermal pressure", value: t.capitalized, color: t.lowercased() == "nominal" ? jgreen : .orange) }
                    }
                } else { CoreSensorsHint() }
            }
            Panel(title: "Cores", icon: "square.grid.3x3.fill", color: .indigo, trailing: "\(sys.coreCount) logical cores") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(Array(sys.cores.enumerated()), id: \.offset) { i, v in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Core \(i + 1)").font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Text(String(format: "%.0f%%", v)).font(mono(12, .bold)).foregroundStyle(loadColor(v)) }
                            FillBar(frac: v / 100, color: loadColor(v), height: 6)
                        }
                    }
                }
                if sys.perfCores > 0 || sys.effCores > 0 {
                    Text("\(sys.perfCores) performance + \(sys.effCores) efficiency cores").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Grid2(a: Panel(title: "System", icon: "info.circle.fill", color: .cyan) {
                KV(k: "Chip", v: sys.chip)
                KV(k: "Model", v: sysctlStr("hw.model"))
                KV(k: "Uptime", v: fmtUptimeLong(sys.uptime))
                KV(k: "Processes", v: "\(sys.procCount)")
                if let t = sys.socTemp { KV(k: "SoC temperature", v: String(format: "%.1f °C", t), color: tempColor(t)) }
            }, b: Panel(title: "Load average", icon: "gauge.with.dots.needle.50percent", color: .yellow) {
                KV(k: "1 minute", v: String(format: "%.2f", sys.load.0), color: .yellow)
                KV(k: "5 minutes", v: String(format: "%.2f", sys.load.1))
                KV(k: "15 minutes", v: String(format: "%.2f", sys.load.2))
            })
            Panel(title: "Top processes", icon: "list.number", color: .orange, trailing: "by CPU") {
                ProcRows(procs: sys.topCPU, color: .orange) { String(format: "%.1f%%", $0) }
            }
        }
    }
}

func exportSessionsCSV(_ sessions: [ChargeSession]) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "dewdrop-sessions.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let f = ISO8601DateFormatter()
    let rows = ["kind,start,end,minutes,start_percent,end_percent,watt_hours,avg_watts,peak_watts"] + sessions.map {
        "\($0.kind),\(f.string(from: $0.start)),\(f.string(from: $0.end)),\(String(format: "%.1f", $0.minutes)),\($0.startPct),\($0.endPct),\(String(format: "%.2f", $0.wh)),\(String(format: "%.1f", $0.avgW)),\(String(format: "%.1f", $0.peakW))"
    }
    try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
}

func fmtUptimeLong(_ s: Double) -> String {
    let t = Int(s); let d = t / 86400, h = t % 86400 / 3600, m = t % 3600 / 60
    return d > 0 ? "\(d)d \(h)h \(m)m" : "\(h)h \(m)m"
}

// MARK: - GPU

struct GPUPage: View {
    @ObservedObject var sys: SystemStore
    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "Utilization", icon: "display", color: Mod.gpu.color, trailing: minAvgMax(sys.gpuHist, "%.0f") + " %") {
                HStack(alignment: .top) {
                    Big(label: "Device", value: String(format: "%.0f", sys.gpu.util), unit: "%", color: Mod.gpu.color)
                    Big(label: "Renderer", value: String(format: "%.0f", sys.gpu.render), unit: "%", color: .white)
                    Big(label: "Tiler", value: String(format: "%.0f", sys.gpu.tiler), unit: "%", color: .white)
                    Big(label: "GPU memory", value: fmtBytes(sys.gpu.mem), color: .cyan)
                }
                BigChart(series: [Series(name: "", values: sys.gpuHist, color: Mod.gpu.color)], unit: "%", height: 180, minY: 0, maxY: 100)
            }
            Panel(title: "GPU power", icon: "bolt.fill", color: .yellow, trailing: sys.gpuPower == nil ? "needs IOReport" : minAvgMax(sys.gpuPowerHist, "%.2f") + " W") {
                Big(label: "Now", value: sys.gpuWatts.map { String(format: "%.2f", $0) } ?? "—", unit: "W", color: .yellow)
                BigChart(series: [Series(name: "", values: sys.gpuPowerHist, color: .yellow)], unit: " W", height: 140)
                Text("Measured from the GPU's energy counter. CPU and memory energy counters are not readable on this macOS without admin rights.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Memory

struct MemoryPage: View {
    @ObservedObject var sys: SystemStore
    var pct: Double { sys.ramTotal > 0 ? sys.ramUsed / sys.ramTotal * 100 : 0 }
    func seg(_ v: Double) -> CGFloat { sys.ramTotal > 0 ? CGFloat(v / sys.ramTotal) : 0 }
    var pressure: (String, Color) { switch sys.pressure { case 2: return ("Warning", .yellow); case 4: return ("Critical", .red); default: return ("Normal", jgreen) } }

    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "Usage", icon: "memorychip", color: Mod.ram.color, trailing: minAvgMax(sys.ramHist, "%.0f") + " %") {
                HStack(alignment: .top) {
                    Big(label: "In use", value: String(format: "%.0f", pct), unit: "%", color: Mod.ram.color, caption: "\(fmtBytes(sys.ramUsed)) of \(fmtBytes(sys.ramTotal))")
                    Big(label: "Pressure", value: pressure.0, color: pressure.1)
                    Big(label: "Swap used", value: fmtBytes(sys.swapUsed), color: .white, caption: "of \(fmtBytes(sys.swapTotal))")
                }
                BigChart(series: [Series(name: "", values: sys.ramHist, color: Mod.ram.color)], unit: "%", height: 170, minY: 0, maxY: 100)
            }
            Panel(title: "Breakdown", icon: "chart.pie.fill", color: .purple) {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3).fill(Mod.ram.color).frame(width: g.size.width * seg(sys.ramApp))
                        RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: g.size.width * seg(sys.ramWired))
                        RoundedRectangle(cornerRadius: 3).fill(Color.yellow).frame(width: g.size.width * seg(sys.ramComp))
                        RoundedRectangle(cornerRadius: 3).fill(Color.cyan.opacity(0.7)).frame(width: g.size.width * seg(sys.ramCache))
                        Spacer(minLength: 0)
                    }
                }.frame(height: 14).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                KV(k: "App memory", v: fmtBytes(sys.ramApp), color: Mod.ram.color)
                KV(k: "Wired", v: fmtBytes(sys.ramWired), color: .red)
                KV(k: "Compressed", v: fmtBytes(sys.ramComp), color: .yellow)
                KV(k: "Cached files", v: fmtBytes(sys.ramCache), color: .cyan)
                KV(k: "Free", v: fmtBytes(sys.ramFree), color: jgreen)
            }
            Panel(title: "Paging (since boot)", icon: "arrow.up.arrow.down", color: .teal) {
                KV(k: "Pages in", v: fmtCount(sys.pageIns))
                KV(k: "Pages out", v: fmtCount(sys.pageOuts))
                KV(k: "Swap in", v: fmtCount(sys.swapIns))
                KV(k: "Swap out", v: fmtCount(sys.swapOuts))
            }
            Panel(title: "Top processes", icon: "list.number", color: .orange, trailing: "by memory") {
                ProcRows(procs: sys.topMem, color: Mod.ram.color) { fmtBytes($0) }
            }
        }
    }
}

func fmtCount(_ v: Double) -> String { NumberFormatter.localizedString(from: NSNumber(value: v), number: .decimal) }

// MARK: - Disk

struct DiskPage: View {
    @ObservedObject var sys: SystemStore
    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "Volumes", icon: "externaldrive.fill", color: Mod.disk.color) {
                ForEach(sys.volumes) { v in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(v.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Text("\(fmtFileBytes(v.free)) free of \(fmtFileBytes(v.total))").font(mono(12, .regular)).foregroundStyle(.secondary)
                        }
                        FillBar(frac: (v.total - v.free) / v.total, color: loadColor((v.total - v.free) / v.total * 100), height: 8)
                        Text(v.path).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }
            Panel(title: "Activity", icon: "arrow.up.arrow.down", color: .orange) {
                HStack(alignment: .top) {
                    Big(label: "Read", value: fmtRate(sys.diskRead), color: .cyan)
                    Big(label: "Write", value: fmtRate(sys.diskWrite), color: .orange)
                }
                BigChart(series: [Series(name: "Read", values: sys.diskReadHist, color: .cyan), Series(name: "Write", values: sys.diskWriteHist, color: .orange)], unit: "", height: 160)
            }
            Panel(title: "Top processes", icon: "list.number", color: .orange, trailing: "by disk I/O") {
                ProcRows(procs: sys.topDisk, color: Mod.disk.color) { fmtRate($0) }
            }
        }
    }
}

// MARK: - Network

struct NetworkPage: View {
    @ObservedObject var sys: SystemStore
    @ObservedObject var prefs = Prefs.shared
    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "Throughput", icon: "network", color: Mod.network.color) {
                HStack(alignment: .top) {
                    Big(label: "Download", value: fmtRate(sys.netDown), color: .mint, caption: "peak " + fmtRateShort(sys.netDownHist.max() ?? 0))
                    Big(label: "Upload", value: fmtRate(sys.netUp), color: .orange, caption: "peak " + fmtRateShort(sys.netUpHist.max() ?? 0))
                }
                BigChart(series: [Series(name: "Download", values: sys.netDownHist, color: .mint), Series(name: "Upload", values: sys.netUpHist, color: .orange)], unit: "", height: 180)
                KV(k: "Downloaded since launch", v: fmtFileBytes(sys.netTotalDown), color: .mint)
                KV(k: "Uploaded since launch", v: fmtFileBytes(sys.netTotalUp), color: .orange)
            }
            Grid2(a: Panel(title: "Connection", icon: "globe", color: .cyan) {
                KV(k: "Interface", v: sys.iface ?? "—")
                KV(k: "Local IP", v: sys.localIP ?? "—")
                KV(k: "Public IP", v: prefs.cfg.publicIP ? (sys.publicIP ?? "Fetching…") : "Off (Settings)")
            }, b: Panel(title: "Wi-Fi", icon: "wifi", color: .blue) {
                if let w = sys.wifi {
                    KV(k: "Signal", v: "\(w.rssi) dBm", color: w.rssi > -60 ? jgreen : (w.rssi > -75 ? .yellow : .red))
                    KV(k: "Link speed", v: String(format: "%.0f Mbps", w.rate))
                    if let c = w.channel { KV(k: "Channel", v: "\(c)") }
                    if let b = w.band { KV(k: "Band", v: b) }
                } else { Text("Not connected to Wi-Fi").font(.system(size: 13)).foregroundStyle(.secondary) }
            })
            Panel(title: "Top processes", icon: "list.number", color: .orange, trailing: "by network traffic") {
                ProcRows(procs: sys.topNet, color: .mint) { fmtRate($0) }
            }
        }
    }
}

// MARK: - Sensors

struct SensorsPage: View {
    @ObservedObject var sys: SystemStore
    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "SoC temperature", icon: "thermometer.medium", color: .red, trailing: minAvgMax(sys.socHist, "%.1f") + " °C") {
                HStack(alignment: .top) {
                    Big(label: "Average", value: sys.socTemp.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", color: sys.socTemp.map(tempColor) ?? .gray)
                    Big(label: "Hottest die", value: sys.socMax.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", color: sys.socMax.map(tempColor) ?? .gray)
                    Big(label: "Storage", value: sys.nandTemp.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", color: sys.nandTemp.map(tempColor) ?? .gray)
                    Big(label: "Battery", value: sys.battTemp.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", color: sys.battTemp.map(tempColor) ?? .gray)
                }
                BigChart(series: [Series(name: "", values: sys.socHist, color: .red)], unit: "°", height: 160, minY: (sys.socHist.min() ?? 20) - 3)
            }
            Panel(title: "Power rails", icon: "bolt.fill", color: .yellow) {
                HStack(alignment: .top) {
                    Big(label: "System total", value: sys.systemPower.map { String(format: "%.1f", $0) } ?? "—", unit: "W", color: .yellow)
                    Big(label: "DC input", value: sys.dcInPower.map { String(format: "%.1f", $0) } ?? "—", unit: "W", color: .orange)
                    Big(label: "GPU", value: sys.gpuWatts.map { String(format: "%.2f", $0) } ?? "—", unit: "W", color: .purple)
                    if sys.coreFresh, let c = sys.core {
                        Big(label: "CPU", value: c.cpuW.map { String(format: "%.2f", $0) } ?? "—", unit: "W", color: .yellow)
                    }
                }
            }
            if sys.hasFans {
                Panel(title: "Fans", icon: "fan.fill", color: .teal) {
                    ForEach(sys.fans) { f in KV(k: "Fan \(f.id + 1)", v: String(format: "%.0f rpm", f.rpm), color: .teal) }
                }
            }
            Panel(title: "All sensors", icon: "list.bullet", color: .gray, trailing: "\(sys.temps.count) readings") {
                ForEach(sys.temps) { s in
                    HStack(spacing: 10) {
                        Text(s.name).font(.system(size: 12)).foregroundStyle(.white).frame(width: 170, alignment: .leading)
                        FillBar(frac: s.value / 110, color: tempColor(s.value), height: 5)
                        Text(String(format: "%.1f °C", s.value)).font(mono(12, .bold)).foregroundStyle(tempColor(s.value)).frame(width: 70, alignment: .trailing)
                    }
                }
            }
        }
    }
}
