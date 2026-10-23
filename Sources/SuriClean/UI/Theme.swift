import SwiftUI
import AppKit

enum Theme {
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.91)
    static let peach = Color(red: 1.00, green: 0.80, blue: 0.68)
    static let pink = Color(red: 1.00, green: 0.50, blue: 0.66)
    static let coral = Color(red: 1.00, green: 0.47, blue: 0.43)
    static let orange = Color(red: 1.00, green: 0.66, blue: 0.36)
    static let lemon = Color(red: 1.00, green: 0.82, blue: 0.30)
    static let mint = Color(red: 0.38, green: 0.84, blue: 0.68)
    static let sky = Color(red: 0.42, green: 0.70, blue: 1.00)
    static let lilac = Color(red: 0.66, green: 0.56, blue: 0.98)
    static let cocoa = Color(red: 0.33, green: 0.22, blue: 0.17)
    static let fur = Color(red: 0.90, green: 0.72, blue: 0.50)
    static let furLight = Color(red: 0.98, green: 0.90, blue: 0.76)
    static let furDark = Color(red: 0.45, green: 0.30, blue: 0.21)
    static let sand = Color(red: 0.96, green: 0.85, blue: 0.62)
    static let dirt = Color(red: 0.62, green: 0.45, blue: 0.30)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    func mixed(with other: NSColor, _ f: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(nsColor: base.blended(withFraction: f, of: other) ?? base)
    }
    var darker: Color { mixed(with: .black, 0.3) }
    var lighter: Color { mixed(with: .white, 0.5) }
}

extension View {
    /// Chunky "sticker" card with a coloured drop.
    func kawaiiCard(color: Color, radius: CGFloat = 22) -> some View {
        background(
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color.opacity(0.55)).offset(y: 5)
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white)
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color.opacity(0.45), lineWidth: 2)
            }
        )
    }
}

// MARK: - Buttons

struct BubblyButtonStyle: ButtonStyle {
    var color: Color = Theme.pink
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        BubblyBody(configuration: configuration, color: color, big: big)
    }
}

private struct BubblyBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let big: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.font(big ? 18 : 13.5, .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, big ? 28 : 16)
            .padding(.vertical, big ? 14 : 8)
            .background(
                ZStack {
                    Capsule().fill(color.darker).offset(y: pressed ? 1 : 4)
                    Capsule().fill(color).offset(y: pressed ? 2 : 0)
                    Capsule().fill(Color.white.opacity(0.28)).padding(.horizontal, 10).padding(.top, 3)
                        .frame(height: big ? 12 : 8).frame(maxHeight: .infinity, alignment: .top)
                        .offset(y: pressed ? 2 : 0)
                }
            )
            .offset(y: pressed ? 2 : 0)
            .scaleEffect(hover && enabled ? 1.05 : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: hover)
            .onHover { h in
                hover = h
                if h && enabled { Chiptune.shared.sfx(.blip) }
            }
    }
}

struct RoundIconButton: View {
    let symbol: String
    var color: Color = Theme.cocoa
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: { Chiptune.shared.sfx(.pop); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(hover ? 1 : 0.7)))
                .scaleEffect(hover ? 1.14 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { hover = h } }
    }
}

// MARK: - Small pieces

struct IconBlob: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.36, style: .continuous).fill(color.opacity(0.22))
            Image(systemName: symbol).font(.system(size: size * 0.45, weight: .bold)).foregroundColor(color.darker)
        }
        .frame(width: size, height: size)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(Theme.font(10.5, .bold))
            .foregroundColor(color.darker)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.2)))
    }
}

struct RiskTag: View {
    let risk: Risk
    var body: some View { Pill(text: risk.label, color: risk.color) }
}

struct KawaiiCheckbox: View {
    let on: Bool
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? color : Color.white)
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? color.darker : Theme.cocoa.opacity(0.25), lineWidth: 2)
            if on {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .scaleEffect(on ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.45), value: on)
    }
}

struct SizeBar: View {
    let frac: Double
    let color: Color
    @State private var shown = 0.0
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cocoa.opacity(0.08))
                Capsule().fill(color).frame(width: max(6, g.size.width * CGFloat(shown)))
            }
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { shown = min(max(frac, 0), 1) } }
        .onChange(of: frac) { v in withAnimation(.spring()) { shown = min(max(v, 0), 1) } }
    }
}

struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct TypewriterText: View {
    let text: String
    @State private var count = 0
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text).opacity(0)
            Text(String(text.prefix(count)))
        }
        .task(id: text) {
            count = 0
            for i in 0...text.count {
                if Task.isCancelled { return }
                count = i
                try? await Task.sleep(nanoseconds: 18_000_000)
            }
        }
    }
}

struct SpeechBubble: View {
    let text: String
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            BubbleTail().fill(Color.white).frame(width: 14, height: 22).offset(x: 2)
            TypewriterText(text: text)
                .font(Theme.font(15.5, .semibold))
                .foregroundColor(Theme.cocoa)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.peach).offset(y: 4))
        }
    }
}

/// Number that counts up when it changes.
struct AnimatedBytes: View {
    let value: Int64
    @State private var shown: Double = 0
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .modifier(CountingBytes(value: shown))
            .onAppear { withAnimation(.easeOut(duration: 1.0)) { shown = Double(value) } }
            .onChange(of: value) { v in withAnimation(.easeOut(duration: 0.8)) { shown = Double(v) } }
    }
}

struct CountingBytes: AnimatableModifier {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    func body(content: Content) -> some View {
        Text(Fmt.bytes(Int64(value)))
    }
}

struct StripedProgress: View {
    let progress: Double?
    var color: Color = Theme.pink
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = Double(size.width), h = Double(size.height)
                let bg = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: h / 2)
                ctx.fill(bg, with: .color(Theme.cocoa.opacity(0.1)))
                var fw = w * 0.3
                var fx = (w - fw) * (sin(t * 2.2) * 0.5 + 0.5)
                if let p = progress {
                    fw = max(h, w * min(max(p, 0), 1))
                    fx = 0
                }
                let fill = Path(roundedRect: CGRect(x: fx, y: 0, width: fw, height: h), cornerRadius: h / 2)
                ctx.fill(fill, with: .color(color))
                var c2 = ctx
                c2.clip(to: fill)
                var x = -h * 2 + frac(t * 1.5) * 16 - 16
                while x < w + h {
                    var s = Path()
                    s.move(to: CGPoint(x: x, y: h))
                    s.addLine(to: CGPoint(x: x + h, y: 0))
                    s.addLine(to: CGPoint(x: x + h + 7, y: 0))
                    s.addLine(to: CGPoint(x: x + 7, y: h))
                    s.closeSubpath()
                    c2.fill(s, with: .color(Color.white.opacity(0.35)))
                    x += 16
                }
            }
        }
    }
}

/// Pastel gradient with slow floating bubbles and stars.
struct KawaiiBackground: View {
    private let colors = [Theme.pink, Theme.sky, Theme.lemon, Theme.lilac, Theme.mint]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = Double(size.width), h = Double(size.height)
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                         with: .linearGradient(Gradient(colors: [Theme.cream, Theme.peach.opacity(0.55), Theme.mint.opacity(0.45)]),
                                               startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
                for i in 0..<16 {
                    let seed = Double(i) * 12.9898
                    let speed = 8 + Double(i % 5) * 4
                    let y = (h + 40) - (t * speed + Double(i) * 97).truncatingRemainder(dividingBy: h + 80)
                    let x = (sin(seed) * 0.5 + 0.5) * w + sin(t * 0.5 + seed) * 20
                    let r = 6 + Double(i % 4) * 5
                    let c = colors[i % colors.count].opacity(0.22)
                    if i % 3 == 0 {
                        ctx.draw(Text("✦").font(.system(size: r * 2.2)).foregroundColor(c), at: CGPoint(x: x, y: y))
                    } else {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(c))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ConfettiView: View {
    @State private var start = Date()
    private let colors = [Theme.pink, Theme.lemon, Theme.sky, Theme.mint, Theme.lilac, Theme.coral]
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let w = Double(size.width), h = Double(size.height)
                for i in 0..<90 {
                    let s = Double(i)
                    let delay = (s * 0.037).truncatingRemainder(dividingBy: 1.2)
                    let tt = t - delay
                    if tt < 0 { continue }
                    let x0 = (sin(s * 91.7) * 0.5 + 0.5) * w
                    let fall = -20 + tt * (120 + (s * 13).truncatingRemainder(dividingBy: 90))
                    let y = fall.truncatingRemainder(dividingBy: h + 40)
                    let x = x0 + sin(tt * 3 + s) * 30
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(tt * (2 + s.truncatingRemainder(dividingBy: 3))))
                    let pw = 6 + s.truncatingRemainder(dividingBy: 5)
                    let ph = (10 + (s * 3).truncatingRemainder(dividingBy: 6)) * max(0.15, abs(cos(tt * 4 + s)))
                    c.fill(Path(roundedRect: CGRect(x: -pw / 2, y: -ph / 2, width: pw, height: ph), cornerRadius: 2),
                           with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct FileIcon: View {
    let url: URL
    var body: some View {
        Image(nsImage: IconCache.icon(url)).resizable().interpolation(.high)
    }
}
