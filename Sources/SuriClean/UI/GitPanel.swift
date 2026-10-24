import SwiftUI
import AppKit

/// Expanded view of a git repo: branches, stashes and maintenance, each with a safe clean-up.
struct GitRepoPanel: View {
    let item: CleanItem
    let color: Color
    @EnvironmentObject var model: AppModel
    @State private var confirm: AppModel.GitAction?
    @State private var showConfirm = false

    var body: some View {
        let d = model.gitDetails[item.url]
        let working = model.gitWorking.contains(item.url)
        VStack(alignment: .leading, spacing: 10) {
            if let d = d {
                section(t("mac.gitp.branches"), t("mac.gitp.branches.sub", d.branches.count, d.defaultBranch))
                ForEach(d.branches) { b in branchRow(b) }

                section(t("mac.gitp.stash"), d.stashes.isEmpty ? t("mac.gitp.none") : "\(d.stashes.count)")
                ForEach(d.stashes) { s in stashRow(s) }

                section(t("mac.gitp.maint"), t("mac.gitp.gitsize", Fmt.bytes(d.gitSize)))
                HStack(spacing: 10) {
                    Text(t("mac.gitp.gc.text"))
                        .font(Theme.font(11.5, .medium)).opacity(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(t("mac.gitp.gc")) { model.runGit(.compact, on: item.url) }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint))
                        .disabled(working)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7)
                    Text(t("mac.gitp.loading")).font(Theme.font(12.5, .bold)).opacity(0.6)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color.opacity(0.08)))
        .overlay(alignment: .topTrailing) {
            if working && d != nil { ProgressView().scaleEffect(0.6).padding(8) }
        }
        .alert(confirmTitle, isPresented: $showConfirm) {
            Button(t("mac.common.cancel"), role: .cancel) { confirm = nil }
            Button(t("mac.gitp.ok"), role: .destructive) {
                if let a = confirm { model.runGit(a, on: item.url) }
                confirm = nil
            }
        } message: {
            Text(confirmText)
        }
    }

    private func section(_ title: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Theme.font(13.5, .heavy))
            Text(note).font(Theme.font(11, .bold)).opacity(0.5)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func branchRow(_ b: GitBranch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11, weight: .bold)).foregroundColor(color.darker)
            Text(b.name).font(Theme.font(12.5, .bold)).lineLimit(1).truncationMode(.middle)
            if b.isCurrent { Pill(text: t("mac.gitp.current"), color: Theme.sky) }
            if b.merged { Pill(text: t("mac.gitp.merged"), color: Theme.mint) }
            if b.unpushed == 0 { Pill(text: t("mac.gitp.pushed"), color: Theme.mint) }
            else { Pill(text: t("mac.gitp.onlyhere", b.unpushed), color: Theme.coral) }
            Text(Fmt.relative(b.date)).font(Theme.font(10.5, .semibold)).opacity(0.5)
            Spacer()
            Button(action: { ask(.deleteBranch(b)) }) {
                Image(systemName: "scissors").font(.system(size: 12, weight: .bold))
                    .foregroundColor(b.canDelete ? Theme.coral.darker : Theme.cocoa.opacity(0.25))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .disabled(!b.canDelete || model.gitWorking.contains(item.url))
            .help(b.isCurrent ? t("mac.gitp.h.current")
                  : (b.canDelete ? t("mac.gitp.h.delete")
                     : t("mac.gitp.h.unique")))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.75)))
    }

    private func stashRow(_ s: GitStash) -> some View {
        HStack(spacing: 8) {
            Text("📦").font(.system(size: 12))
            Text(s.message).font(Theme.font(12.5, .bold)).lineLimit(1).truncationMode(.tail)
            Text("\(s.id) · \(Fmt.relative(s.date))").font(Theme.font(10.5, .semibold)).opacity(0.5)
            Spacer()
            Button(action: { ask(.dropStash(s)) }) {
                Image(systemName: "trash").font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.coral.darker)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .disabled(model.gitWorking.contains(item.url))
            .help(t("mac.gitp.h.stash"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.75)))
    }

    private func ask(_ a: AppModel.GitAction) {
        Chiptune.shared.sfx(.pop)
        confirm = a
        showConfirm = true
    }

    private var confirmTitle: String {
        switch confirm {
        case .deleteBranch(let b)?: return t("mac.gitp.q.branch", b.name)
        case .dropStash?: return t("mac.gitp.q.stash")
        default: return t("mac.gitp.q.confirm")
        }
    }

    private var confirmText: String {
        switch confirm {
        case .deleteBranch(let b)?:
            return b.merged ? t("mac.gitp.m.merged")
                : t("mac.gitp.m.pushed")
        case .dropStash(let s)?:
            return t("mac.gitp.m.stash", s.message)
        default: return ""
        }
    }
}
