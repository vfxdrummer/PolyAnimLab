# Usage: python3 scripts/make_demo_music.py  → writes demo_music.wav (27 s, drop at 2.53 s)
# Original synth-pop loop, generated from scratch (royalty-free: nothing sampled).
# 133.3 BPM so two intro bars end at 3.6s, when the home feed appears in the demo.
import math, random, wave, struct, array
SR = 44100
DUR = 27.0
N = int(SR * DUR)
BPM = 400 / 3            # 133.33 → beat 0.45s, bar 1.8s
BEAT = 60 / BPM
BAR = BEAT * 4
DROP = 2.53              # drums + bass enter exactly when the home feed appears in the video
OFFSET = DROP - 2 * BAR  # music grid starts before 0 so the 2-bar intro ends on the drop
random.seed(7)

L = array.array('f', [0.0]) * N
R = array.array('f', [0.0]) * N

# Band-limited saw wavetable (8 harmonics) and sine table
TS = 2048
SAW = [sum(math.sin(2 * math.pi * h * i / TS) / h for h in range(1, 9)) * 0.55 for i in range(TS)]
SIN = [math.sin(2 * math.pi * i / TS) for i in range(TS)]

def hz(semitones_from_a4): return 440 * 2 ** (semitones_from_a4 / 12)

# i–VI–III–VII in A minor: Am F C G
CHORDS = [[-12, -9, -5], [-16, -12, -9], [-9, -5, -2], [-14, -10, -7]]   # A3 C4 E4 | F3 A3 C4 | C4 E4 G4 | G3 B3 D4
ROOTS = [-36, -40, -33, -38]                                             # A1 F1 C2 G1

def add(buf_l, buf_r, start, samples, pan=0.0):
    gl, gr = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
    for i, s in enumerate(samples):
        j = start + i
        if j < 0: continue
        if j >= N: break
        buf_l[j] += s * gl
        buf_r[j] += s * gr

def tone(freq, length, table, amp, attack, decay, sustain=1.0):
    n = int(length * SR); out = [0.0] * n; ph = 0.0; step = freq * TS / SR
    a = max(1, int(attack * SR))
    for i in range(n):
        env = (i / a if i < a else sustain * math.exp(-(i - a) / (decay * SR)) if decay else sustain)
        out[i] = table[int(ph) & (TS - 1)] * env * amp
        ph += step
    return out

def kick_duck(t):
    """Sidechain-style ducking: dip right after each kick (after the drop)."""
    if t < DROP: return 1.0
    x = ((t - DROP) % BEAT) / BEAT
    return 0.45 + 0.55 * min(1.0, x * 3.2)

bars = int((DUR - OFFSET) / BAR) + 1

# Pads: two detuned saws per chord tone, slow attack, ducked by the kick
for b in range(bars):
    t0 = b * BAR + OFFSET
    for note in CHORDS[b % 4]:
        for det, pan in ((-0.08, -0.5), (0.08, 0.5)):
            s = tone(hz(note + det), BAR, SAW, 0.045, 0.35, 0)
            start = int(t0 * SR)
            s = [v * kick_duck((start + i) / SR) for i, v in enumerate(s)]
            add(L, R, start, s, pan)

# Arp: 16th-note plucks over chord tones an octave up, ping-ponged
PATTERN = [0, 1, 2, 1, 0, 2, 1, 2]
for b in range(bars):
    for k in range(16):
        t = b * BAR + k * BEAT / 4 + OFFSET
        note = CHORDS[b % 4][PATTERN[k % 8]] + 12
        amp = 0.07 if t < DROP else 0.055
        add(L, R, int(t * SR), tone(hz(note), 0.22, SIN, amp, 0.003, 0.09), -0.35 if k % 2 else 0.35)

# Drums + bass after the drop
for b in range(bars):
    for beat in range(4):
        t = b * BAR + beat * BEAT + OFFSET
        if t < DROP - 0.01: continue
        # Kick: pitch sweep 150 → 48 Hz
        n = int(0.32 * SR); ph = 0.0; ks = [0.0] * n
        for i in range(n):
            f = 48 + 102 * math.exp(-i / (0.035 * SR))
            ph += 2 * math.pi * f / SR
            ks[i] = math.sin(ph) * math.exp(-i / (0.12 * SR)) * 0.55
        add(L, R, int(t * SR), ks)
        # Clap on 2 and 4: filtered noise + body tone
        if beat in (1, 3):
            n = int(0.18 * SR); prev = 0.0; cs = [0.0] * n
            for i in range(n):
                w = random.uniform(-1, 1); hp = w - prev; prev = w
                cs[i] = (hp * 0.22 + math.sin(2 * math.pi * 190 * i / SR) * 0.06) * math.exp(-i / (0.05 * SR))
            add(L, R, int((t + 0.004) * SR), cs, 0.1)
        # Hats on the off-beats (and a quiet 16th ghost)
        for off, amp in ((0.5, 0.11), (0.75, 0.04)):
            n = int(0.05 * SR); prev = 0.0; hs = [0.0] * n
            for i in range(n):
                w = random.uniform(-1, 1); hp = w - prev; prev = w
                hs[i] = hp * amp * math.exp(-i / (0.012 * SR))
            add(L, R, int((t + off * BEAT) * SR), hs, -0.2)
        # Bass: 8th notes on the root, punchy envelope, ducked
        for e in (0.0, 0.5):
            tb = t + e * BEAT
            s = tone(hz(ROOTS[b % 4]), BEAT * 0.48, SAW, 0.22, 0.004, 0.16)
            start = int(tb * SR)
            add(L, R, start, [v * kick_duck((start + i) / SR) for i, v in enumerate(s)])

# Master: fade in/out, normalize, soft-clip
peak = max(max(abs(min(L)), max(L)), max(abs(min(R)), max(R)))
gain = 0.89 / peak
frames = bytearray()
for i in range(N):
    t = i / SR
    fade = min(1.0, t / 0.6) * min(1.0, (DUR - t) / 2.5)
    for v in (L[i], R[i]):
        x = math.tanh(v * gain * 1.15) * fade
        frames += struct.pack('<h', int(x * 32000))
with wave.open('demo_music.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(frames))
print('wrote', DUR, 's, drop at', DROP)
