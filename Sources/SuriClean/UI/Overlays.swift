import SwiftUI

enum Quips {
    static func list(_ a: MeerkatActivity) -> [String] {
        switch a {
        case .digging: return ["Hori-hori! Scavo scavo~ 🕳️", "Ooh! Qui sotto c'è qualcosa di ciccione!", "Zampette turbo attivate ☆", "Sniff… odore di file giganti!"]
        case .detective: return ["Hmm~ questi due sono gemellini! 🔍", "Confronto le impronte SHA-256, kira!", "Elementare, mio caro Mac ♡", "Nessun gemello sfugge a Suri-chan!"]
        case .sweeping: return ["Saa~ spazza spazza! 🧹", "Bye-bye polverina digitale!", "Pika-pika, tutto lucido ✨", "Che soddisfazione, kyaa~!"]
        case .reading: return ["Leggo i diari segreti dei repo 📜", "Eeh?! Ultimo commit… secoli fa!", "Tutto pushato? Controllo bene ♡", "git log, git status, git… nyaa~"]
        case .sleepy: return ["Shh~ le app fanno la nanna 💤", "Questa dorme dal Pleistocene!", "Una pecorella, due pecorelle… ☁️"]
        case .hacking: return ["Bip-bup! Annuso i file dei robot 🤖", "Claude e Codex lasciano briciole~", "Modelli AI in vista, sugoi!", "01101110 = «nyam» ♡"]
        case .sniffing: return ["Kun-kun! Sento le cache 👃", "Profumino di file temporanei~", "Briciole ovunque, waa!", "Odore di app dimenticata…"]
        case .lookout: return ["Sentinella Suri, pronta! 👀", "Download antichi all'orizzonte!", "Dalla collinetta vedo tutto ☆"]
        case .celebrating: return ["Yatta~! 🎉"]
        case .idle, .wave: return ["Eccomi!"]
        }
    }
}

struct LoadingOverlay: View {
    let state: BusyState
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 14) {
                MeerkatView(activity: state.activity, size: 230)
                Text(state.title).font(Theme.font(22, .heavy)).multilineTextAlignment(.center)
                TimelineView(.periodic(from: Date(), by: 2.6)) { tl in
                    let q = Quips.list(state.activity)
                    let idx = Int(tl.date.timeIntervalSinceReferenceDate / 2.6) % max(q.count, 1)
                    Text(q[idx])
                        .font(Theme.font(14, .semibold))
                        .foregroundColor(Theme.cocoa.opacity(0.75))
                        .id(idx)
                }
                StripedProgress(progress: state.progress).frame(width: 380, height: 18)
                Text(state.detail.isEmpty ? " " : state.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(width: 400)
                    .opacity(0.55)
                if state.foundCount > 0 {
                    HStack(spacing: 6) {
                        Text("Bottino ☆").font(Theme.font(13, .bold)).opacity(0.6)
                        AnimatedBytes(value: state.foundBytes).font(Theme.font(16, .heavy)).foregroundColor(Theme.mint.darker)
                        Text("· \(state.foundCount) elementi").font(Theme.font(13, .bold)).opacity(0.6)
                    }
                }
                if state.steps > 1 {
                    Text("Zona \(state.step + 1) di \(state.steps)").font(Theme.font(11.5, .bold)).opacity(0.45)
                }
                Button("Annulla") { model.cancel() }
                    .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
            }
            .padding(30)
            .frame(width: 480)
            .kawaiiCard(color: Theme.lemon, radius: 34)
        }
    }
}

struct CelebrationOverlay: View {
    let c: Celebration
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
                .onTapGesture { model.dismissCelebration() }
            ConfettiView().ignoresSafeArea()
            VStack(spacing: 12) {
                MeerkatView(activity: .celebrating, size: 210)
                Text(title).font(Theme.font(32, .heavy))
                Text(subtitle).font(Theme.font(17, .bold)).multilineTextAlignment(.center)
                if !c.message.isEmpty {
                    Text(c.message).font(Theme.font(12.5, .medium)).opacity(0.65)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if c.kind == .trashed && c.bytes > 0 {
                    Text("Psst~ lo spazio torna libero davvero quando svuoti il Cestino ♡")
                        .font(Theme.font(12.5, .semibold)).foregroundColor(Theme.coral.darker)
                }
                HStack(spacing: 12) {
                    if c.kind == .trashed && model.trashSize > 0 {
                        Button(action: { model.askEmptyTrash = true }) {
                            Label("Svuota il Cestino", systemImage: "trash.fill")
                        }
                        .buttonStyle(BubblyButtonStyle(color: Theme.coral, big: true))
                    }
                    Button("Arigatō! ♡") { model.dismissCelebration() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint, big: true))
                }
                .padding(.top, 6)
            }
            .padding(30)
            .frame(width: 500)
            .kawaiiCard(color: Theme.pink, radius: 34)
        }
    }

    private var title: String {
        switch c.kind {
        case .trashed: return c.bytes > 0 ? "Yatta~!! 🎉" : "Ehh… gomen! 🙈"
        case .emptied: return "Pika-pika! Cestino vuoto ✨"
        case .info: return "Sugoi! Fatto 🌟"
        }
    }

    private var subtitle: String {
        switch c.kind {
        case .trashed: return c.bytes > 0 ? "Ho spedito \(Fmt.bytes(c.bytes)) nel Cestino ☆" : "Non sono riuscita a spostare niente, scusa~"
        case .emptied: return "Hai recuperato \(Fmt.bytes(c.bytes)) di spazio vero! Sugoi~ ♡"
        case .info: return "Spazio recuperato: \(Fmt.bytes(c.bytes))"
        }
    }
}
