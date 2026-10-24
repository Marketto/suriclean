package com.suriclean.app

import android.content.Intent
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.delay
import java.io.File

private val QUIPS = mapOf(
    Act.DIGGING to listOf("Hori-hori! Scavo scavo~ 🕳️", "Ooh! Qui sotto c'è qualcosa di ciccione!", "Zampette turbo attivate ☆"),
    Act.DETECTIVE to listOf("Hmm~ questi due sono gemellini! 🔍", "Confronto le impronte SHA-256, kira!", "Nessun gemello sfugge a Suri-chan!"),
    Act.SWEEPING to listOf("Saa~ spazza spazza! 🧹", "Bye-bye polverina digitale!", "Pika-pika, tutto lucido ✨"),
    Act.SNIFFING to listOf("Kun-kun! Sento le chat 👃", "Profumino di video ricevuti~", "Quanti vocali, waa!"),
    Act.LOOKOUT to listOf("Sentinella Suri, pronta! 👀", "Download antichi all'orizzonte!", "Dalla collinetta vedo tutto ☆"),
    Act.SLEEPY to listOf("Shh~ le app fanno la nanna 💤", "Questa dorme dal Pleistocene!", "Una pecorella, due pecorelle… ☁️"),
)

@Composable
fun SuriApp(vm: AppVM) {
    BackHandler(enabled = vm.view != null) { vm.open(null) }
    Box(Modifier.fillMaxSize()) {
        KawaiiBackground()
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            TopBar(vm)
            val v = vm.view
            if (v == null) Home(vm) else Detail(vm, v)
        }
        vm.toast?.let { t ->
            Box(Modifier.fillMaxSize().navigationBarsPadding().padding(bottom = 90.dp), contentAlignment = Alignment.BottomCenter) {
                KText(t, 13.sp, modifier = Modifier.padding(horizontal = 20.dp).kawaiiCard(Kawaii.lemon, 18.dp).padding(horizontal = 16.dp, vertical = 10.dp))
            }
        }
        AnimatedVisibility(vm.busy != null, enter = fadeIn() + scaleIn(initialScale = 0.92f), exit = fadeOut()) { vm.busy?.let { BusyOverlay(vm, it) } }
        AnimatedVisibility(vm.celebration != null, enter = fadeIn() + scaleIn(initialScale = 0.85f), exit = fadeOut()) { vm.celebration?.let { CelebrationOverlay(vm, it) } }
    }
}

@Composable
private fun TopBar(vm: AppVM) {
    Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.55f)).padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (vm.view != null) {
            KText("‹", 30.sp, modifier = Modifier.clickable { vm.open(null) }.padding(horizontal = 8.dp))
        }
        Suri(vm.busy?.act ?: Act.IDLE, 46.dp)
        Column(Modifier.weight(1f).padding(start = 6.dp)) {
            KText("SuriClean", 19.sp)
            KText("スリちゃん · spazzina kawaii", 10.sp, bold = false, alpha = 0.55f)
        }
        vm.update?.let { u -> BubblyButton("✨ ${u.version}", Kawaii.hot) { vm.installUpdate() } }
        KText(if (vm.muted) "🔇" else "🎵", 22.sp, modifier = Modifier.clickable { vm.toggleMute() }.padding(8.dp))
    }
}

// ───────────────────────── home ─────────────────────────

@Composable
private fun Home(vm: AppVM) {
    val ctx = LocalContext.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Suri(Act.IDLE, 150.dp)
            Column(Modifier.weight(1f)) {
                Box(Modifier.kawaiiCard(Kawaii.peach, 18.dp).padding(12.dp)) { Typewriter(vm.greeting(), 13.5.sp) }
            }
        }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BubblyButton("✨ Via allo scavo! ☆", Kawaii.hot, big = true, enabled = vm.busy == null) { vm.scanAll() }
            if (vm.recommendedTotal > 0) Row(verticalAlignment = Alignment.Bottom) {
                KText(Fs.bytes(vm.recommendedTotal), 20.sp, color = Kawaii.mint.darker())
                KText("  liberabili senza pensieri ✧", 11.sp, bold = false, alpha = 0.6f)
            }
        }
        if (!vm.hasFiles || !vm.hasUsage) PermissionsCard(vm)
        if (vm.askPerms) ConfirmDialog("Onegai~! Mi apri le porte? 🔑",
            (if (!vm.hasFiles) "📂 «Accesso a tutti i file» per guardare foto, video, Download, chat e le aree di sistema.\n" else "") +
            (if (!vm.hasUsage) "📊 «Accesso ai dati di utilizzo» per sapere quanto pesano le app e quando le usi.\n" else "") +
            "Ti porto io alle pagine giuste, una alla volta: accendi l'interruttore e torna indietro ♡ Leggo solo il telefono e non invio niente.",
            "Andiamo! ☆", onDismiss = { vm.snoozePerms() }) { vm.startPermTour() }
        StorageCard(vm)
        if (vm.breakdown.isNotEmpty()) BreakdownCard(vm)
        TipsCard(vm) { i -> ctx.startActivity(i) }
        Column {
            KText("Dove scaviamo oggi? ♡", 21.sp)
            KText("tocca una zona, pika!", 12.sp, bold = false, alpha = 0.5f)
        }
        Category.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                row.forEach { c -> ZoneCard(vm, c, Modifier.weight(1f)) }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        LevelCard(vm)
        Row(verticalAlignment = Alignment.CenterVertically) {
            KText("v${vm.version} · controlla aggiornamenti", 11.sp, alpha = 0.5f, modifier = Modifier.clickable { vm.checkUpdate(true) }.padding(vertical = 6.dp))
            Spacer(Modifier.weight(1f))
            KText(if (vm.autoUpdate) "🔄 auto ON" else "🔄 auto OFF", 11.sp, alpha = 0.6f, modifier = Modifier.clickable { vm.setAuto(!vm.autoUpdate) }.padding(6.dp))
        }
        Spacer(Modifier.height(30.dp))
    }
}

@Composable
private fun PermissionsCard(vm: AppVM) {
    val ctx = LocalContext.current
    Column(Modifier.fillMaxWidth().kawaiiCard(Kawaii.orange).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        KText("Onegai~! Fammi entrare 🙏", 16.sp)
        if (!vm.hasFiles) {
            KText("Per guardare foto, video, Download e chat mi serve l'«Accesso a tutti i file». Leggo solo la memoria del telefono e non invio niente a nessuno.", 12.sp, bold = false, alpha = 0.75f)
            BubblyButton("📂 Accesso a tutti i file", Kawaii.orange) { vm.startPermTour() }
        }
        if (!vm.hasUsage) {
            KText("Per sapere quanto pesano le app e quando le hai usate l'ultima volta mi serve l'«Accesso ai dati di utilizzo».", 12.sp, bold = false, alpha = 0.75f)
            BubblyButton("📊 Accesso ai dati di utilizzo", Kawaii.lilac) { vm.startPermTour() }
        }
    }
}

@Composable
private fun StorageCard(vm: AppVM) {
    val (total, free) = vm.storage
    val used = (total - free).coerceAtLeast(0)
    val frac = if (total > 0) used.toFloat() / total else 0f
    val rec = if (total > 0) (vm.recommendedTotal.toFloat() / total).coerceAtMost(frac) else 0f
    Row(Modifier.fillMaxWidth().kawaiiCard(Kawaii.pink).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(120.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize().padding(8.dp)) {
                val st = 18.dp.toPx()
                drawArc(Kawaii.mint.copy(alpha = 0.22f), 0f, 360f, false, style = Stroke(st))
                drawArc(Brush.sweepGradient(listOf(Kawaii.peach, Kawaii.pink, Kawaii.peach)), -90f, 360f * frac, false, style = Stroke(st, cap = StrokeCap.Round))
                if (rec > 0) drawArc(Kawaii.mint, -90f + 360f * (frac - rec), 360f * rec, false, style = Stroke(st * 0.45f, cap = StrokeCap.Round))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                KText("${(frac * 100).toInt()}%", 26.sp)
                KText("pieno", 11.sp, alpha = 0.5f)
            }
        }
        Column(Modifier.weight(1f).padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Legend(Kawaii.pink, "Occupato", Fs.bytes(used))
            Legend(Kawaii.mint.copy(alpha = 0.4f), "Libero", Fs.bytes(free))
            Legend(Kawaii.mint, "Liberabile", if (vm.recommendedTotal > 0) Fs.bytes(vm.recommendedTotal) else "—")
            Legend(Kawaii.lemon, "Trovato", if (vm.foundTotal > 0) Fs.bytes(vm.foundTotal) else "—")
        }
    }
}

@Composable
private fun Legend(c: Color, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).background(c, RoundedCornerShape(50)))
        KText(label, 11.sp, bold = false, alpha = 0.75f, maxLines = 1, modifier = Modifier.padding(start = 6.dp).weight(1f))
        KText(value, 11.5.sp, maxLines = 1)
    }
}

@Composable
private fun TipsCard(vm: AppVM, start: (Intent) -> Unit) {
    var askEmpty by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().kawaiiCard(Kawaii.sky).padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        KText("Trucchetti segreti di Suri ✧", 16.sp)
        TipRow("🗑️", "Cestino di Suri", "Lo spazio torna libero quando lo svuoti", Fs.bytes(vm.trashSize),
            if (vm.trashSize > 0) "Svuota" else null, Kawaii.coral) { askEmpty = true }
        TipRow("🧽", "Cache di tutte le app", if (vm.appCache > 0) "Una sola conferma di Android, le app le ricreano" else "Scansiona le «App dormienti» per vedere quanto pesano",
            if (vm.appCache > 0) Fs.bytes(vm.appCache) else "", if (Build.VERSION.SDK_INT >= 25) "Pulisci" else null, Kawaii.mint) {
            vm.clearAllCaches()
        }
    }
    if (askEmpty) ConfirmDialog("Svuotare il Cestino di Suri?", "Tutto ciò che c'è dentro (${Fs.bytes(vm.trashSize)}) verrà eliminato per sempre.", "Svuota per sempre",
        onDismiss = { askEmpty = false }) { askEmpty = false; vm.emptyTrash() }
}

@Composable
private fun TipRow(icon: String, title: String, note: String, value: String, button: String?, color: Color, onClick: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(36.dp).background(color.copy(alpha = 0.22f), RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) { KText(icon, 17.sp) }
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
            KText(title, 13.sp); KText(note, 10.5.sp, bold = false, alpha = 0.55f)
        }
        KText(value, 13.sp, modifier = Modifier.padding(end = 8.dp))
        button?.let { BubblyButton(it, color, onClick = onClick) }
    }
}

@Composable
private fun ZoneCard(vm: AppVM, c: Category, modifier: Modifier) {
    val r = vm.results[c]
    Column(modifier.height(170.dp).kawaiiCard(c.color).clickable { vm.open(c) }.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Box(Modifier.size(40.dp).background(c.color.copy(alpha = 0.22f), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) { KText(c.emoji, 20.sp) }
            Spacer(Modifier.weight(1f))
            Pill(c.risk.label, c.risk.color)
        }
        KText(c.title, 14.5.sp, maxLines = 2)
        KText(c.subtitle, 11.sp, bold = false, alpha = 0.62f, maxLines = 2)
        Spacer(Modifier.weight(1f))
        if (r != null) KText(if (r.isEmpty()) "pika-pika ✨" else "${Fs.bytes(vm.displayTotal(c))} · ${r.size}", 15.sp, color = c.color.darker())
        else KText("Ancora da esplorare~ 🐾", 11.5.sp, alpha = 0.45f)
    }
}

@Composable
private fun LevelCard(vm: AppVM) {
    val (name, prog, next) = vm.level()
    Column(Modifier.fillMaxWidth().kawaiiCard(Kawaii.mint, 16.dp).padding(12.dp)) {
        KText(name, 13.sp)
        KText("Liberati in totale: ${Fs.bytes(vm.freed)}", 10.5.sp, bold = false, alpha = 0.6f)
        StripedProgress(prog.coerceAtLeast(0.04f), Kawaii.mint, Modifier.fillMaxWidth().padding(vertical = 6.dp).height(9.dp))
        KText(next, 10.sp, bold = false, alpha = 0.5f)
    }
}

// ───────────────────────── detail ─────────────────────────

private class Node(val path: String, var name: String) {
    val kids = LinkedHashMap<String, Node>()
    var children: List<Node> = emptyList()
    var item: Item? = null
    var size = 0L
    var ids: List<Long> = emptyList()
}

private fun buildTree(list: List<Item>, sort: Int): List<Node> {
    val root = Node("", "")
    for (it in list) {
        var n = root; var path = ""
        for (p in it.path.split('/').filter { s -> s.isNotEmpty() }) {
            path += "/$p"
            n = n.kids.getOrPut(p) { Node(path, p) }
        }
        n.item = it
    }
    fun finish(n: Node) {
        n.children = n.kids.values.toList()
        n.children.forEach { finish(it) }
        val sum = n.children.sumOf { it.size }
        n.size = n.item?.let { maxOf(it.size, sum) } ?: sum
        n.ids = n.children.flatMap { it.ids } + listOfNotNull(n.item?.id)
        n.children = when (sort) { 1 -> n.children.sortedBy { it.item?.date ?: 0 }; 2 -> n.children.sortedBy { it.name.lowercase() }; else -> n.children.sortedByDescending { it.size } }
    }
    finish(root)
    fun compress(n: Node): Node {
        var c = n
        while (c.item == null && c.children.size == 1) { val o = c.children[0]; o.name = c.name + "/" + o.name; c = o }
        c.children = c.children.map { compress(it) }
        return c
    }
    return root.children.map { compress(it) }.onEach { it.name = Fs.pretty(File(it.path)) }
}

@Composable
private fun Detail(vm: AppVM, c: Category) {
    var sort by rememberSaveable(c) { mutableIntStateOf(if (c == Category.DOWNLOADS) 1 else 0) }
    var tree by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable(c) { mutableStateOf("") }
    var confirm by remember { mutableStateOf(false) }
    var expanded by remember(c) { mutableStateOf(setOf<String>()) }
    val all = vm.items(c)
    val list = all.filter { query.isEmpty() || it.name.contains(query, true) || it.detail.contains(query, true) }.let { l ->
        when (sort) { 1 -> l.sortedBy { it.date ?: 0 }; 2 -> l.sortedBy { it.name.lowercase() }; else -> l.sortedByDescending { it.size } }
    }
    val max = (list.maxOfOrNull { it.size } ?: 1).coerceAtLeast(1)
    val treeMode = (tree || c.viewOnly) && c != Category.APPS
    val sel = vm.selected(c)

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(48.dp).background(c.color.copy(alpha = 0.22f), RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) { KText(c.emoji, 24.sp) }
                Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                    KText(c.title, 20.sp)
                    Row { Pill(c.risk.label, c.risk.color) }
                }
                Suri(c.act, 74.dp)
            }
            KText(c.explain, 11.5.sp, bold = false, alpha = 0.68f)
            if (vm.results[c] != null) KText("${all.size} elementi · ${Fs.bytes(vm.displayTotal(c))}", 12.sp, color = c.color.darker())
            if (c == Category.MAP && vm.breakdown.isNotEmpty()) BreakdownCard(vm)
            if (c == Category.APPS && !vm.hasUsage) KText("⚠️ Senza l'«Accesso ai dati di utilizzo» Android non mi dice quanto pesano le app: attivalo dalla tana ♡", 11.5.sp, color = Kawaii.coral.darker())
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!c.viewOnly && c != Category.APPS) SegmentRow(listOf("☰ Lista" to !tree, "🌳 Albero" to tree), c.color) { tree = it == 1; expanded = emptySet() }
                SegmentRow(listOf("Più grandi" to (sort == 0), "Più vecchi" to (sort == 1), "Nome" to (sort == 2)), c.color) { sort = it }
                BubblyButton("🔄", Kawaii.sky, enabled = vm.busy == null) { vm.rescan(c) }
            }
            BasicTextField(query, { query = it }, singleLine = true, textStyle = ktext(13.sp, false),
                modifier = Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.85f), RoundedCornerShape(50)).padding(horizontal = 14.dp, vertical = 9.dp),
                decorationBox = { inner -> Box { if (query.isEmpty()) KText("🔍 Cerca…", 13.sp, bold = false, alpha = 0.45f); inner() } })
        }
        Box(Modifier.weight(1f)) {
            when {
                vm.results[c] == null -> Empty(c, false) { vm.rescan(c) }
                list.isEmpty() -> Empty(c, true) {}
                treeMode -> {
                    val roots = remember(list, sort) { buildTree(list, sort) }
                    if (expanded.isEmpty()) LaunchedEffect(roots) {
                        expanded = roots.flatMap { r -> listOf(r.path) + r.children.take(8).filter { it.children.isNotEmpty() }.map { it.path } }.toSet()
                    }
                    val rows = ArrayList<Pair<Node, Int>>()
                    fun walk(ns: List<Node>, d: Int) { ns.forEach { n -> rows.add(n to d); if (n.path in expanded) walk(n.children, d + 1) } }
                    walk(roots, 0)
                    val tmax = (roots.maxOfOrNull { it.size } ?: 1).coerceAtLeast(1)
                    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        items(rows, key = { it.first.path }) { (n, d) ->
                            TreeRow(vm, c, n, d, tmax, n.path in expanded) {
                                expanded = if (n.path in expanded) expanded - n.path else expanded + n.path; Chiptune.sfx(Sfx.BLIP)
                            }
                        }
                    }
                }
                else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    items(list, key = { it.id }) { ItemRow(vm, c, it, max) }
                }
            }
        }
        if (c.viewOnly) {
            KText("ℹ️ La mappa serve solo a guardare ☆ Per liberare spazio usa le altre zone.", 11.5.sp, bold = false, alpha = 0.7f,
                modifier = Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.7f)).padding(14.dp))
        } else Column(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.75f)).padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    KText("${sel.size} selezionati", 11.sp, alpha = 0.6f)
                    KText(Fs.bytes(vm.total(sel)), 19.sp, color = c.color.darker())
                }
                BubblyButton(if (c == Category.APPS) "🗑️ Disinstalla ☆" else "🧹 Spazza via! ☆", Kawaii.coral, big = true, enabled = sel.isNotEmpty() && vm.busy == null) { confirm = true }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BubblyButton("Consigliati", Kawaii.mint) { vm.selRecommended(c) }
                BubblyButton("Tutti", Kawaii.lilac) { vm.setSel(all.map { it.id }, true) }
                BubblyButton("Nessuno", Kawaii.lilac) { vm.setSel(all.map { it.id }, false) }
            }
        }
    }
    if (confirm) ConfirmDialog(
        if (c == Category.APPS) "Disinstallare ${sel.size} app?" else "Spostare nel Cestino di Suri?",
        if (c == Category.APPS) "Android ti chiederà conferma per ognuna. I loro dati verranno eliminati."
        else "${sel.size} elementi per ${Fs.bytes(vm.total(sel))} finiranno nel Cestino di Suri: potrai recuperarli finché non lo svuoti.",
        if (c == Category.APPS) "Sì, disinstalla" else "Sì, spazza spazza! 🧹", onDismiss = { confirm = false }) { confirm = false; vm.clean(c) }
}

@Composable
private fun Empty(c: Category, scanned: Boolean, onScan: () -> Unit) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Suri(if (scanned) Act.CELEBRATING else c.act, 150.dp)
        KText(if (scanned) "Pika-pika! Qui è tutto lucido ✨" else "Questa zona è ancora un mistero~ ♡", 17.sp, modifier = Modifier.padding(12.dp))
        if (!scanned) BubblyButton("🐾 Esploriamo! ☆", c.color, big = true, onClick = onScan)
    }
}

@Composable
private fun AppIcon(pkg: String) {
    val ctx = LocalContext.current
    val bmp = remember(pkg) {
        try { val d: Drawable = ctx.packageManager.getApplicationIcon(pkg); d.toBitmap(96, 96).asImageBitmap() } catch (e: Exception) { null }
    }
    if (bmp != null) Image(bmp, null, Modifier.size(34.dp)) else KText("📱", 22.sp)
}

private fun emojiFor(it: Item): String {
    if (it.isDir) return "📁"
    return when (it.path.substringAfterLast('.', "").lowercase()) {
        "mp4", "mkv", "mov", "3gp", "webm" -> "🎬"; "jpg", "jpeg", "png", "heic", "webp", "gif" -> "🖼️"
        "mp3", "m4a", "opus", "ogg", "wav", "flac" -> "🎵"; "apk", "xapk" -> "📦"; "pdf" -> "📄"; "zip", "rar", "7z" -> "🗜️"
        else -> "📄"
    }
}

private fun openItem(ctx: android.content.Context, it: Item) {
    try {
        val f = File(it.path)
        if (f.isDirectory) return
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", f)
        val mime = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(f.extension.lowercase()) ?: "*/*"
        ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), it.name))
    } catch (e: Exception) { /* no viewer */ }
}

@Composable
private fun ItemRow(vm: AppVM, c: Category, it: Item, max: Long) {
    val ctx = LocalContext.current
    val on = it.id in vm.selection
    Row(Modifier.fillMaxWidth()
        .background(if (on) c.color.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.85f), RoundedCornerShape(16.dp))
        .clickable(remember { MutableInteractionSource() }, null) { vm.toggle(it) }
        .padding(horizontal = 10.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        Checkbox(on, color = c.color)
        Box(Modifier.padding(horizontal = 8.dp).size(34.dp), contentAlignment = Alignment.Center) {
            if (it.packageName != null) AppIcon(it.packageName) else KText(emojiFor(it), 22.sp)
        }
        Column(Modifier.weight(1f)) {
            KText(it.name, 13.5.sp, maxLines = 1)
            if (it.badges.isNotEmpty() || it.risk == Risk.CAREFUL && it.packageName == null && c != Category.MAP) Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                it.badges.forEach { b -> Pill(b, c.color) }
            }
            KText(it.detail, 10.5.sp, bold = false, alpha = 0.58f, maxLines = 1)
        }
        Column(horizontalAlignment = Alignment.End, modifier = Modifier.width(78.dp).padding(start = 6.dp)) {
            KText(Fs.bytes(it.size), 13.sp, maxLines = 1)
            SizeBar(it.size.toFloat() / max, c.color, Modifier.fillMaxWidth().padding(top = 4.dp).height(6.dp))
        }
        if (it.packageName == null && !it.isDir) KText("👁️", 16.sp, modifier = Modifier.clickable { openItem(ctx, it) }.padding(start = 6.dp))
        if (it.packageName != null) KText("⚙️", 18.sp, modifier = Modifier.clickable { vm.openAppSettings(it.packageName) }.padding(start = 6.dp))
    }
}

@Composable
private fun TreeRow(vm: AppVM, c: Category, n: Node, depth: Int, max: Long, open: Boolean, toggle: () -> Unit) {
    val ctx = LocalContext.current
    val nsel = n.ids.count { it in vm.selection }
    val all = nsel == n.ids.size && nsel > 0
    val folder = n.item == null || n.children.isNotEmpty()
    Row(Modifier.fillMaxWidth().padding(start = (depth * 14).dp)
        .background(if (all) c.color.copy(alpha = 0.18f) else if (folder) c.color.copy(alpha = 0.07f).compositeOverWhite() else Color.White.copy(alpha = 0.85f), RoundedCornerShape(14.dp))
        .clickable { if (c.viewOnly) { if (n.children.isNotEmpty()) toggle() } else vm.setSel(n.ids, !all) }
        .padding(horizontal = 8.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
        KText(if (n.children.isEmpty()) " " else if (open) "▾" else "▸", 16.sp, color = c.color.darker(),
            modifier = Modifier.width(22.dp).clickable(enabled = n.children.isNotEmpty()) { toggle() })
        if (!c.viewOnly) Checkbox(all, nsel > 0 && !all, c.color)
        KText(if (folder) "📁" else n.item?.let { emojiFor(it) } ?: "📄", 18.sp, modifier = Modifier.padding(horizontal = 6.dp))
        Column(Modifier.weight(1f)) {
            KText(if (!folder) n.item!!.name else n.name, 12.5.sp, maxLines = 1)
            if (n.item == null) KText("${n.ids.size} elementi", 10.sp, bold = false, alpha = 0.5f)
            else if (n.item!!.badges.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { n.item!!.badges.take(2).forEach { Pill(it, c.color) } }
        }
        Column(horizontalAlignment = Alignment.End, modifier = Modifier.width(74.dp)) {
            KText(Fs.bytes(n.size), 12.5.sp, maxLines = 1)
            SizeBar(n.size.toFloat() / max, c.color, Modifier.fillMaxWidth().padding(top = 3.dp).height(5.dp))
        }
        if (!folder) KText("👁️", 15.sp, modifier = Modifier.clickable { openItem(ctx, n.item!!) }.padding(start = 6.dp))
    }
}

private fun Color.compositeOverWhite(): Color = Color(
    red = red * alpha + (1 - alpha), green = green * alpha + (1 - alpha), blue = blue * alpha + (1 - alpha), alpha = 0.9f)

// ───────────────────────── overlays ─────────────────────────

@Composable
fun ConfirmDialog(title: String, text: String, ok: String, onDismiss: () -> Unit, onOk: () -> Unit) {
    // a real window on top of everything: placed inline it ended up below the screen and never showed
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.25f)).clickable(remember { MutableInteractionSource() }, null) { onDismiss() },
        contentAlignment = Alignment.Center) {
        Column(Modifier.padding(24.dp).kawaiiCard(Kawaii.coral, 30.dp).clickable(remember { MutableInteractionSource() }, null) {}.padding(22.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Suri(Act.SWEEPING, 110.dp)
            KText(title, 18.sp)
            KText(text, 12.5.sp, bold = false, alpha = 0.7f)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                BubblyButton("Annulla", Kawaii.lilac, onClick = onDismiss)
                BubblyButton(ok, Kawaii.coral, onClick = onOk)
            }
        }
    }
    }
}

@Composable
private fun BusyOverlay(vm: AppVM, b: Busy) {
    var qi by remember { mutableIntStateOf(0) }
    LaunchedEffect(b.act) { while (true) { delay(2600); qi++ } }
    val q = QUIPS[b.act] ?: listOf("…")
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.22f)).clickable(remember { MutableInteractionSource() }, null) {}, contentAlignment = Alignment.Center) {
        Column(Modifier.padding(20.dp).kawaiiCard(Kawaii.lemon, 32.dp).padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Suri(b.act, 190.dp)
            KText(b.title, 19.sp)
            KText(q[qi % q.size], 13.sp, bold = false, alpha = 0.75f)
            StripedProgress(b.progress, Kawaii.pink, Modifier.fillMaxWidth().height(16.dp))
            KText(b.detail.ifEmpty { " " }, 10.5.sp, bold = false, alpha = 0.55f, maxLines = 1)
            if (b.found > 0) KText("Bottino ☆ ${Fs.bytes(b.foundBytes)} · ${b.found} elementi", 12.sp, color = Kawaii.mint.darker())
            if (b.steps > 1) KText("Zona ${b.step + 1} di ${b.steps}", 11.sp, alpha = 0.45f)
            BubblyButton("Annulla", Kawaii.lilac) { vm.cancelJob() }
        }
    }
}

@Composable
private fun CelebrationOverlay(vm: AppVM, c: Celebration) {
    var askEmpty by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.2f)).clickable(remember { MutableInteractionSource() }, null) { vm.dismissCelebration() }, contentAlignment = Alignment.Center) {
        Confetti()
        Column(Modifier.padding(20.dp).kawaiiCard(Kawaii.pink, 32.dp).padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Suri(Act.CELEBRATING, 190.dp)
            KText(c.title, 26.sp)
            KText(c.subtitle, 15.sp)
            if (c.message.isNotEmpty()) KText(c.message, 12.sp, bold = false, alpha = 0.65f)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (c.offerEmptyTrash && vm.trashSize > 0) BubblyButton("🗑️ Svuota il Cestino", Kawaii.coral) { askEmpty = true }
                BubblyButton("Arigatō! ♡", Kawaii.mint) { vm.dismissCelebration() }
            }
        }
    }
    if (askEmpty) ConfirmDialog("Svuotare il Cestino di Suri?", "Tutto ciò che c'è dentro (${Fs.bytes(vm.trashSize)}) verrà eliminato per sempre.", "Svuota per sempre",
        onDismiss = { askEmpty = false }) { askEmpty = false; vm.emptyTrash() }
}


@Composable
private fun BreakdownCard(vm: AppVM) {
    val slices = vm.breakdown
    val total = slices.sumOf { it.bytes }.coerceAtLeast(1)
    Column(Modifier.fillMaxWidth().kawaiiCard(Kawaii.lemon).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        KText("Dove sono tutti i GB? ☆", 15.sp)
        KText("memoria da ${Fs.bytes(vm.storage.first)} · come la conta Android", 11.sp, bold = false, alpha = 0.55f)
        Row(Modifier.fillMaxWidth().height(16.dp).background(Kawaii.cocoa.copy(alpha = 0.06f), RoundedCornerShape(50))) {
            slices.forEach { sl ->
                val w = (sl.bytes.toFloat() / total).coerceAtLeast(0.004f)
                Box(Modifier.weight(w).fillMaxSize().padding(horizontal = 1.dp).background(sl.color, RoundedCornerShape(4.dp)))
            }
        }
        slices.forEach { sl ->
            Row(verticalAlignment = Alignment.Top) {
                Box(Modifier.padding(top = 4.dp).size(10.dp).background(sl.color, RoundedCornerShape(50)))
                Column(Modifier.weight(1f).padding(start = 8.dp)) {
                    Row { KText(sl.name, 12.5.sp, modifier = Modifier.weight(1f)); KText(Fs.bytes(sl.bytes), 12.5.sp, color = sl.color.darker()) }
                    KText(sl.note, 10.5.sp, bold = false, alpha = 0.58f)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            BubblyButton("😴 App pesanti", Kawaii.sky) { vm.open(Category.APPS) }
            BubblyButton("🧽 Pulisci cache", Kawaii.mint) { vm.clearAllCaches() }
        }
    }
}
