import SwiftUI
import AppKit

/// «Pulisci»: everything that can go without worries, already ticked, grouped by zone.
/// The user unticks what to keep, then everything ticked goes to the Trash.
struct QuickCleanSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var open: Set<CleanCategory> = []
    @State private var emptyAfter = false

    var body: some View {
        let groups = model.quickGroups
        let all = groups.flatMap { $0.items }
        let picked = all.filter { model.quickPick.contains($0.id) }
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                MeerkatView(activity: .sweeping, size: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("mac.quick.title")).font(Theme.font(22, .heavy))
                    Text(t("mac.quick.intro")).font(Theme.font(12.5, .medium)).opacity(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 10)

            HStack(spacing: 10) {
                Button(t("mac.quick.all")) { model.toggleQuick(all.map { $0.id }, on: true) }
                    .buttonStyle(BubblyButtonStyle(color: Theme.mint))
                Button(t("mac.quick.none")) { model.toggleQuick(all.map { $0.id }, on: false) }
                    .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                Spacer()
                Text(t("mac.quick.count", picked.count, all.count)).font(Theme.font(12, .bold)).opacity(0.55)
            }
            .padding(.horizontal, 22).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(groups) { g in group(g.category, g.items) }
                }
                .padding(.horizontal, 22).padding(.vertical, 6)
            }
            .frame(minHeight: 260, maxHeight: 440)

            VStack(spacing: 10) {
                Toggle(isOn: $emptyAfter) {
                    Text(model.trashSize > 0 ? t("mac.quick.empty.more", Fmt.bytes(model.trashSize)) : t("mac.quick.empty"))
                        .font(Theme.font(12, .semibold))
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(emptyAfter ? t("mac.quick.note.forever") : t("mac.quick.note.trash"))
                    .font(Theme.font(11, .medium)).opacity(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(t("mac.common.cancel")) { model.showQuickClean = false }
                        .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    Spacer()
                    Text(Fmt.bytes(picked.totalSize)).font(Theme.font(20, .heavy)).foregroundColor(Theme.mint.darker)
                    Button(action: { model.runQuickClean(emptyTrashAfter: emptyAfter) }) {
                        Label(t("mac.quick.go"), systemImage: "sparkles")
                    }
                    .buttonStyle(BubblyButtonStyle(color: Theme.pink, big: true))
                    .disabled(picked.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(Color.white.opacity(0.55))
        }
        .frame(width: 660)
        .foregroundColor(Theme.cocoa)
        .background(Theme.cream)
    }

    private func group(_ c: CleanCategory, _ items: [CleanItem]) -> some View {
        let ids = items.map { $0.id }
        let n = ids.filter { model.quickPick.contains($0) }.count
        let expanded = open.contains(c)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: { model.toggleQuick(ids, on: n < ids.count) }) {
                    KawaiiCheckbox(on: n == ids.count, color: c.color, partial: n > 0)
                }
                .buttonStyle(.plain)
                IconBlob(symbol: c.icon, color: c.color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title).font(Theme.font(14, .heavy))
                    Text(t("mac.quick.count", n, ids.count)).font(Theme.font(11, .semibold)).opacity(0.55)
                }
                Spacer()
                Text(Fmt.bytes(items.filter { model.quickPick.contains($0.id) }.totalSize)).font(Theme.font(14, .heavy))
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if expanded { open.remove(c) } else { open.insert(c) }
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(c.color.darker)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? t("mac.quick.hide") : t("mac.quick.show"))
            }
            if expanded {
                VStack(spacing: 4) {
                    ForEach(items) { it in row(it, c.color) }
                }
                .padding(.leading, 34)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.75)))
    }

    private func row(_ it: CleanItem, _ color: Color) -> some View {
        let on = model.quickPick.contains(it.id)
        return HStack(spacing: 10) {
            KawaiiCheckbox(on: on, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(it.name).font(Theme.font(12.5, .bold)).lineLimit(1)
                Text(it.detail.isEmpty ? FS.pretty(it.url) : it.detail)
                    .font(Theme.font(10.5, .medium)).opacity(0.55)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Text(Fmt.bytes(it.size)).font(Theme.font(12.5, .heavy))
            RoundIconButton(symbol: "magnifyingglass", color: color.darker) {
                NSWorkspace.shared.activateFileViewerSelecting([it.url])
            }
            .help(t("mac.reveal"))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleQuick([it.id], on: !on) }
        .opacity(on ? 1 : 0.6)
    }
}

/// «Cosa cresce»: which folders grew since an earlier scan, and how much grew outside the home folder.
struct GrowthSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                MeerkatView(activity: .detective, size: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("mac.grow.title")).font(Theme.font(22, .heavy))
                    if let g = model.growth {
                        Text(t("mac.grow.since", Fmt.relative(g.since))).font(Theme.font(12.5, .medium)).opacity(0.7)
                    }
                }
            }
            if let g = model.growth {
                HStack(spacing: 10) {
                    stat(t("mac.grow.disk"), g.usedDelta, Theme.pink)
                    stat(t("mac.grow.home"), g.homeDelta, Theme.mint)
                    stat(t("mac.grow.outside"), g.outside, Theme.sky)
                }
                if g.top.isEmpty {
                    Text(t("mac.grow.notop")).font(Theme.font(12.5, .medium)).opacity(0.7)
                } else {
                    Text(t("mac.grow.top")).font(Theme.font(15, .heavy))
                    VStack(spacing: 6) {
                        ForEach(g.top) { e in
                            let url = URL(fileURLWithPath: e.path)
                            HStack(spacing: 10) {
                                IconBlob(symbol: "arrow.up.right", color: Theme.coral, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(url.lastPathComponent).font(Theme.font(13, .bold)).lineLimit(1)
                                        if let b = Scanners.hiddenBadge(e.path) { Pill(text: b, color: Theme.coral) }
                                    }
                                    Text(FS.pretty(url)).font(Theme.font(10.5, .medium)).opacity(0.55)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text("+" + Fmt.bytes(e.delta)).font(Theme.font(13.5, .heavy)).foregroundColor(Theme.coral.darker)
                                RoundIconButton(symbol: "magnifyingglass", color: Theme.coral.darker) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .help(t("mac.reveal"))
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.75)))
                }
                if g.outside >= Growth.minShown {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("mac.grow.outside.title", Fmt.bytes(g.outside))).font(Theme.font(14, .heavy))
                        Text(t("mac.grow.outside.text", Fmt.bytes(model.swapSize), model.snapshotCount ?? 0))
                            .font(Theme.font(11.5, .medium)).opacity(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button(t("mac.grow.measure")) { model.showGrowth = false; model.scanFullDisk() }
                                .buttonStyle(BubblyButtonStyle(color: Theme.sky))
                            if (model.snapshotCount ?? 0) > 0 {
                                Button(t("mac.tips.snaps.btn")) { model.showGrowth = false; model.thinSnapshots() }
                                    .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.sky.opacity(0.15)))
                }
            } else {
                Text(t("mac.grow.first")).font(Theme.font(12.5, .medium)).opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(t("legal.close")) { model.showGrowth = false }
                    .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 600)
        .foregroundColor(Theme.cocoa)
        .background(Theme.cream)
    }

    private func stat(_ label: String, _ v: Int64, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((v >= 0 ? "+" : "−") + Fmt.bytes(abs(v))).font(Theme.font(18, .heavy)).foregroundColor(c.darker)
            Text(label).font(Theme.font(11, .semibold)).opacity(0.6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.opacity(0.15)))
    }
}
