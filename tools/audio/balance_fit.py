#!/usr/bin/env python3
"""Estimate how loud the OKI is relative to the YM2149 in a recording of the
real PCB, compared with the core's mix (method used for v0.1.6).

  balance_fit.py PCB.wav CORE.raw MAP [MAP ...] [--t0 SECONDS]

PCB.wav   recording of the PCB (any rate; a phone video's audio is fine)
CORE.raw  output of scripts/snd_replay.sh for the same tune (float32 x3:
          psg_snd, oki_snd, snd). Drop the SFX commands (OKI phrases < 32)
          from the log first, so only the music's drums are on the OKI side.
MAP       PCB_START:DURATION:OFFSET  - PCB time t plays the same music as
          log time t+OFFSET (find offsets with a spectrogram cross-correlation)
--t0      log time of CORE.raw sample 0 (if the log was trimmed and shifted)

For 1 s pieces, each fine-aligned (+-60 ms), the band powers (300-3600 Hz,
8 log bands) are fitted as  PCB = a*AY + b*OKI + noise  (trimmed least squares,
so clicks and voices in the recording drop out). Prints b/a in dB per band:
how much louder the OKI is on the PCB, relative to the YM2149, than in the
core's mix. 0 dB = the core matches. Bands below ~500 Hz are skewed by the
phone's microphone; trust the middle bands and the median.
"""
import sys, wave, argparse
import numpy as np
from scipy.signal import resample_poly, stft, lfilter

ap = argparse.ArgumentParser()
ap.add_argument('pcb'); ap.add_argument('core'); ap.add_argument('maps', nargs='+')
ap.add_argument('--t0', type=float, default=0.0)
ap.add_argument('--ay-gain', type=float, default=16); ap.add_argument('--oki-gain', type=float, default=8)
a = ap.parse_args()
FS = 8000
w = wave.open(a.pcb); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float)
if w.getnchannels() > 1: x = x.reshape(-1, w.getnchannels()).mean(1)
P = resample_poly(x, FS, w.getframerate())
r = np.fromfile(a.core, np.float32); r = r[:len(r) // 3 * 3].reshape(-1, 3).astype(float)
k = np.exp(-2 * np.pi * 14.6 / 48000)                       # the mixer's DC blocker
ay = lfilter([1, -1], [1, -k], r[:, 0] - r[0, 0]) * (1 + k) / 2
A = resample_poly(ay * a.ay_gain, 1, 6); O = resample_poly(r[:, 1] * a.oki_gain, 1, 6)
edges = np.geomspace(300, 3600, 9)
def bp(s):
    f, t, Z = stft(s, FS, nperseg=256, noverlap=216); S = np.abs(Z) ** 2
    return np.array([S[(f >= lo) & (f < hi)].sum(0) for lo, hi in zip(edges[:-1], edges[1:])])
def seg(s, t0): return s[int(round(t0 * FS)):int(round((t0 + 1.0) * FS))]
Bp, Ba, Bo = [], [], []
for m in a.maps:
    p0, dur, off = map(float, m.split(':'))
    for p in np.arange(p0, p0 + dur - 0.99, 1.0):
        yp = bp(seg(P, p)); best = None
        for d in np.arange(-0.06, 0.061, 0.005):
            c0 = p + off + d - a.t0
            ya, yo = bp(seg(A, c0)), bp(seg(O, c0)); n = min(yp.shape[1], ya.shape[1])
            sc = np.corrcoef(np.log(yp[:, :n] + 1).ravel(), np.log(ya[:, :n] + yo[:, :n] + 1).ravel())[0, 1]
            if best is None or sc > best[0]: best = (sc, ya[:, :n], yo[:, :n], yp[:, :n])
        Ba.append(best[1]); Bo.append(best[2]); Bp.append(best[3])
Bp, Ba, Bo = [np.concatenate(v, 1) for v in (Bp, Ba, Bo)]
res = []
for i in range(len(edges) - 1):
    y = Bp[i]; X = np.stack([Ba[i], Bo[i], np.ones_like(y)], 1); keep = np.ones(len(y), bool)
    for _ in range(8):
        c, *_ = np.linalg.lstsq(X[keep], y[keep], rcond=None)
        e = np.abs(y - X @ c); keep = e <= np.quantile(e, 0.8)
    db = 10 * np.log10(max(c[1], 1e-30) / max(c[0], 1e-30)); res.append(db)
    print('band %4d-%4d Hz: OKI vs YM2149, PCB relative to core: %+5.1f dB' % (edges[i], edges[i + 1], db))
print('median %+.1f dB  (multiply the OKI gain by %.2f)' % (np.median(res), 10 ** (np.median(res) / 20)))
