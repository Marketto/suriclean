import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 215), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !model.hasFDA { FDABanner() }
                HStack(alignment: .top, spacing: 16) {
                    DiskGauge(disk: model.disk, reclaimable: model.recommendedTotal)
                        .frame(width: 300)
                    TipsPanel()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Dove scaviamo oggi? ♡").font(Theme.font(23, .heavy))
                    Text("tocca una zona, pika!").font(Theme.font(13, .semibold)).opacity(0.5)
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(CleanCategory.allCases) { CategoryCard(category: $0) }
                }
            }
            .padding(28)
            .padding(.top, 8)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            MeerkatView(activity: .idle, size: 180)
            VStack(alignment: .leading, spacing: 16) {
                SpeechBubble(text: model.greeting)
                HStack(spacing: 14) {
                    Button(action: { model.scanAll() }) {
                        Label("Via allo scavo! ☆", systemImage: "sparkles")
                    }
                    .buttonStyle(BubblyButtonStyle(color: Theme.pink, big: true))
                    .disabled(model.busy != nil)
                    if model.recommendedTotal > 0 {
                        VStack(alignment: .leading, spacing: 0) {
                            AnimatedBytes(value: model.recommendedTotal)
                                .font(Theme.font(24, .heavy))
                                .foregroundColor(Theme.mint.darker)
                            Text("liberabili senza pensieri ✧").font(Theme.font(11.5, .semibold)).opacity(0.6)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct FDABanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            IconBlob(symbol: "lock.open.fill", color: Theme.orange, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Onegai~! Fammi entrare in tutte le stanze 🙏").font(Theme.font(15, .heavy))
                Text("Senza l'«Accesso completo al disco» non vedo backup iPhone, Mail, Messaggi e qualche cache. Impostazioni › Sicurezza e privacy › Privacy › Accesso completo al disco › aggiungi SuriClean, poi riapri l'app.")
                    .font(Theme.font(12, .medium)).opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Apri Impostazioni") { model.openFDASettings() }
                .buttonStyle(BubblyButtonStyle(color: Theme.orange))
            Button("Ricontrolla") { model.recheckFDA() }
                .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
        }
        .padding(16)
        .kawaiiCard(color: Theme.orange)
    }
}

struct DiskGauge: View {
    let disk: DiskInfo
    let reclaimable: Int64
    @State private var appear = false

    var body: some View {
        let used = disk.usedFraction
        let rec = min(Double(reclaimable) / Double(max(disk.total, 1)), used)
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.mint.opacity(0.22), lineWidth: 26)
                Circle()
                    .trim(from: 0, to: appear ? used : 0)
                    .stroke(LinearGradient(gradient: Gradient(colors: [Theme.peach, Theme.pink]), startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 26, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: appear ? max(0, used - rec) : used, to: used)
                    .stroke(Theme.mint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(used * 100))%").font(Theme.font(36, .heavy))
                    Text("pieno").font(Theme.font(13, .bold)).opacity(0.5)
                }
            }
            .frame(width: 168, height: 168)
            .padding(.top, 6)
            VStack(spacing: 6) {
                legend(Theme.pink, "Occupato", Fmt.bytes(disk.used))
                legend(Theme.mint.opacity(0.4), "Libero", Fmt.bytes(disk.availableImportant))
                legend(Theme.mint, "Liberabile (consigliato)", reclaimable > 0 ? Fmt.bytes(reclaimable) : "—")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .kawaiiCard(color: Theme.pink)
        .onAppear { withAnimation(.spring(response: 1.3, dampingFraction: 0.7)) { appear = true } }
        .animation(.spring(response: 0.9, dampingFraction: 0.75), value: reclaimable)
        .animation(.spring(response: 0.9, dampingFraction: 0.75), value: disk.availableImportant)
    }

    private func legend(_ c: Color, _ label: String, _ value: String) -> some View {
        HStack {
            Circle().fill(c).frame(width: 10, height: 10)
            Text(label).font(Theme.font(12.5, .semibold)).opacity(0.75)
            Spacer()
            Text(value).font(Theme.font(12.5, .heavy))
        }
    }
}

struct TipsPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trucchetti segreti di Suri ✧").font(Theme.font(18, .heavy))
            TipRow(icon: "trash.fill", color: Theme.coral, title: "Cestino",
                   note: "Lo spazio torna libero solo quando lo svuoti",
                   value: Fmt.bytes(model.trashSize),
                   buttonTitle: model.trashSize > 0 ? "Svuota" : nil) { model.askEmptyTrash = true }
            TipRow(icon: "clock.arrow.circlepath", color: Theme.sky, title: "Istantanee locali di Time Machine",
                   note: "Copie che macOS tiene sul disco interno",
                   value: model.snapshotCount.map { "\($0)" } ?? "…",
                   buttonTitle: (model.snapshotCount ?? 0) > 0 ? "Assottiglia" : nil) { model.thinSnapshots() }
            TipRow(icon: "icloud.fill", color: Theme.lilac, title: "Spazio «purgeable»",
                   note: "macOS lo libera da solo quando serve",
                   value: Fmt.bytes(model.disk.purgeable), buttonTitle: nil) {}
            TipRow(icon: "arrow.clockwise", color: Theme.mint, title: "Aggiorna i numeri del disco",
                   note: "Dopo aver svuotato il Cestino o disinstallato app",
                   value: "", buttonTitle: "Aggiorna") {
                model.refreshDisk(); model.refreshTrash(); model.refreshSnapshots()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kawaiiCard(color: Theme.sky)
    }
}

struct TipRow: View {
    let icon: String
    let color: Color
    let title: String
    let note: String
    let value: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBlob(symbol: icon, color: color, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(13.5, .bold))
                Text(note).font(Theme.font(11, .medium)).opacity(0.55)
            }
            Spacer()
            Text(value).font(Theme.font(14, .heavy))
            if let b = buttonTitle {
                Button(b, action: action).buttonStyle(BubblyButtonStyle(color: color))
            }
        }
    }
}

struct CategoryCard: View {
    let category: CleanCategory
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    var body: some View {
        let items = model.results[category]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                IconBlob(symbol: category.icon, color: category.color)
                    .rotationEffect(.degrees(hover ? -10 : 0))
                    .scaleEffect(hover ? 1.12 : 1)
                Spacer()
                RiskTag(risk: category.risk)
            }
            Text(category.title).font(Theme.font(16, .heavy))
            Text(category.subtitle)
                .font(Theme.font(12, .medium)).opacity(0.62)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let items = items {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AnimatedBytes(value: model.displayTotal(category))
                        .font(Theme.font(22, .heavy))
                        .foregroundColor(category.color.darker)
                    Text(items.isEmpty ? "pika-pika ✨" : "· \(items.count) elementi").font(Theme.font(11.5, .semibold)).opacity(0.55)
                }
            } else {
                Text("Ancora da esplorare~ 🐾").font(Theme.font(12.5, .bold)).opacity(0.45)
            }
        }
        .padding(16)
        .frame(height: 188, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kawaiiCard(color: category.color)
        .scaleEffect(hover ? 1.035 : 1)
        .rotationEffect(.degrees(hover ? -0.8 : 0))
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hover = h }
            if h { Chiptune.shared.sfx(.blip) }
        }
        .onTapGesture { model.open(category) }
    }
}
