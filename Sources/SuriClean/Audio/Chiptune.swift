import AVFoundation

/// Procedural 16-bit style music: pulse lead, triangle bass, arpeggio and noise drums,
/// synthesised sample by sample. Every mood has its own song and tempo.
enum MusicMood: Int { case menu, scanning, detective, cleaning, victory, results }
enum SFX: Int { case pop = 1, blip, coin, whoosh, error }

struct Song {
    let bpm: Double
    let lead: [Int]
    let bass: [Int]
    let drums: [UInt8]
    let duty: Double
    let arp: Bool

    init(bpm: Double, lead: [Int], bass: [Int], drums: String, duty: Double = 0.25, arp: Bool = false) {
        self.bpm = bpm
        self.lead = lead
        self.bass = bass
        self.drums = Array(drums.utf8)
        self.duty = duty
        self.arp = arp
    }
}

enum Songs {
    static func song(_ m: MusicMood) -> Song {
        switch m {
        case .menu: return menu
        case .scanning: return scanning
        case .detective: return detective
        case .cleaning: return cleaning
        case .victory: return victory
        case .results: return results
        }
    }

    // Calm, bouncy C major — strolling around the burrow.
    static let menu = Song(bpm: 100,
        lead: [72,0,76,0,79,0,76,0, 74,0,72,0,67,0,0,0, 69,0,72,0,76,0,74,0, 72,0,0,0,0,0,0,0,
               72,0,76,0,79,0,81,0, 79,0,76,0,74,0,0,0, 77,0,76,0,74,0,71,0, 72,0,0,0,0,0,0,0],
        bass: [48,0,0,0,55,0,0,0, 53,0,0,0,55,0,0,0, 45,0,0,0,52,0,0,0, 53,0,0,0,55,0,0,0],
        drums: "k...h...s...h...k...h...s...h.hh", duty: 0.25)

    // Driving A minor with arpeggios — digging fast.
    static let scanning = Song(bpm: 128,
        lead: [76,0,79,0,81,0,79,76, 74,0,76,0,72,0,0,0, 76,0,79,0,84,0,81,79, 81,0,79,0,76,0,74,0],
        bass: [45,0,57,0,45,0,57,0, 41,0,53,0,41,0,53,0, 43,0,55,0,43,0,55,0, 48,0,60,0,48,0,60,0],
        drums: "k.h.s.h.k.h.s.hh", duty: 0.5, arp: true)

    // Sneaky, thin pulse — the detective tiptoes.
    static let detective = Song(bpm: 108,
        lead: [69,0,0,72,0,0,71,0, 69,0,0,0,64,0,0,0, 69,0,0,72,0,0,74,0, 75,0,74,0,71,0,0,0],
        bass: [45,0,52,0,45,0,52,0, 43,0,50,0,43,0,50,0, 41,0,48,0,41,0,48,0, 40,0,47,0,44,0,40,0],
        drums: "k..hs..hk.h.s..h", duty: 0.125)

    // Frantic sweeping!
    static let cleaning = Song(bpm: 150,
        lead: [84,0,83,0,81,0,79,0, 81,0,79,0,76,0,79,0, 84,0,86,0,88,0,86,84, 83,0,79,0,81,0,0,0],
        bass: [48,48,0,48,48,0,48,0, 53,53,0,53,53,0,53,0, 55,55,0,55,55,0,55,0, 43,43,0,43,55,0,43,0],
        drums: "k.hhs.hhk.hhs.sh", duty: 0.25, arp: true)

    // Little fanfare.
    static let victory = Song(bpm: 140,
        lead: [72,76,79,84,0,0,79,0, 84,0,0,0,0,0,0,0, 81,0,84,0,88,0,0,0, 91,0,0,0,0,0,0,0],
        bass: [48,0,0,0,55,0,0,0, 48,0,0,0,0,0,0,0, 53,0,0,0,57,0,0,0, 48,0,0,0,0,0,0,0],
        drums: "k...s...k.k.s...", duty: 0.5)

    // Happy browsing of the loot.
    static let results = Song(bpm: 112,
        lead: [79,0,76,0,72,0,76,0, 77,0,74,0,71,0,74,0, 76,0,72,0,69,0,72,0, 74,0,0,79,0,0,0,0],
        bass: [48,0,0,48,0,0,48,0, 50,0,0,50,0,0,50,0, 45,0,0,45,0,0,45,0, 43,0,0,43,0,0,47,0],
        drums: "k..hs..hk..hs.h.", duty: 0.25)
}

final class SynthState {
    var mood: MusicMood = .menu
    var pendingMood: MusicMood? = nil
    var intensity: Double = 0
    var muted = false
    var volume: Double = 0.5
    var sfxKind: Int = 0
    var sfxReset = false
    /// Dubstep/trap remix: half-time drums, wobble bass, trap hat rolls, echoed chiptune lead.
    var remix = false

    // remix voices
    private var wobFreq = 55.0, wobPhase = 0.0, wobPhase2 = 0.0, subPhase = 0.0
    private var svfLow = 0.0, svfBand = 0.0
    private var gate = 0.0, gateTarget = 0.0, wobSteps = 2.0
    private var echoFreq = 0.0, echoAmp = 0.0, echoPhase = 0.0
    private var echoQueue = [0, 0, 0, 0]
    private var kickAge = 1.0
    private var rollPending = false

    private var sampleRate: Double = 44_100
    private var song: Song = Songs.menu
    private var stepIndex = -1
    private var stepPos = Double.greatestFiniteMagnitude
    private var leadPhase = 0.0, leadFreq = 440.0, leadAmp = 0.0, vibT = 0.0
    private var bassPhase = 0.0, bassFreq = 110.0, bassAmp = 0.0
    private var arpPhase = 0.0, arpClock = 0.0, arpIdx = 0
    private var drumKind = 0, drumT = 0.0, kickPhase = 0.0
    private var lfsr: UInt16 = 0xACE1
    private var sfxT = 0.0, sfxPhase = 0.0, sfxLP = 0.0
    private var leadDecay = 0.9998, bassDecay = 0.9999

    func configure(sampleRate sr: Double) {
        sampleRate = sr
        leadDecay = exp(-6.5 / sr)
        bassDecay = exp(-3.0 / sr)
    }

    private static func midi(_ n: Int) -> Double { 440 * pow(2, Double(n - 69) / 12) }

    private func noise() -> Double {
        let bit = ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1
        lfsr = (lfsr >> 1) | (bit << 15)
        return (lfsr & 1) == 1 ? 1 : -1
    }

    private func advanceStep() {
        if let pm = pendingMood {
            pendingMood = nil
            mood = pm
            song = Songs.song(pm)
            stepIndex = 0
        } else {
            stepIndex += 1
        }
        let i = stepIndex
        if remix { advanceRemix(i); return }
        let ln = song.lead[i % song.lead.count]
        if ln > 0 { leadFreq = SynthState.midi(ln); leadAmp = 1; vibT = 0 }
        let bn = song.bass[i % song.bass.count]
        if bn > 0 { bassFreq = SynthState.midi(bn); bassAmp = 1 }
        switch song.drums[i % song.drums.count] {
        case UInt8(ascii: "k"): drumKind = 1; drumT = 0; kickPhase = 0
        case UInt8(ascii: "s"): drumKind = 2; drumT = 0
        case UInt8(ascii: "h"): drumKind = 3; drumT = 0
        default: break
        }
    }

    /// Root of the chord playing at step i (last bass note at or before it).
    private func heldBass(_ i: Int) -> Int {
        for k in 0..<32 {
            let n = song.bass[((i - k) % song.bass.count + song.bass.count) % song.bass.count]
            if n > 0 { return n }
        }
        return 45
    }

    private var remixBpm: Double { min(150, max(132, song.bpm * 1.15)) * (1 + intensity * 0.08) }

    private func advanceRemix(_ i: Int) {
        let bar = i / 16, st = i % 16
        // lead + echo three 16ths later
        let echo = echoQueue[i % 4]
        echoQueue[i % 4] = 0
        if echo > 0 { echoFreq = SynthState.midi(echo); echoAmp = 0.45 }
        let ln = song.lead[i % song.lead.count]
        if ln > 0 { leadFreq = SynthState.midi(ln); leadAmp = 1; vibT = 0; echoQueue[(i + 3) % 4] = ln }
        // wobble bass on the chord root
        var n = heldBass(i)
        while n > 45 { n -= 12 }
        while n < 33 { n += 12 }
        wobFreq = SynthState.midi(n)
        wobSteps = [4.0, 2.0, 8.0 / 3.0, 1.0][bar % 4]
        gateTarget = Array("xxxxxxxx.xxxxx.x".utf8)[st] == UInt8(ascii: "x") ? 1 : 0
        // half-time drums with trap rolls
        let fill = bar % 4 == 3 && st >= 12
        let roll = bar % 2 == 1 && st >= 12 && !fill
        if st == 0 || st == 10 || (bar % 2 == 1 && st == 3) {
            drumKind = 1; drumT = 0; kickPhase = 0; kickAge = 0
        } else if st == 8 || fill {
            drumKind = 4; drumT = 0
        } else if st % 2 == 0 || roll {
            drumKind = 3; drumT = 0
            rollPending = roll
        }
    }

    private func nextRemix(_ dt: Double, stepLen: Double) -> Double {
        if rollPending && stepPos >= stepLen / 2 { rollPending = false; drumKind = 3; drumT = 0 }
        var out = 0.0
        kickAge += dt
        let duck = 1 - 0.65 * exp(-kickAge * 9)
        // wobble: two detuned saws through a resonant low-pass whose cutoff follows a tempo-synced LFO
        let pos = ((Double(stepIndex % 48) + stepPos / stepLen).truncatingRemainder(dividingBy: wobSteps)) / wobSteps
        let lfo = 0.5 - 0.5 * cos(2 * Double.pi * pos)
        let cutoff = 110 + 2600 * lfo * lfo
        wobPhase += wobFreq * 2 * dt; wobPhase -= floor(wobPhase)
        wobPhase2 += wobFreq * 2.012 * dt; wobPhase2 -= floor(wobPhase2)
        let saw = (wobPhase * 2 - 1) + (wobPhase2 * 2 - 1)
        let f = 2 * sin(Double.pi * min(cutoff, sampleRate / 6) / sampleRate)
        svfLow += f * svfBand
        let high = saw - svfLow - 0.28 * svfBand
        svfBand += f * high
        gate += (gateTarget - gate) * 0.004
        subPhase += wobFreq * dt; subPhase -= floor(subPhase)
        out += (max(-1.5, min(1.5, svfLow)) * 0.22 + sin(2 * Double.pi * subPhase) * 0.22) * gate * duck
        // chiptune lead and its echo
        if leadAmp > 0.001 {
            vibT += dt
            let vib = vibT > 0.12 ? sin(vibT * 2 * Double.pi * 7) * 0.008 : 0
            leadPhase += leadFreq * (1 + vib) * dt; leadPhase -= floor(leadPhase)
            out += (leadPhase < 0.25 ? 1.0 : -1.0) * leadAmp * 0.13 * (0.55 + 0.45 * duck)
            leadAmp *= leadDecay
        }
        if echoAmp > 0.001 {
            echoPhase += echoFreq * 2 * dt; echoPhase -= floor(echoPhase)
            out += (echoPhase < 0.125 ? 1.0 : -1.0) * echoAmp * 0.07
            echoAmp *= leadDecay
        }
        if drumKind != 0 {
            drumT += dt
            switch drumKind {
            case 1:
                let fr = 42 + 140 * exp(-drumT * 26)
                kickPhase += fr * dt
                out += sin(2 * Double.pi * kickPhase) * exp(-drumT * 9) * 0.6
                if drumT > 0.4 { drumKind = 0 }
            case 4:
                kickPhase += 185 * dt
                out += (noise() * exp(-drumT * 13) * 0.26 + sin(2 * Double.pi * kickPhase) * exp(-drumT * 30) * 0.22)
                if drumT > 0.35 { drumKind = 0 }
            default:
                out += noise() * exp(-drumT * 90) * 0.05
                if drumT > 0.05 { drumKind = 0 }
            }
        }
        return out
    }

    func next() -> Float {
        let dt = 1.0 / sampleRate
        if remix {
            let stepLen = sampleRate * 60 / remixBpm / 4
            if stepPos >= stepLen { stepPos = 0; advanceStep() }
            stepPos += 1
            var out = nextRemix(dt, stepLen: stepLen) * volume
            if sfxReset { sfxReset = false; sfxT = 0; sfxPhase = 0; sfxLP = 0 }
            if sfxKind != 0 { out += sfx(dt) }
            if muted { return 0 }
            return Float(max(-1, min(1, out)))
        }
        let bpm = song.bpm * (1 + intensity * 0.3)
        let stepLen = sampleRate * 60 / bpm / 4
        if stepPos >= stepLen { stepPos = 0; advanceStep() }
        stepPos += 1

        var out = 0.0
        if leadAmp > 0.001 {
            vibT += dt
            let vib = vibT > 0.15 ? sin(vibT * 2 * Double.pi * 6) * 0.006 : 0
            leadPhase += leadFreq * (1 + vib) * dt
            leadPhase -= floor(leadPhase)
            out += (leadPhase < song.duty ? 1.0 : -1.0) * leadAmp * 0.19
            leadAmp *= leadDecay
        }
        if bassAmp > 0.001 {
            bassPhase += bassFreq * dt
            bassPhase -= floor(bassPhase)
            out += (4 * abs(bassPhase - 0.5) - 1) * min(1, bassAmp * 1.4) * 0.30
            bassAmp *= bassDecay
        }
        if song.arp {
            arpClock += dt
            if arpClock > 0.05 { arpClock = 0; arpIdx = (arpIdx + 1) % 3 }
            let mult: Double
            switch arpIdx { case 0: mult = 2.0; case 1: mult = 2.5198; default: mult = 2.9966 }
            arpPhase += bassFreq * mult * dt
            arpPhase -= floor(arpPhase)
            out += (arpPhase < 0.125 ? 1.0 : -1.0) * 0.045 * min(1, bassAmp + 0.3)
        }
        if drumKind != 0 {
            drumT += dt
            switch drumKind {
            case 1:
                let f = 45 + 120 * exp(-drumT * 30)
                kickPhase += f * dt
                out += sin(2 * Double.pi * kickPhase) * exp(-drumT * 14) * 0.45
                if drumT > 0.3 { drumKind = 0 }
            case 2:
                out += noise() * exp(-drumT * 22) * 0.16
                if drumT > 0.25 { drumKind = 0 }
            default:
                out += noise() * exp(-drumT * 75) * 0.06
                if drumT > 0.06 { drumKind = 0 }
            }
        }
        out *= volume

        if sfxReset { sfxReset = false; sfxT = 0; sfxPhase = 0; sfxLP = 0 }
        if sfxKind != 0 { out += sfx(dt) }
        if muted { return 0 }
        return Float(max(-1, min(1, out)))
    }

    private func sfx(_ dt: Double) -> Double {
        sfxT += dt
        var v = 0.0
        var dur = 0.1
        switch sfxKind {
        case SFX.pop.rawValue:
            dur = 0.08
            sfxPhase += (520 + 1500 * (sfxT / dur)) * dt
            v = sin(2 * Double.pi * sfxPhase) * (1 - sfxT / dur) * 0.3
        case SFX.blip.rawValue:
            dur = 0.035
            sfxPhase += 1760 * dt
            v = (frac(sfxPhase) < 0.5 ? 1.0 : -1.0) * 0.04 * (1 - sfxT / dur)
        case SFX.coin.rawValue:
            dur = 0.24
            sfxPhase += (sfxT < 0.07 ? 987.77 : 1318.5) * dt
            v = (frac(sfxPhase) < 0.5 ? 1.0 : -1.0) * 0.11 * (1 - sfxT / dur)
        case SFX.whoosh.rawValue:
            dur = 0.45
            let a = 0.02 + 0.3 * (1 - sfxT / dur)
            sfxLP += a * (noise() - sfxLP)
            v = sfxLP * sin(Double.pi * sfxT / dur) * 0.4
        case SFX.error.rawValue:
            dur = 0.25
            sfxPhase += (300 - 160 * sfxT / dur) * dt
            v = (frac(sfxPhase) < 0.5 ? 1.0 : -1.0) * 0.09
        default:
            break
        }
        if sfxT >= dur { sfxKind = 0 }
        return v
    }
}

final class Chiptune {
    static let shared = Chiptune()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let synth = SynthState()
    private var running = false
    private var observer: NSObjectProtocol?

    func start() {
        guard !running else { return }
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        let sr = outFormat.sampleRate > 0 ? outFormat.sampleRate : 44_100
        synth.configure(sampleRate: sr)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { return }
        let s = synth
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            let n = Int(frameCount)
            guard abl.count > 0, let first = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<n { first[i] = s.next() }
            if abl.count > 1 {
                for b in 1..<abl.count {
                    if let ptr = abl[b].mData?.assumingMemoryBound(to: Float.self) {
                        for i in 0..<n { ptr[i] = first[i] }
                    }
                }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            try? self?.engine.start()
        }
        do {
            try engine.start()
            running = true
        } catch {
            NSLog("SuriClean audio: \(error)")
        }
    }

    var mood: MusicMood {
        get { synth.pendingMood ?? synth.mood }
        set { if newValue != (synth.pendingMood ?? synth.mood) { synth.pendingMood = newValue } }
    }

    var intensity: Double {
        get { synth.intensity }
        set { synth.intensity = newValue }
    }

    var muted: Bool {
        get { synth.muted }
        set { synth.muted = newValue }
    }

    var remix: Bool {
        get { synth.remix }
        set { synth.remix = newValue }
    }

    func sfx(_ e: SFX) {
        synth.sfxReset = true
        synth.sfxKind = e.rawValue
    }
}
