import Foundation

/// Splits the used space of the startup disk into the APFS volumes macOS keeps,
/// so the disk map can explain what it cannot see.
struct DiskSlice: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let note: String
    let kind: Kind
    enum Kind { case measured, system, vm, boot, hidden, purgeable, other, free }
}

enum APFSInfo {
    private static func plist(_ args: [String]) -> [String: Any]? {
        let r = Shell.run("/usr/sbin/diskutil", args)
        guard r.status == 0, let d = r.output.data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: d, options: [], format: nil)) as? [String: Any]
    }

    /// Used bytes per volume of the container that holds the user's data.
    static func volumes() -> [(name: String, roles: [String], used: Int64)] {
        guard let info = plist(["info", "-plist", "/System/Volumes/Data"]) ?? plist(["info", "-plist", "/"]),
              let container = info["APFSContainerReference"] as? String,
              let list = plist(["apfs", "list", "-plist"]),
              let containers = list["Containers"] as? [[String: Any]],
              let c = containers.first(where: { ($0["ContainerReference"] as? String) == container }),
              let vols = c["Volumes"] as? [[String: Any]] else { return [] }
        return vols.map { v in
            let used = (v["CapacityInUse"] as? NSNumber)?.int64Value ?? 0
            return (v["Name"] as? String ?? "?", v["Roles"] as? [String] ?? [], used)
        }
    }

    /// APFS snapshots of the data volume (Time Machine and other backup tools).
    static func snapshots() -> [String] {
        guard let d = plist(["apfs", "listSnapshots", "-plist", "/System/Volumes/Data"]),
              let list = d["Snapshots"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["SnapshotName"] as? String }
    }

    static func breakdown(measured: Int64, measuredLabel: String, purgeable: Int64 = 0, snapshots: [String] = [], denied: Int = 0) -> [DiskSlice] {
        let vols = volumes()
        guard !vols.isEmpty else { return [] }
        var out = [DiskSlice(name: measuredLabel, size: measured, note: "le cartelle che vedi qui sotto", kind: .measured)]
        var boot: Int64 = 0
        for v in vols {
            if v.roles.contains("Data") {
                let hidden = max(0, v.used - measured)
                let purge = min(hidden, max(0, purgeable))
                if purge > 0 {
                    out.append(DiskSlice(name: "Spazio purgeable", size: purge,
                                         note: "copie locali di iCloud e cache che macOS libera da solo quando serve spazio", kind: .purgeable))
                }
                var why: [String] = []
                if !snapshots.isEmpty { why.append("\(snapshots.count) istantanee APFS che tengono vivi file già cancellati") }
                if denied > 0 { why.append("\(denied) cartelle protette che macOS non ha lasciato leggere") }
                if measuredLabel.contains("Inizio") { why.append("gli altri utenti e le cartelle di sistema (usa «Misura tutto il disco»)") }
                if why.isEmpty { why.append("metadati del file system e file aperti ma già cancellati") }
                out.append(DiskSlice(name: "Non misurabile", size: hidden - purge,
                                     note: why.joined(separator: " · "), kind: .hidden))
            } else if v.roles.contains("System") {
                out.append(DiskSlice(name: "macOS (\(v.name))", size: v.used, note: "il sistema operativo, sigillato: non si tocca", kind: .system))
            } else if v.roles.contains("VM") {
                out.append(DiskSlice(name: "Memoria virtuale", size: v.used, note: "swap e file di sospensione, li gestisce macOS", kind: .vm))
            } else if v.roles.contains("Preboot") || v.roles.contains("Recovery") || v.roles.contains("Update") {
                boot += v.used
            } else if v.used > 0 {
                out.append(DiskSlice(name: v.name, size: v.used, note: "un altro volume nello stesso disco", kind: .other))
            }
        }
        if boot > 0 { out.append(DiskSlice(name: "Avvio e ripristino", size: boot, note: "Preboot e Recovery di macOS", kind: .boot)) }
        return out.filter { $0.size > 0 }
    }
}
