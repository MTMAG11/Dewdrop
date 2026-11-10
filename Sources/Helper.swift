import SwiftUI
import Combine

// MARK: - Core sensors (optional, needs admin once)
//
// CPU/GPU/ANE power, cluster frequencies and thermal pressure are only exposed by `powermetrics`, which needs root.
// Installing the helper creates a small LaunchDaemon that runs powermetrics only while Dewdrop is open.

struct CoreSensors {
    var cpuW: Double?, gpuW: Double?, aneW: Double?, packageW: Double?
    var clusters: [(name: String, mhz: Double)] = []
    var gpuMHz: Double?
    var thermal: String?
}

enum Helper {
    static let label = "com.rishaan.dewdrop.helper"
    static let dir = "/Library/Application Support/Dewdrop"
    static let dataPath = dir + "/power.plist"
    static let daemonPlist = "/Library/LaunchDaemons/\(label).plist"
    static let flag = "/private/tmp/com.rishaan.dewdrop.active"

    static var installed: Bool { FileManager.default.fileExists(atPath: daemonPlist) }

    /// Tell the daemon the app is open (it only samples while this file is fresh)
    static func touch() { FileManager.default.createFile(atPath: flag, contents: Data()) }

    /// Latest sample if it is fresh
    static func read() -> (CoreSensors, Date)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dataPath), let mod = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mod) < 6, var data = FileManager.default.contents(atPath: dataPath) else { return nil }
        if let nul = data.firstIndex(of: 0) { data = data.prefix(upTo: nul) }      // powermetrics may NUL-terminate
        guard let root = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return nil }
        return (parse(root), mod)
    }

    static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    static func mhz(_ hz: Double?) -> Double? { hz.map { $0 > 1e6 ? $0 / 1e6 : $0 } }   // plist reports Hz; tolerate MHz

    static func parse(_ root: [String: Any]) -> CoreSensors {
        var c = CoreSensors()
        let proc = root["processor"] as? [String: Any] ?? [:]
        let gpu = root["gpu"] as? [String: Any] ?? [:]
        let ane = root["ane"] as? [String: Any] ?? [:]
        let elapsedMs = (num(root["elapsed_ns"]) ?? 0) / 1e6
        func watts(_ powerKey: String, _ energyKey: String, in dicts: [[String: Any]]) -> Double? {
            for d in dicts {
                if let mw = num(d[powerKey]) { return mw / 1000 }                                   // mW
                if let mj = num(d[energyKey]), elapsedMs > 0 { return mj / elapsedMs }              // mJ per ms = W
            }
            return nil
        }
        c.cpuW = watts("cpu_power", "cpu_energy", in: [proc, root])
        c.gpuW = watts("gpu_power", "gpu_energy", in: [proc, gpu, root])
        c.aneW = watts("ane_power", "ane_energy", in: [proc, ane, root])
        c.packageW = watts("combined_power", "package_energy", in: [proc, root])
        if let clusters = proc["clusters"] as? [[String: Any]] {
            for cl in clusters {
                let name = cl["name"] as? String ?? "Cluster"
                var f = mhz(num(cl["freq_hz"]))
                if f == nil, let cpus = cl["cpus"] as? [[String: Any]] {
                    let fs = cpus.compactMap { mhz(num($0["freq_hz"])) }
                    if !fs.isEmpty { f = fs.reduce(0, +) / Double(fs.count) }
                }
                if let f { c.clusters.append((name, f)) }
            }
        }
        c.gpuMHz = mhz(num(gpu["freq_hz"]))
        c.thermal = root["thermal_pressure"] as? String
        return c
    }

    // MARK: install / remove (macOS shows its own admin password prompt)

    static func runAdmin(_ script: String) -> (ok: Bool, msg: String) {
        let apple = "on run argv\ndo shell script (item 1 of argv) with administrator privileges\nend run"
        let out = runCmd("/usr/bin/osascript", ["-e", apple, script], timeout: 180, mergeErr: true).trimmingCharacters(in: .whitespacesAndNewlines)
        return (installed, out.contains("-128") ? "Cancelled." : out)
    }

    static func installScript() -> String? {
        guard let res = Bundle.main.resourcePath else { return nil }
        return """
        set -e
        mkdir -p "\(dir)"
        rm -f "\(dir)/dewdrop-helper.sh"
        cp "\(res)/dewdrop-helper.pl" "\(dir)/dewdrop-helper.pl"
        chown root:wheel "\(dir)" "\(dir)/dewdrop-helper.pl"
        chmod 755 "\(dir)" "\(dir)/dewdrop-helper.pl"
        cp "\(res)/\(label).plist" "\(daemonPlist)"
        chown root:wheel "\(daemonPlist)"
        chmod 644 "\(daemonPlist)"
        launchctl bootout system/\(label) 2>/dev/null || true
        launchctl bootstrap system "\(daemonPlist)"
        """
    }

    static let uninstallScript = """
    launchctl bootout system/\(label) 2>/dev/null || true
    rm -f "\(daemonPlist)"
    rm -rf "\(dir)"
    """
}

final class HelperState: ObservableObject {
    static let shared = HelperState()
    @Published var installed = Helper.installed
    @Published var busy = false
    @Published var message = ""

    func refresh() { installed = Helper.installed }

    func install() {
        guard !busy, let script = Helper.installScript() else { message = "Could not locate the helper files inside the app."; return }
        busy = true; message = "Waiting for administrator approval…"
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Helper.runAdmin(script)
            DispatchQueue.main.async {
                self.busy = false; self.refresh()
                self.message = self.installed ? "Core sensors are on. They update while Dewdrop is open." : (r.msg == "Cancelled." || r.msg.isEmpty ? "Cancelled." : "Failed: " + r.msg)
            }
        }
    }

    func uninstall() {
        guard !busy else { return }
        busy = true; message = "Waiting for administrator approval…"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Helper.runAdmin(Helper.uninstallScript)
            DispatchQueue.main.async {
                self.busy = false; self.refresh()
                self.message = self.installed ? "Not removed." : "Core sensors removed."
            }
        }
    }
}

/// Card shown in popups/dashboard when the helper is not installed
struct CoreSensorsHint: View {
    @ObservedObject var st = HelperState.shared
    var body: some View {
        if !st.installed {
            VStack(alignment: .leading, spacing: 8) {
                Text("CPU watts and frequency need admin rights.").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text("Turn on Core sensors once (macOS asks for your password). It only runs while Dewdrop is open.").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Set up core sensors…") { SettingsNav.shared.tab = "core"; openSettingsWindow() }
                    .buttonStyle(.borderedProminent).tint(jgreen)
            }
        }
    }
}

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab = "general"
}
