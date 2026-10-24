import SwiftUI
import AppKit

@main
struct SuriCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    init() {
        // Started as the admin helper for another user's folder? Do the job without UI and quit.
        HelperMode.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("SuriClean") {
            ContentView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Suri") {
                Button("Scansiona tutto") { model.scanAll() }.keyboardShortcut("r")
                Button("Torna alla tana") { model.open(nil) }.keyboardShortcut("0")
                Button("Controlla aggiornamenti…") { Task { await model.checkForUpdates(manual: true) } }
                Button(model.muted ? "Attiva musica" : "Silenzia musica") { model.muted.toggle() }.keyboardShortcut("m")
                Button(model.remix ? "Musica originale" : "Musica remix 🎧") { model.remix.toggle() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Svuota il Cestino…") { model.askEmptyTrash = true }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        // a downloaded update is swapped in right after we quit
        Updater.pendingApply?()
        Updater.pendingApply = nil
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            KawaiiBackground()
            HStack(spacing: 0) {
                Sidebar()
                ZStack {
                    if let cat = model.selectedCategory {
                        CategoryDetailView(category: cat)
                            .id(cat)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    } else {
                        DashboardView()
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(Theme.font(13.5, .bold))
                        .foregroundColor(Theme.cocoa)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .kawaiiCard(color: Theme.lemon, radius: 18)
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let busy = model.busy {
                LoadingOverlay(state: busy)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            if let c = model.celebration {
                CelebrationOverlay(c: c)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            if let p = model.passwordPrompt {
                PasswordOverlay(prompt: p)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .foregroundColor(Theme.cocoa)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.selectedCategory)
        .animation(.easeInOut(duration: 0.25), value: model.busy != nil)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: model.celebration?.id)
        .animation(.spring(), value: model.toast)
        .preferredColorScheme(.light)
        .frame(minWidth: 1060, minHeight: 690)
        .onAppear { model.start() }
        .confirmationDialog("Dove scaviamo? ☆", isPresented: $model.askScanScope, titleVisibility: .visible) {
            Button("🐾 Solo la mia cartella") { model.scanAll(full: false) }
            Button("💽 Tutto il disco, tutti gli utenti 🔐") { model.scanAll(full: true) }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("«Tutto il disco» chiede la password una volta e guarda anche le cartelle degli altri utenti e di sistema. Poi in ogni zona potrai filtrare «Io» o «Tutti».")
        }
        .sheet(isPresented: $model.showFDAGuide) { FDAGuide().environmentObject(model) }
        .alert("Svuotare il Cestino?", isPresented: $model.askEmptyTrash) {
            Button("Annulla", role: .cancel) {}
            Button("Svuota per sempre", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Tutto ciò che è nel Cestino (\(Fmt.bytes(model.trashSize))) verrà eliminato definitivamente, anche le cose che non ci ha messo Suri.")
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MeerkatView(activity: model.busy?.activity ?? .idle, size: 56)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SuriClean").font(Theme.font(21, .heavy))
                    Text("スリちゃん · spazzina kawaii").font(Theme.font(11, .semibold)).opacity(0.55)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 4)

            SidebarRow(icon: "house.fill", title: "La tana ♡", color: Theme.lemon,
                       selected: model.selectedCategory == nil, trailing: nil) { model.open(nil) }

            Text("ZONE DI SCAVO ☆").font(Theme.font(10, .heavy)).opacity(0.4).padding(.top, 6).padding(.leading, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(CleanCategory.allCases) { cat in
                        SidebarRow(icon: cat.icon, title: cat.title, color: cat.color,
                                   selected: model.selectedCategory == cat,
                                   trailing: model.results[cat].map { _ in Fmt.bytes(model.displayTotal(cat)) }) { model.open(cat) }
                    }
                }
            }

            UpdatePill()
            LevelCard()

            HStack {
                Button(action: { model.muted.toggle(); Chiptune.shared.sfx(.pop) }) {
                    Label(model.muted ? "Musica in pausa~" : "Musica pikopiko ♪",
                          systemImage: model.muted ? "speaker.slash.fill" : "music.note")
                        .font(Theme.font(12, .bold))
                }
                .buttonStyle(.plain)
                .opacity(0.7)
                Spacer()
                Button(action: { model.remix.toggle(); if model.muted { model.muted = false }; Chiptune.shared.sfx(.pop) }) {
                    Text(model.remix ? "🎧 Remix ON" : "🎧 Remix")
                        .font(Theme.font(11, .heavy))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(model.remix ? Theme.pink.opacity(0.85) : Color.white.opacity(0.6)))
                        .foregroundColor(model.remix ? .white : Theme.cocoa)
                }
                .buttonStyle(.plain)
                .help("Versione remix: dubstep/trap con basso wobble")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 12)
        .frame(width: 252)
        .background(Color.white.opacity(0.5))
    }
}

struct SidebarRow: View {
    let icon: String
    let title: String
    let color: Color
    let selected: Bool
    let trailing: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? color : color.opacity(0.22))
                    Image(systemName: icon).font(.system(size: 12.5, weight: .bold)).foregroundColor(selected ? .white : color.darker)
                }
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(hover ? -8 : 0))
                Text(title).font(Theme.font(13, .bold)).lineLimit(1)
                Spacer(minLength: 4)
                if let trailing = trailing {
                    Text(trailing)
                        .font(Theme.font(10.5, .heavy))
                        .foregroundColor(color.darker)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.18)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white : (hover ? Color.white.opacity(0.7) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? color : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .offset(x: hover && !selected ? 3 : 0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { hover = h }
            if h { Chiptune.shared.sfx(.blip) }
        }
    }
}

struct LevelCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let lv = model.level
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lv.emoji).font(.system(size: 20))
                VStack(alignment: .leading, spacing: 0) {
                    Text(lv.title).font(Theme.font(13, .heavy))
                    Text("Liberati in totale: \(Fmt.bytes(model.totalFreed))").font(Theme.font(10.5, .semibold)).opacity(0.6)
                }
            }
            StripedProgress(progress: max(0.04, lv.progress), color: Theme.mint).frame(height: 9)
            Text(lv.next).font(Theme.font(10, .semibold)).opacity(0.5)
        }
        .padding(12)
        .kawaiiCard(color: Theme.mint, radius: 16)
        .padding(.vertical, 6)
    }
}


struct UpdatePill: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            switch model.updateState {
            case .ready:
                Button(action: { model.installUpdateNow() }) {
                    HStack(spacing: 8) {
                        Text("✨").font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Nuova versione \(model.update?.version ?? "")!").font(Theme.font(12.5, .heavy))
                            Text("Riavvia e aggiorna ☆").font(Theme.font(10.5, .bold)).opacity(0.75)
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.pink))
                }
                .buttonStyle(.plain)
            case .downloading:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                    Text("Scarico la versione \(model.update?.version ?? "")…").font(Theme.font(11.5, .bold)).opacity(0.7)
                }
                .padding(.horizontal, 8)
            case .failed(let msg):
                Button(action: { Task { await model.downloadUpdate() } }) {
                    Text("Aggiornamento non riuscito, riprova 🔄").font(Theme.font(11.5, .bold)).foregroundColor(Theme.coral.darker)
                }
                .buttonStyle(.plain)
                .help(msg)
                .padding(.horizontal, 8)
            default:
                HStack(spacing: 6) {
                    Button(action: { Task { await model.checkForUpdates(manual: true) } }) {
                        Text(model.updateState == .checking ? "Controllo aggiornamenti…" : "v\(Updater.currentVersion) · controlla aggiornamenti")
                            .font(Theme.font(10.5, .bold)).opacity(0.5)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Toggle("auto", isOn: $model.autoUpdate)
                        .toggleStyle(.switch).controlSize(.mini)
                        .font(Theme.font(10, .bold))
                        .help("Scarica e installa da sola le nuove versioni")
                }
                .padding(.horizontal, 8)
            }
        }
    }
}
