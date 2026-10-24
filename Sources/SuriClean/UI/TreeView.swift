import SwiftUI
import AppKit

/// Folder tree built from the found items' paths.
final class TreeNode: Identifiable {
    let id: String          // absolute path of this node
    var name: String
    var children: [TreeNode] = []
    var childIndex: [String: TreeNode] = [:]
    var item: CleanItem?
    var size: Int64 = 0
    var itemIDs: [UUID] = []
    var newest: Date?

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    var isLeafItem: Bool { item != nil && children.isEmpty }
}

enum TreeBuilder {
    static func build(_ items: [CleanItem], sort: SortMode) -> [TreeNode] {
        let root = TreeNode(id: "", name: "")
        for it in items {
            var node = root
            var path = ""
            for c in it.url.standardizedFileURL.pathComponents where c != "/" {
                path += "/" + c
                if let n = node.childIndex[c] {
                    node = n
                } else {
                    let n = TreeNode(id: path, name: c)
                    node.childIndex[c] = n
                    node.children.append(n)
                    node = n
                }
            }
            node.item = it
        }
        finish(root, sort: sort)
        let top = root.children.map { compress($0) }
        for n in top { n.name = FS.pretty(URL(fileURLWithPath: n.id)) }
        return top
    }

    private static func finish(_ n: TreeNode, sort: SortMode) {
        var childSum: Int64 = 0
        var ids: [UUID] = []
        var newest = n.item?.date
        for c in n.children {
            finish(c, sort: sort)
            childSum += c.size
            ids += c.itemIDs
            if let d = c.newest, d > (newest ?? .distantPast) { newest = d }
        }
        if let it = n.item { ids.append(it.id) }
        n.itemIDs = ids
        n.size = n.item.map { max($0.size, childSum) } ?? childSum
        n.newest = newest
        switch sort {
        case .size: n.children.sort { $0.size > $1.size }
        case .date: n.children.sort { ($0.newest ?? .distantPast) < ($1.newest ?? .distantPast) }
        case .name: n.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Merges chains of single-child folders: "Library" › "Caches" becomes "Library/Caches".
    private static func compress(_ n: TreeNode) -> TreeNode {
        var cur = n
        while cur.item == nil, cur.children.count == 1 {
            let only = cur.children[0]
            only.name = cur.name + "/" + only.name
            cur = only
        }
        cur.children = cur.children.map { compress($0) }
        return cur
    }
}

struct TreeRowData: Identifiable {
    let node: TreeNode
    let depth: Int
    var id: String { node.id }
}

struct TreeListView: View {
    let items: [CleanItem]
    let sort: SortMode
    let color: Color
    var selectable: Bool = true
    @EnvironmentObject var model: AppModel
    @State private var expanded: Set<String> = []
    @State private var didInit = false

    var body: some View {
        let roots = TreeBuilder.build(items, sort: sort)
        let rows = flatten(roots)
        let maxSize = max(roots.map { $0.size }.max() ?? 1, 1)
        LazyVStack(spacing: 4) {
            HStack(spacing: 8) {
                Button(t("mac.tree.expand")) { withAnimation(.spring(response: 0.35)) { expanded = allIDs(roots) }; Chiptune.shared.sfx(.pop) }
                    .buttonStyle(BubblyButtonStyle(color: Theme.sky))
                Button(t("mac.tree.collapse")) { withAnimation(.spring(response: 0.35)) { expanded = [] }; Chiptune.shared.sfx(.pop) }
                    .buttonStyle(BubblyButtonStyle(color: Theme.lilac))
                Spacer()
            }
            .padding(.bottom, 6)
            ForEach(rows) { r in
                TreeRowView(node: r.node, depth: r.depth, maxSize: maxSize, color: color,
                            isExpanded: expanded.contains(r.node.id), selectable: selectable) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if expanded.contains(r.node.id) { expanded.remove(r.node.id) } else { expanded.insert(r.node.id) }
                    }
                    Chiptune.shared.sfx(.blip)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            // open the first two levels so the structure is visible at a glance
            var open = Set<String>()
            for r in roots where !r.children.isEmpty {
                open.insert(r.id)
                for c in r.children.prefix(8) where !c.children.isEmpty { open.insert(c.id) }
            }
            expanded = open
        }
    }

    private func flatten(_ nodes: [TreeNode], depth: Int = 0) -> [TreeRowData] {
        var out: [TreeRowData] = []
        for n in nodes {
            out.append(TreeRowData(node: n, depth: depth))
            if expanded.contains(n.id) { out += flatten(n.children, depth: depth + 1) }
        }
        return out
    }

    private func allIDs(_ nodes: [TreeNode]) -> Set<String> {
        var s = Set<String>()
        for n in nodes where !n.children.isEmpty {
            s.insert(n.id)
            s.formUnion(allIDs(n.children))
        }
        return s
    }
}

struct TreeRowView: View {
    let node: TreeNode
    let depth: Int
    let maxSize: Int64
    let color: Color
    let isExpanded: Bool
    var selectable: Bool = true
    let toggleExpand: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    var body: some View {
        let selectedCount = node.itemIDs.filter { model.selection.contains($0) }.count
        let all = selectedCount == node.itemIDs.count && selectedCount > 0
        let partial = selectedCount > 0 && !all
        HStack(spacing: 10) {
            Color.clear.frame(width: CGFloat(depth) * 20, height: 1)
            if !node.children.isEmpty {
                Button(action: toggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(color.darker)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            if selectable { KawaiiCheckbox(on: all, color: color, partial: partial) }
            if let it = node.item {
                FileIcon(url: it.url).frame(width: 26, height: 26)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 17))
                    .foregroundColor(color)
                    .frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.item?.name ?? node.name)
                        .font(Theme.font(13, node.item == nil ? .heavy : .bold))
                        .lineLimit(1).truncationMode(.middle)
                    if let it = node.item {
                        ForEach(it.badges, id: \.self) { Pill(text: $0, color: color) }
                    } else {
                        Pill(text: t("mac.tree.count", node.itemIDs.count), color: color)
                    }
                }
                if let it = node.item, depth == 0 || !node.children.isEmpty {
                    Text(it.detail).font(Theme.font(10.5, .medium)).opacity(0.55).lineLimit(1).truncationMode(.middle)
                } else if node.item != nil {
                    Text(node.name).font(Theme.font(10.5, .medium)).opacity(0.5).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.bytes(node.size)).font(Theme.font(13, .heavy))
                SizeBar(frac: Double(node.size) / Double(maxSize), color: color).frame(width: 80, height: 6)
            }
            if let it = node.item, node.children.isEmpty || selectable {
                RoundIconButton(symbol: "magnifyingglass", color: color.darker) {
                    NSWorkspace.shared.activateFileViewerSelecting([it.url])
                }
                .help(t("mac.reveal"))
            } else {
                RoundIconButton(symbol: "folder", color: color.darker) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: node.id))
                }
                .help(t("mac.tree.open"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(all ? color.opacity(0.15) : (node.item == nil ? color.opacity(hover ? 0.12 : 0.06) : Color.white.opacity(hover ? 0.97 : 0.78)))
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture {
            if selectable {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    model.setSelection(node.itemIDs, on: !all)
                }
            } else if !node.children.isEmpty {
                toggleExpand()
            }
        }
    }
}
