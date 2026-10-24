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
            Text(granted ? t("mac.fdag.yes") : t("mac.fdag.ask"))
                .font(Theme.font(20, .heavy))
            Text(granted
                 ? t("mac.fdag.yes.text")
                 : t("mac.fdag.ask.text"))
                .font(Theme.font(13, .medium)).opacity(0.75).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !granted {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, t("mac.fdag.s1"), t("mac.fdag.s1.text")) {
                        Button(t("mac.fdag.open")) { model.openFDASettings() }
                            .buttonStyle(BubblyButtonStyle(color: Theme.orange))
                    }
                    step(2, t("mac.fdag.s2"), t("mac.fdag.s2.text")) { EmptyView() }
                    step(3, t("mac.fdag.s3"), t("mac.fdag.s3.text")) {
                        Button(t("mac.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                            .buttonStyle(BubblyButtonStyle(color: Theme.sky))
                    }
                    step(4, t("mac.fdag.s4"), t("mac.fdag.s4.text")) { EmptyView() }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.7)))
            }

            HStack(spacing: 10) {
                if granted {
                    Button(t("mac.common.continue")) { model.fdaGrantedContinue() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    Button(t("mac.fdag.relaunch")) { model.relaunch() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint, big: true))
                } else {
                    Button(t("mac.fdag.notnow")) { model.fdaGuideDismissed() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    Button(t("mac.fdag.done")) { model.relaunch() }
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
