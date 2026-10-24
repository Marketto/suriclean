package com.suriclean.app

import android.content.Context
import android.os.Build
import android.os.LocaleList
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * Translations shared with the other platforms: one flat JSON per language in the repo's i18n folder
 * (packaged as assets). The language follows the phone unless the user picks one in the 🌐 menu.
 * Missing keys fall back to English, then Italian.
 */
object L {
    data class Lang(val code: String, val name: String, val rtl: Boolean)

    @Volatile private var appCtx: Context? = null
    @Volatile var languages: List<Lang> = emptyList()
        private set
    private val tables = ConcurrentHashMap<String, Map<String, String>>()
    @Volatile private var current: Map<String, String> = emptyMap()

    /** Compose-observable current language code (changes recompose the whole UI). */
    var lang by mutableStateOf("it")
        private set
    /** Language picked by the user, or null when following the phone. */
    @Volatile var chosen: String? = null
        private set

    val isRtl: Boolean get() = languages.firstOrNull { it.code == lang }?.rtl == true
    val locale: Locale get() = Locale.forLanguageTag(lang)

    @Synchronized
    fun init(ctx: Context) {
        if (appCtx != null) return
        appCtx = ctx.applicationContext
        languages = try {
            val a = JSONArray(ctx.assets.open("languages.json").bufferedReader().use { it.readText() })
            (0 until a.length()).map { i ->
                val o = a.getJSONObject(i)
                Lang(o.getString("code"), o.getString("name"), o.optBoolean("rtl", false))
            }
        } catch (e: Exception) { listOf(Lang("it", "Italiano", false)) }
        chosen = ctx.getSharedPreferences("suri", 0).getString("lang", null)
        apply()
    }

    /** null = follow the phone's language. */
    fun set(code: String?) {
        chosen = code
        appCtx?.getSharedPreferences("suri", 0)?.edit()?.apply { if (code == null) remove("lang") else putString("lang", code) }?.apply()
        apply()
    }

    private fun apply() {
        val code = chosen?.takeIf { c -> languages.any { it.code == c } } ?: systemMatch()
        current = table(code)
        lang = code
    }

    private fun table(code: String): Map<String, String> = tables.getOrPut(code) {
        try {
            val o = JSONObject(appCtx!!.assets.open("$code.json").bufferedReader().use { it.readText() })
            val m = HashMap<String, String>(o.length() * 2)
            for (k in o.keys()) m[k] = o.getString(k)
            m
        } catch (e: Exception) { emptyMap() }
    }

    private fun match(loc: Locale): String? {
        val codes = languages.map { it.code }.toSet()
        val l = loc.language.lowercase()
        val mapped = when (l) {
            "zh" -> {
                val c = loc.country.uppercase()
                if (loc.script == "Hant" || c == "TW" || c == "HK" || c == "MO") "zh-Hant" else "zh-Hans"
            }
            "no", "nn", "nb" -> "nb"
            "iw" -> "he"
            else -> l
        }
        return mapped.takeIf { it in codes }
    }

    private fun systemMatch(): String {
        val list = if (Build.VERSION.SDK_INT >= 24) LocaleList.getDefault().let { ll -> (0 until ll.size()).map { ll[it] } } else listOf(Locale.getDefault())
        for (loc in list) match(loc)?.let { return it }
        return if (languages.any { it.code == "en" }) "en" else "it"
    }

    /** Translated text for [key], with {0}, {1}… replaced by [args]. */
    fun t(key: String, vararg args: Any): String {
        if (appCtx == null) return key
        var s = current[key] ?: table("en")[key] ?: table("it")[key] ?: key
        for ((i, a) in args.withIndex()) s = s.replace("{$i}", a.toString())
        return s
    }

    /** Plural: [keyBase].one when [n] is 1, otherwise [keyBase].other. */
    fun tp(keyBase: String, n: Number, vararg args: Any): String =
        t(if (n.toLong() == 1L && n.toDouble() == 1.0) "$keyBase.one" else "$keyBase.other", *args)
}
