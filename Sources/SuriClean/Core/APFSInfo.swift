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
        var out = [DiskSlice(name: measuredLabel, size: measured, note: t("mac.slice.measured.note"), kind: .measured)]
        var boot: Int64 = 0
        for v in vols {
            if v.roles.contains("Data") {
                let hidden = max(0, v.used - measured)
                let purge = min(hidden, max(0, purgeable))
                if purge > 0 {
                    out.append(DiskSlice(name: t("mac.slice.purge"), size: purge,
                                         note: t("mac.slice.purge.note"), kind: .purgeable))
                }
                var why: [String] = []
                if !snapshots.isEmpty { why.append(t("mac.slice.why.snaps", snapshots.count)) }
                if denied > 0 { why.append(t("mac.slice.why.denied", denied)) }
                if measuredLabel == t("mac.slice.home") { why.append(t("mac.slice.why.others")) }
                if why.isEmpty { why.append(t("mac.slice.why.meta")) }
                out.append(DiskSlice(name: t("mac.slice.hidden"), size: hidden - purge,
                                     note: why.joined(separator: " · "), kind: .hidden))
            } else if v.roles.contains("System") {
                out.append(DiskSlice(name: "macOS (\(v.name))", size: v.used, note: t("mac.slice.system.note"), kind: .system))
            } else if v.roles.contains("VM") {
                out.append(DiskSlice(name: t("mac.slice.vm"), size: v.used, note: t("mac.slice.vm.note"), kind: .vm))
            } else if v.roles.contains("Preboot") || v.roles.contains("Recovery") || v.roles.contains("Update") {
                boot += v.used
            } else if v.used > 0 {
                out.append(DiskSlice(name: v.name, size: v.used, note: t("mac.slice.other.note"), kind: .other))
            }
        }
        if boot > 0 { out.append(DiskSlice(name: t("mac.slice.boot"), size: boot, note: t("mac.slice.boot.note"), kind: .boot)) }
        return out.filter { $0.size > 0 }
    }
}
