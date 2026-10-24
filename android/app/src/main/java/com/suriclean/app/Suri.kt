package com.suriclean.app

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin

private fun frac(x: Double) = x - floor(x)

private class Pose {
    var bodyX = 0.0; var bodyY = 0.0; var lean = 0.0; var squash = 1.0
    var headTilt = 0.0; var headY = 0.0
    var leftArm = 12.0; var rightArm = 12.0
    var eyeX = 0.0; var eyeY = 0.0; var blink = 1.0
    var eyes = 0            // 0 open, 1 closed, 2 happy
    var mouthOpen = false
    var nose = 1.0
    var tail = 0.0

    companion object {
        fun make(a: Act, t: Double): Pose {
            val p = Pose()
            val breath = sin(t * 2.2)
            p.squash = 1 + breath * 0.012
            p.headY = breath * 1.5
            p.blink = if (frac(t / 3.9) * 3.9 < 0.13) 0.12 else 1.0
            p.tail = sin(t * 1.7) * 6
            when (a) {
                Act.IDLE -> {
                    p.leftArm = 10 + sin(t * 1.3) * 3; p.rightArm = 10 + sin(t * 1.3 + 1) * 3
                    p.eyeX = sin(t * 0.6) * 3; p.headTilt = sin(t * 0.6) * 4
                    if (frac(t / 9) * 9 < 1.8) { p.rightArm = 150 + sin(t * 12) * 18; p.mouthOpen = true; p.headTilt = -6.0 }
                }
                Act.WAVE -> { p.rightArm = 150 + sin(t * 12) * 18; p.mouthOpen = true; p.headTilt = -6 + sin(t * 3) * 2 }
                Act.DIGGING -> {
                    val s = sin(t * 8)
                    p.lean = 8.0; p.rightArm = 35 + s * 25; p.leftArm = -10 + s * 10; p.eyeX = 3.0; p.eyeY = 3.0
                    p.headTilt = 6.0; p.bodyY = -abs(s) * 2; p.tail = sin(t * 8) * 10
                }
                Act.DETECTIVE -> { val s = sin(t * 1.5); p.bodyX = s * 8; p.rightArm = -165 + sin(t * 3) * 4; p.eyeX = s * 3; p.headTilt = s * 5 }
                Act.SWEEPING -> {
                    val s = sin(t * 6)
                    p.rightArm = -20 + s * 28; p.leftArm = -30 + s * 20; p.lean = s * 4; p.bodyX = s * 4; p.eyeX = s * 2; p.eyeY = 2.0; p.mouthOpen = true
                }
                Act.READING -> { p.leftArm = -40.0; p.rightArm = -40.0; p.eyeY = 3.0; p.eyeX = sin(t * 3) * 3; p.headTilt = sin(t * 0.5) * 3 }
                Act.SLEEPY -> { p.eyes = 1; p.squash = 1 + sin(t * 1.2) * 0.025; p.headTilt = 10.0; p.headY = sin(t * 1.2) * 3; p.leftArm = 6.0; p.rightArm = 6.0; p.tail = 0.0 }
                Act.SNIFFING -> { p.nose = 1 + abs(sin(t * 10)) * 0.2; p.headTilt = sin(t * 1.3) * 10; p.eyeX = sin(t * 1.3) * 3; p.leftArm = -22.0; p.rightArm = -22.0 }
                Act.LOOKOUT -> { p.squash = 1.05 + breath * 0.01; p.leftArm = -25.0; p.rightArm = -25.0; p.eyeX = sin(t * 0.9) * 4; p.headTilt = sin(t * 0.9) * 8 }
                Act.CELEBRATING -> {
                    val j = abs(sin(t * 5))
                    p.bodyY = -j * 24; p.squash = if (j < 0.15) 0.94 else 1.02
                    p.leftArm = 150 + sin(t * 10) * 15; p.rightArm = 150 + sin(t * 10 + 1) * 15
                    p.eyes = 2; p.mouthOpen = true; p.tail = sin(t * 10) * 15
                }
            }
            return p
        }
    }
}

private val FUR = Color(0xFFE6B880)
private val LIGHT = Color(0xFFFAE6C2)
private val DARK = Color(0xFF734D36)
private val COCOA = Color(0xFF54382B)
private val WOOD = Color(0xFF9E6B42)

/** Suri, animated. [height] is the drawn height; width is 220/260 of it. */
@Composable
fun Suri(act: Act, height: Dp = 180.dp, modifier: Modifier = Modifier) {
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        val start = System.nanoTime()
        while (true) withFrameNanos { t = ((it - start) / 1e9).toFloat() }
    }
    Canvas(modifier.size(height * 220f / 260f, height)) {
        val k = size.height / 260f
        scale(k, k, pivot = Offset.Zero) { drawSuri(act, t.toDouble() + 1000.0) }
    }
}

private fun DrawScope.oval(cx: Float, cy: Float, w: Float, h: Float, c: Color) =
    drawOval(c, Offset(cx - w / 2, cy - h / 2), Size(w, h))

private fun DrawScope.drawSuri(act: Act, t: Double) {
    val p = Pose.make(act, t)
    // back layer
    when (act) {
        Act.DIGGING -> { oval(180f, 248f, 84f, 28f, Color(0xFF9E7350)); oval(180f, 244f, 46f, 12f, Color(0xFF6F5038)) }
        Act.LOOKOUT -> oval(110f, 254f, 210f, 46f, Kawaii.sand)
        else -> {}
    }
    oval(110f, 249f, maxOf(60f, (120 + p.bodyY * 1.5).toFloat()), 16f, DARK.copy(alpha = 0.16f))

    withTransform({
        translate(p.bodyX.toFloat(), p.bodyY.toFloat())
        rotate(p.lean.toFloat(), Offset(110f, 260f))
        scale((1 / p.squash).toFloat(), p.squash.toFloat(), Offset(110f, 260f))
    }) {
        // tail
        rotate(p.tail.toFloat(), Offset(140f, 228f)) {
            val tail = Path().apply { moveTo(135f, 232f); cubicTo(190f, 242f, 205f, 190f, 193f, 150f) }
            drawPath(tail, FUR, style = Stroke(16f, cap = StrokeCap.Round))
            drawLine(DARK, Offset(191f, 160f), Offset(193f, 150f), 16f, StrokeCap.Round)
        }
        oval(88f, 240f, 38f, 18f, FUR); oval(132f, 240f, 38f, 18f, FUR)
        oval(110f, 178f, 96f, 130f, FUR); oval(110f, 190f, 60f, 92f, LIGHT)
        // head
        withTransform({ translate(0f, p.headY.toFloat()); rotate(p.headTilt.toFloat(), Offset(110f, 94f)) }) { head(p, act, t) }
        // front props
        if (act == Act.READING) book(t)
        // arms (right one may hold a prop)
        arm(144f, -p.rightArm.toFloat(), act)
        arm(76f, p.leftArm.toFloat(), null)
    }
    effects(act, t)
}

private fun DrawScope.head(p: Pose, act: Act, t: Double) {
    for (x in listOf(58f, 162f)) { drawCircle(DARK, 14f, Offset(x, 70f)); drawCircle(Kawaii.pink.copy(alpha = 0.55f), 6.5f, Offset(x, 70f)) }
    oval(110f, 92f, 120f, 100f, FUR)
    drawRoundRect(DARK.copy(alpha = 0.22f), Offset(104f, 43f), Size(12f, 26f), CornerRadius(6f))
    oval(110f, 113f, 56f, 38f, LIGHT)
    rotate(20f, Offset(82f, 88f)) { oval(82f, 88f, 38f, 46f, DARK) }
    rotate(-20f, Offset(138f, 88f)) { oval(138f, 88f, 38f, 46f, DARK) }
    for (cx in listOf(82f, 138f)) {
        val x = cx + p.eyeX.toFloat(); val y = 89f + p.eyeY.toFloat()
        when (p.eyes) {
            0 -> {
                oval(x, y, 26f, (30 * p.blink).toFloat(), Color.Black)
                if (p.blink > 0.5) { drawCircle(Color.White, 5.5f, Offset(x - 5, y - 7)); drawCircle(Color.White, 2.5f, Offset(x + 5, y + 7)) }
            }
            1 -> drawPath(Path().apply { moveTo(x - 10, y - 1); quadraticTo(x, y + 11, x + 10, y - 1) }, Color.Black, style = Stroke(3f, cap = StrokeCap.Round))
            else -> drawPath(Path().apply { moveTo(x - 10, y + 5); quadraticTo(x, y - 11, x + 10, y + 5) }, Color.Black, style = Stroke(3.5f, cap = StrokeCap.Round))
        }
    }
    oval(64f, 116f, 22f, 12f, Kawaii.pink.copy(alpha = 0.5f)); oval(156f, 116f, 22f, 12f, Kawaii.pink.copy(alpha = 0.5f))
    scale(p.nose.toFloat(), p.nose.toFloat(), Offset(110f, 105f)) {
        drawPath(Path().apply { moveTo(104f, 99.5f); lineTo(116f, 99.5f); quadraticTo(120f, 99.5f, 110f, 110.5f); quadraticTo(100f, 99.5f, 104f, 99.5f); close() }, COCOA)
    }
    if (p.mouthOpen) {
        drawPath(Path().apply { moveTo(102f, 114f); lineTo(118f, 114f); quadraticTo(117f, 127f, 110f, 127f); quadraticTo(103f, 127f, 102f, 114f); close() }, Kawaii.coral)
    } else {
        drawPath(Path().apply { moveTo(101f, 112f); quadraticTo(105.5f, 121f, 110f, 112f); quadraticTo(114.5f, 121f, 119f, 112f) }, COCOA, style = Stroke(2.2f, cap = StrokeCap.Round))
    }
    when (act) {
        Act.DETECTIVE -> {
            drawRoundRect(Color(0xFF664A33), Offset(57f, 46f), Size(106f, 12f), CornerRadius(6f))
            drawPath(Path().apply { moveTo(71f, 52f); quadraticTo(110f, -20f, 149f, 52f); close() }, Color(0xFF8F6E4F))
            drawRoundRect(Kawaii.coral, Offset(71f, 43.5f), Size(78f, 7f), CornerRadius(3.5f))
        }
        Act.SLEEPY -> {
            drawPath(Path().apply { moveTo(72f, 58f); quadraticTo(102f, -6f, 172f, -6f); quadraticTo(157f, 26f, 162f, 58f); close() }, Kawaii.lilac)
            drawRoundRect(Color.White, Offset(59f, 43f), Size(98f, 14f), CornerRadius(7f))
            drawCircle(Color.White, 8f, Offset(172f, (-4 + sin(t * 1.2) * 3).toFloat()))
        }
        Act.CELEBRATING -> {
            drawPath(Path().apply { moveTo(110f, -3f); lineTo(132f, 47f); lineTo(88f, 47f); close() },
                Brush.verticalGradient(listOf(Kawaii.pink, Kawaii.lemon), startY = -3f, endY = 47f))
            drawCircle(Kawaii.sky, 6.5f, Offset(110f, -4f))
        }
        else -> {}
    }
}

private fun DrawScope.arm(sx: Float, angle: Float, act: Act?) {
    rotate(angle, Offset(sx, 138f)) {
        when (act) {
            Act.DIGGING -> {
                drawRoundRect(WOOD, Offset(sx - 3, 182f), Size(6f, 36f), CornerRadius(3f))
                drawPath(Path().apply { moveTo(sx - 12, 216f); lineTo(sx + 12, 216f); quadraticTo(sx + 12, 238f, sx, 242f); quadraticTo(sx - 12, 238f, sx - 12, 216f); close() }, Color(0xFFBDBDBD))
            }
            Act.DETECTIVE -> {
                drawRoundRect(WOOD, Offset(sx - 3.5f, 184f), Size(7f, 16f), CornerRadius(3f))
                drawCircle(Kawaii.sky.copy(alpha = 0.35f), 16.5f, Offset(sx, 216f))
                drawCircle(Color(0xFF8C8C8C), 16.5f, Offset(sx, 216f), style = Stroke(5f))
                drawCircle(Color.White, 4f, Offset(sx - 7, 209f))
            }
            Act.SWEEPING -> {
                drawRoundRect(WOOD, Offset(sx - 2.5f, 182f), Size(5f, 40f), CornerRadius(2.5f))
                drawRoundRect(Kawaii.coral, Offset(sx - 11, 221f), Size(22f, 6f), CornerRadius(3f))
                drawPath(Path().apply { moveTo(sx - 10, 227f); lineTo(sx + 10, 227f); lineTo(sx + 20, 253f); lineTo(sx - 20, 253f); close() }, Kawaii.lemon)
            }
            else -> {}
        }
        drawRoundRect(FUR, Offset(sx - 9, 138f), Size(18f, 52f), CornerRadius(9f))
        drawCircle(LIGHT, 8f, Offset(sx, 184f))
    }
}

private fun DrawScope.book(t: Double) {
    drawRoundRect(Kawaii.pink, Offset(67f, 147f), Size(86f, 58f), CornerRadius(5f))
    drawRoundRect(Color.White, Offset(71f, 151f), Size(38f, 50f), CornerRadius(3f))
    drawRoundRect(Color.White, Offset(111f, 151f), Size(38f, 50f), CornerRadius(3f))
    for (i in 0..3) {
        drawRoundRect(COCOA.copy(alpha = 0.15f), Offset(77f, 160f + i * 9), Size(26f, 3f), CornerRadius(1.5f))
        drawRoundRect(COCOA.copy(alpha = 0.15f), Offset(117f, 160f + i * 9), Size(26f, 3f), CornerRadius(1.5f))
    }
    val flip = frac(t / 3.0)
    if (flip < 0.25) {
        val sx = cos(flip / 0.25 * PI).toFloat()
        scale(sx, 1f, Offset(110f, 176f)) { drawRoundRect(Color(0xFFEEEEEE), Offset(110f, 151f), Size(38f, 50f), CornerRadius(3f)) }
    }
}

private fun DrawScope.effects(act: Act, t: Double) {
    when (act) {
        Act.DIGGING -> for (i in 0 until 8) {
            val ph = frac(t * 1.6 + i / 8.0)
            drawCircle(Color(0xFF9E7350).copy(alpha = (1 - ph).toFloat()), (3.5 + i % 3).toFloat(),
                Offset((180 + ph * (24 + i * 4)).toFloat(), (240 - sin(ph * PI) * (50 + (i % 4) * 8)).toFloat()))
        }
        Act.SWEEPING -> for (i in 0 until 6) {
            val ph = frac(t * 0.9 + i / 6.0)
            drawCircle(Color.Gray.copy(alpha = ((1 - ph) * 0.35).toFloat()), (5 + ph * 13).toFloat(),
                Offset((70 + i * 16 + sin(t * 6 + i) * 10).toFloat(), (246 - ph * 50).toFloat()))
        }
        Act.SLEEPY -> for (i in 0 until 3) {
            val ph = frac(t * 0.35 + i / 3.0)
            val x = (160 + ph * 34).toFloat(); val y = (60 - ph * 50).toFloat(); val s = (7 + ph * 8).toFloat()
            val c = Kawaii.lilac.copy(alpha = sin(ph * PI).toFloat())
            drawPath(Path().apply { moveTo(x - s, y - s); lineTo(x + s, y - s); lineTo(x - s, y + s); lineTo(x + s, y + s) }, c, style = Stroke(3f, cap = StrokeCap.Round))
        }
        Act.SNIFFING -> for (i in 0 until 5) {
            val ph = frac(t * 0.7 + i / 5.0)
            drawCircle(Kawaii.lemon.copy(alpha = sin(ph * PI).toFloat()), 3f, Offset((212 - ph * 80).toFloat(), (110 + sin(ph * 9 + i) * 8).toFloat()))
        }
        Act.CELEBRATING -> for (i in 0 until 6) {
            val a = t * 1.5 + i * PI / 3
            val c = listOf(Kawaii.pink, Kawaii.lemon, Kawaii.sky)[i % 3].copy(alpha = (0.5 + 0.5 * sin(t * 4 + i)).toFloat())
            star(Offset((110 + cos(a) * 100).toFloat(), (130 + sin(a) * 100).toFloat()), (7 + (i % 3) * 3).toFloat(), c)
        }
        Act.LOOKOUT -> if (frac(t * 0.5) < 0.3) {
            drawRoundRect(Kawaii.coral, Offset(178f, 18f), Size(6f, 20f), CornerRadius(3f)); drawCircle(Kawaii.coral, 3.5f, Offset(181f, 44f))
        }
        Act.DETECTIVE -> {
            val ph = frac(t * 0.4)
            val c = Kawaii.lilac.copy(alpha = sin(ph * PI).toFloat())
            translate(0f, (-ph * 20).toFloat()) {
                drawPath(Path().apply { moveTo(178f, 40f); quadraticTo(178f, 30f, 186f, 30f); quadraticTo(194f, 30f, 194f, 38f); quadraticTo(194f, 44f, 186f, 47f); lineTo(186f, 52f) }, c, style = Stroke(4f, cap = StrokeCap.Round))
                drawCircle(c, 2.5f, Offset(186f, 59f))
            }
        }
        else -> {}
    }
}

fun DrawScope.star(c: Offset, r: Float, color: Color) {
    val p = Path()
    for (i in 0 until 8) {
        val a = PI / 4 * i - PI / 2
        val rr = if (i % 2 == 0) r else r * 0.38f
        val x = c.x + cos(a).toFloat() * rr; val y = c.y + sin(a).toFloat() * rr
        if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
    }
    p.close()
    drawPath(p, color)
}
