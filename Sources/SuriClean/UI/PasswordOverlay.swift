import SwiftUI

/// Suri asks the administrator password herself, so root commands keep Full Disk Access (see Admin).
struct PasswordOverlay: View {
    @EnvironmentObject var model: AppModel
    let prompt: PasswordPrompt
    @State private var pw = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 12) {
                MeerkatView(activity: .lookout, size: 110)
                Text(t("mac.pw.title")).font(Theme.font(19, .heavy))
                Text(prompt.reason).font(Theme.font(13, .bold)).opacity(0.8).multilineTextAlignment(.center)
                Text(t("mac.pw.why"))
                    .font(Theme.font(11.5, .medium)).opacity(0.6).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField(t("mac.pw.field", NSFullUserName()), text: $pw, onCommit: { model.submitPassword(pw) })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .frame(width: 300)
                    .disabled(prompt.checking)
                if let e = prompt.error {
                    Text(e).font(Theme.font(12, .heavy)).foregroundColor(Theme.coral)
                }
                HStack(spacing: 10) {
                    Button(t("mac.common.cancel")) { model.cancelPassword() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    Button(prompt.checking ? t("mac.pw.checking") : t("mac.common.continue")) { model.submitPassword(pw) }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint))
                        .disabled(pw.isEmpty || prompt.checking)
                }
            }
            .padding(24)
            .frame(width: 440)
            .foregroundColor(Theme.cocoa)
            .kawaiiCard(color: Theme.orange)
        }
        .onChange(of: prompt.error) { _ in pw = "" }
    }
}
