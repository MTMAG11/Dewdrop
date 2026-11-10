import SwiftUI
import AppKit

struct WData {
    var label = ""
    var value = ""
    var frac = 0.0
    var hist: [Double] = []
    var histMax: Double? = 100
    var color: Color = jgreen
    var line1 = "", line2 = ""
    var symbol = ""
    var charging = false
    var pct = 0
    var extra = ""
}

func levelColor(_ pct: Double) -> Color { pct < 60 ? jgreen : (pct < 85 ? .yellow : .red) }

let clockFormatter = DateFormatter()

func widgetData(_ m: Mod, _ sys: SystemStore, _ batt: Monitor, _ cfg: Config) -> WData {
    var d = WData(label: m.short, symbol: m.icon)
    switch m {
    case .battery:
        let i = batt.info
        d.value = "\(i.percent)%" + (cfg.batteryWatts ? String(format: " · %.1fW", i.displayWatts) : "")
        d.frac = Double(i.percent) / 100
        d.pct = i.percent
        d.extra = cfg.batteryText ? String(format: "%.1fW", i.displayWatts) : ""   // pill shows the % inside, watts beside it
        d.charging = i.isCharging
        d.color = i.percent <= 20 && !i.pluggedIn ? .red : (i.percent <= 40 && !i.pluggedIn ? .orange : jgreen)
        d.hist = batt.history.suffix(60).map { Double($0.pct) }
    case .cpu:
        d.value = String(format: "%.0f%%", sys.cpuTotal); d.frac = sys.cpuTotal / 100; d.hist = sys.cpuHist; d.color = levelColor(sys.cpuTotal)
    case .gpu:
        d.value = String(format: "%.0f%%", sys.gpu.util); d.frac = sys.gpu.util / 100; d.hist = sys.gpuHist; d.color = levelColor(sys.gpu.util)
    case .ram:
        let p = sys.ramTotal > 0 ? sys.ramUsed / sys.ramTotal * 100 : 0
        d.value = String(format: "%.0f%%", p); d.frac = p / 100; d.hist = sys.ramHist; d.color = levelColor(p)
    case .disk:
        let v = sys.volumes.first(where: { $0.path == "/" }) ?? sys.volumes.first
        let p = v.map { ($0.total - $0.free) / $0.total * 100 } ?? 0
        d.value = String(format: "%.0f%%", p); d.frac = p / 100; d.color = levelColor(p)
        d.hist = zip(sys.diskReadHist, sys.diskWriteHist).map { $0 + $1 }; d.histMax = nil
    case .network:
        d.line1 = "↓ " + fmtRateShort(sys.netDown); d.line2 = "↑ " + fmtRateShort(sys.netUp)
        d.value = "↓\(fmtRateShort(sys.netDown).replacingOccurrences(of: "/s", with: "")) ↑\(fmtRateShort(sys.netUp).replacingOccurrences(of: "/s", with: ""))"
        d.hist = sys.netDownHist; d.histMax = nil; d.color = .mint
    case .sensors:
        d.value = sys.socTemp.map { String(format: "%.0f°", $0) } ?? "—"; d.color = sys.socTemp.map(tempColor) ?? .gray
    case .fans:
        d.value = sys.fans.first.map { String(format: "%.0f rpm", $0.rpm) } ?? "No fan"
    case .bluetooth:
        d.value = ""
    case .clock:
        let f = clockFormatter
        f.dateFormat = cfg.clock24 ? (cfg.clockSeconds ? "HH:mm:ss" : "HH:mm") : (cfg.clockSeconds ? "h:mm:ss a" : "h:mm a")
        if let id = cfg.timeZones.first, let tz = TimeZone(identifier: id) { f.timeZone = tz }
        d.value = f.string(from: Date())
        d.label = cfg.timeZones.first.flatMap { $0.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } } ?? "CLOCK"
    }
    return d
}

struct Spark: Shape {
    let values: [Double]
    let maxV: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        for (i, v) in values.enumerated() {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = r.maxY - r.height * CGFloat(min(1, v / max(maxV, 0.0001)))
            i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }
}

struct BatteryGlyph: View {
    let frac: Double, color: Color, fg: Color, charging: Bool
    var body: some View {
        HStack(spacing: 0.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(fg.opacity(0.55), lineWidth: 1).frame(width: 21, height: 11)
                RoundedRectangle(cornerRadius: 1.8).fill(color).frame(width: max(2, 18 * CGFloat(frac)), height: 8).padding(.leading, 1.5)
                if charging { Image(systemName: "bolt.fill").font(.system(size: 7)).foregroundStyle(.white).frame(width: 21) }
            }
            RoundedRectangle(cornerRadius: 1).fill(fg.opacity(0.55)).frame(width: 1.5, height: 4)
        }
    }
}

/// Pill-style menu bar icon: rounded pill filled to the charge level with the number inside
struct PillGlyph: View {
    let pct: Int, frac: Double, color: Color, charging: Bool
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.20)).frame(width: 27, height: 15)
                RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.55)).frame(width: max(5, 27 * CGFloat(min(1, frac))), height: 15)
                RoundedRectangle(cornerRadius: 5).strokeBorder(color, lineWidth: 1.3).frame(width: 27, height: 15)
                HStack(spacing: 1) {
                    if charging { Image(systemName: "bolt.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white) }
                    Text("\(pct)").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                }.frame(width: 27)
            }
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 1.8, height: 5)
        }
    }
}

struct WidgetView: View {
    let d: WData
    let kind: WidgetKind
    let showLabel: Bool
    let colored: Bool
    let fg: Color
    var tint: Color { colored ? d.color : fg }

    var body: some View {
        Group {
            switch kind {
            case .stacked:
                VStack(spacing: -1) {
                    if showLabel { Text(d.label).font(.system(size: 7.5, weight: .bold)).foregroundStyle(fg.opacity(0.65)) }
                    Text(d.value).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                }
            case .text:
                HStack(spacing: 4) {
                    if showLabel { Text(d.label).font(.system(size: 10, weight: .bold)).foregroundStyle(fg.opacity(0.65)) }
                    Text(d.value).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                }
            case .bar:
                HStack(spacing: 4) {
                    if showLabel { Text(d.label).font(.system(size: 8, weight: .bold)).foregroundStyle(fg.opacity(0.65)) }
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(fg.opacity(0.22)).frame(width: 7, height: 15)
                        RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 7, height: max(2, 15 * CGFloat(min(1, d.frac))))
                    }
                }
            case .graph:
                HStack(spacing: 4) {
                    if showLabel { Text(d.label).font(.system(size: 8, weight: .bold)).foregroundStyle(fg.opacity(0.65)) }
                    ZStack {
                        RoundedRectangle(cornerRadius: 2).fill(fg.opacity(0.10)).frame(width: 32, height: 15)
                        Spark(values: d.hist.suffix(30).map { $0 }, maxV: d.histMax ?? max(d.hist.suffix(30).max() ?? 1, 1))
                            .stroke(tint, lineWidth: 1.2).frame(width: 30, height: 13)
                    }
                }
            case .pie:
                HStack(spacing: 4) {
                    if showLabel { Text(d.label).font(.system(size: 8, weight: .bold)).foregroundStyle(fg.opacity(0.65)) }
                    ZStack {
                        Circle().stroke(fg.opacity(0.22), lineWidth: 3)
                        Circle().trim(from: 0, to: CGFloat(min(1, d.frac))).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    }.frame(width: 15, height: 15)
                }
            case .pill:
                HStack(spacing: 6) {
                    PillGlyph(pct: d.pct, frac: d.frac, color: d.color, charging: d.charging)
                    if !d.extra.isEmpty {
                        Text(d.extra).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(fg)
                    }
                }
            case .battery:
                HStack(spacing: 5) {
                    BatteryGlyph(frac: d.frac, color: tint, fg: fg, charging: d.charging)
                    Text(d.value).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(fg)
                }
            case .speeds:
                VStack(alignment: .trailing, spacing: 0) {
                    Text(d.line1).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(colored ? Color.mint : fg)
                    Text(d.line2).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(colored ? Color.orange : fg)
                }
            case .icon:
                Image(systemName: d.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(fg)
            }
        }
        .fixedSize()
    }
}

struct MenuBarStrip: View {
    let mods: [Mod]
    @ObservedObject var sys: SystemStore
    @ObservedObject var batt: Monitor
    let cfg: Config
    let fg: Color
    var body: some View {
        HStack(spacing: 9) {
            ForEach(mods) { m in
                let c = cfg.cfg(m)
                WidgetView(d: widgetData(m, sys, batt, cfg), kind: c.widget, showLabel: c.label, colored: c.colored, fg: fg)
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
    }
}

func renderStrip(mods: [Mod], dark: Bool, sys: SystemStore, batt: Monitor, cfg: Config) -> NSImage? {
    MainActor.assumeIsolated {
        let fg: Color = dark ? .white : .black
        let r = ImageRenderer(content: MenuBarStrip(mods: mods, sys: sys, batt: batt, cfg: cfg, fg: fg).environment(\.colorScheme, dark ? .dark : .light))
        r.scale = 2
        return r.nsImage
    }
}
