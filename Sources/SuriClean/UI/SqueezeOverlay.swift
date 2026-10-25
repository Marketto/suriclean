import SwiftUI

private let ink = Color(red: 0x3b / 255, green: 0x2a / 255, blue: 0x4a / 255)
private func rgb(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255).opacity(a)
}

/// Piecewise-linear keyframes over one loop (phase 0…1), like the CSS of proposal A.
private func kf(_ p: Double, _ k: [(Double, Double)]) -> Double {
    guard let first = k.first else { return 0 }
    if p <= first.0 { return first.1 }
    for i in 1..<k.count where p <= k[i].0 {
        let a = k[i - 1], b = k[i]
        let f = b.0 > a.0 ? (p - a.0) / (b.0 - a.0) : 1
        return a.1 + (b.1 - a.1) * f
    }
    return k[k.count - 1].1
}

/// The four-pointed spark of Schiaccia's press.
private struct Spark: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 48
        let pts: [(CGFloat, CGFloat)] = [(24, 0), (31, 17), (48, 24), (31, 31), (24, 48), (17, 31), (0, 24), (17, 17)]
        var p = Path()
        p.move(to: CGPoint(x: r.minX + pts[0].0 * s, y: r.minY + pts[0].1 * s))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: r.minX + q.0 * s, y: r.minY + q.1 * s)) }
        p.closeSubpath()
        return p
    }
}

/// The «w» mouth of the press: M240 258 q8 11 16 0 q8 11 16 0.
private struct PressMouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + 16, y: r.minY), control: CGPoint(x: r.minX + 8, y: r.minY + 11))
        p.addQuadCurve(to: CGPoint(x: r.minX + 32, y: r.minY), control: CGPoint(x: r.minX + 24, y: r.minY + 11))
        return p
    }
}

/// Schiaccia's mascot, the press, redrawn from its SVG (tools/mascot.mjs, viewBox 70 48 400 404).
/// `slam` moves the head down (SVG units), `squash` flattens the sheet under it (0…1).
struct PressView: View {
    var kind: SqueezeKind
    var slam: Double
    var squash: Double

    private func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x - 70, y: y - 48) }

    var body: some View {
        ZStack {
            post.position(at(118, 275))
            post.position(at(394, 275))
            sheet
                .scaleEffect(x: 1, y: 1 - 0.6 * squash, anchor: .bottom)
                .position(at(256, 365))
            RoundedRectangle(cornerRadius: 25, style: .continuous).fill(rgb(0xa48cf0))
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(ink, lineWidth: 10))
                .frame(width: 344, height: 50)
                .position(at(256, 417))
            head
                .scaleEffect(x: 1, y: slam > 30 ? 0.92 : 1, anchor: .bottom)
                .offset(y: slam)
            Spark().fill(rgb(0xfff6a8))
                .overlay(Spark().stroke(ink, style: StrokeStyle(lineWidth: 6, lineJoin: .round)))
                .frame(width: 48, height: 48)
                .position(at(424, 108))
        }
        .frame(width: 400, height: 404)
    }

    private var post: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(rgb(0xcdb8ff))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ink, lineWidth: 10))
            .frame(width: 36, height: 250)
    }

    @ViewBuilder private var sheet: some View {
        switch kind {
        case .pdf:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ink, lineWidth: 10))
                VStack(spacing: 15) {
                    Capsule().fill(rgb(0xf0b6c8)).frame(width: 116, height: 7)
                    Capsule().fill(rgb(0xf0b6c8)).frame(width: 116, height: 7)
                }
            }
            .frame(width: 160, height: 70)
        case .jpg:
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ink, lineWidth: 10))
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(rgb(0x9ad7ff))
                    Circle().fill(rgb(0xffd23f)).frame(width: 18, height: 18).offset(x: 102, y: -28)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 54)); p.addLine(to: CGPoint(x: 36, y: 24)); p.addLine(to: CGPoint(x: 58, y: 42))
                        p.addLine(to: CGPoint(x: 76, y: 28)); p.addLine(to: CGPoint(x: 132, y: 54)); p.closeSubpath()
                    }.fill(rgb(0x3ddc97))
                }
                .frame(width: 132, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(width: 160, height: 74)
        case .video:
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ink)
                VStack(alignment: .leading, spacing: 9) {
                    Capsule().fill(Color.white).frame(width: 90, height: 7)
                    Capsule().fill(Color.white).frame(width: 56, height: 7)
                }
                .offset(x: -14)
                Circle().fill(rgb(0xff5a4e)).frame(width: 14, height: 14).offset(x: 56, y: 12)
            }
            .frame(width: 152, height: 56)
        }
    }

    private var head: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 88, style: .continuous).fill(rgb(0xffb3c7))
                .overlay(RoundedRectangle(cornerRadius: 88, style: .continuous).strokeBorder(ink, lineWidth: 10))
                .frame(width: 256, height: 206)
                .position(at(256, 215))
            Ellipse().fill(Color.white.opacity(0.55)).frame(width: 92, height: 30)
                .rotationEffect(.degrees(-18)).position(at(196, 146))
            eye(198)
            eye(314)
            Ellipse().fill(rgb(0xff7fa3, 0.8)).frame(width: 38, height: 20).position(at(156, 266))
            Ellipse().fill(rgb(0xff7fa3, 0.8)).frame(width: 38, height: 20).position(at(356, 266))
            PressMouth().stroke(ink, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 11)
                .position(at(256, 263.5))
        }
        .frame(width: 400, height: 404)
    }

    private func eye(_ cx: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(ink).frame(width: 60, height: 72).position(at(cx, 222))
            Ellipse().fill(rgb(0x8f6bd9, 0.75)).frame(width: 40, height: 28).position(at(cx, 240))
            Ellipse().fill(Color.white).frame(width: 24, height: 28).position(at(cx - 9, 207))
            Circle().fill(Color.white).frame(width: 11, height: 11).position(at(cx + 11, 236))
        }
    }
}

/// Little card of the file Suri carries.
private struct FileCard: View {
    let kind: SqueezeKind
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ink, lineWidth: 3))
            .overlay(Text(kind.tag).font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(kind == .video ? Theme.sky.darker : (kind == .jpg ? Theme.mint.darker : Theme.coral)))
            .frame(width: 34, height: 42)
    }
}

/// Animation A «Il corriere»: Suri runs with the file, throws it under Schiaccia's press, the head slams,
/// the flattened file flies off with the real saving of the last file.
struct CourierStage: View {
    let run: SqueezeRunState
    private let width: CGFloat = 460
    private let height: CGFloat = 230
    private let cycle = 3.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
            let suriX = kf(p, [(0, 0), (0.1, 0), (0.35, 110), (0.55, 110), (0.8, 0), (1, 0)])
            let fx = kf(p, [(0, 108), (0.1, 108), (0.35, 218), (0.48, 352), (0.62, 352), (0.78, 438), (1, 438)])
            let fy = kf(p, [(0, 128), (0.1, 128), (0.35, 128), (0.48, 186), (0.62, 196), (0.78, 40), (1, 40)])
            let fsq = kf(p, [(0, 1), (0.55, 1), (0.62, 0.35), (1, 0.35)])
            let fop = kf(p, [(0, 1), (0.78, 1), (0.86, 0), (0.98, 0), (1, 1)])
            let slam = kf(p, [(0, 0), (0.5, 0), (0.58, 38), (0.66, 0), (1, 0)])
            let squash = kf(p, [(0, 0), (0.5, 0), (0.58, 1), (0.9, 1), (1, 0)])
            let badge = kf(p, [(0, 0), (0.62, 0), (0.7, 1), (0.88, 1), (1, 0)])
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [rgb(0xe9fbf4), rgb(0xfde8f0)], startPoint: .top, endPoint: .bottom))
                PressView(kind: run.kind, slam: slam, squash: squash)
                    .scaleEffect(0.43)
                    .frame(width: 172, height: 174)
                    .position(x: width - 100, y: height - 92)
                MeerkatView(activity: p > 0.62 && p < 0.9 ? .celebrating : .lookout, size: 120)
                    .position(x: 70 + suriX, y: height - 66)
                FileCard(kind: run.kind)
                    .scaleEffect(x: 1, y: fsq, anchor: .bottom)
                    .opacity(fop)
                    .position(x: fx, y: fy)
                if let s = run.lastSaving {
                    Text("−\(s)% ✨")
                        .font(Theme.font(17, .heavy))
                        .foregroundColor(Theme.mint.darker)
                        .opacity(badge)
                        .offset(y: (1 - badge) * 8)
                        .position(x: width - 70, y: 26)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: width, height: height)
    }
}

struct SqueezeOverlay: View {
    let run: SqueezeRunState
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(t("mac.sq.title")).font(Theme.font(22, .heavy))
                CourierStage(run: run)
                Text(run.name.isEmpty ? " " : run.name)
                    .font(Theme.font(13, .bold)).lineLimit(1).truncationMode(.middle)
                    .frame(width: 440)
                StripedProgress(progress: run.progress).frame(width: 400, height: 18)
                HStack(spacing: 14) {
                    Text(t("mac.sq.count", min(run.index + 1, run.total), run.total)).font(Theme.font(12.5, .bold)).opacity(0.6)
                    HStack(spacing: 6) {
                        Text(t("mac.sq.saved")).font(Theme.font(12.5, .bold)).opacity(0.6)
                        AnimatedBytes(value: run.saved).font(Theme.font(16, .heavy)).foregroundColor(Theme.mint.darker)
                    }
                }
                Text(t("mac.sq.engine", Squeeze.version)).font(Theme.font(10.5, .semibold)).opacity(0.4)
                Button(run.cancelling ? t("mac.sq.stopping") : t("mac.common.cancel")) { model.cancelSqueeze() }
                    .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                    .disabled(run.cancelling)
            }
            .padding(26)
            .frame(width: 520)
            .kawaiiCard(color: Theme.lilac, radius: 34)
        }
    }
}

/// Type chips and strength for «Da schiacciare».
struct SqueezeControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(SqueezeKind.allCases) { k in
                    let on = model.squeezeKinds.contains(k)
                    let n = model.items(.squeeze).filter { SqueezeKind.of($0.url) == k }.count
                    Button(action: { model.toggleSqueezeKind(k) }) {
                        Text("\(k.label) · \(n)")
                            .font(Theme.font(12.5, .heavy))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(on ? Theme.lilac.darker : Color.white.opacity(0.8)))
                            .foregroundColor(on ? .white : Theme.cocoa)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 10)
                Text(t("mac.sq.level")).font(Theme.font(12, .bold)).opacity(0.6)
                Picker("", selection: $model.squeezeLevel) {
                    ForEach(SqueezeLevel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
                .labelsHidden()
                .onChange(of: model.squeezeLevel) { _ in Chiptune.shared.sfx(.pop) }
            }
            Text(model.squeezeLevel.note)
                .font(Theme.font(11.5, .medium)).opacity(0.6)
        }
    }
}
