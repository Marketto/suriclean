package com.suriclean.app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.sin

enum class Mood { MENU, SCANNING, DETECTIVE, CLEANING, VICTORY, RESULTS }
enum class Sfx { POP, BLIP, COIN, WHOOSH, ERROR }

private class Song(val bpm: Double, val lead: IntArray, val bass: IntArray, drums: String, val duty: Double = 0.25, val arp: Boolean = false) {
    val drums = drums.toCharArray()
}

/** Procedural 16-bit music, same songs as the desktop versions. */
object Chiptune {
    private val songs = mapOf(
        Mood.MENU to Song(100.0,
            intArrayOf(72,0,76,0,79,0,76,0, 74,0,72,0,67,0,0,0, 69,0,72,0,76,0,74,0, 72,0,0,0,0,0,0,0,
                72,0,76,0,79,0,81,0, 79,0,76,0,74,0,0,0, 77,0,76,0,74,0,71,0, 72,0,0,0,0,0,0,0),
            intArrayOf(48,0,0,0,55,0,0,0, 53,0,0,0,55,0,0,0, 45,0,0,0,52,0,0,0, 53,0,0,0,55,0,0,0),
            "k...h...s...h...k...h...s...h.hh"),
        Mood.SCANNING to Song(128.0,
            intArrayOf(76,0,79,0,81,0,79,76, 74,0,76,0,72,0,0,0, 76,0,79,0,84,0,81,79, 81,0,79,0,76,0,74,0),
            intArrayOf(45,0,57,0,45,0,57,0, 41,0,53,0,41,0,53,0, 43,0,55,0,43,0,55,0, 48,0,60,0,48,0,60,0),
            "k.h.s.h.k.h.s.hh", 0.5, true),
        Mood.DETECTIVE to Song(108.0,
            intArrayOf(69,0,0,72,0,0,71,0, 69,0,0,0,64,0,0,0, 69,0,0,72,0,0,74,0, 75,0,74,0,71,0,0,0),
            intArrayOf(45,0,52,0,45,0,52,0, 43,0,50,0,43,0,50,0, 41,0,48,0,41,0,48,0, 40,0,47,0,44,0,40,0),
            "k..hs..hk.h.s..h", 0.125),
        Mood.CLEANING to Song(150.0,
            intArrayOf(84,0,83,0,81,0,79,0, 81,0,79,0,76,0,79,0, 84,0,86,0,88,0,86,84, 83,0,79,0,81,0,0,0),
            intArrayOf(48,48,0,48,48,0,48,0, 53,53,0,53,53,0,53,0, 55,55,0,55,55,0,55,0, 43,43,0,43,55,0,43,0),
            "k.hhs.hhk.hhs.sh", 0.25, true),
        Mood.VICTORY to Song(140.0,
            intArrayOf(72,76,79,84,0,0,79,0, 84,0,0,0,0,0,0,0, 81,0,84,0,88,0,0,0, 91,0,0,0,0,0,0,0),
            intArrayOf(48,0,0,0,55,0,0,0, 48,0,0,0,0,0,0,0, 53,0,0,0,57,0,0,0, 48,0,0,0,0,0,0,0),
            "k...s...k.k.s...", 0.5),
        Mood.RESULTS to Song(112.0,
            intArrayOf(79,0,76,0,72,0,76,0, 77,0,74,0,71,0,74,0, 76,0,72,0,69,0,72,0, 74,0,0,79,0,0,0,0),
            intArrayOf(48,0,0,48,0,0,48,0, 50,0,0,50,0,0,50,0, 45,0,0,45,0,0,45,0, 43,0,0,43,0,0,47,0),
            "k..hs..hk..hs.h."),
    )

    private const val SR = 44_100.0
    @Volatile var muted = false
    @Volatile var intensity = 0.0
    /** Dubstep/trap remix: half-time drums, wobble bass, trap hat rolls, echoed chiptune lead. */
    @Volatile var remix = false
    private var wobFreq = 55.0; private var wobPhase = 0.0; private var wobPhase2 = 0.0; private var subPhase = 0.0
    private var svfLow = 0.0; private var svfBand = 0.0
    private var gate = 0.0; private var gateTarget = 0.0; private var wobSteps = 2.0
    private var echoFreq = 0.0; private var echoAmp = 0.0; private var echoPhase = 0.0
    private val echoQueue = IntArray(4)
    private var kickAge = 1.0
    private var rollPending = false
    private val gatePattern = "xxxxxxxx.xxxxx.x"
    @Volatile private var pending: Mood? = null
    @Volatile var mood: Mood = Mood.MENU
        private set
    @Volatile private var sfxKind: Sfx? = null
    @Volatile private var sfxReset = false

    private var song = songs.getValue(Mood.MENU)
    private var stepIndex = -1
    private var stepPos = Double.MAX_VALUE
    private var leadPhase = 0.0; private var leadFreq = 440.0; private var leadAmp = 0.0; private var vibT = 0.0
    private var bassPhase = 0.0; private var bassFreq = 110.0; private var bassAmp = 0.0
    private var arpPhase = 0.0; private var arpClock = 0.0; private var arpIdx = 0
    private var drum = 0; private var drumT = 0.0; private var kickPhase = 0.0
    private var lfsr = 0xACE1
    private var sfxT = 0.0; private var sfxPhase = 0.0; private var sfxLp = 0.0
    private val leadDecay = exp(-6.5 / SR)
    private val bassDecay = exp(-3.0 / SR)
    private var thread: Thread? = null

    fun setMood(m: Mood) { if (m != (pending ?: mood)) pending = m }
    fun currentMood(): Mood = pending ?: mood
    fun sfx(s: Sfx) { sfxReset = true; sfxKind = s }

    fun start() {
        if (thread != null) return
        val minBuf = AudioTrack.getMinBufferSize(SR.toInt(), AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(SR.toInt()).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(maxOf(minBuf, 4096))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track.play()
        thread = Thread {
            val buf = ShortArray(1024)
            while (!Thread.currentThread().isInterrupted) {
                for (i in buf.indices) buf[i] = (next() * 32767).toInt().toShort()
                track.write(buf, 0, buf.size)
            }
            track.release()
        }.apply { isDaemon = true; name = "chiptune"; start() }
    }

    fun stop() { thread?.interrupt(); thread = null }

    private fun midi(n: Int) = 440.0 * 2.0.pow((n - 69) / 12.0)

    private fun noise(): Double {
        val bit = ((lfsr shr 0) xor (lfsr shr 2) xor (lfsr shr 3) xor (lfsr shr 5)) and 1
        lfsr = (lfsr shr 1) or (bit shl 15)
        return if (lfsr and 1 == 1) 1.0 else -1.0
    }

    private fun advance() {
        val p = pending
        if (p != null) { pending = null; mood = p; song = songs.getValue(p); stepIndex = 0 } else stepIndex++
        val i = stepIndex
        if (remix) { advanceRemix(i); return }
        val ln = song.lead[i % song.lead.size]
        if (ln > 0) { leadFreq = midi(ln); leadAmp = 1.0; vibT = 0.0 }
        val bn = song.bass[i % song.bass.size]
        if (bn > 0) { bassFreq = midi(bn); bassAmp = 1.0 }
        when (song.drums[i % song.drums.size]) {
            'k' -> { drum = 1; drumT = 0.0; kickPhase = 0.0 }
            's' -> { drum = 2; drumT = 0.0 }
            'h' -> { drum = 3; drumT = 0.0 }
        }
    }

    private fun heldBass(i: Int): Int {
        for (k in 0 until 32) {
            val n = song.bass[Math.floorMod(i - k, song.bass.size)]
            if (n > 0) return n
        }
        return 45
    }

    private fun remixBpm() = min(150.0, max(132.0, song.bpm * 1.15)) * (1 + intensity * 0.08)

    private fun advanceRemix(i: Int) {
        val bar = i / 16; val st = i % 16
        val echo = echoQueue[i % 4]
        echoQueue[i % 4] = 0
        if (echo > 0) { echoFreq = midi(echo); echoAmp = 0.45 }
        val ln = song.lead[i % song.lead.size]
        if (ln > 0) { leadFreq = midi(ln); leadAmp = 1.0; vibT = 0.0; echoQueue[(i + 3) % 4] = ln }
        var n = heldBass(i)
        while (n > 45) n -= 12
        while (n < 33) n += 12
        wobFreq = midi(n)
        wobSteps = doubleArrayOf(4.0, 2.0, 8.0 / 3.0, 1.0)[bar % 4]
        gateTarget = if (gatePattern[st] == 'x') 1.0 else 0.0
        val fill = bar % 4 == 3 && st >= 12
        val roll = bar % 2 == 1 && st >= 12 && !fill
        if (st == 0 || st == 10 || (bar % 2 == 1 && st == 3)) { drum = 1; drumT = 0.0; kickPhase = 0.0; kickAge = 0.0 }
        else if (st == 8 || fill) { drum = 4; drumT = 0.0 }
        else if (st % 2 == 0 || roll) { drum = 3; drumT = 0.0; rollPending = roll }
    }

    private fun nextRemix(dt: Double, stepLen: Double): Double {
        if (rollPending && stepPos >= stepLen / 2) { rollPending = false; drum = 3; drumT = 0.0 }
        var out = 0.0
        kickAge += dt
        val duck = 1 - 0.65 * exp(-kickAge * 9)
        val pos = (((stepIndex % 48) + stepPos / stepLen) % wobSteps) / wobSteps
        val lfo = 0.5 - 0.5 * cos(2 * PI * pos)
        val cutoff = 110 + 2600 * lfo * lfo
        wobPhase += wobFreq * 2 * dt; wobPhase -= floor(wobPhase)
        wobPhase2 += wobFreq * 2.012 * dt; wobPhase2 -= floor(wobPhase2)
        val saw = (wobPhase * 2 - 1) + (wobPhase2 * 2 - 1)
        val f = 2 * sin(PI * min(cutoff, SR / 6) / SR)
        svfLow += f * svfBand
        val high = saw - svfLow - 0.28 * svfBand
        svfBand += f * high
        gate += (gateTarget - gate) * 0.004
        subPhase += wobFreq * dt; subPhase -= floor(subPhase)
        out += (svfLow.coerceIn(-1.5, 1.5) * 0.22 + sin(2 * PI * subPhase) * 0.22) * gate * duck
        if (leadAmp > 0.001) {
            vibT += dt
            val vib = if (vibT > 0.12) sin(vibT * 2 * PI * 7) * 0.008 else 0.0
            leadPhase += leadFreq * (1 + vib) * dt; leadPhase -= floor(leadPhase)
            out += (if (leadPhase < 0.25) 1.0 else -1.0) * leadAmp * 0.13 * (0.55 + 0.45 * duck)
            leadAmp *= leadDecay
        }
        if (echoAmp > 0.001) {
            echoPhase += echoFreq * 2 * dt; echoPhase -= floor(echoPhase)
            out += (if (echoPhase < 0.125) 1.0 else -1.0) * echoAmp * 0.07
            echoAmp *= leadDecay
        }
        if (drum != 0) {
            drumT += dt
            when (drum) {
                1 -> { val fr = 42 + 140 * exp(-drumT * 26); kickPhase += fr * dt; out += sin(2 * PI * kickPhase) * exp(-drumT * 9) * 0.6; if (drumT > 0.4) drum = 0 }
                4 -> { kickPhase += 185 * dt; out += noise() * exp(-drumT * 13) * 0.26 + sin(2 * PI * kickPhase) * exp(-drumT * 30) * 0.22; if (drumT > 0.35) drum = 0 }
                else -> { out += noise() * exp(-drumT * 90) * 0.05; if (drumT > 0.05) drum = 0 }
            }
        }
        return out
    }

    private fun next(): Double {
        val dt = 1.0 / SR
        if (remix) {
            val stepLen = SR * 60 / remixBpm() / 4
            if (stepPos >= stepLen) { stepPos = 0.0; advance() }
            stepPos += 1
            var out = nextRemix(dt, stepLen) * 0.5
            if (sfxReset) { sfxReset = false; sfxT = 0.0; sfxPhase = 0.0; sfxLp = 0.0 }
            sfxKind?.let { out += sfxSample(it, dt) }
            if (muted) return 0.0
            return out.coerceIn(-1.0, 1.0)
        }
        val stepLen = SR * 60 / (song.bpm * (1 + intensity * 0.3)) / 4
        if (stepPos >= stepLen) { stepPos = 0.0; advance() }
        stepPos += 1
        var out = 0.0
        if (leadAmp > 0.001) {
            vibT += dt
            val vib = if (vibT > 0.15) sin(vibT * 2 * PI * 6) * 0.006 else 0.0
            leadPhase += leadFreq * (1 + vib) * dt; leadPhase -= floor(leadPhase)
            out += (if (leadPhase < song.duty) 1.0 else -1.0) * leadAmp * 0.19
            leadAmp *= leadDecay
        }
        if (bassAmp > 0.001) {
            bassPhase += bassFreq * dt; bassPhase -= floor(bassPhase)
            out += (4 * abs(bassPhase - 0.5) - 1) * minOf(1.0, bassAmp * 1.4) * 0.30
            bassAmp *= bassDecay
        }
        if (song.arp) {
            arpClock += dt
            if (arpClock > 0.05) { arpClock = 0.0; arpIdx = (arpIdx + 1) % 3 }
            val mult = when (arpIdx) { 0 -> 2.0; 1 -> 2.5198; else -> 2.9966 }
            arpPhase += bassFreq * mult * dt; arpPhase -= floor(arpPhase)
            out += (if (arpPhase < 0.125) 1.0 else -1.0) * 0.045 * minOf(1.0, bassAmp + 0.3)
        }
        if (drum != 0) {
            drumT += dt
            when (drum) {
                1 -> { val f = 45 + 120 * exp(-drumT * 30); kickPhase += f * dt; out += sin(2 * PI * kickPhase) * exp(-drumT * 14) * 0.45; if (drumT > 0.3) drum = 0 }
                2 -> { out += noise() * exp(-drumT * 22) * 0.16; if (drumT > 0.25) drum = 0 }
                else -> { out += noise() * exp(-drumT * 75) * 0.06; if (drumT > 0.06) drum = 0 }
            }
        }
        out *= 0.5
        if (sfxReset) { sfxReset = false; sfxT = 0.0; sfxPhase = 0.0; sfxLp = 0.0 }
        sfxKind?.let { out += sfxSample(it, dt) }
        if (muted) return 0.0
        return out.coerceIn(-1.0, 1.0)
    }

    private fun sq(p: Double) = if (p - floor(p) < 0.5) 1.0 else -1.0

    private fun sfxSample(k: Sfx, dt: Double): Double {
        sfxT += dt
        var dur = 0.1
        val v = when (k) {
            Sfx.POP -> { dur = 0.08; sfxPhase += (520 + 1500 * (sfxT / dur)) * dt; sin(2 * PI * sfxPhase) * (1 - sfxT / dur) * 0.3 }
            Sfx.BLIP -> { dur = 0.035; sfxPhase += 1760 * dt; sq(sfxPhase) * 0.04 * (1 - sfxT / dur) }
            Sfx.COIN -> { dur = 0.24; sfxPhase += (if (sfxT < 0.07) 987.77 else 1318.5) * dt; sq(sfxPhase) * 0.11 * (1 - sfxT / dur) }
            Sfx.WHOOSH -> { dur = 0.45; val a = 0.02 + 0.3 * (1 - sfxT / dur); sfxLp += a * (noise() - sfxLp); sfxLp * sin(PI * sfxT / dur) * 0.4 }
            Sfx.ERROR -> { dur = 0.25; sfxPhase += (300 - 160 * sfxT / dur) * dt; sq(sfxPhase) * 0.09 }
        }
        if (sfxT >= dur) sfxKind = null
        return v
    }
}
