import SwiftUI
import AppKit

/// Walks the user through granting Full Disk Access (macOS cannot show a yes/no prompt for it)
/// and notices by itself when the permission arrives.
struct FDAGuide: View {
    @EnvironmentObject var model: AppModel
    @State private var granted = FS.hasFullDiskAccess()
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            MeerkatView(activity: granted ? .celebrating : .wave, size: 120)
            Text(granted ? "Yatta~! Ora ho le chiavi di casa 🔑✨" : "Onegai~! Mi apri tutte le stanze? 🙏")
                .font(Theme.font(20, .heavy))
            Text(granted
                 ? "Riavviami un attimo e vedrò anche Scrivania, Documenti, Download, Cestini, Mail, Messaggi e le cartelle degli altri utenti."
                 : "Per misurare tutto il disco macOS vuole che tu mi dia l'«Accesso completo al disco». Non può chiederlo con un semplice Sì/No: si fa una volta in Impostazioni, e io mi accorgo da sola quando è fatto.")
                .font(Theme.font(13, .medium)).opacity(0.75).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !granted {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Apri le Impostazioni", "Si apre Privacy › Accesso completo al disco.") {
                        Button("Apri Impostazioni") { model.openFDASettings() }
                            .buttonStyle(BubblyButtonStyle(color: Theme.orange))
                    }
                    step(2, "Sblocca il lucchetto 🔒", "In basso a sinistra, con la tua password.") { EmptyView() }
                    step(3, "Aggiungi SuriClean", "Premi «+» e scegli SuriClean in Applicazioni, oppure trascina l'icona dal Finder nell'elenco. Se c'è già con la spunta, toglila con «–» e riaggiungila: era della versione vecchia.") {
                        Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                            .buttonStyle(BubblyButtonStyle(color: Theme.sky))
                    }
                    step(4, "Torna qui", "Appena macOS me lo concede lo vedo da sola ♡ Se ti chiede «Esci e riapri», va benissimo.") { EmptyView() }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.7)))
            }

            HStack(spacing: 10) {
                if granted {
                    Button("🔄 Riavvia SuriClean") { model.relaunch() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint, big: true))
                } else {
                    Button("Non ora") { model.fdaGuideDismissed() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    Button("L'ho fatto, riavviami") { model.relaunch() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint))
                }
            }
        }
        .padding(26)
        .frame(width: 560)
        .foregroundColor(Theme.cocoa)
        .background(Theme.cream)
        .onReceive(poll) { _ in
            if !granted && FS.hasFullDiskAccess() {
                granted = true
                model.hasFDA = true
                Chiptune.shared.sfx(.coin)
            }
        }
    }

    private func step<Accessory: View>(_ n: Int, _ title: String, _ text: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(Theme.font(14, .heavy)).foregroundColor(.white)
                .frame(width: 26, height: 26).background(Circle().fill(Theme.pink))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(14, .heavy))
                Text(text).font(Theme.font(12, .medium)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            accessory()
        }
    }
}
