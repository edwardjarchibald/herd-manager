#!/usr/bin/env python3
"""Render assets/chime.wav: herd's blocked chime (pure stdlib, deterministic).
A soft two-note glass bell, E6 then B6 (rising perfect fifth), each built from additive sine
partials with slightly inharmonic bell overtones, 6 ms raised-cosine attack, exponential decay
(~2 s), a little stereo detune shimmer plus a light diffuse tail, faded to exact silence, peak -18 dBFS.
Run: python3 assets/chime.py"""
import math, os, random, struct, wave
SR, DUR = 44100, 2.6
N = int(SR * DUR)
# (ratio to fundamental, amplitude, decay time constant s) - bell-ish, mildly inharmonic
PARTIALS = [(1.0, 1.0, 0.95), (2.004, 0.32, 0.55), (2.76, 0.14, 0.38), (4.07, 0.06, 0.22), (5.43, 0.025, 0.14)]
NOTES = [(1318.51, 0.0, 1.0), (1975.53, 0.16, 0.8)]          # E6, B6 (Hz, onset s, gain)
ATT = int(0.006 * SR)
L = [0.0] * N; R = [0.0] * N
for f0, t0, g in NOTES:
    s0 = int(t0 * SR)
    for ratio, amp, tau in PARTIALS:
        f = f0 * ratio
        if f > SR * 0.45: continue
        for ch, det, buf in ((0, -0.6, L), (1, 0.6, R)):          # +-0.6 Hz detune: slow stereo shimmer
            w = 2 * math.pi * (f + det) / SR; ph = random.Random(int(f)).random() * 0.0 + ch * 0.3
            for i in range(N - s0):
                env = math.exp(-i / (tau * SR))
                if env < 1e-5: break
                if i < ATT: env *= 0.5 - 0.5 * math.cos(math.pi * i / ATT)
                buf[s0 + i] += g * amp * env * math.sin(w * i + ph)
# light diffuse tail: a few decaying cross-fed delays (no feedback blow-up)
for d_ms, gain in ((23, 0.18), (37, 0.14), (53, 0.10), (79, 0.07), (113, 0.05)):
    d = int(d_ms * SR / 1000)
    L2, R2 = L[:], R[:]
    for i in range(d, N): L2[i] += gain * R[i - d]; R2[i] += gain * L[i - d]
    L, R = L2, R2
fade = int(0.25 * SR)                                              # guarantee a click-free end
for i in range(fade):
    k = 0.5 + 0.5 * math.cos(math.pi * i / fade); L[N - fade + i] *= k; R[N - fade + i] *= k
peak = max(max(map(abs, L)), max(map(abs, R)))
scale = 10 ** (-18 / 20) / peak
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "chime.wav")
with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<hh", int(l * scale * 32767), int(r * scale * 32767)) for l, r in zip(L, R)))
print(out)
