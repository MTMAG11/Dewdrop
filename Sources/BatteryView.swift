import SwiftUI
import Charts

struct BatteryContent: View {
    @ObservedObject var m: Monitor
    @ObservedObject var prefs = Prefs.shared
    @AppStorage("range") var range = 1

    var i: BatteryInfo { m.info }
    var desc: Bool { prefs.cfg.descriptiveLabels }

    var stateText: String {
        if i.fullyCharged || (i.pluggedIn && !i.isCharging && i.percent >= 99) { return "Fully Charged" }
        if i.isCharging { return "Charging" }
        if i.pluggedIn { return "Plugged In" }
        return "On Battery"
    }
    var tint: Color { i.percent <= 20 && !i.pluggedIn ? .red : (i.percent <= 40 && !i.pluggedIn ? .orange : jgreen) }
    var timeLabel: String { i.isCharging ? "UNTIL FULL" : "TIME LEFT" }
    var timeValue: String { (i.pluggedIn && !i.isCharging) ? "—" : fmtTime(i.minutesRemaining) }
    var healthColor: Color { i.health >= 80 ? jgreen : (i.health >= 70 ? .yellow : .red) }

    var healthWord: String { i.health >= 80 ? "Good" : "Reduced" }
    func tempWord(_ t: Double) -> (String, String, Color) {
        if t < 40 { return ("Normal", "Optimal performance", jgreen) }
        if t < 45 { return ("Warm", "Charging may slow down", .yellow) }
        return ("Hot", "Performance may be reduced", .red)
    }
    var wattWord: String {
        let w = i.pluggedIn ? i.systemLoad : abs(i.batteryPower)
        if w < 5 { return "Sipping power: idle or light tasks" }
        if w < 15 { return "Light use: typical for web and docs" }
        if w < 30 { return "Moderate use: media, light work" }
        return "Heavy use: demanding tasks"
    }

    var body: some View {
        VStack(spacing: 10) { SectionList(mod: .battery) { AnyView(section($0)) } }
    }

    @ViewBuilder func section(_ id: String) -> some View {
        switch id {
        case "header": header
        case "info": info
        case "energy": energy
        case "devices": if m.devices.contains(where: { !$0.levels.isEmpty }) { devices }
        case "sessions": sessionsSection
        case "history": historySection
        default: EmptyView()
        }
    }

    // MARK: header card

    var header: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(i.percent)").font(.system(size: 50, weight: .bold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
                            Text("%").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(tint.opacity(0.85))
                        }
                        HStack(spacing: 8) {
                            if i.isCharging { Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(tint) }
                            else { RoundedRectangle(cornerRadius: 3.5).fill(tint).frame(width: 22, height: 11) }
                            Text(stateText).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(timeLabel).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                        Text(timeValue).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                    }.padding(.top, 10)
                }
                FillBar(frac: Double(i.percent) / 100, color: tint, height: 8, ticks: true)
            }.padding(16)
        }
    }

    // MARK: battery information

    var info: some View {
        Collapsible(id: "info", title: "Battery Information", icon: "info.circle.fill", color: .blue) {
            Block(title: "Battery Health", icon: "checkmark.circle.fill", color: healthColor,
                  info: "Maximum capacity compared with the battery's design capacity.") {
                HStack(alignment: .lastTextBaseline) {
                    Text(String(format: "%.0f%%", min(100, i.health))).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(healthColor)
                    if desc { Text(healthWord).font(.system(size: 14, weight: .semibold)).foregroundStyle(healthColor) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(i.cycles)/\(i.designCycles)").font(mono(16, .bold)).foregroundStyle(.white)
                        Text("Cycle Count").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                FillBar(frac: i.health / 100, color: healthColor, height: 8)
            }
            if let t = i.temperature {
                Divide()
                let w = tempWord(t)
                Block(title: "Temperature", icon: desc ? "checkmark.circle.fill" : "thermometer.medium", color: desc ? w.2 : .orange,
                      info: "Battery temperature reported by the battery gauge.") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: "thermometer.medium").font(.system(size: 22)).foregroundStyle(w.2)
                                Text(String(format: "%.1f°C", t)).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(w.2)
                            }
                            Text(String(format: "%.1f°F", t * 9 / 5 + 32)).font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if desc {
                            VStack(alignment: .trailing, spacing: 3) {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(w.2)
                                    Text(w.0).font(.system(size: 15, weight: .semibold)).foregroundStyle(w.2)
                                }
                                Text(w.1).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                            }.padding(.top, 6)
                        }
                    }
                }
            }
            Divide()
            Block(title: "Power & Electrical", icon: "bolt.circle.fill", color: .orange,
                  info: "Live readings from the battery gauge and power telemetry.") {
                HStack(alignment: .top) {
                    Stat(label: i.displayLabel, value: String(format: "%.1f", i.displayWatts), unit: "W",
                         color: i.holdingAtLimit ? .cyan : (i.batteryPower >= 0 ? jgreen : .white))
                    Stat(label: "Voltage", value: String(format: "%.2f", i.voltage), unit: "V", trailing: true)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(i.amperage >= 0 ? "Current In" : "Current Out").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(String(format: "%.0f", abs(i.amperage) * 1000)).font(mono(20, .bold)).foregroundStyle(.white)
                            Text("mA").font(mono(16, .bold)).foregroundStyle(.white)
                            Image(systemName: i.amperage >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill").foregroundStyle(i.amperage >= 0 ? jgreen : Color.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            if i.isCharging { Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(jgreen) }
                            else { RoundedRectangle(cornerRadius: 2.5).stroke(.white, lineWidth: 1.5).frame(width: 15, height: 8) }
                            Text(i.isCharging ? "Charging" : (i.pluggedIn ? "Plugged In" : "Discharging")).font(.system(size: 14, weight: .semibold)).foregroundStyle(i.isCharging ? jgreen : .white)
                        }
                        if desc, let lo = i.lifeMinPackV, let hi = i.lifeMaxPackV, i.voltage >= lo, i.voltage <= hi {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                                Text("Normal voltage").font(.system(size: 11, weight: .medium))
                            }.foregroundStyle(jgreen)
                        }
                    }
                }
                if i.pluggedIn && (i.adapterWatts > 0 || i.adapterVolts > 0) {
                    HStack(alignment: .top) {
                        if i.adapterWatts > 0 { Stat(label: "Adapter", value: "\(i.adapterWatts)", unit: "W", color: .orange) }
                        if i.adapterVolts > 0 { Stat(label: "Adapter Input", value: String(format: "%.1f", i.adapterVolts), unit: "V", color: .orange, trailing: true) }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HistChart(values: Array(m.live.suffix(60)).map { i.pluggedIn ? $0.wall : abs($0.battery) }, color: i.pluggedIn ? .yellow : .orange, height: 64)
                    Text(i.pluggedIn ? "Wall power, last minute" : "Power draw, last minute").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                flow
            }
            Divide()
            Block(title: "Capacity Details", icon: "battery.100percent", color: .blue) {
                LineRow(label: "Remaining", value: "\(i.currentCapacity) mAh", color: jgreen)
                LineRow(label: "Current Full", value: "\(i.maxCapacity) mAh", color: .cyan)
                LineRow(label: "Design Capacity", value: "\(i.designCapacity) mAh")
                if let lo = i.dailyMinSoc, let hi = i.dailyMaxSoc, hi > 0 { LineRow(label: "Today's charge range", value: "\(lo)% – \(hi)%", color: .purple) }
            }
            if i.lifeMaxTemp != nil {
                Divide()
                Block(title: "Lifetime (battery gauge)", icon: "clock.arrow.circlepath", color: .pink) {
                    if let lo = i.lifeMinTemp, let hi = i.lifeMaxTemp { LineRow(label: "Temperature range", value: "\(lo)°C – \(hi)°C", color: .orange) }
                    if let lo = i.lifeMinPackV, let hi = i.lifeMaxPackV { LineRow(label: "Pack voltage range", value: String(format: "%.2f – %.2f V", lo, hi), color: .yellow) }
                    if let c = i.lifeMaxChargeA { LineRow(label: "Max charge current", value: String(format: "%.2f A", c), color: jgreen) }
                    if let c = i.lifeMaxDischargeA { LineRow(label: "Max discharge current", value: String(format: "%.2f A", c), color: .orange) }
                }
            }
        }
    }

    // MARK: power flow (reference layout: [source] [watts] [system])

    var flow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "circle.hexagongrid").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Power Flow").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            if i.pluggedIn { pluggedFlow } else { batteryFlow }
            caption
            if i.pluggedIn && i.adapterWatts > 0 {
                HStack(spacing: 8) {
                    infoTile("CHARGER", "\(i.adapterWatts) W")
                    if i.adapterContractV > 0 {
                        infoTile("NEGOTIATED", String(format: "%.0f V · %.1f A", i.adapterContractV, i.adapterContractA))
                    }
                }
            }
        }
    }

    func infoTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(.white.opacity(0.85))
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    var batteryFlow: some View {
        HStack(spacing: 6) {
            VStack(spacing: 4) {
                Image(systemName: "battery.50percent").font(.system(size: 16)).foregroundStyle(.white.opacity(0.85))
                Text("Batt").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }.frame(width: 54, height: 78).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.42), Color(white: 0.16)], startPoint: .leading, endPoint: .trailing))
                Text(String(format: "%.1f W", abs(i.batteryPower))).font(mono(19, .bold)).foregroundStyle(.white)
            }.frame(height: 78)
            VStack(spacing: 4) {
                Image(systemName: "laptopcomputer").font(.system(size: 18)).foregroundStyle(.white.opacity(0.85))
            }.frame(width: 54, height: 78).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Plugged in: [adapter total] → [into battery / system, stacked by share] → [battery icon / laptop icon]
    var pluggedFlow: some View {
        let batt = i.batteryPower
        let sys = i.systemLoad
        let total = max(abs(batt) + sys, 0.1)
        let totalH: CGFloat = 132
        let topH = min(max(totalH * CGFloat(abs(batt) / total), 40), totalH - 40 - 6)
        let botH = totalH - topH - 6
        let charging = batt >= 0
        return HStack(spacing: 6) {
            VStack(spacing: 6) {
                Image(systemName: "powerplug.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.9))
                Text(String(format: "%.0fW", i.adapterIn)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }.frame(width: 56, height: totalH).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(LinearGradient(
                        colors: charging ? [Color(red: 0.03, green: 0.30, blue: 0.14), Color(red: 0.07, green: 0.42, blue: 0.20)] : [Color(red: 0.35, green: 0.18, blue: 0.03), Color(red: 0.5, green: 0.28, blue: 0.05)],
                        startPoint: .bottom, endPoint: .top))
                    Text(String(format: "%.1f W", abs(batt))).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }.frame(height: topH)
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.32)], startPoint: .bottom, endPoint: .top))
                    Text(String(format: "%.1f W", sys)).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }.frame(height: botH)
            }
            VStack(spacing: 6) {
                Image(systemName: charging ? "battery.100percent.bolt" : "battery.50percent").font(.system(size: 18))
                    .foregroundStyle(charging ? jgreen : .orange).frame(width: 56, height: topH)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                Image(systemName: "laptopcomputer").font(.system(size: 18)).foregroundStyle(.white.opacity(0.85)).frame(width: 56, height: botH)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    var caption: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                if i.pluggedIn && i.isCharging { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(jgreen) }
                else { RoundedRectangle(cornerRadius: 2.5).stroke(.white, lineWidth: 1.4).frame(width: 14, height: 8) }
                Text(i.pluggedIn
                     ? ((i.isCharging && !i.holdingAtLimit) ? String(format: "Charging at %.0f W", i.batteryPower) : "Plugged in · not drawing from the battery")
                     : String(format: "On battery • %.0f W", abs(i.batteryPower)))
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            }
            if desc { Text(wattWord).font(.system(size: 11)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity)
    }

    // MARK: energy / devices / history

    var energy: some View {
        Collapsible(id: "energy", title: "Apps Using Significant Energy", icon: "bolt.circle", color: .white) {
            if m.energy.isEmpty { Text("No apps using significant energy right now.").font(.system(size: 13)).foregroundStyle(.secondary) }
            ProcRowsE(apps: m.energy)
            Text("Energy Impact, as shown in Activity Monitor.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    var devices: some View {
        Collapsible(id: "devices", title: "Connected Devices", icon: "iphone", color: .white) {
            ForEach(m.devices.filter { !$0.levels.isEmpty }) { d in DeviceRow(d: d) }
        }
    }

    var healthLine: String {
        let h = m.healthHistory
        guard let first = h.first, let last = h.last, h.count >= 2 else { return "Battery health is saved once a day. The trend appears after the second day." }
        let d = last.health - first.health
        return String(format: "Health %.1f%% → %.1f%% since %@ (%+.1f)", first.health, last.health, first.day.formatted(.dateTime.day().month(.abbreviated)), d)
    }

    var sessionsSection: some View {
        Collapsible(id: "sessions", title: "Charge History", icon: "bolt.badge.clock", color: .yellow) {
            if m.sessions.isEmpty {
                Text("Charging and on-battery sessions are logged here. Nothing recorded yet.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(Array(m.sessions.suffix(5).reversed())) { SessionRowView(s: $0) }
            Divide()
            Text(healthLine).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    var cutoff: Date { Date(timeIntervalSinceNow: -[3600.0, 21600, 86400, 604800][range]) }

    var historySection: some View {
        let data = m.history.filter { $0.t >= cutoff }
        return Collapsible(id: "history", title: "History", icon: "chart.xyaxis.line", color: jgreen) {
            Picker("", selection: $range) {
                Text("1h").tag(0); Text("6h").tag(1); Text("24h").tag(2); Text("7d").tag(3)
            }.pickerStyle(.segmented).labelsHidden()
            Block(title: "Charge level", icon: "battery.75percent", color: jgreen) {
                Chart(data) { LineMark(x: .value("t", $0.t), y: .value("%", $0.pct)).foregroundStyle(jgreen).interpolationMethod(.monotone) }
                    .chartYScale(domain: 0...100).frame(height: 100)
            }
            Block(title: "Power  (+ in / − out)", icon: "bolt.fill", color: .orange) {
                Chart(data) { AreaMark(x: .value("t", $0.t), y: .value("W", $0.watts))
                    .foregroundStyle(LinearGradient(colors: [.orange, .orange.opacity(0.1)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone) }
                    .frame(height: 100)
            }
            last24
            if data.count < 2 { Text("History builds up as the app runs (one point per minute).").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }

    var last24: some View {
        let d = m.history.filter { $0.t >= Date(timeIntervalSinceNow: -86400) }
        let out = d.filter { $0.watts < 0 && !$0.charging }
        let inn = d.filter { $0.charging && $0.watts > 0 }
        return Block(title: "Measured by this app (24h)", icon: "chart.bar.fill", color: .pink) {
            if d.count < 2 {
                Text("Collecting samples, one per minute.").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                if !out.isEmpty {
                    LineRow(label: "Avg battery draw", value: String(format: "%.1f W", out.map { -$0.watts }.reduce(0, +) / Double(out.count)), color: .orange)
                    LineRow(label: "Peak battery draw", value: String(format: "%.1f W", out.map { -$0.watts }.max() ?? 0), color: .orange)
                    LineRow(label: "Battery energy used", value: String(format: "%.2f Wh", out.map { -$0.watts }.reduce(0, +) / 60), color: .orange)
                    LineRow(label: "Time on battery", value: "\(out.count) min")
                }
                if !inn.isEmpty {
                    LineRow(label: "Peak charge rate", value: String(format: "%.1f W", inn.map(\.watts).max() ?? 0), color: jgreen)
                    LineRow(label: "Time charging", value: "\(inn.count) min", color: jgreen)
                }
            }
        }
    }
}

struct SessionRowView: View {
    let s: ChargeSession
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: s.isCharge ? "bolt.fill" : "battery.50percent").foregroundStyle(s.isCharge ? jgreen : .orange).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(fmtDuration(s.minutes) + (s.isCharge ? " · charging" : " · on battery")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(s.startPct)% → \(s.endPct)%").font(mono(13, .bold)).foregroundStyle(.white)
                Text(String(format: "%.1f Wh · avg %.1f W", s.wh, s.avgW)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProcRowsE: View {
    let apps: [EnergyApp]
    var body: some View {
        let top = max(apps.first?.impact ?? 1, 1)
        ForEach(apps) { a in
            HStack(spacing: 10) {
                Text(a.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                FillBar(frac: a.impact / top, color: .orange, height: 5).frame(width: 56)
                Text(String(format: "%.0f", a.impact)).font(mono(12, .bold)).foregroundStyle(.orange).frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - Footer rows (Settings / Battery Settings / Low Power Mode / Quit)

struct PopupFooter: View {
    @ObservedObject var m: Monitor
    var showBattery: Bool
    var page: Page = .overview
    var body: some View {
        CardBox {
            VStack(spacing: 0) {
                MenuRow(icon: "macwindow", title: "Open Dashboard…") { openDashboard(page) }
                Divide()
                MenuRow(icon: "gearshape.fill", title: "Settings…") { openSettingsWindow() }
                if showBattery {
                    Divide()
                    MenuRow(icon: "battery.100percent", title: "Battery Settings…") {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(u) }
                    }
                    Divide()
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill").font(.system(size: 14, weight: .semibold)).frame(width: 22).foregroundStyle(.yellow)
                        Text("Low Power Mode").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Toggle("", isOn: Binding(get: { m.lowPower }, set: { m.setLowPower($0) })).labelsHidden().toggleStyle(.switch).tint(jgreen)
                    }.padding(.horizontal, 14).padding(.vertical, 9)
                }
                Divide()
                MenuRow(icon: "power", title: "Quit", color: .red, trailing: "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")) { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
