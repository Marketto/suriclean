package com.suriclean.app

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.PI
import kotlin.math.sin

// ───────────────────────── zone controls ─────────────────────────

/** Types to squeeze (PDF / photos / videos) and Schiaccia's three strengths. */
@Composable
fun SqueezeControls(vm: AppVM) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            for (k in listOf("pdf", "jpg", "video")) {
                if (k == "video" && vm.canVideo == false) continue
                val on = k in vm.squeezeKinds
                KText(L.t("and.sq.kind.$k"), 12.sp, color = if (on) Color.White else Kawaii.cocoa, maxLines = 1,
                    modifier = Modifier
                        .background(if (on) Kawaii.lilac else Color.White.copy(alpha = 0.7f), RoundedCornerShape(50))
                        .clickable { vm.toggleSqueezeKind(k) }
                        .padding(horizontal = 11.dp, vertical = 5.dp))
            }
        }
        val lv = vm.squeezeLevel
        SegmentRow(listOf(L.t("and.sq.level.soft") to (lv == "soft"), L.t("and.sq.level.mid") to (lv == "mid"), L.t("and.sq.level.hard") to (lv == "hard")),
            Kawaii.lilac) { vm.chooseSqueezeLevel(listOf("soft", "mid", "hard")[it]) }
        KText(L.t("and.sq.level.${lv}Note"), 10.5.sp, bold = false, alpha = 0.6f)
        if (vm.canVideo == false) KText(L.t("and.sq.noVideo"), 10.5.sp, bold = false, color = Kawaii.coral.darker())
    }
}

// ───────────────────────── «Il corriere»: Suri brings the file, Schiaccia's press squashes it ─────────────────────────

@Composable
fun SqueezeOverlay(vm: AppVM, run: SqueezeRun) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.22f)).clickable(remember { MutableInteractionSource() }, null) {},
        contentAlignment = Alignment.Center) {
        Column(Modifier.padding(16.dp).kawaiiCard(Kawaii.lilac, 32.dp).padding(18.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(9.dp)) {
            KText(L.t("and.sq.run.title"), 18.sp)
            KText(L.t("and.sq.run.count", run.index + 1, run.total), 12.sp, alpha = 0.6f)
            key(run.shot) { CourierStage(run) }
            KText(run.name, 12.sp, bold = false, alpha = 0.75f, maxLines = 1)
            StripedProgress(run.pct / 100f, Kawaii.lilac, Modifier.fillMaxWidth().height(14.dp))
            if (run.saved > 0) KText(L.t("and.sq.run.saved", Fs.bytes(run.saved)), 13.sp, color = Kawaii.mint.darker())
            BubblyButton(L.t("and.btn.cancel"), Kawaii.coral) { vm.cancelSqueeze() }
        }
    }
}

/** Piecewise-linear value of [t] (0…1) through ([at], [v]) points. */
private fun track(t: Float, vararg kf: Pair<Float, Float>): Float {
    if (t <= kf.first().first) return kf.first().second
    for (i in 1 until kf.size) {
        val (t1, v1) = kf[i]
        val (t0, v0) = kf[i - 1]
        if (t <= t1) return if (t1 == t0) v1 else v0 + (v1 - v0) * (t - t0) / (t1 - t0)
    }
    return kf.last().second
}

@Composable
private fun CourierStage(run: SqueezeRun) {
    val tr = rememberInfiniteTransition(label = "courier")
    val t by tr.animateFloat(0f, 1f, infiniteRepeatable(tween(3000, easing = LinearEasing), RepeatMode.Restart), label = "t")
    BoxWithConstraints(Modifier.fillMaxWidth().height(250.dp).clip(RoundedCornerShape(18.dp))
        .background(Brush.verticalGradient(listOf(Color(0xFFE9FBF4), Color(0xFFFDE8F0))))) {
        val w = maxWidth
        val pressW = 150.dp
        val pressH = pressW * (404f / 400f)
        val pressLeft = w - pressW - 16.dp
        val pressTop = 250.dp - 16.dp - pressH
        // the press, its head slamming at 58% of every cycle (same timing as proposal A)
        val headDy = track(t, 0f to 0f, 0.5f to 0f, 0.58f to 38f, 0.66f to 0f, 1f to 0f)
        Canvas(Modifier.offset(pressLeft, pressTop).size(pressW, pressH)) { drawPress(headDy, run.kind) }
        // Suri runs to the press and back
        val sx = track(t, 0f to 0f, 0.10f to 0f, 0.35f to 70f, 0.55f to 70f, 0.80f to 0f, 1f to 0f)
        val act = when {
            t in 0.10f..0.35f -> Act.LOOKOUT
            t in 0.60f..0.80f -> Act.CELEBRATING
            else -> Act.WAVE
        }
        Suri(act, 120.dp, Modifier.offset(6.dp + sx.dp, 250.dp - 14.dp - 120.dp))
        // the file: carried, thrown under the press, squashed, sent off
        val x0 = 76f
        val y0 = 250f - 92f - 42f
        val xp = pressLeft.value + 69.75f - 17f
        val yp = pressTop.value + 132f * pressH.value / 151.5f - 42f
        val u = ((t - 0.35f) / 0.13f).coerceIn(0f, 1f)
        val fx = track(t, 0f to x0, 0.10f to x0, 0.35f to x0 + 70f, 0.48f to xp, 0.62f to xp, 0.78f to w.value + 10f, 1f to w.value + 10f)
        val fyLine = track(t, 0f to y0, 0.35f to y0, 0.48f to yp, 0.62f to yp, 0.78f to 6f, 1f to 6f)
        val fy = fyLine - if (t in 0.35f..0.48f) 40f * sin(PI.toFloat() * u) else 0f
        val sy = track(t, 0f to 1f, 0.55f to 1f, 0.62f to 0.35f, 1f to 0.35f)
        val fa = track(t, 0f to 1f, 0.78f to 1f, 0.86f to 0f, 0.99f to 0f, 1f to 1f)
        Canvas(Modifier.offset(fx.dp - 9.dp, fy.dp + 12.dp).size(52.dp, 30.dp).alpha(fa)
            .graphicsLayer { scaleY = sy; transformOrigin = TransformOrigin(0.5f, 1f); rotationZ = if (t > 0.62f) -18f * ((t - 0.62f) / 0.16f).coerceAtMost(1f) else 0f }) {
            // same object as under the press, drawn from the press geometry (sheet area x 168…344, y 308…408)
            val k = size.width / 176f
            withTransform({ scale(k, k, Offset.Zero); translate(-168f, -308f) }) { drawSheet(run.kind) }
        }
        // the saving of the last file, popping up after the squash
        val ba = track(t, 0f to 0f, 0.62f to 0f, 0.70f to 1f, 0.88f to 1f, 1f to 0f)
        val by = track(t, 0f to 8f, 0.62f to 8f, 0.70f to 0f, 1f to 0f)
        val saving = run.lastSaving
        if (saving != null) KText("−$saving% ✨", 16.sp, color = Color(0xFF2FBF86),
            modifier = Modifier.offset(w - 120.dp, (16f + by).dp).alpha(ba))
    }
}

private val INK = Color(0xFF3B2A4A)

/** Schiaccia's press, drawn from its mascot source (tools/mascot.mjs, workPressSvg; viewBox 70 48 400 404). */
fun DrawScope.drawPress(headDy: Float, kind: String) {
    val k = size.width / 400f
    val line = Stroke(10f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    fun rr(x: Float, y: Float, w: Float, h: Float, r: Float, fill: Color, stroke: Stroke? = line) {
        drawRoundRect(fill, Offset(x, y), Size(w, h), CornerRadius(r))
        if (stroke != null) drawRoundRect(INK, Offset(x, y), Size(w, h), CornerRadius(r), style = stroke)
    }
    fun oval(cx: Float, cy: Float, rx: Float, ry: Float, c: Color) = drawOval(c, Offset(cx - rx, cy - ry), Size(rx * 2, ry * 2))
    withTransform({ scale(k, k, Offset.Zero); translate(-70f, -48f) }) {
        // posts
        rr(100f, 150f, 36f, 250f, 18f, Color(0xFFCDB8FF))
        rr(376f, 150f, 36f, 250f, 18f, Color(0xFFCDB8FF))
        // the sheet under the press, as in Schiaccia's PDF / JPG / video modes
        drawSheet(kind)
        // base
        rr(84f, 392f, 344f, 50f, 25f, Color(0xFFA48CF0))
        // the head, which comes down on the file
        withTransform({ translate(0f, headDy) }) {
            rr(128f, 112f, 256f, 206f, 88f, Color(0xFFFFB3C7))
            rotate(-18f, Offset(196f, 146f)) { oval(196f, 146f, 46f, 15f, Color.White.copy(alpha = 0.55f)) }
            for (cx in listOf(198f, 314f)) {
                oval(cx, 222f, 30f, 36f, INK)
                oval(cx, 240f, 20f, 14f, Color(0xFF8F6BD9).copy(alpha = 0.75f))
                oval(cx - 9f, 207f, 12f, 14f, Color.White)
                drawCircle(Color.White, 5.5f, Offset(cx + 11f, 236f))
            }
            oval(156f, 266f, 19f, 10f, Color(0xFFFF7FA3).copy(alpha = 0.8f))
            oval(356f, 266f, 19f, 10f, Color(0xFFFF7FA3).copy(alpha = 0.8f))
            val mouth = Path().apply { moveTo(240f, 258f); relativeQuadraticBezierTo(8f, 11f, 16f, 0f); relativeQuadraticBezierTo(8f, 11f, 16f, 0f) }
            drawPath(mouth, INK, style = Stroke(8f, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
        // sparkle
        val spark = Path().apply {
            moveTo(424f, 84f); relativeLineTo(7f, 17f); relativeLineTo(17f, 7f); relativeLineTo(-17f, 7f); relativeLineTo(-7f, 17f)
            relativeLineTo(-7f, -17f); relativeLineTo(-17f, -7f); relativeLineTo(17f, -7f); close()
        }
        drawPath(spark, Color(0xFFFFF6A8)); drawPath(spark, INK, style = Stroke(6f, join = StrokeJoin.Round))
    }
}

/** The object under the press and in Suri's paws (press SVG units): PDF sheet, photo or clapperboard. */
fun DrawScope.drawSheet(kind: String) {
    val line = Stroke(10f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    fun rr(x: Float, y: Float, w: Float, h: Float, r: Float, fill: Color, stroke: Stroke? = line) {
        drawRoundRect(fill, Offset(x, y), Size(w, h), CornerRadius(r))
        if (stroke != null) drawRoundRect(INK, Offset(x, y), Size(w, h), CornerRadius(r), style = stroke)
    }
    when (kind) {
        "jpg" -> {
            rr(176f, 326f, 160f, 74f, 8f, Color.White)
            drawRoundRect(Color(0xFF9AD7FF), Offset(190f, 336f), Size(132f, 54f), CornerRadius(3f))
            drawCircle(Color(0xFFFFD23F), 9f, Offset(300f, 352f))
            drawPath(Path().apply { moveTo(190f, 390f); relativeLineTo(36f, -30f); relativeLineTo(22f, 18f); relativeLineTo(18f, -14f); relativeLineTo(56f, 26f); close() }, Color(0xFF3DDC97))
            drawRoundRect(INK, Offset(190f, 336f), Size(132f, 54f), CornerRadius(3f), style = Stroke(5f))
        }
        "video" -> {
            rr(180f, 348f, 152f, 52f, 8f, INK)
            val clap = Path().apply { moveTo(176f, 330f); relativeLineTo(150f, -14f); relativeLineTo(4f, 22f); relativeLineTo(-150f, 14f); close() }
            drawPath(clap, Color.White); drawPath(clap, INK, style = line)
            drawLine(Color.White, Offset(200f, 366f), Offset(290f, 366f), 7f)
            drawLine(Color.White, Offset(200f, 382f), Offset(256f, 382f), 7f)
            drawCircle(Color(0xFFFF5A4E), 7f, Offset(312f, 386f))
        }
        else -> {
            rr(176f, 330f, 160f, 70f, 12f, Color.White)
            drawLine(Color(0xFFF0B6C8), Offset(198f, 353f), Offset(314f, 353f), 7f)
            drawLine(Color(0xFFF0B6C8), Offset(198f, 375f), Offset(314f, 375f), 7f)
        }
    }
}
