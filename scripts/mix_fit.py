#!/usr/bin/env python3
"""Fit MAME's heberpop/blocken mono output as a*FM + b*OKI, using the core's own
chips replayed from MAME's register log (scripts/snd2_replay.sh).

    scripts/mix_fit.py MAME.wav REPLAY.raw [T0 T1]

REPLAY.raw: float32 x4 (fm_left, fm_right, oki, snd) at 48 kHz.
Prints the best lag, the fitted a, b (MAME units per core unit), their ratio
compared with ga9201_mixer's, and the fit's residual.
"""
import sys, wave, numpy as np
w = wave.open(sys.argv[1])
n, ch, sw, fr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
m = np.frombuffer(w.readframes(n), dtype='<i2').astype(np.float64).reshape(-1, ch).mean(axis=1)
assert fr == 48000
r = np.fromfile(sys.argv[2], dtype='<f4').reshape(-1, 4).astype(np.float64)
fm = r[:, 0] + r[:, 1]; oki = r[:, 2]; snd = r[:, 3]
t0 = float(sys.argv[3]) if len(sys.argv) > 3 else 25.0
t1 = float(sys.argv[4]) if len(sys.argv) > 4 else min(len(r), len(m)) / 48000 - 1
i0, i1 = int(t0 * 48000), int(t1 * 48000)
best = None
for lag in range(-48, 49, 1):                # +-1 ms (MAME and the replay share one timeline)
    if i0 + lag < 0 or i1 + lag > len(m): continue
    y = m[i0 + lag:i1 + lag]
    A = np.stack([fm[i0:i1], oki[i0:i1]], 1)
    coef, res, *_ = np.linalg.lstsq(A, y, rcond=None)
    e = np.sum((y - A @ coef) ** 2) / np.sum(y ** 2)
    if best is None or e < best[0]: best = (e, lag, coef)
e, lag, (a, b) = best
print(f'window {t0:.1f}-{t1:.1f} s, best lag {lag} samples ({lag/48:.2f} ms), residual {100*e:.1f}% of MAME energy')
print(f'MAME = {a:.4f} * (fmL+fmR) + {b:.4f} * oki   ->  oki/fm ratio {b/a:.2f}')
print(f'in ga9201_mixer units (1/64): k_fm = {a*64:.1f}, k_oki = {b*64:.0f}  (current default 19, 1011)')
print(f'RMS: MAME {np.sqrt(np.mean(m[i0:i1]**2)):.0f}, core mix {np.sqrt(np.mean(snd[i0:i1]**2)):.0f}')
