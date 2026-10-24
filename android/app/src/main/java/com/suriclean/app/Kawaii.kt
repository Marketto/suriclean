package com.suriclean.app

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

object Kawaii {
    val cream = Color(0xFFFFF7E8)
    val peach = Color(0xFFFFCCAD)
    val pink = Color(0xFFFF80A8)
    val hot = Color(0xFFFF5A82)
    val coral = Color(0xFFFF786E)
    val orange = Color(0xFFFFA85C)
    val lemon = Color(0xFFFFD14D)
    val mint = Color(0xFF61D6AD)
    val sky = Color(0xFF6CB2FF)
    val lilac = Color(0xFFA88FFA)
    val cocoa = Color(0xFF54382B)
    val sand = Color(0xFFF5D99E)
    val font = FontFamily(Font(R.font.mplus_rounded_medium, FontWeight.Medium), Font(R.font.mplus_rounded_extrabold, FontWeight.ExtraBold))
}

fun Color.darker(f: Float = 0.3f) = lerp(this, Color.Black, f)

fun ktext(size: TextUnit, bold: Boolean = true, color: Color = Kawaii.cocoa) =
    TextStyle(fontFamily = Kawaii.font, fontWeight = if (bold) FontWeight.ExtraBold else FontWeight.Medium, fontSize = size, color = color)

@Composable
fun KText(text: String, size: TextUnit = 14.sp, bold: Boolean = true, color: Color = Kawaii.cocoa, modifier: Modifier = Modifier,
          maxLines: Int = Int.MAX_VALUE, alpha: Float = 1f) {
    Text(text, modifier, style = ktext(size, bold, color.copy(alpha = color.alpha * alpha)), maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

/** Sticker-like card with a coloured drop shadow. */
fun Modifier.kawaiiCard(color: Color, radius: Dp = 22.dp) = this
    .drawBehind {
        drawRoundRect(color.copy(alpha = 0.55f), Offset(0f, 5.dp.toPx()), size, CornerRadius(radius.toPx()))
    }
    .background(Color.White, RoundedCornerShape(radius))
    .border(2.dp, color.copy(alpha = 0.45f), RoundedCornerShape(radius))

@Composable
fun BubblyButton(text: String, color: Color = Kawaii.pink, big: Boolean = false, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed) 0.94f else 1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy), label = "press")
    Box(
        modifier
            .scale(s)
            .drawBehind {
                val r = CornerRadius(size.height / 2)
                drawRoundRect(color.darker(), Offset(0f, if (pressed) 1.dp.toPx() else 4.dp.toPx()), size, r)
                drawRoundRect(color, Offset(0f, if (pressed) 2.dp.toPx() else 0f), size, r)
                drawRoundRect(Color.White.copy(alpha = 0.28f), Offset(size.height * 0.4f, 3.dp.toPx()), Size(size.width - size.height * 0.8f, 6.dp.toPx()), CornerRadius(3.dp.toPx()))
            }
            .clickable(src, null, enabled = enabled) { Chiptune.sfx(Sfx.POP); onClick() }
            .padding(horizontal = if (big) 26.dp else 15.dp, vertical = if (big) 13.dp else 8.dp)
            .offset(y = if (pressed) 2.dp else 0.dp),
        contentAlignment = Alignment.Center,
    ) {
        KText(text, if (big) 17.sp else 13.sp, color = Color.White.copy(alpha = if (enabled) 1f else 0.5f), maxLines = 1)
    }
}

@Composable
fun Pill(text: String, color: Color) {
    KText(text, 10.5.sp, color = color.darker(), maxLines = 1,
        modifier = Modifier.background(color.copy(alpha = 0.2f), RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 2.dp))
}

@Composable
fun Checkbox(on: Boolean, partial: Boolean = false, color: Color) {
    val s by animateFloatAsState(if (on) 1.1f else 1f, spring(dampingRatio = Spring.DampingRatioHighBouncy), label = "chk")
    Box(Modifier.size(24.dp).scale(s)
        .background(if (on) color else if (partial) color.copy(alpha = 0.35f) else Color.White, RoundedCornerShape(8.dp))
        .border(2.dp, if (on || partial) color.darker() else Kawaii.cocoa.copy(alpha = 0.25f), RoundedCornerShape(8.dp)),
        contentAlignment = Alignment.Center) {
        if (on) KText("🐾", 10.sp) else if (partial) KText("–", 14.sp, color = Color.White)
    }
}

@Composable
fun SizeBar(frac: Float, color: Color, modifier: Modifier = Modifier) {
    val v by animateFloatAsState(frac.coerceIn(0.02f, 1f), spring(dampingRatio = 0.7f, stiffness = 120f), label = "bar")
    Canvas(modifier) {
        drawRoundRect(Kawaii.cocoa.copy(alpha = 0.08f), cornerRadius = CornerRadius(size.height / 2))
        drawRoundRect(color, size = Size(size.width * v, size.height), cornerRadius = CornerRadius(size.height / 2))
    }
}

/** Candy-striped progress bar; null progress = bouncing. */
@Composable
fun StripedProgress(progress: Float?, color: Color = Kawaii.pink, modifier: Modifier = Modifier) {
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) { val s = System.nanoTime(); while (true) withFrameNanos { t = ((it - s) / 1e9).toFloat() } }
    Canvas(modifier) {
        val h = size.height; val w = size.width
        drawRoundRect(Kawaii.cocoa.copy(alpha = 0.1f), cornerRadius = CornerRadius(h / 2))
        val fw = if (progress == null) w * 0.3f else maxOf(h, w * progress.coerceIn(0f, 1f))
        val fx = if (progress == null) (w - fw) * (sin(t * 2.2f) * 0.5f + 0.5f) else 0f
        val bar = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(fx, 0f, fx + fw, h, CornerRadius(h / 2))) }
        drawPath(bar, color)
        clipPath(bar) {
            var x = -h * 2 + (t * 24 % 16) - 16
            while (x < w + h) {
                drawPath(Path().apply { moveTo(x, h); lineTo(x + h, 0f); lineTo(x + h + 7, 0f); lineTo(x + 7, h); close() }, Color.White.copy(alpha = 0.35f))
                x += 16
            }
        }
    }
}

/** Pastel background with floating bubbles and stars. */
@Composable
fun KawaiiBackground(modifier: Modifier = Modifier) {
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) { val s = System.nanoTime(); while (true) { withFrameNanos { t = ((it - s) / 1e9).toFloat() }; delay(40) } }
    val cols = listOf(Kawaii.pink, Kawaii.sky, Kawaii.lemon, Kawaii.lilac, Kawaii.mint)
    Canvas(modifier.fillMaxSize()) {
        drawRect(Brush.linearGradient(listOf(Kawaii.cream, Kawaii.peach.copy(alpha = 0.55f), Kawaii.mint.copy(alpha = 0.45f)), Offset.Zero, Offset(size.width, size.height)))
        for (i in 0 until 14) {
            val seed = i * 12.9898f
            val speed = 14 + (i % 5) * 6
            val y = (size.height + 40) - ((t * speed + i * 97) % (size.height + 80))
            val x = (sin(seed) * 0.5f + 0.5f) * size.width + sin(t * 0.5f + seed) * 20
            val r = (6 + (i % 4) * 5).dp.toPx() / 2
            val c = cols[i % cols.size].copy(alpha = 0.22f)
            if (i % 3 == 0) star(Offset(x, y), r * 1.6f, c) else drawCircle(c, r, Offset(x, y))
        }
    }
}

@Composable
fun Confetti(modifier: Modifier = Modifier) {
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) { val s = System.nanoTime(); while (true) withFrameNanos { t = ((it - s) / 1e9).toFloat() } }
    val cols = listOf(Kawaii.pink, Kawaii.lemon, Kawaii.sky, Kawaii.mint, Kawaii.lilac, Kawaii.coral)
    Canvas(modifier.fillMaxSize()) {
        for (i in 0 until 80) {
            val tt = t - (i * 0.037f) % 1.2f
            if (tt < 0) continue
            val x0 = (sin(i * 91.7f) * 0.5f + 0.5f) * size.width
            val y = (-20 + tt * (180 + (i * 13) % 120)) % (size.height + 40)
            val x = x0 + sin(tt * 3 + i) * 30
            val w = 10f + i % 6; val h = (16f + (i * 3) % 8) * maxOf(0.15f, abs(cos(tt * 4 + i)))
            rotate(tt * (90f + i % 3 * 60), Offset(x, y)) {
                drawRect(cols[i % cols.size], Offset(x - w / 2, y - h / 2), Size(w, h))
            }
        }
    }
}

@Composable
fun Typewriter(text: String, size: TextUnit = 15.sp, modifier: Modifier = Modifier) {
    var n by remember(text) { mutableIntStateOf(0) }
    LaunchedEffect(text) { n = 0; while (n < text.length) { delay(18); n++ } }
    Box(modifier) {
        KText(text, size, bold = false, alpha = 0f)
        KText(text.take(n), size, bold = false)
    }
}

@Composable
fun SegmentRow(options: List<Pair<String, Boolean>>, color: Color = Kawaii.pink, onPick: (Int) -> Unit) {
    Row(Modifier.background(Color.White.copy(alpha = 0.7f), RoundedCornerShape(50)).padding(3.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        options.forEachIndexed { i, (label, on) ->
            KText(label, 12.sp, color = if (on) color.darker() else Kawaii.cocoa, maxLines = 1,
                modifier = Modifier
                    .background(if (on) Color.White else Color.Transparent, RoundedCornerShape(50))
                    .clickable { Chiptune.sfx(Sfx.POP); onPick(i) }
                    .padding(horizontal = 10.dp, vertical = 5.dp))
        }
    }
}
