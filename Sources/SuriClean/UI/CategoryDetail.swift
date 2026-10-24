import SwiftUI
import AppKit

struct DupGroup: Identifiable {
    let id: Int
    let label: String
    let items: [CleanItem]
}

struct CategoryDetailView: View {
    let category: CleanCategory
    @EnvironmentObject var model: AppModel
    @State private var sort: SortMode
    @State private var query = ""
    @State private var confirm = false
    @AppStorage("suri.treeView") private var treeView = false

    init(category: CleanCategory) {
        self.category = category
        _sort = State(initialValue: category.defaultSort)
    }

    private var list: [CleanItem] {
        var l = model.items(category)
        if !query.isEmpty {
            l = l.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .size: l.sort { $0.size > $1.size }
        case .date: l.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        case .name: l.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return l
    }

    private func groups(_ l: [CleanItem]) -> [DupGroup] {
        let dict = Dictionary(grouping: l, by: { $0.group ?? -1 })
        return dict.map { key, value in
            DupGroup(id: key, label: value.first?.groupLabel ?? "",
                     items: value.sorted { ($0.recommended ? 1 : 0) < ($1.recommended ? 1 : 0) })
        }
        .sorted { $0.items.totalSize > $1.items.totalSize }
    }

    var body: some View {
        let l = list
        let selected = model.selectedItems(category)
        let maxSize = max(l.map { $0.size }.max() ?? 1, 1)
        VStack(spacing: 0) {
            header(count: l.count)
            if category == .diskMap && !model.diskBreakdown.isEmpty && model.results[category] != nil {
                DiskBreakdownCard().padding(.horizontal, 24).padding(.bottom, 4)
            }
            if model.results[category] == nil {
                emptyState(scanned: false)
            } else if l.isEmpty {
                emptyState(scanned: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if treeView || category == .diskMap {
                            TreeListView(items: l, sort: sort, color: category.color, selectable: category != .diskMap)
                        } else if category == .duplicates {
                            ForEach(groups(l)) { g in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "doc.on.doc.fill").foregroundColor(category.color.darker)
                                        Text(g.label).font(Theme.font(13, .heavy)).lineLimit(1)
                                    }
                                    .padding(.leading, 6)
                                    ForEach(g.items) { ItemRow(item: $0, maxSize: maxSize, color: category.color) }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(category.color.opacity(0.08)))
                            }
                        } else {
                            ForEach(l) { ItemRow(item: $0, maxSize: maxSize, color: category.color) }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
            if category == .diskMap { mapFooter } else { footer(selected: selected) }
        }
        .alert("Spostare nel Cestino?", isPresented: $confirm) {
            Button("Annulla", role: .cancel) {}
            Button("Sì, spazza spazza! 🧹", role: .destructive) { model.clean(category) }
        } message: {
            Text("\(selected.count) elementi per \(Fmt.bytes(selected.totalSize)) finiranno nel Cestino: potrai ancora recuperarli finché non lo svuoti.")
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                IconBlob(symbol: category.icon, color: category.color, size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(category.title).font(Theme.font(26, .heavy))
                        RiskTag(risk: category.risk)
                    }
                    Text(category.explain)
                        .font(Theme.font(12.5, .medium)).opacity(0.68)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.results[category] != nil {
                        Text("\(count) elementi · \(Fmt.bytes(model.displayTotal(category)))")
                            .font(Theme.font(12.5, .heavy))
                            .foregroundColor(category.color.darker)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    if category == .diskMap {
                        Button(action: { model.scanFullDisk() }) {
                            Label("Tutto il disco", systemImage: "lock.shield.fill")
                        }
                        .buttonStyle(BubblyButtonStyle(color: Theme.orange))
                        .disabled(model.busy != nil)
                        .help("Misura tutto il disco, compresi gli altri utenti e le cartelle di sistema (chiede la password una volta)")
                    }
                    Button(action: { model.rescan(category) }) {
                        Label("Riscansiona", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(BubblyButtonStyle(color: Theme.sky))
                    .disabled(model.busy != nil)
                }
                .padding(.top, 4)
                MeerkatView(activity: category.activity, size: 96)
            }
            HStack(spacing: 10) {
                if model.fullScanDone && category != .diskMap {
                    Picker("", selection: $model.scope) {
                        Text("🐾 Io").tag(AppModel.Scope.me)
                        Text("👥 Tutti").tag(AppModel.Scope.all)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .labelsHidden()
                    .onChange(of: model.scope) { _ in Chiptune.shared.sfx(.pop) }
                    .help("Mostra solo le tue cose o anche quelle degli altri utenti")
                }
                if category != .diskMap {
                Picker("", selection: $treeView) {
                    Label("Lista", systemImage: "list.bullet").tag(false)
                    Label("Albero", systemImage: "list.bullet.indent").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .labelsHidden()
                .onChange(of: treeView) { _ in Chiptune.shared.sfx(.pop) }
                }
                Picker("", selection: $sort) {
                    ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .labelsHidden()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").opacity(0.5)
                    TextField("Cerca…", text: $query).textFieldStyle(.plain).font(Theme.font(13, .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.85)))
                .frame(minWidth: 110, maxWidth: 240)
                .layoutPriority(-1)
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 10)
    }

    private func emptyState(scanned: Bool) -> some View {
        VStack(spacing: 14) {
            Spacer()
            MeerkatView(activity: scanned ? .celebrating : category.activity, size: 170)
            Text(scanned ? "Pika-pika! Qui è tutto lucido ✨" : "Questa zona è ancora un mistero~ ♡")
                .font(Theme.font(19, .heavy))
            if !scanned {
                Button(action: { model.rescan(category) }) { Label("Esploriamo! ☆", systemImage: "pawprint.fill") }
                    .buttonStyle(BubblyButtonStyle(color: category.color, big: true))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var mapFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundColor(category.color.darker)
            Text("La mappa serve solo a guardare ☆ Per liberare spazio usa le altre zone, oppure apri la cartella nel Finder con 📁")
                .font(Theme.font(12.5, .semibold)).opacity(0.7)
            Spacer()
            Text("Disco usato: \(Fmt.bytes(model.disk.used))").font(Theme.font(13, .heavy))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.7))
    }

    private func footer(selected: [CleanItem]) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(selected.count) selezionati").font(Theme.font(12, .bold)).opacity(0.6)
                AnimatedBytes(value: selected.totalSize).font(Theme.font(22, .heavy)).foregroundColor(category.color.darker)
            }
            Spacer()
            Button("Consigliati") { model.selectRecommended(category) }.buttonStyle(BubblyButtonStyle(color: Theme.mint))
            Button("Tutti") { model.selectAll(category) }.buttonStyle(BubblyButtonStyle(color: Theme.lilac))
            Button("Nessuno") { model.selectNone(category) }.buttonStyle(BubblyButtonStyle(color: Theme.lilac))
            Button(action: { Chiptune.shared.sfx(.pop); confirm = true }) {
                Label("Spazza via! ☆", systemImage: "trash.fill")
            }
            .buttonStyle(BubblyButtonStyle(color: Theme.coral, big: true))
            .disabled(selected.isEmpty || model.busy != nil)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.7))
    }
}

struct ItemRow: View {
    let item: CleanItem
    let maxSize: Int64
    let color: Color
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            row
            if item.isGitRepo && item.owner.isEmpty && model.expandedRepos.contains(item.id) {
                GitRepoPanel(item: item, color: color)
                    .padding(.leading, 34)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var row: some View {
        let selected = model.selection.contains(item.id)
        let expanded = model.expandedRepos.contains(item.id)
        return HStack(spacing: 12) {
            if item.isGitRepo && item.owner.isEmpty {
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.toggleRepo(item) } }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(color.darker)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Mostra rami e stash")
            }
            KawaiiCheckbox(on: selected, color: color)
            FileIcon(url: item.url).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(Theme.font(14, .bold)).lineLimit(1)
                    if item.risk == .careful { RiskTag(risk: .careful) }
                    ForEach(item.badges, id: \.self) { Pill(text: $0, color: color) }
                }
                Text(item.detail)
                    .font(Theme.font(11, .medium)).opacity(0.58)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.bytes(item.size)).font(Theme.font(14, .heavy))
                SizeBar(frac: Double(item.size) / Double(maxSize), color: color).frame(width: 90, height: 7)
            }
            if let copy = item.copyText {
                RoundIconButton(symbol: "doc.on.clipboard", color: color.darker) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copy, forType: .string)
                    model.showToast("Copiato! Il git clone è al sicuro ♡")
                }
                .help(copy)
            }
            RoundIconButton(symbol: "magnifyingglass", color: color.darker) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .help("Mostra nel Finder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? color.opacity(0.16) : Color.white.opacity(hover ? 0.97 : 0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? color.opacity(0.6) : Color.clear, lineWidth: 2)
        )
        .scaleEffect(hover ? 1.006 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { model.toggle(item) } }
    }
}


struct DiskBreakdownCard: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmSnaps = false
    @State private var showDenied = false

    private func color(_ k: DiskSlice.Kind) -> Color {
        switch k {
        case .measured: return Theme.lemon
        case .system: return Theme.sky
        case .vm: return Theme.lilac
        case .boot: return Theme.mint
        case .hidden: return Theme.coral
        case .purgeable: return Theme.peach
        case .other: return Theme.orange
        }
    }

    var body: some View {
        let slices = model.diskBreakdown
        let total = max(slices.reduce(Int64(0)) { $0 + $1.size }, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dove sono tutti i GB? ☆").font(Theme.font(15, .heavy))
                Text("occupati sul disco: \(Fmt.bytes(model.disk.used))").font(Theme.font(11.5, .bold)).opacity(0.55)
                Spacer()
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(slices) { sl in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color(sl.kind))
                            .frame(width: max(4, (g.size.width - CGFloat(slices.count) * 2) * CGFloat(Double(sl.size) / Double(total))))
                            .help("\(sl.name): \(Fmt.bytes(sl.size))")
                    }
                }
            }
            .frame(height: 16)
            .clipShape(Capsule())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10, alignment: .topLeading)], alignment: .leading, spacing: 8) {
                ForEach(slices) { sl in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(color(sl.kind)).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(sl.name).font(Theme.font(12.5, .heavy))
                                Text(Fmt.bytes(sl.size)).font(Theme.font(12.5, .heavy)).foregroundColor(color(sl.kind).darker)
                            }
                            Text(sl.note).font(Theme.font(10.5, .medium)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                if !model.diskMapIsFull {
                    Button(action: { model.scanFullDisk() }) { Label("Misura tutto il disco", systemImage: "lock.shield.fill") }
                        .buttonStyle(BubblyButtonStyle(color: Theme.orange))
                }
                if model.snapshotNames.contains(where: { !$0.hasPrefix("com.apple.os.update") }) {
                    Button(action: { Chiptune.shared.sfx(.pop); confirmSnaps = true }) {
                        Label("Elimina \(model.snapshotNames.count) istantanee", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(BubblyButtonStyle(color: Theme.sky))
                }
                if !model.hasFDA {
                    Button(action: { model.openFDASettings() }) { Label("Accesso completo al disco", systemImage: "lock.open.fill") }
                        .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                }
                Spacer()
            }
            .disabled(model.busy != nil)
            if !model.deniedPaths.isEmpty {
                Button(action: { withAnimation(.spring(response: 0.3)) { showDenied.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                            .rotationEffect(.degrees(showDenied ? 90 : 0))
                        Text("🔒 \(model.deniedPaths.count) cartelle che macOS non ha lasciato leggere")
                            .font(Theme.font(12, .heavy))
                    }
                }
                .buttonStyle(.plain)
                if showDenied {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.deniedPaths.prefix(15)), id: \.self) { p in
                            Text(p).font(.system(size: 11, design: .monospaced)).opacity(0.7).lineLimit(1).truncationMode(.middle)
                        }
                        if model.deniedPaths.count > 15 {
                            Text("…e altre \(model.deniedPaths.count - 15)").font(Theme.font(11, .bold)).opacity(0.5)
                        }
                        Text("Sono protette dalla privacy di macOS anche per l'amministratore. Se c'è la tua cartella, controlla che SuriClean abbia l'Accesso completo al disco (dopo un aggiornamento macOS a volte lo chiede di nuovo: togli e rimetti la spunta). Quelle degli altri utenti puoi controllarle solo entrando col loro account.")
                            .font(Theme.font(11, .medium)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(.leading, 18)
                }
            }
        }
        .padding(16)
        .kawaiiCard(color: Theme.lemon)
        .alert("Eliminare le istantanee locali?", isPresented: $confirmSnaps) {
            Button("Annulla", role: .cancel) {}
            Button("Sì, eliminale", role: .destructive) { model.deleteSnapshots() }
        } message: {
            Text("Sono copie del disco fatte da Time Machine o da altri programmi di backup: tengono occupato lo spazio dei file che hai già cancellato. I tuoi file attuali non vengono toccati e i backup sul disco esterno restano. Lascio stare quelle degli aggiornamenti di macOS.\n\n" + model.snapshotNames.prefix(6).joined(separator: "\n") + (model.snapshotNames.count > 6 ? "\n…" : ""))
        }
    }
}
