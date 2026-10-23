import SwiftUI

/// What Suri is doing. Each activity has its own pose, props and particle effects.
enum MeerkatActivity: String {
    case idle, wave, digging, detective, sweeping, reading, sleepy, hacking, sniffing, lookout, celebrating
}

enum EyeStyle { case open, closed, happy }
enum HandProp { case shovel, magnifier, broom }
enum FrontProp { case book, laptop }
enum HatKind { case detective, nightcap, party }

/// All the numbers that describe one frame of animation.
struct MeerkatPose {
    var bodyX = 0.0, bodyY = 0.0, lean = 0.0, squash = 1.0
    var headTilt = 0.0, headY = 0.0
    var leftArm = 12.0, rightArm = 12.0     // degrees, positive = away from the body
    var eyeX = 0.0, eyeY = 0.0, blink = 1.0
    var eyes: EyeStyle = .open
    var mouthOpen = false
    var noseScale = 1.0
    var tailWag = 0.0

    static func make(_ a: MeerkatActivity, _ t: Double) -> MeerkatPose {
        var p = MeerkatPose()
        let breath = sin(t * 2.2)
        p.squash = 1 + breath * 0.012
        p.headY = breath * 1.5
        p.blink = frac(t / 3.9) * 3.9 < 0.13 ? 0.12 : 1
        p.tailWag = sin(t * 1.7) * 6
        switch a {
        case .idle:
            p.leftArm = 10 + sin(t * 1.3) * 3
            p.rightArm = 10 + sin(t * 1.3 + 1) * 3
            p.eyeX = sin(t * 0.6) * 3
            p.headTilt = sin(t * 0.6) * 4
            if frac(t / 9) * 9 < 1.8 {          // a little hello every few seconds
                p.rightArm = 150 + sin(t * 12) * 18
                p.mouthOpen = true
                p.headTilt = -6
            }
        case .wave:
            p.rightArm = 150 + sin(t * 12) * 18
            p.mouthOpen = true
            p.headTilt = -6 + sin(t * 3) * 2
        case .digging:
            let s = sin(t * 8)
            p.lean = 8
            p.rightArm = 35 + s * 25
            p.leftArm = -10 + s * 10
            p.eyeX = 3; p.eyeY = 3
            p.headTilt = 6
            p.bodyY = -abs(s) * 2
            p.tailWag = sin(t * 8) * 10
        case .detective:
            let s = sin(t * 1.5)
            p.bodyX = s * 8
            p.rightArm = -165 + sin(t * 3) * 4
            p.leftArm = 12
            p.eyeX = s * 3
            p.headTilt = s * 5
        case .sweeping:
            let s = sin(t * 6)
            p.rightArm = -20 + s * 28
            p.leftArm = -30 + s * 20
            p.lean = s * 4
            p.bodyX = s * 4
            p.eyeX = s * 2; p.eyeY = 2
            p.mouthOpen = true
        case .reading:
            p.leftArm = -40; p.rightArm = -40
            p.eyeY = 3
            p.eyeX = sin(t * 3) * 3
            p.headTilt = sin(t * 0.5) * 3
        case .sleepy:
            p.eyes = .closed
            p.squash = 1 + sin(t * 1.2) * 0.025
            p.headTilt = 10
            p.headY = sin(t * 1.2) * 3
            p.leftArm = 6; p.rightArm = 6
            p.tailWag = 0
        case .hacking:
            let j = sin(t * 24)
            p.leftArm = -32 + j * 5
            p.rightArm = -32 - j * 5
            p.eyeY = 3
            p.eyeX = sin(t * 2) * 2
        case .sniffing:
            p.noseScale = 1 + abs(sin(t * 10)) * 0.2
            p.headTilt = sin(t * 1.3) * 10
            p.eyeX = sin(t * 1.3) * 3
            p.leftArm = -22; p.rightArm = -22
        case .lookout:
            p.squash = 1.05 + breath * 0.01
            p.leftArm = -25; p.rightArm = -25
            p.eyeX = sin(t * 0.9) * 4
            p.headTilt = sin(t * 0.9) * 8
        case .celebrating:
            let j = abs(sin(t * 5))
            p.bodyY = -j * 24
            p.squash = j < 0.15 ? 0.94 : 1.02
            p.leftArm = 150 + sin(t * 10) * 15
            p.rightArm = 150 + sin(t * 10 + 1) * 15
            p.eyes = .happy
            p.mouthOpen = true
            p.tailWag = sin(t * 10) * 15
        }
        return p
    }
}

/// Drop-in animated mascot. `size` is the height in points.
struct MeerkatView: View {
    var activity: MeerkatActivity
    var size: CGFloat = 200

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            MeerkatFigure(activity: activity, t: tl.date.timeIntervalSinceReferenceDate)
                .frame(width: 220, height: 260)
                .scaleEffect(size / 260)
                .frame(width: 220 * size / 260, height: size)
        }
        .frame(width: 220 * size / 260, height: size)
        .allowsHitTesting(false)
    }
}

/// The meerkat drawn on a fixed 220×260 canvas.
struct MeerkatFigure: View {
    let activity: MeerkatActivity
    let t: Double

    private var handProp: HandProp? {
        switch activity {
        case .digging: return .shovel
        case .detective: return .magnifier
        case .sweeping: return .broom
        default: return nil
        }
    }

    private var frontProp: FrontProp? {
        switch activity {
        case .reading: return .book
        case .hacking: return .laptop
        default: return nil
        }
    }

    private var hat: HatKind? {
        switch activity {
        case .detective: return .detective
        case .sleepy: return .nightcap
        case .celebrating: return .party
        default: return nil
        }
    }

    var body: some View {
        let p = MeerkatPose.make(activity, t)
        return ZStack {
            backLayer
            Ellipse().fill(Theme.furDark.opacity(0.16))
                .frame(width: max(60, 120 + p.bodyY * 1.5), height: 16)
                .position(x: 110, y: 249)
            ZStack {
                tail(p)
                Ellipse().fill(Theme.fur).frame(width: 38, height: 18).position(x: 88, y: 240)
                Ellipse().fill(Theme.fur).frame(width: 38, height: 18).position(x: 132, y: 240)
                Ellipse().fill(Theme.fur).frame(width: 96, height: 130).position(x: 110, y: 178)
                Ellipse().fill(Theme.furLight).frame(width: 60, height: 92).position(x: 110, y: 190)
                MeerkatHead(p: p, hat: hat, t: t)
                    .offset(y: p.headY)
                    .rotationEffect(.degrees(p.headTilt), anchor: UnitPoint(x: 0.5, y: 0.36))
                if let fp = frontProp {
                    FrontPropView(prop: fp, t: t)
                }
                MeerkatArm(prop: handProp)
                    .rotationEffect(.degrees(-p.rightArm), anchor: .top)
                    .position(x: 144, y: 164)
                MeerkatArm(prop: nil)
                    .rotationEffect(.degrees(p.leftArm), anchor: .top)
                    .position(x: 76, y: 164)
            }
            .frame(width: 220, height: 260)
            .scaleEffect(x: 1 / p.squash, y: p.squash, anchor: .bottom)
            .rotationEffect(.degrees(p.lean), anchor: .bottom)
            .offset(x: p.bodyX, y: p.bodyY)
            effects
        }
        .frame(width: 220, height: 260)
    }

    private func tail(_ p: MeerkatPose) -> some View {
        ZStack {
            TailShape(tipOnly: false).stroke(Theme.fur, style: StrokeStyle(lineWidth: 16, lineCap: .round))
            TailShape(tipOnly: true).stroke(Theme.furDark, style: StrokeStyle(lineWidth: 16, lineCap: .round))
        }
        .frame(width: 220, height: 260)
        .rotationEffect(.degrees(p.tailWag), anchor: UnitPoint(x: 140.0 / 220.0, y: 228.0 / 260.0))
    }

    @ViewBuilder private var backLayer: some View {
        switch activity {
        case .digging:
            Ellipse().fill(Theme.dirt).frame(width: 84, height: 28).position(x: 180, y: 248)
            Ellipse().fill(Theme.dirt.darker).frame(width: 46, height: 12).position(x: 180, y: 244)
        case .lookout:
            Ellipse().fill(Theme.sand).frame(width: 210, height: 46).position(x: 110, y: 254)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var effects: some View {
        switch activity {
        case .digging:
            ForEach(0..<8, id: \.self) { i in
                let ph = frac(t * 1.6 + Double(i) / 8)
                let s: CGFloat = 7 + CGFloat(i % 3) * 2
                let spread: Double = 24 + Double(i) * 4
                let height: Double = 50 + Double(i % 4) * 8
                let px: CGFloat = CGFloat(180 + ph * spread)
                let py: CGFloat = CGFloat(240 - sin(ph * Double.pi) * height)
                Circle().fill(Theme.dirt)
                    .frame(width: s, height: s)
                    .opacity(1 - ph)
                    .position(x: px, y: py)
            }
        case .sweeping:
            ForEach(0..<6, id: \.self) { i in
                let ph = frac(t * 0.9 + Double(i) / 6)
                let s = 10 + ph * 26
                Circle().fill(Color.gray.opacity(0.35))
                    .frame(width: s, height: s)
                    .opacity(1 - ph)
                    .position(x: 70 + Double(i) * 16 + sin(t * 6 + Double(i)) * 10, y: 246 - ph * 50)
            }
        case .sleepy:
            ForEach(0..<3, id: \.self) { i in
                let ph = frac(t * 0.35 + Double(i) / 3)
                Text("z")
                    .font(Theme.font(14 + ph * 16, .heavy))
                    .foregroundColor(Theme.lilac.darker)
                    .opacity(sin(ph * Double.pi))
                    .position(x: 160 + ph * 34 + sin(ph * 6) * 6, y: 60 - ph * 50)
            }
        case .hacking:
            ForEach(0..<7, id: \.self) { i in
                let ph = frac(t * 0.6 + Double(i) / 7)
                Text(i % 2 == 0 ? "1" : "0")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.mint.darker)
                    .opacity(sin(ph * Double.pi))
                    .position(x: 70 + Double(i) * 13 + sin(t * 2 + Double(i)) * 4, y: 160 - ph * 130)
            }
        case .sniffing:
            ForEach(0..<5, id: \.self) { i in
                let ph = frac(t * 0.7 + Double(i) / 5)
                Circle().fill(Theme.lemon)
                    .frame(width: 6, height: 6)
                    .opacity(sin(ph * Double.pi))
                    .position(x: 212 - ph * 80, y: 110 + sin(ph * 9 + Double(i)) * 8)
            }
        case .detective:
            ForEach(0..<1, id: \.self) { _ in
                let ph = frac(t * 0.4)
                Text("?")
                    .font(Theme.font(24, .heavy))
                    .foregroundColor(Theme.lilac.darker)
                    .opacity(sin(ph * Double.pi))
                    .position(x: 186, y: 54 - ph * 22)
            }
        case .lookout:
            ForEach(0..<1, id: \.self) { _ in
                let ph = frac(t * 0.5)
                Text("!")
                    .font(Theme.font(26, .heavy))
                    .foregroundColor(Theme.coral)
                    .opacity(ph < 0.3 ? 1 : 0)
                    .scaleEffect(ph < 0.3 ? 1 + ph : 1)
                    .position(x: 182, y: 40)
            }
        case .celebrating:
            ForEach(0..<6, id: \.self) { i in
                let a: Double = t * 1.5 + Double(i) * Double.pi / 3
                let fs: CGFloat = 12 + CGFloat(i % 3) * 5
                let op: Double = 0.5 + 0.5 * sin(t * 4 + Double(i))
                let px: CGFloat = CGFloat(110 + cos(a) * 100)
                let py: CGFloat = CGFloat(130 + sin(a) * 100)
                Text("✦")
                    .font(.system(size: fs))
                    .foregroundColor([Theme.pink, Theme.lemon, Theme.sky][i % 3])
                    .opacity(op)
                    .position(x: px, y: py)
            }
        default:
            EmptyView()
        }
    }
}

struct MeerkatHead: View {
    let p: MeerkatPose
    let hat: HatKind?
    let t: Double

    var body: some View {
        ZStack {
            // ears
            Circle().fill(Theme.furDark).frame(width: 28, height: 28).position(x: 58, y: 70)
            Circle().fill(Theme.furDark).frame(width: 28, height: 28).position(x: 162, y: 70)
            Circle().fill(Theme.pink.opacity(0.55)).frame(width: 13, height: 13).position(x: 58, y: 70)
            Circle().fill(Theme.pink.opacity(0.55)).frame(width: 13, height: 13).position(x: 162, y: 70)
            // head
            Ellipse().fill(Theme.fur).frame(width: 120, height: 100).position(x: 110, y: 92)
            Capsule().fill(Theme.furDark.opacity(0.22)).frame(width: 12, height: 26).position(x: 110, y: 56)
            Ellipse().fill(Theme.furLight).frame(width: 56, height: 38).position(x: 110, y: 113)
            // the meerkat "mask"
            Ellipse().fill(Theme.furDark).frame(width: 38, height: 46).rotationEffect(.degrees(20)).position(x: 82, y: 88)
            Ellipse().fill(Theme.furDark).frame(width: 38, height: 46).rotationEffect(.degrees(-20)).position(x: 138, y: 88)
            eye.position(x: 82 + p.eyeX, y: 89 + p.eyeY)
            eye.position(x: 138 + p.eyeX, y: 89 + p.eyeY)
            // blush
            Ellipse().fill(Theme.pink.opacity(0.5)).frame(width: 22, height: 12).position(x: 64, y: 116)
            Ellipse().fill(Theme.pink.opacity(0.5)).frame(width: 22, height: 12).position(x: 156, y: 116)
            // nose & mouth
            NoseShape().fill(Theme.cocoa).frame(width: 17, height: 11).scaleEffect(p.noseScale).position(x: 110, y: 105)
            if p.mouthOpen {
                MouthOpenShape().fill(Theme.coral).frame(width: 16, height: 10).position(x: 110, y: 119)
            } else {
                MouthW().stroke(Theme.cocoa, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 6).position(x: 110, y: 115)
            }
            if let hat = hat {
                HatView(kind: hat, t: t)
            }
        }
        .frame(width: 220, height: 260)
    }

    @ViewBuilder private var eye: some View {
        switch p.eyes {
        case .open:
            ZStack {
                Ellipse().fill(Color.black).frame(width: 26, height: 30)
                Circle().fill(Color.white).frame(width: 11, height: 11).offset(x: -5, y: -7)
                Circle().fill(Color.white).frame(width: 5, height: 5).offset(x: 5, y: 7)
            }
            .scaleEffect(x: 1, y: p.blink)
        case .closed:
            ArcShape(up: false).stroke(Color.black, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 20, height: 8)
        case .happy:
            ArcShape(up: true).stroke(Color.black, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).frame(width: 20, height: 10)
        }
    }
}

struct MeerkatArm: View {
    let prop: HandProp?
    var body: some View {
        ZStack(alignment: .top) {
            Capsule().fill(Theme.fur).frame(width: 18, height: 52)
            if let prop = prop {
                HandPropView(prop: prop).offset(y: 42)
            }
            Circle().fill(Theme.furLight).frame(width: 16, height: 16).offset(y: 38)
        }
        .frame(width: 18, height: 52, alignment: .top)
    }
}

struct HandPropView: View {
    let prop: HandProp
    private let wood = Color(red: 0.62, green: 0.42, blue: 0.26)

    var body: some View {
        switch prop {
        case .shovel:
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(wood).frame(width: 6, height: 36)
                ShovelBlade().fill(Color(white: 0.74)).frame(width: 24, height: 26)
            }
        case .magnifier:
            VStack(spacing: -3) {
                RoundedRectangle(cornerRadius: 3).fill(wood).frame(width: 7, height: 16)
                ZStack {
                    Circle().fill(Theme.sky.opacity(0.35))
                    Circle().stroke(Color(white: 0.55), lineWidth: 5)
                    Circle().fill(Color.white.opacity(0.85)).frame(width: 8, height: 8).offset(x: -7, y: -7)
                }
                .frame(width: 38, height: 38)
            }
        case .broom:
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(wood).frame(width: 5, height: 40)
                RoundedRectangle(cornerRadius: 3).fill(Theme.coral).frame(width: 22, height: 6)
                Trapezoid().fill(Theme.lemon).frame(width: 40, height: 26)
            }
        }
    }
}

struct FrontPropView: View {
    let prop: FrontProp
    let t: Double

    var body: some View {
        switch prop {
        case .book:
            let flip = frac(t / 3.0)
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Theme.pink).frame(width: 86, height: 58)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white)
                    RoundedRectangle(cornerRadius: 3).fill(Color.white)
                }
                .frame(width: 78, height: 50)
                HStack(spacing: 14) {
                    lines
                    lines
                }
                if flip < 0.25 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.93))
                        .frame(width: 38, height: 50)
                        .scaleEffect(x: cos(flip / 0.25 * Double.pi), y: 1, anchor: .leading)
                        .offset(x: 19)
                }
            }
            .position(x: 110, y: 176)
        case .laptop:
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.80)).frame(width: 80, height: 54).position(x: 110, y: 178)
                Image(systemName: "heart.fill").font(.system(size: 15)).foregroundColor(Theme.pink).position(x: 110, y: 178)
                Image(systemName: "star.fill").font(.system(size: 8)).foregroundColor(Theme.lemon).position(x: 128, y: 166)
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.62)).frame(width: 94, height: 8).position(x: 110, y: 208)
                Circle().fill(Theme.mint.opacity(0.5 + 0.5 * sin(t * 6))).frame(width: 5, height: 5).position(x: 142, y: 200)
            }
        }
    }

    private var lines: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { _ in
                Capsule().fill(Theme.cocoa.opacity(0.15)).frame(width: 26, height: 3)
            }
        }
    }
}

struct HatView: View {
    let kind: HatKind
    let t: Double

    var body: some View {
        switch kind {
        case .detective:
            ZStack {
                Capsule().fill(Color(red: 0.40, green: 0.29, blue: 0.20)).frame(width: 106, height: 12).position(x: 110, y: 52)
                HalfDome().fill(Color(red: 0.56, green: 0.43, blue: 0.31)).frame(width: 78, height: 36).position(x: 110, y: 34)
                Capsule().fill(Theme.coral).frame(width: 78, height: 7).position(x: 110, y: 47)
            }
        case .nightcap:
            ZStack {
                NightcapShape().fill(Theme.lilac).frame(width: 100, height: 64).position(x: 122, y: 26)
                Capsule().fill(Color.white).frame(width: 98, height: 14).position(x: 108, y: 50)
                Circle().fill(Color.white).frame(width: 16, height: 16).position(x: 172, y: -2 + sin(t * 1.2) * 3)
            }
        case .party:
            ZStack {
                Triangle().fill(LinearGradient(gradient: Gradient(colors: [Theme.pink, Theme.lemon]), startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 50).position(x: 110, y: 22)
                Circle().fill(Theme.sky).frame(width: 13, height: 13).position(x: 110, y: -2)
            }
        }
    }
}

// MARK: - Shapes

struct MouthW: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY + r.height * 0.6))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.75, y: r.maxY + r.height * 0.6))
        return p
    }
}

struct MouthOpenShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height))
        p.closeSubpath()
        return p
    }
}

struct ArcShape: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height))
        }
        return p
    }
}

struct NoseShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.15, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.15, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.6))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.15, y: r.minY), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.6))
        p.closeSubpath()
        return p
    }
}

struct TailShape: Shape {
    var tipOnly: Bool
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x / 220 * r.width, y: r.minY + y / 260 * r.height)
        }
        var p = Path()
        if tipOnly {
            p.move(to: pt(191, 160))
            p.addLine(to: pt(193, 150))
        } else {
            p.move(to: pt(135, 232))
            p.addCurve(to: pt(193, 150), control1: pt(190, 242), control2: pt(205, 190))
        }
        return p
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Trapezoid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.25, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.25, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct ShovelBlade: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY * 0.8))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.minX, y: r.maxY * 0.8))
        p.closeSubpath()
        return p
    }
}

struct HalfDome: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height))
        p.closeSubpath()
        return p
    }
}

struct NightcapShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.3, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.9, y: r.maxY), control: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + r.height * 0.5))
        p.closeSubpath()
        return p
    }
}
