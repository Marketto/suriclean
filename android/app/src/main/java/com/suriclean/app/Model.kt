package com.suriclean.app

import androidx.compose.ui.graphics.Color

enum class Risk(private val key: String, val color: Color) {
    SAFE("safe", Kawaii.mint),
    REVIEW("review", Kawaii.orange),
    CAREFUL("careful", Kawaii.coral);

    val label: String get() = L.t("and.risk.$key")
}

enum class Act { IDLE, WAVE, DIGGING, DETECTIVE, SWEEPING, READING, SLEEPY, SNIFFING, LOOKOUT, CELEBRATING }

/** Texts come from the translations at use time, so a language change shows up right away. */
enum class Category(
    val emoji: String,
    val color: Color,
    val risk: Risk,
    val act: Act,
    val viewOnly: Boolean = false,
) {
    MAP("🗺️", Kawaii.lemon, Risk.CAREFUL, Act.DIGGING, viewOnly = true),
    CHATS("💬", Kawaii.mint, Risk.REVIEW, Act.SNIFFING),
    DUPLICATES("👯", Kawaii.lilac, Risk.REVIEW, Act.DETECTIVE),
    BIG("🦖", Kawaii.pink, Risk.CAREFUL, Act.DIGGING),
    DOWNLOADS("📥", Kawaii.sky, Risk.REVIEW, Act.LOOKOUT),
    APKS("📦", Kawaii.orange, Risk.SAFE, Act.LOOKOUT),
    JUNK("🧹", Kawaii.coral, Risk.SAFE, Act.SWEEPING),
    SYSTEM("⚙️", Kawaii.sky, Risk.REVIEW, Act.SWEEPING),
    APPS("😴", Kawaii.lilac, Risk.CAREFUL, Act.SLEEPY);

    private val k get() = name.lowercase()
    val title: String get() = L.t("and.cat.$k.title")
    val subtitle: String get() = L.t("and.cat.$k.subtitle")
    val explain: String get() = L.t("and.cat.$k.explain")
    val scanTitle: String get() = L.t("and.cat.$k.scan")
}

data class Item(
    val id: Long,
    val path: String,
    val name: String,
    val detail: String,
    val size: Long,
    val date: Long?,            // millis
    val risk: Risk,
    val recommended: Boolean,
    val badges: List<String> = emptyList(),
    val group: Int? = null,
    val groupLabel: String? = null,
    val packageName: String? = null,   // for apps
    val isDir: Boolean = false,
    val appBytes: Long = 0,            // for apps: the program itself (size - appBytes = data)
)

data class Busy(
    val act: Act,
    val title: String,
    val detail: String = "",
    val progress: Float? = 0f,
    val found: Int = 0,
    val foundBytes: Long = 0,
    val step: Int = 0,
    val steps: Int = 1,
)

data class Celebration(val title: String, val subtitle: String, val message: String = "", val offerEmptyTrash: Boolean = false)

data class AppUpdate(val version: String, val url: String)

data class Slice(val name: String, val bytes: Long, val color: androidx.compose.ui.graphics.Color, val note: String)
