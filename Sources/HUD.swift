import SwiftUI
import AppKit

// MARK: - Events

enum BatteryEvent {
    case plugged(pct: Int, adapterW: Int, charging: Bool)
    case unplugged(pct: Int, minutes: Int?)
    case low(pct: Int, minutes: Int?)
    case critical(pct: Int, minutes: Int?)
    case full
    case limit(pct: Int, limit: Int)

    var tint: Color {
        switch self {
        case .plugged, .full: return jgreen
        case .unplugged: return .cyan
        case .low: return .orange
        case .critical: return .red
        case .limit: return .yellow
        }
    }
    var title: String {
        switch self {
        case .plugged(_, _, let c): return c ? "Charging" : "Plugged In"
        case .unplugged: return "On Battery"
        case .low: return "Low Battery"
        case .critical: return "Critical Battery"
        case .full: return "Fully Charged"
        case .limit(_, let l): return "Reached \(l)%"
        }
    }
    var subtitle: String {
        func t(_ m: Int?) -> String { m.map { " · \(fmtTime($0)) left" } ?? "" }
        switch self {
        case .plugged(let p, let w, _): return "\(p)%" + (w > 0 ? " · \(w) W adapter" : "")
        case .unplugged(let p, let m): return "\(p)%" + t(m)
        case .low(let p, let m): return "\(p)%" + t(m) + " · plug in soon"
        case .critical(let p, let m): return "\(p)%" + t(m) + " · plug in now"
        case .full: return "100% · you can unplug"
        case .limit(let p, _): return "\(p)% · unplug to protect battery health"
        }
    }
    var pct: Int {
        switch self {
        case .plugged(let p, _, _), .unplugged(let p, _), .low(let p, _), .critical(let p, _), .limit(let p, _): return p
        case .full: return 100
        }
    }
    var symbol: String {
        switch self {
        case .plugged: return "bolt.fill"
        case .unplugged: return "powerplug"
        case .low, .critical: return "exclamationmark"
        case .full: return "checkmark"
        case .limit: return "hand.raised.fill"
        }
    }
    var urgent: Bool { if case .critical = self { return true }; if case .low = self { return true }; return false }
    var duration: Double { urgent ? 6.5 : 3.6 }
}

// MARK: - Card (pure, so it can be snapshotted)

struct HUDCard: View {
    let event: BatteryEvent
    let t: Double   // seconds since shown

    var body: some View {
        let grow = min(1, t / 0.9)
        let eased = 1 - pow(1 - grow, 3)
        let pulse = 0.5 + 0.5 * sin(t * 2 * .pi * (event.urgent ? 1.6 : 1.0))
        let shake = event.urgent && t < 1.2 ? sin(t * 38) * 3 * (1 - t / 1.2) : 0
        let fill = Double(event.pct) / 100 * eased

        HStack(spacing: 16) {
            ZStack {
                // battery body
                RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.5), lineWidth: 2.5).frame(width: 66, height: 34)
                RoundedRectangle(cornerRadius: 6).fill(event.tint.gradient)
                    .frame(width: max(6, 57 * fill), height: 25).frame(width: 57, alignment: .leading).offset(x: 0)
                Image(systemName: event.symbol).font(.system(size: 17, weight: .black)).foregroundStyle(.white)
                    .scaleEffect(1 + 0.16 * pulse).shadow(color: event.tint.opacity(0.9), radius: 6 * pulse)
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.5)).frame(width: 4, height: 12).offset(x: 37)
            }
            .frame(width: 80)
            .offset(x: shake)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(event.subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            Text("\(Int((Double(event.pct) * eased).rounded()))%").font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(event.tint).monospacedDigit()
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(width: 400, height: 84)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(event.tint.opacity(event.urgent ? 0.35 + 0.55 * pulse : 0.45), lineWidth: 1.6))
        .shadow(color: event.tint.opacity(0.35 + 0.25 * pulse), radius: 22, y: 6)
    }
}

final class HUDModel: ObservableObject {
    @Published var event: BatteryEvent = .full
    @Published var shown = false
    @Published var shownAt = Date()
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var body: some View {
        VStack {
            if model.shown {
                TimelineView(.animation) { ctx in
                    HUDCard(event: model.event, t: ctx.date.timeIntervalSince(model.shownAt))
                }
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .scale(scale: 0.85)).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .frame(width: 460, height: 150, alignment: .top)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: model.shown)
    }
}

// MARK: - Window

final class HUDController {
    static let shared = HUDController()
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    private func ensurePanel() -> NSPanel {
        if let p = panel { return p }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: HUDView(model: model))
        host.sizingOptions = []
        p.contentView = host
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar; p.ignoresMouseEvents = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = p
        return p
    }

    func show(_ e: BatteryEvent, force: Bool = false) {
        let c = Prefs.shared.cfg
        guard force || c.hudEnabled else { return }
        if !force {
            switch e {
            case .plugged, .unplugged: if !c.hudPlug { return }
            case .low, .critical, .limit: if !c.hudLow { return }
            case .full: if !c.hudFull { return }
            }
        }
        DispatchQueue.main.async {
            let p = self.ensurePanel()
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let vis = screen.visibleFrame
            p.setFrame(NSRect(x: screen.frame.midX - 230, y: vis.maxY - 150, width: 460, height: 150), display: true)
            self.hideWork?.cancel()
            self.model.event = e
            self.model.shownAt = Date()
            p.orderFrontRegardless()
            self.model.shown = false
            DispatchQueue.main.async { self.model.shown = true }
            let w = DispatchWorkItem { [weak self] in
                self?.model.shown = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.panel?.orderOut(nil) }
            }
            self.hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + e.duration, execute: w)
        }
    }
}
