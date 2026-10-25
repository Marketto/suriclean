import SwiftUI

enum Quips {
    static func list(_ a: MeerkatActivity) -> [String] {
        switch a {
        case .digging: return [t("mac.quip.digging.1"), t("mac.quip.digging.2"), t("mac.quip.digging.3"), t("mac.quip.digging.4")]
        case .detective: return [t("mac.quip.detective.1"), t("mac.quip.detective.2"), t("mac.quip.detective.3"), t("mac.quip.detective.4")]
        case .sweeping: return [t("mac.quip.sweeping.1"), t("mac.quip.sweeping.2"), t("mac.quip.sweeping.3"), t("mac.quip.sweeping.4")]
        case .reading: return [t("mac.quip.reading.1"), t("mac.quip.reading.2"), t("mac.quip.reading.3"), t("mac.quip.reading.4")]
        case .sleepy: return [t("mac.quip.sleepy.1"), t("mac.quip.sleepy.2"), t("mac.quip.sleepy.3")]
        case .hacking: return [t("mac.quip.hacking.1"), t("mac.quip.hacking.2"), t("mac.quip.hacking.3"), t("mac.quip.hacking.4")]
        case .sniffing: return [t("mac.quip.sniffing.1"), t("mac.quip.sniffing.2"), t("mac.quip.sniffing.3"), t("mac.quip.sniffing.4")]
        case .lookout: return [t("mac.quip.lookout.1"), t("mac.quip.lookout.2"), t("mac.quip.lookout.3")]
        case .celebrating: return [t("mac.quip.celebrating.1")]
        case .idle, .wave: return [t("mac.quip.idle.1")]
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
                        Text(t("mac.busy.loot")).font(Theme.font(13, .bold)).opacity(0.6)
                        AnimatedBytes(value: state.foundBytes).font(Theme.font(16, .heavy)).foregroundColor(Theme.mint.darker)
                        Text(t("mac.zone.count", state.foundCount)).font(Theme.font(13, .bold)).opacity(0.6)
                    }
                }
                if state.steps > 1 {
                    Text(t("mac.busy.zone", state.step + 1, state.steps)).font(Theme.font(11.5, .bold)).opacity(0.45)
                }
                Button(t("mac.common.cancel")) { model.cancel() }
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
                if (c.kind == .trashed || c.kind == .squeezed) && c.bytes > 0 {
                    Text(t("mac.cele.psst"))
                        .font(Theme.font(12.5, .semibold)).foregroundColor(Theme.coral.darker)
                }
                HStack(spacing: 12) {
                    if (c.kind == .trashed || c.kind == .squeezed) && model.trashSize > 0 {
                        Button(action: { model.askEmptyTrash = true }) {
                            Label(t("mac.cele.empty"), systemImage: "trash.fill")
                        }
                        .buttonStyle(BubblyButtonStyle(color: Theme.coral, big: true))
                    }
                    Button(t("mac.cele.thanks")) { model.dismissCelebration() }
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
        case .trashed: return c.bytes > 0 ? t("mac.cele.yatta") : t("mac.cele.gomen")
        case .emptied: return t("mac.cele.emptied")
        case .info: return t("mac.cele.info")
        case .squeezed: return c.bytes > 0 ? t("mac.sq.cele.title") : t("mac.cele.gomen")
        }
    }

    private var subtitle: String {
        switch c.kind {
        case .trashed: return c.bytes > 0 ? t("mac.cele.sent", Fmt.bytes(c.bytes)) : t("mac.cele.nothing")
        case .emptied: return t("mac.cele.recovered", Fmt.bytes(c.bytes))
        case .info: return t("mac.cele.space", Fmt.bytes(c.bytes))
        case .squeezed: return c.bytes > 0 ? t("mac.sq.cele.saved", Fmt.bytes(c.bytes)) : t("mac.sq.cele.nothing")
        }
    }
}
