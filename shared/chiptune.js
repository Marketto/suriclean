/* Chiptune engine (WebAudio) — same songs and moods as the native macOS version.
   Chiptune.start() must be called from a user gesture (click/key). */
(function () {
  function S(bpm, lead, bass, drums, duty, arp) { return { bpm, lead, bass, drums, duty: duty || 0.25, arp: !!arp }; }
  const SONGS = {
    menu: S(100,
      [72,0,76,0,79,0,76,0, 74,0,72,0,67,0,0,0, 69,0,72,0,76,0,74,0, 72,0,0,0,0,0,0,0,
       72,0,76,0,79,0,81,0, 79,0,76,0,74,0,0,0, 77,0,76,0,74,0,71,0, 72,0,0,0,0,0,0,0],
      [48,0,0,0,55,0,0,0, 53,0,0,0,55,0,0,0, 45,0,0,0,52,0,0,0, 53,0,0,0,55,0,0,0],
      "k...h...s...h...k...h...s...h.hh", 0.25),
    scanning: S(128,
      [76,0,79,0,81,0,79,76, 74,0,76,0,72,0,0,0, 76,0,79,0,84,0,81,79, 81,0,79,0,76,0,74,0],
      [45,0,57,0,45,0,57,0, 41,0,53,0,41,0,53,0, 43,0,55,0,43,0,55,0, 48,0,60,0,48,0,60,0],
      "k.h.s.h.k.h.s.hh", 0.5, true),
    detective: S(108,
      [69,0,0,72,0,0,71,0, 69,0,0,0,64,0,0,0, 69,0,0,72,0,0,74,0, 75,0,74,0,71,0,0,0],
      [45,0,52,0,45,0,52,0, 43,0,50,0,43,0,50,0, 41,0,48,0,41,0,48,0, 40,0,47,0,44,0,40,0],
      "k..hs..hk.h.s..h", 0.125),
    cleaning: S(150,
      [84,0,83,0,81,0,79,0, 81,0,79,0,76,0,79,0, 84,0,86,0,88,0,86,84, 83,0,79,0,81,0,0,0],
      [48,48,0,48,48,0,48,0, 53,53,0,53,53,0,53,0, 55,55,0,55,55,0,55,0, 43,43,0,43,55,0,43,0],
      "k.hhs.hhk.hhs.sh", 0.25, true),
    victory: S(140,
      [72,76,79,84,0,0,79,0, 84,0,0,0,0,0,0,0, 81,0,84,0,88,0,0,0, 91,0,0,0,0,0,0,0],
      [48,0,0,0,55,0,0,0, 48,0,0,0,0,0,0,0, 53,0,0,0,57,0,0,0, 48,0,0,0,0,0,0,0],
      "k...s...k.k.s...", 0.5),
    results: S(112,
      [79,0,76,0,72,0,76,0, 77,0,74,0,71,0,74,0, 76,0,72,0,69,0,72,0, 74,0,0,79,0,0,0,0],
      [48,0,0,48,0,0,48,0, 50,0,0,50,0,0,50,0, 45,0,0,45,0,0,45,0, 43,0,0,43,0,0,47,0],
      "k..hs..hk..hs.h.", 0.25),
  };

  let ctx = null, master = null, sfxBus = null, noiseBuf = null, waves = {};
  let mood = "menu", pending = null, step = 0, nextTime = 0, timer = null;
  let intensity = 0, muted = false, volume = 0.5;
  // Dubstep/trap remix: half-time drums, wobble bass, trap hat rolls, echoed chiptune lead.
  let remix = false, wob = null;
  const GATE = "xxxxxxxx.xxxxx.x", WOB_STEPS = [4, 2, 8 / 3, 1];

  const midi = n => 440 * Math.pow(2, (n - 69) / 12);

  function pulseWave(duty) {
    const n = 64, re = new Float32Array(n), im = new Float32Array(n);
    for (let k = 1; k < n; k++) im[k] = (2 / (k * Math.PI)) * Math.sin(Math.PI * k * duty) * 2;
    return ctx.createPeriodicWave(re, im);
  }

  function init() {
    if (ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    ctx = new AC();
    master = ctx.createGain(); master.gain.value = muted ? 0 : volume; master.connect(ctx.destination);
    sfxBus = ctx.createGain(); sfxBus.gain.value = muted ? 0 : 0.8; sfxBus.connect(ctx.destination);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    [0.125, 0.25, 0.5].forEach(x => waves[x] = pulseWave(x));
  }

  function tone(type, freq, t, dur, gain, dest, wave) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    if (wave) o.setPeriodicWave(wave); else o.type = type;
    o.frequency.setValueAtTime(freq, t);
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    o.connect(g); g.connect(dest || master);
    o.start(t); o.stop(t + dur + 0.02);
    return o;
  }

  function noise(t, dur, gain, hp) {
    const s = ctx.createBufferSource(), g = ctx.createGain(), f = ctx.createBiquadFilter();
    s.buffer = noiseBuf; f.type = "highpass"; f.frequency.value = hp;
    g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    s.connect(f); f.connect(g); g.connect(master);
    s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
  }

  function kick(t, big) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.frequency.setValueAtTime(big ? 180 : 165, t); o.frequency.exponentialRampToValueAtTime(big ? 42 : 45, t + 0.12);
    g.gain.setValueAtTime(big ? 0.65 : 0.5, t); g.gain.exponentialRampToValueAtTime(0.001, t + (big ? 0.42 : 0.28));
    o.connect(g); g.connect(master); o.start(t); o.stop(t + (big ? 0.45 : 0.3));
  }

  function wobChain() {
    if (wob) return wob;
    const saw1 = ctx.createOscillator(), saw2 = ctx.createOscillator(), sub = ctx.createOscillator();
    saw1.type = saw2.type = "sawtooth"; sub.type = "sine"; saw2.detune.value = 20;
    const filt = ctx.createBiquadFilter(); filt.type = "lowpass"; filt.Q.value = 9; filt.frequency.value = 200;
    const sawG = ctx.createGain(); sawG.gain.value = 0.16;
    const subG = ctx.createGain(); subG.gain.value = 0.3;
    const gate = ctx.createGain(); gate.gain.value = 0;
    const duck = ctx.createGain(); duck.gain.value = 1;
    saw1.connect(sawG); saw2.connect(sawG); sawG.connect(filt); filt.connect(gate); sub.connect(subG); subG.connect(gate);
    gate.connect(duck); duck.connect(master);
    [saw1, saw2, sub].forEach(o => o.start());
    wob = { saw1, saw2, sub, filt, gate, duck };
    return wob;
  }

  function dropWob() {
    if (!wob) return;
    const w = wob; wob = null;
    w.gate.gain.setTargetAtTime(0, ctx.currentTime, 0.03);
    setTimeout(() => { [w.saw1, w.saw2, w.sub].forEach(o => { try { o.stop(); } catch (e) {} }); w.duck.disconnect(); }, 300);
  }

  function heldBass(s, i) {
    for (let k = 0; k < 32; k++) { const n = s.bass[((i - k) % s.bass.length + s.bass.length) % s.bass.length]; if (n > 0) return n; }
    return 45;
  }

  function remixStep(s, i, t, stepDur) {
    const w = wobChain(), bar = Math.floor(i / 16), st = i % 16;
    const ln = s.lead[i % s.lead.length];
    if (ln > 0) {
      tone(null, midi(ln), t, 0.45, 0.10, master, waves[0.25]);
      tone(null, midi(ln) * 2, t + 3 * stepDur, 0.4, 0.035, master, waves[0.125]);   // echo
    }
    let n = heldBass(s, i);
    while (n > 45) n -= 12;
    while (n < 33) n += 12;
    const f = midi(n);
    w.saw1.frequency.setValueAtTime(f * 2, t); w.saw2.frequency.setValueAtTime(f * 2, t); w.sub.frequency.setValueAtTime(f, t);
    const ws = WOB_STEPS[bar % 4];
    for (let k = 0; k <= 4; k++) {   // tempo-synced LFO on the filter cutoff
      const pos = (((i % 48) + k / 4) % ws) / ws, lfo = 0.5 - 0.5 * Math.cos(2 * Math.PI * pos);
      const v = 110 + 2600 * lfo * lfo, tt = t + k * stepDur / 4;
      if (k === 0) w.filt.frequency.setValueAtTime(v, tt); else w.filt.frequency.linearRampToValueAtTime(v, tt);
    }
    w.gate.gain.setTargetAtTime(GATE[st] === "x" ? 1 : 0, t, 0.012);
    const fill = bar % 4 === 3 && st >= 12, roll = bar % 2 === 1 && st >= 12 && !fill;
    if (st === 0 || st === 10 || (bar % 2 === 1 && st === 3)) {
      kick(t, true);
      w.duck.gain.setValueAtTime(0.35, t); w.duck.gain.setTargetAtTime(1, t + 0.01, 0.09);
    } else if (st === 8 || fill) {
      noise(t, 0.32, 0.24, 900); tone("triangle", 185, t, 0.12, 0.22);
    } else if (st % 2 === 0 || roll) {
      noise(t, 0.03, 0.045, 8000);
      if (roll) noise(t + stepDur / 2, 0.03, 0.04, 8000);
    }
  }

  function schedule() {
    while (nextTime < ctx.currentTime + 0.12) {
      if (pending) { mood = pending; pending = null; step = 0; }
      const s = SONGS[mood];
      if (remix) {
        const stepDur = 60 / (Math.min(150, Math.max(132, s.bpm * 1.15)) * (1 + intensity * 0.08)) / 4;
        remixStep(s, step, nextTime, stepDur);
        nextTime += stepDur; step++;
        continue;
      }
      const stepDur = 60 / (s.bpm * (1 + intensity * 0.3)) / 4;
      const t = nextTime;
      const ln = s.lead[step % s.lead.length];
      if (ln > 0) tone(null, midi(ln), t, 0.45, 0.13, master, waves[s.duty]);
      const bn = s.bass[step % s.bass.length];
      if (bn > 0) tone("triangle", midi(bn), t, 0.7, 0.32);
      if (s.arp) {
        const root = s.bass[Math.floor(step / 4) * 4 % s.bass.length] || 48;
        [2, 2.5198, 2.9966].forEach((m, i) => tone(null, midi(root) * m, t + i * stepDur / 3, stepDur / 3, 0.025, master, waves[0.125]));
      }
      const dch = s.drums[step % s.drums.length];
      if (dch === "k") kick(t);
      else if (dch === "s") noise(t, 0.16, 0.14, 1200);
      else if (dch === "h") noise(t, 0.04, 0.06, 7000);
      nextTime += stepDur;
      step++;
    }
  }

  function start() {
    init();
    if (!ctx) return;
    if (ctx.state === "suspended") ctx.resume();
    if (timer) return;
    nextTime = ctx.currentTime + 0.05;
    timer = setInterval(schedule, 25);
  }

  function stop() { if (timer) { clearInterval(timer); timer = null; } if (ctx) dropWob(); }

  function setRemix(on) {
    remix = !!on;
    if (!remix && ctx) dropWob();
  }

  function setMood(m) { if (SONGS[m] && m !== (pending || mood)) pending = m; }
  function getMood() { return pending || mood; }
  function setIntensity(v) { intensity = Math.max(0, Math.min(1, v)); }
  function setMuted(m) {
    muted = m;
    if (master) master.gain.setTargetAtTime(m ? 0 : volume, ctx.currentTime, 0.05);
    if (sfxBus) sfxBus.gain.setTargetAtTime(m ? 0 : 0.8, ctx.currentTime, 0.05);
  }

  function sfx(kind) {
    if (!ctx || muted) return;
    const t = ctx.currentTime;
    if (kind === "pop") {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.frequency.setValueAtTime(520, t); o.frequency.exponentialRampToValueAtTime(2000, t + 0.08);
      g.gain.setValueAtTime(0.25, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.09);
      o.connect(g); g.connect(sfxBus); o.start(t); o.stop(t + 0.1);
    } else if (kind === "blip") {
      tone("square", 1760, t, 0.035, 0.03, sfxBus);
    } else if (kind === "coin") {
      tone("square", 987.77, t, 0.08, 0.09, sfxBus);
      tone("square", 1318.5, t + 0.07, 0.2, 0.09, sfxBus);
    } else if (kind === "whoosh") {
      const s = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
      s.buffer = noiseBuf; f.type = "lowpass";
      f.frequency.setValueAtTime(4000, t); f.frequency.exponentialRampToValueAtTime(300, t + 0.45);
      g.gain.setValueAtTime(0.001, t); g.gain.linearRampToValueAtTime(0.35, t + 0.15); g.gain.exponentialRampToValueAtTime(0.001, t + 0.45);
      s.connect(f); f.connect(g); g.connect(sfxBus); s.start(t); s.stop(t + 0.5);
    } else if (kind === "error") {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = "square"; o.frequency.setValueAtTime(300, t); o.frequency.linearRampToValueAtTime(140, t + 0.25);
      g.gain.setValueAtTime(0.08, t); g.gain.linearRampToValueAtTime(0.001, t + 0.26);
      o.connect(g); g.connect(sfxBus); o.start(t); o.stop(t + 0.27);
    }
  }

  window.Chiptune = { start, stop, setMood, setRemix, get remix() { return remix; }, getMood, setIntensity, setMuted, sfx, get muted() { return muted; }, get running() { return !!timer; } };
})();
