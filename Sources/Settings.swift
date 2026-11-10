import SwiftUI
import ServiceManagement

final class TZPick: ObservableObject { @Published var selected = "Europe/London" }

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var batt: Monitor
    @ObservedObject var nav = SettingsNav.shared
    @ObservedObject var helper = HelperState.shared
    @StateObject private var tz = TZPick()
    @AppStorage("highAlert") var highAlert = true
    @AppStorage("highLimit") var highLimit = 80
    @AppStorage("lowAlert") var lowAlert = true
    @AppStorage("lowLimit") var lowLimit = 20

    var body: some View {
        TabView(selection: $nav.tab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            modules.tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }.tag("menubar")
            layout.tabItem { Label("Layout", systemImage: "rectangle.3.group") }.tag("layout")
            alerts.tabItem { Label("Alerts", systemImage: "bell") }.tag("alerts")
            core.tabItem { Label("Core sensors", systemImage: "cpu") }.tag("core")
            about.tabItem { Label("About", systemImage: "info.circle") }.tag("about")
        }
        .frame(width: 560, height: 560)
    }

    // MARK: General

    var general: some View {
        Form {
            Section("Updates") {
                Picker("Menu bar refresh (dropdown closed)", selection: prefs.binding(\.interval)) {
                    ForEach([2.0, 3.0, 5.0, 10.0, 15.0, 30.0], id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                Text("Longer = less battery use. While a dropdown is open everything updates every second.").font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $batt.launchAtLogin)
                    .onChange(of: batt.launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { batt.launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
            Section("Display") {
                Toggle("Show descriptive labels (Good, Normal, “Sipping power”…)", isOn: prefs.binding(\.descriptiveLabels))
                Toggle("Show wattage next to the battery pill (e.g. 8.7W)", isOn: prefs.binding(\.batteryText))
                Toggle("Include watts in the “69% · 8.7W” text of the other battery styles", isOn: prefs.binding(\.batteryWatts))
                Toggle("Look up public IP address (contacts api.ipify.org)", isOn: prefs.binding(\.publicIP))
            }
            Section("Clock") {
                Toggle("24-hour time", isOn: prefs.binding(\.clock24))
                Toggle("Show seconds", isOn: prefs.binding(\.clockSeconds))
                ForEach(Array(prefs.cfg.timeZones.enumerated()), id: \.offset) { i, id in
                    HStack {
                        Text(id)
                        if i == 0 { Text("(menu bar)").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if i > 0 { Button { prefs.cfg.timeZones.swapAt(i, i - 1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless) }
                        Button { prefs.cfg.timeZones.remove(at: i) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                            .disabled(prefs.cfg.timeZones.count <= 1)
                    }
                }
                HStack {
                    Picker("Add", selection: $tz.selected) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Button("Add") { if !prefs.cfg.timeZones.contains(tz.selected) { prefs.cfg.timeZones.append(tz.selected) } }
                }
            }
        }.formStyle(.grouped)
    }

    // MARK: Modules

    var modules: some View {
        Form {
            Section {
                Text("Turn modules on, choose how each looks in the menu bar, and optionally merge several into one menu bar item. Use the arrows to reorder (top = leftmost).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(prefs.cfg.orderedMods.enumerated()), id: \.element) { idx, m in
                Section {
                    HStack {
                        Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 22)
                        Toggle(m.title, isOn: prefs.binding(m, \.enabled)).font(.headline)
                        Spacer()
                        Button { move(idx, -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless).disabled(idx == 0)
                        Button { move(idx, 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.borderless).disabled(idx == Mod.allCases.count - 1)
                    }
                    if prefs.cfg.cfg(m).enabled {
                        if m.kinds.count > 1 {
                            Picker("Widget", selection: prefs.binding(m, \.widget)) {
                                ForEach(m.kinds) { Text($0.title).tag($0) }
                            }
                        }
                        Toggle("Show label", isOn: prefs.binding(m, \.label))
                        Toggle("Use color", isOn: prefs.binding(m, \.colored))
                        Toggle("Merge into the combined menu bar item", isOn: prefs.binding(m, \.combined))
                        if m == .fans { Text("Fans: this Mac has \(SystemStore.shared.hasFans ? "fans" : "no fans").").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.formStyle(.grouped)
    }

    func move(_ i: Int, _ d: Int) {
        var o = prefs.cfg.orderedMods.map(\.rawValue)
        let j = i + d
        guard o.indices.contains(i), o.indices.contains(j) else { return }
        o.swapAt(i, j)
        prefs.cfg.order = o
    }

    // MARK: Layout

    var layout: some View {
        Form {
            Section {
                Text("Choose which sections each dropdown shows and in what order (top = first). You can also drag sections around inside the dropdown, or right-click one for Move to Top. To move menu bar icons, hold ⌘ and drag them.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Reset layout to default") { prefs.resetLayout() }
            }
            ForEach(Mod.allCases.filter { !defaultSections($0).isEmpty }) { m in
                Section {
                    HStack { Image(systemName: m.icon).foregroundStyle(m.color); Text(m.title).font(.headline) }
                    ForEach(Array(prefs.sections(m).enumerated()), id: \.element) { idx, id in
                        HStack {
                            Toggle(sectionTitle(id), isOn: Binding(get: { !prefs.cfg.hidden.contains(id) }, set: { prefs.setHidden(id, !$0) }))
                            Spacer()
                            Button { prefs.moveSection(id, to: 0) } label: { Image(systemName: "arrow.up.to.line") }.buttonStyle(.borderless).help("Move to top").disabled(idx == 0)
                            Button { prefs.move(id, by: -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless).disabled(idx == 0)
                            Button { prefs.move(id, by: 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.borderless).disabled(idx == prefs.sections(m).count - 1)
                        }
                    }
                }
            }
        }.formStyle(.grouped)
    }

    // MARK: Alerts

    var alerts: some View {
        Form {
            Section("Battery") {
                Toggle("Notify me to unplug at", isOn: $highAlert)
                Stepper("\(highLimit)%", value: $highLimit, in: 50...100, step: 5).disabled(!highAlert)
                Toggle("Notify me to plug in at", isOn: $lowAlert)
                Stepper("\(lowLimit)%", value: $lowLimit, in: 5...50, step: 5).disabled(!lowAlert)
            }
            Section("On-screen animations") {
                Toggle("Show animated pop-ups on screen", isOn: prefs.binding(\.hudEnabled))
                Toggle("When plugged in or unplugged", isOn: prefs.binding(\.hudPlug)).disabled(!prefs.cfg.hudEnabled)
                Toggle("When battery is low or hits the charge limit", isOn: prefs.binding(\.hudLow)).disabled(!prefs.cfg.hudEnabled)
                Toggle("When fully charged", isOn: prefs.binding(\.hudFull)).disabled(!prefs.cfg.hudEnabled)
                HStack {
                    Button("Preview plug-in") { HUDController.shared.show(.plugged(pct: batt.info.percent, adapterW: batt.info.adapterWatts, charging: true), force: true) }
                    Button("Preview low") { HUDController.shared.show(.low(pct: 20, minutes: batt.info.minutesRemaining), force: true) }
                    Button("Preview critical") { HUDController.shared.show(.critical(pct: 5, minutes: batt.info.minutesRemaining), force: true) }
                }
            }
            Section("System") {
                Toggle("CPU usage above", isOn: prefs.binding(\.cpuAlertOn))
                Stepper("\(prefs.cfg.cpuAlertAt)%", value: prefs.binding(\.cpuAlertAt), in: 20...100, step: 5).disabled(!prefs.cfg.cpuAlertOn)
                Toggle("Memory usage above", isOn: prefs.binding(\.ramAlertOn))
                Stepper("\(prefs.cfg.ramAlertAt)%", value: prefs.binding(\.ramAlertAt), in: 20...100, step: 5).disabled(!prefs.cfg.ramAlertOn)
                Toggle("Free disk space below", isOn: prefs.binding(\.diskAlertOn))
                Stepper("\(prefs.cfg.diskAlertGB) GB", value: prefs.binding(\.diskAlertGB), in: 1...500, step: 5).disabled(!prefs.cfg.diskAlertOn)
                Toggle("SoC temperature above", isOn: prefs.binding(\.tempAlertOn))
                Stepper("\(prefs.cfg.tempAlertAt)°C", value: prefs.binding(\.tempAlertAt), in: 50...110, step: 5).disabled(!prefs.cfg.tempAlertOn)
            }
        }.formStyle(.grouped)
    }

    // MARK: Core sensors (admin)

    var core: some View {
        Form {
            Section("What this unlocks") {
                Text("CPU, GPU and Neural Engine power in watts, CPU and GPU frequency, and thermal pressure. macOS only gives these to administrators, so Dewdrop needs a small helper.")
                    .font(.callout)
            }
            Section("What it installs") {
                Text("• A system service (com.rishaan.dewdrop.helper) in /Library/LaunchDaemons that runs Apple's own powermetrics tool.\n• It only samples while the Dewdrop dropdown or dashboard is open, so it does not use battery in the background.\n• It only reads sensors and writes one readable file. It cannot change anything else on your Mac, and you can remove it here at any time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Status") {
                HStack {
                    Image(systemName: helper.installed ? "checkmark.circle.fill" : "circle").foregroundStyle(helper.installed ? jgreen : .secondary)
                    Text(helper.installed ? "Core sensors are installed" : "Not installed")
                    Spacer()
                    if helper.installed {
                        Button("Remove…") { helper.uninstall() }.disabled(helper.busy)
                    } else {
                        Button("Enable… (asks for your password)") { helper.install() }.buttonStyle(.borderedProminent).tint(jgreen).disabled(helper.busy)
                    }
                }
                if !helper.message.isEmpty { Text(helper.message).font(.callout).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped)
    }

    // MARK: About

    var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.batteryblock.fill").font(.system(size: 44)).foregroundStyle(jgreen)
            Text("Battery & System Monitor").font(.title2.bold())
            Text("Version 1.0").foregroundStyle(.secondary)
            Text("Every number comes straight from macOS (IOKit, Mach, SMC, HID sensors, nettop, libproc). Nothing is estimated or invented. Readings that need admin rights (CPU/GPU frequency, per-core power) are not shown.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
