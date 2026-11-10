import SwiftUI
import Charts

// MARK: - Palette (matches the reference screenshots: black cards on a dark popover)

let jgreen = Color(red: 0.19, green: 0.82, blue: 0.35)
let jbg = Color(white: 0.105)
let jcard = Color.black
let jline = Color.white.opacity(0.10)

func mono(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font { .system(size: size, weight: w, design: .monospaced) }

struct HKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

final class HeightBox: ObservableObject { @Published var h: CGFloat = 420 }

struct AutoScroll<C: View>: View {
    @StateObject private var box = HeightBox()
    let maxH: CGFloat
    @ViewBuilder let content: C
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content.background(GeometryReader { g in Color.clear.preference(key: HKey.self, value: g.size.height) })
        }
        .frame(height: min(box.h, maxH))
        .onPreferenceChange(HKey.self) { box.h = $0 }
    }
}

// MARK: - Cards

struct CardBox<C: View>: View {
    @ViewBuilder let content: C
    var body: some View {
        content
            .background(jcard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(jline))
    }
}

struct Collapsible<C: View>: View {
    @ObservedObject private var st = OpenState.shared
    let id: String, title: String, icon: String, color: Color
    @ViewBuilder let content: C
    var isOpen: Bool { st.open.contains(id) }
    var body: some View {
        CardBox {
            VStack(spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.18)) { st.toggle(id) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color).frame(width: 20)
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 13).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if isOpen {
                    Rectangle().fill(jline).frame(height: 1)
                    VStack(alignment: .leading, spacing: 16) { content }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct Block<C: View>: View {
    let title: String, icon: String, color: Color
    var info: String? = nil
    @ViewBuilder let content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if let info { Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(.secondary).help(info) }
            }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Divide: View { var body: some View { Rectangle().fill(jline).frame(height: 1) } }

struct Stat: View {
    let label: String, value: String
    var unit = ""
    var color: Color = .white
    var trailing = false
    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(mono(20, .bold)).foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(mono(16, .bold)).foregroundStyle(color) }
            }
        }.frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

struct LineRow: View {
    let label: String, value: String
    var color: Color = .white
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Text(value).font(mono(13, .bold)).foregroundStyle(color)
        }
    }
}

struct FillBar: View {
    let frac: Double
    var color: Color = jgreen
    var height: CGFloat = 8
    var ticks = false
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(color).frame(width: max(height, g.size.width * min(1, max(0, frac))))
                if ticks {
                    ForEach([25.0, 50.0, 75.0], id: \.self) { t in
                        Rectangle().fill(.white.opacity(0.55)).frame(width: 1.5, height: height).offset(x: g.size.width * t / 100)
                    }
                }
            }
        }.frame(height: height)
    }
}

struct HistChart: View {
    let values: [Double]
    var color: Color = jgreen
    var maxY: Double? = nil
    var height: CGFloat = 80
    var body: some View {
        let pts = Array(values.enumerated())
        Chart {
            ForEach(pts, id: \.offset) { i, v in
                AreaMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(LinearGradient(colors: [color.opacity(0.5), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone)
                LineMark(x: .value("t", i), y: .value("v", v)).foregroundStyle(color).interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel().foregroundStyle(.secondary) } }
        .chartYScale(domain: 0...(maxY ?? max(values.max() ?? 1, 1) * 1.15))
        .frame(height: height)
    }
}

struct DualChart: View {
    let a: [Double], b: [Double]
    var ca: Color = .mint, cb: Color = .orange
    var height: CGFloat = 80
    var body: some View {
        let top = max(max(a.max() ?? 1, b.max() ?? 1), 1) * 1.15
        Chart {
            ForEach(Array(a.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", "a")).foregroundStyle(ca).interpolationMethod(.monotone)
            }
            ForEach(Array(b.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", "b")).foregroundStyle(cb).interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...top)
        .frame(height: height)
    }
}

/// Big header card in the reference style: huge value, caption, right-hand stat, tick progress bar
struct ModHeader: View {
    let big: String
    var unit = "%"
    let caption: String
    let icon: String
    var right: [(String, String)] = []
    var frac: Double? = nil
    var color: Color = jgreen
    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(big).font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(color).monospacedDigit()
                            Text(unit).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(color.opacity(0.85))
                        }
                        HStack(spacing: 7) {
                            Image(systemName: icon).foregroundStyle(color)
                            Text(caption).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        ForEach(Array(right.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(r.0).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
                                Text(r.1).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                            }
                        }
                    }.padding(.top, 8)
                }
                if let frac { FillBar(frac: frac, color: color, height: 8, ticks: true) }
            }.padding(16)
        }
    }
}

struct ProcRows: View {
    let procs: [Proc]
    let color: Color
    let fmt: (Double) -> String
    var body: some View {
        if procs.isEmpty { Text("Collecting…").font(.system(size: 13)).foregroundStyle(.secondary) }
        let top = max(procs.first?.value ?? 1, 1)
        ForEach(procs) { p in
            HStack(spacing: 10) {
                Text(p.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                FillBar(frac: p.value / top, color: color, height: 5).frame(width: 56)
                Text(fmt(p.value)).font(mono(12, .bold)).foregroundStyle(color).frame(width: 74, alignment: .trailing)
            }
        }
    }
}

struct MenuRow: View {
    let icon: String, title: String
    var color: Color = .white
    var trailing: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 22).foregroundStyle(color)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if let trailing { Text(trailing).font(mono(10, .regular)).foregroundStyle(.secondary) }
                else { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

func tempColor(_ c: Double) -> Color { c < 45 ? jgreen : (c < 65 ? .yellow : (c < 85 ? .orange : .red)) }
func loadColor(_ p: Double) -> Color { p < 60 ? jgreen : (p < 85 ? .yellow : .red) }


// MARK: - Reorderable sections (drag to move, or right-click for Move to Top / Up / Down / Hide)

struct SectionDrag: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .draggable(id)
            .dropDestination(for: String.self) { items, _ in
                guard let d = items.first else { return false }
                withAnimation(.easeInOut(duration: 0.2)) { Prefs.shared.move(d, before: id) }
                return true
            }
            .contextMenu {
                Button("Move to Top") { withAnimation { Prefs.shared.moveToTop(id) } }
                Button("Move Up") { withAnimation { Prefs.shared.move(id, by: -1) } }
                Button("Move Down") { withAnimation { Prefs.shared.move(id, by: 1) } }
                if !id.hasPrefix("mod.") { Divider(); Button("Hide This Section") { Prefs.shared.setHidden(id, true) } }
            }
    }
}

struct SectionList<C: View>: View {
    let mod: Mod
    @ObservedObject private var prefs = Prefs.shared
    @ViewBuilder let build: (String) -> C
    var body: some View {
        ForEach(prefs.sections(mod), id: \.self) { id in
            if !prefs.cfg.hidden.contains(id) { build(id).modifier(SectionDrag(id: id)) }
        }
    }
}
