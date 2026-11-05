import SwiftUI
import AppKit

/// First-launch (and after a change of legal/VERSION) acceptance of the terms of use and the privacy notice.
/// Not dismissable: «Accetto» needs the checkbox, «Esci» quits the app. See legal/README.md.
struct ConsentOverlay: View {
    @EnvironmentObject var model: AppModel
    @State private var agreed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MeerkatView(activity: .wave, size: 78)
                    Text(t("legal.consent.title")).font(Theme.font(22, .heavy))
                }
                if Legal.isUpdate {
                    Text(t("legal.consent.updated"))
                        .font(Theme.font(12.5, .heavy)).foregroundColor(Theme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(t("legal.consent.intro")).font(Theme.font(13.5, .bold))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(["p1", "p2", "p3", "p4"], id: \.self) { k in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").font(Theme.font(13, .heavy))
                        Text(t("legal.consent.\(k)")).font(Theme.font(12.5, .medium)).opacity(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 14) {
                    Button(t("legal.link.terms")) { model.openLegal(.terms) }
                    Button(t("legal.link.privacy")) { model.openLegal(.privacy) }
                }
                .buttonStyle(.link)
                .font(Theme.font(12.5, .heavy))
                Toggle(isOn: $agreed) {
                    Text(t("legal.consent.check")).font(Theme.font(13, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                HStack(spacing: 10) {
                    Spacer()
                    Button(t("legal.consent.decline")) { NSApp.terminate(nil) }
                        .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    Button(t("legal.consent.accept")) { model.acceptLegal() }
                        .buttonStyle(BubblyButtonStyle(color: Theme.mint, big: true))
                        .disabled(!agreed)
                        .opacity(agreed ? 1 : 0.5)
                }
            }
            .padding(24)
            .frame(width: 560)
            .foregroundColor(Theme.cocoa)
            .kawaiiCard(color: Theme.lilac)
        }
    }
}

enum LegalTab: Int, Hashable { case terms, privacy, licenses }

/// «Note legali»: terms of use, privacy notice and third-party licenses, all offline.
struct LegalSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var openLicense: (title: String, text: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("legal.link.title")).font(Theme.font(20, .heavy))
                Spacer()
                Button(t("legal.close")) { model.showLegal = false }
                    .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    .keyboardShortcut(.cancelAction)
            }
            Picker("", selection: $model.legalTab) {
                Text(t("legal.link.terms")).tag(LegalTab.terms)
                Text(t("legal.link.privacy")).tag(LegalTab.privacy)
                Text(t("legal.link.licenses")).tag(LegalTab.licenses)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.legalTab) { _ in openLicense = nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.legalTab {
                    case .terms: document("terms")
                    case .privacy: document("privacy")
                    case .licenses: licenses
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .padding(22)
        .frame(width: 640, height: 600)
        .foregroundColor(Theme.cocoa)
        .background(Theme.cream)
        .environment(\.layoutDirection, L10n.shared.isRTL ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder private func document(_ kind: String) -> some View {
        Text(t("legal.\(kind).title")).font(Theme.font(18, .heavy))
        Text(t("legal.updated", Legal.version)).font(Theme.font(11.5, .bold)).opacity(0.6)
        ForEach(Legal.sections(kind)) { s in
            VStack(alignment: .leading, spacing: 6) {
                Text(s.title).font(Theme.font(14.5, .heavy))
                LegalBody(text: s.body)
            }
        }
    }

    @ViewBuilder private var licenses: some View {
        if let open = openLicense {
            Button(action: { openLicense = nil }) {
                Label(t("legal.link.licenses"), systemImage: "chevron.left").font(Theme.font(12.5, .heavy))
            }
            .buttonStyle(.link)
            Text(open.title).font(Theme.font(15, .heavy))
            Text(open.text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(t("legal.lic.title")).font(Theme.font(18, .heavy))
            Text(t("legal.lic.intro")).font(Theme.font(12.5, .medium)).opacity(0.8)
                .fixedSize(horizontal: false, vertical: true)
            row(name: t("legal.lic.app"), detail: nil, license: "MIT", url: "https://github.com/Marketto/suriclean") {
                openLicense = ("SuriClean · MIT", Legal.appLicense)
            }
            ForEach(Legal.components) { c in
                row(name: c.name,
                    detail: c.sameAuthor ? t("legal.lic.same_author") : t("legal.lic.by", c.by),
                    license: c.license, url: c.url) {
                    openLicense = ("\(c.name) · \(c.license)", Legal.licenseText(c.license, copyright: c.copyright))
                }
            }
        }
    }

    private func row(name: String, detail: String?, license: String, url: String, open: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.font(13.5, .heavy))
                if let d = detail { Text(d).font(Theme.font(11.5, .medium)).opacity(0.65) }
                if let u = URL(string: url), !url.isEmpty {
                    Link(t("legal.lic.source"), destination: u).font(Theme.font(11.5, .bold))
                }
            }
            Spacer()
            Button(action: open) {
                Text("\(license) · \(t("legal.lic.text"))").font(Theme.font(11.5, .heavy))
            }
            .buttonStyle(BubblyButtonStyle(color: Theme.sky))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.75)))
    }
}

/// A legal section body: paragraphs split on blank lines, lines starting with «• » shown as a list.
struct LegalBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, para in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(para.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if line.hasPrefix("• ") {
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").font(Theme.font(12.5, .heavy))
                                Text(String(line.dropFirst(2))).font(Theme.font(12.5, .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, 8)
                        } else if !line.isEmpty {
                            Text(line).font(Theme.font(12.5, .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .opacity(0.88)
    }
}
