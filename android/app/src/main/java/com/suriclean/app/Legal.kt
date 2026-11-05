package com.suriclean.app

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import org.json.JSONArray

/*
 * Legal documents (legal/README.md): the terms of use and privacy policy are accepted once, and again when
 * legal/VERSION changes; «Note legali» shows them at any time together with the licenses of the bundled
 * components. Texts are the shared `legal.*` keys; documents come from assets/legal/ (copied by gradle).
 */

/** One bundled component, from assets/legal/third-party.json. */
data class ThirdParty(val name: String, val by: String, val copyright: String?, val license: String, val url: String, val sameAuthor: Boolean)

object LegalDocs {
    fun asset(ctx: Context, path: String): String =
        try { ctx.assets.open(path).bufferedReader().use { it.readText() } } catch (e: Exception) { "" }

    /** Components shipped in the Android app. */
    fun components(ctx: Context): List<ThirdParty> = try {
        val a = JSONArray(asset(ctx, "legal/third-party.json"))
        (0 until a.length()).map { a.getJSONObject(it) }.filter { o ->
            val p = o.optJSONArray("platforms") ?: JSONArray()
            (0 until p.length()).any { p.optString(it) == "android" }
        }.map { o ->
            ThirdParty(o.optString("name"), o.optString("by"), o.optString("copyright").ifEmpty { null },
                o.optString("license"), o.optString("url"), o.optBoolean("sameAuthor", false))
        }
    } catch (e: Exception) { emptyList() }

    /** Full license text, in its original language; the MIT template gets the component's copyright line. */
    fun licenseText(ctx: Context, c: ThirdParty): String {
        val file = when {
            c.license.startsWith("Apache") -> "Apache-2.0.txt"
            c.license.startsWith("MPL") -> "MPL-2.0.txt"
            c.license.startsWith("OFL") -> "OFL-1.1.txt"
            else -> "MIT.txt"
        }
        val text = asset(ctx, "legal/licenses/$file")
        return if (file == "MIT.txt") text.replace("Copyright (c) <year> <copyright holders>", c.copyright ?: "Copyright (c) ${c.by}") else text
    }
}

private fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}

/** Paragraphs separated by a blank line; lines starting with «• » are bullets. */
@Composable
private fun LegalBody(text: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (para in text.split("\n\n")) {
            for (line in para.split("\n")) {
                if (line.startsWith("• ")) {
                    Row {
                        KText("•", 12.5.sp, bold = false, alpha = 0.8f, modifier = Modifier.width(14.dp))
                        KText(line.removePrefix("• "), 12.5.sp, bold = false, alpha = 0.8f, modifier = Modifier.weight(1f))
                    }
                } else if (line.isNotBlank()) KText(line, 12.5.sp, bold = false, alpha = 0.8f)
            }
        }
    }
}

/** Terms or privacy: title, date and sections s1…sN of `legal.<kind>`. */
@Composable
private fun LegalDoc(kind: String, version: String) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        KText(L.t("legal.$kind.title"), 18.sp)
        KText(L.t("legal.updated", version), 11.sp, bold = false, alpha = 0.55f)
        var i = 1
        while (L.t("legal.$kind.s$i.title") != "legal.$kind.s$i.title") {
            KText(L.t("legal.$kind.s$i.title"), 14.sp)
            LegalBody(L.t("legal.$kind.s$i.body"))
            i++
        }
    }
}

@Composable
private fun LicensesTab(onOpen: (String, String) -> Unit) {
    val ctx = LocalContext.current
    val comps = remember { LegalDocs.components(ctx) }
    val appLicense = remember { LegalDocs.asset(ctx, "legal/LICENSE") }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        KText(L.t("legal.lic.title"), 18.sp)
        KText(L.t("legal.lic.intro"), 12.5.sp, bold = false, alpha = 0.8f)
        LicenseRow("SuriClean", L.t("legal.lic.app"), "MIT") { onOpen("SuriClean · MIT", appLicense) }
        for (c in comps) {
            val who = if (c.sameAuthor) L.t("legal.lic.same_author") else L.t("legal.lic.by", c.by)
            LicenseRow(c.name, "$who · ${c.url}", c.license) { onOpen("${c.name} · ${c.license}", LegalDocs.licenseText(ctx, c)) }
        }
    }
}

@Composable
private fun LicenseRow(name: String, sub: String, license: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.7f), RoundedCornerShape(14.dp)).clickable(onClick = onClick)
        .padding(horizontal = 12.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            KText(name, 13.sp)
            KText(sub, 10.5.sp, bold = false, alpha = 0.6f)
        }
        KText(license, 11.sp, color = Kawaii.lilac.darker(), modifier = Modifier.padding(start = 8.dp))
        KText("  📄", 13.sp)
    }
}

/** «Note legali»: full-screen, three tabs (terms, privacy, licenses); tapping a license shows its full text. */
@Composable
fun LegalViewer(version: String, start: Int = 0, onClose: () -> Unit) {
    var tab by remember { mutableIntStateOf(start) }
    var license by remember { mutableStateOf<Pair<String, String>?>(null) }
    Dialog(onDismissRequest = { if (license != null) license = null else onClose() },
        properties = DialogProperties(usePlatformDefaultWidth = false)) {
        WithDirection {
            Column(Modifier.fillMaxSize().background(Kawaii.cream).statusBarsPadding().navigationBarsPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    KText(L.t("legal.link.title"), 18.sp, modifier = Modifier.weight(1f))
                    BubblyButton(L.t("legal.close"), Kawaii.lilac) { if (license != null) license = null else onClose() }
                }
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(L.t("legal.link.terms"), L.t("legal.link.privacy"), L.t("legal.link.licenses")).forEachIndexed { i, label ->
                        BubblyButton(label, if (tab == i && license == null) Kawaii.hot else Kawaii.sky) { tab = i; license = null; Chiptune.sfx(Sfx.POP) }
                    }
                }
                Spacer(Modifier.height(8.dp))
                val lic = license
                Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 14.dp)) {
                    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
                        if (lic != null) {
                            KText(lic.first, 15.sp)
                            Spacer(Modifier.height(8.dp))
                            Text(lic.second, style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 10.5.sp, color = Kawaii.cocoa))
                        } else when (tab) {
                            0 -> LegalDoc("terms", version)
                            1 -> LegalDoc("privacy", version)
                            else -> LicensesTab { title, text -> license = title to text }
                        }
                    }
                }
            }
        }
    }
}

/** First launch (or new legal/VERSION): cannot be dismissed; the checkbox must be ticked to accept, «Esci» closes the app. */
@Composable
fun LegalConsentDialog(vm: AppVM) {
    val ctx = LocalContext.current
    var checked by remember { mutableStateOf(false) }
    var open by remember { mutableStateOf<Int?>(null) }
    Dialog(onDismissRequest = {}, properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false, usePlatformDefaultWidth = false)) {
        WithDirection {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)), contentAlignment = Alignment.Center) {
                Column(Modifier.padding(18.dp).fillMaxWidth().heightIn(max = 640.dp).kawaiiCard(Kawaii.lilac, 28.dp).padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(9.dp),
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        Suri(Act.WAVE, 100.dp)
                        KText(L.t("legal.consent.title"), 19.sp)
                        if (vm.legalUpdated) KText(L.t("legal.consent.updated"), 12.5.sp, color = Kawaii.coral.darker())
                        KText(L.t("legal.consent.intro"), 13.sp, bold = false, alpha = 0.85f)
                        for (k in listOf("p1", "p2", "p3", "p4")) {
                            Row(Modifier.fillMaxWidth()) {
                                KText("•", 12.5.sp, bold = false, alpha = 0.8f, modifier = Modifier.width(14.dp))
                                KText(L.t("legal.consent.$k"), 12.5.sp, bold = false, alpha = 0.8f, modifier = Modifier.weight(1f))
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            KText("📄 " + L.t("legal.link.terms"), 13.sp, color = Kawaii.sky.darker(), modifier = Modifier.clickable { open = 0 }.padding(4.dp))
                            KText("🔒 " + L.t("legal.link.privacy"), 13.sp, color = Kawaii.sky.darker(), modifier = Modifier.clickable { open = 1 }.padding(4.dp))
                        }
                    }
                    Row(Modifier.fillMaxWidth().clickable { checked = !checked }, verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = checked, onCheckedChange = { checked = it },
                            colors = CheckboxDefaults.colors(checkedColor = Kawaii.hot, uncheckedColor = Kawaii.cocoa))
                        KText(L.t("legal.consent.check"), 12.5.sp, modifier = Modifier.weight(1f))
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally)) {
                        BubblyButton(L.t("legal.consent.decline"), Kawaii.sky) { ctx.findActivity()?.finishAffinity() }
                        BubblyButton(L.t("legal.consent.accept"), Kawaii.hot, enabled = checked) { vm.acceptLegal() }
                    }
                }
            }
        }
    }
    open?.let { LegalViewer(vm.legalVersion, it) { open = null } }
}
