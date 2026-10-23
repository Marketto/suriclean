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
                section("🌿 Rami", "\(d.branches.count) · principale: \(d.defaultBranch)")
                ForEach(d.branches) { b in branchRow(b) }

                section("📦 Stash", d.stashes.isEmpty ? "nessuno ✨" : "\(d.stashes.count)")
                ForEach(d.stashes) { s in stashRow(s) }

                section("🧰 Manutenzione", "cartella .git: \(Fmt.bytes(d.gitSize))")
                HStack(spacing: 10) {
                    Text("Compatta il repo con git gc: riordina gli oggetti e butta via la spazzatura, senza perdere niente.")
                        .font(Theme.font(11.5, .medium)).opacity(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Compatta ✨") { model.runGit(.compact, on: item.url) }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint))
                        .disabled(working)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7)
                    Text("Leggo i rami e gli stash… ♡").font(Theme.font(12.5, .bold)).opacity(0.6)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color.opacity(0.08)))
        .overlay(alignment: .topTrailing) {
            if working && d != nil { ProgressView().scaleEffect(0.6).padding(8) }
        }
        .alert(confirmTitle, isPresented: $showConfirm) {
            Button("Annulla", role: .cancel) { confirm = nil }
            Button("Sì, pulisci ☆", role: .destructive) {
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
            if b.isCurrent { Pill(text: "📍 attuale", color: Theme.sky) }
            if b.merged { Pill(text: "✅ unito", color: Theme.mint) }
            if b.unpushed == 0 { Pill(text: "☁️ tutto sul remote", color: Theme.mint) }
            else { Pill(text: "⬆️ \(b.unpushed) solo qui", color: Theme.coral) }
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
            .help(b.isCurrent ? "È il ramo attuale: non si può eliminare"
                  : (b.canDelete ? "Elimina il ramo (il commit resta annotato per ricrearlo)"
                     : "Ha commit che esistono solo qui: Suri non lo tocca"))
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
            .help("Elimina lo stash (prima ne salvo una copia .patch in Documenti)")
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
        case .deleteBranch(let b)?: return "Eliminare il ramo «\(b.name)»?"
        case .dropStash?: return "Eliminare questo stash?"
        default: return "Confermi?"
        }
    }

    private var confirmText: String {
        switch confirm {
        case .deleteBranch(let b)?:
            return b.merged ? "È già unito al ramo principale. Annoto il commit in Documenti › SuriClean - backup git, così puoi ricrearlo con un comando."
                : "Tutti i suoi commit sono già sul remote. Annoto il commit in Documenti › SuriClean - backup git per ricrearlo."
        case .dropStash(let s)?:
            return "«\(s.message)»: prima ne salvo una copia .patch in Documenti › SuriClean - backup git, poi lo elimino."
        default: return ""
        }
    }
}
