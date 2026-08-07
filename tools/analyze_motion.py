#!/usr/bin/env python3
"""Offline analysis of the Watch raw motion captures.

Three questions per file:
  1. BREATHING: is there a stable spectral peak in 0.033-0.5 Hz on any
     attitude axis (pitch/roll/yaw or the PCA mix), and at what breaths/min?
  2. TREMOR: how much 8-12 Hz physiological tremor energy is in the
     acceleration, and does it decline across the session?
  3. BCG (long shot): any cardiac-band (0.7-2.5 Hz) periodicity in accel?

numpy only - no scipy on this machine.
"""
import sys, glob, os
import numpy as np

def load(path):
    d = np.genfromtxt(path, delimiter=",", names=True)
    return d

def periodogram(x, fs):
    x = x - x.mean()
    w = np.hanning(len(x))
    X = np.fft.rfft(x * w)
    f = np.fft.rfftfreq(len(x), 1.0 / fs)
    p = (np.abs(X) ** 2)
    return f, p

def band_peak(f, p, lo, hi):
    m = (f >= lo) & (f <= hi)
    if not m.any() or p[m].sum() == 0:
        return None, 0.0
    fi = np.argmax(p[m])
    peak_f = f[m][fi]
    # concentration: power within +-15% of the peak / total band power
    pm = (f >= peak_f * 0.85) & (f <= peak_f * 1.15) & m
    conc = p[pm].sum() / p[m].sum()
    return peak_f, conc

def decimate(x, factor):
    n = (len(x) // factor) * factor
    return x[:n].reshape(-1, factor).mean(axis=1)

def analyze(path):
    name = os.path.basename(path)
    d = load(path)
    t = d["t"]
    dur = t[-1] - t[0]
    fs = (len(t) - 1) / dur
    print(f"\n=== {name}")
    print(f"rows={len(t)} dur={dur:.1f}s actual_rate={fs:.1f} Hz")

    # trim edges (5 s) like the engine does
    keep = (t >= t[0] + 5) & (t <= t[-1] - 5)
    if keep.sum() < 200:
        print("  too short after trim; skipping")
        return
    t2 = t[keep]

    # --- 1. breathing band on attitude ---------------------------------
    # decimate to ~10 Hz for the slow band
    factor = max(1, int(round(fs / 10)))
    fs_lo = fs / factor
    axes = {}
    for ax in ("pitch", "roll", "yaw"):
        axes[ax] = decimate(d[ax][keep], factor)
    # PCA over (pitch, roll) after removing linear trend
    P = axes["pitch"] - np.polyval(np.polyfit(np.arange(len(axes["pitch"])), axes["pitch"], 1), np.arange(len(axes["pitch"])))
    R = axes["roll"] - np.polyval(np.polyfit(np.arange(len(axes["roll"])), axes["roll"], 1), np.arange(len(axes["roll"])))
    cov = np.cov(np.vstack([P, R]))
    evals, evecs = np.linalg.eigh(cov)
    pca = evecs[:, -1][0] * P + evecs[:, -1][1] * R
    axes["pca(p,r)"] = pca

    print("  breathing band 0.033-0.5 Hz (2-30 breaths/min):")
    best = None
    for ax, sig in axes.items():
        # detrend
        n = np.arange(len(sig))
        sig = sig - np.polyval(np.polyfit(n, sig, 1), n)
        f, p = periodogram(sig, fs_lo)
        pk, conc = band_peak(f, p, 0.033, 0.5)
        amp = np.std(sig)
        if pk is None:
            continue
        bpm = pk * 60
        print(f"    {ax:9s} peak={bpm:5.1f}/min conc={conc:.2f} amp(sd)={amp*1000:.2f} mrad")
        if best is None or conc > best[2]:
            best = (ax, bpm, conc)
    if best:
        print(f"  -> best axis {best[0]}: {best[1]:.1f} breaths/min (conc {best[2]:.2f})")

    # --- 2. tremor band 8-12 Hz on accel -------------------------------
    if fs >= 30:
        acc = np.sqrt(d["ax"][keep]**2 + d["ay"][keep]**2 + d["az"][keep]**2)
        f, p = periodogram(acc, fs)
        band = (f >= 8) & (f <= 12)
        total = (f >= 1) & (f <= min(30, fs/2 - 1))
        frac = p[band].sum() / max(p[total].sum(), 1e-12)
        # amplitude trend: first half vs second half RMS in band
        halves = []
        mid = len(acc) // 2
        for seg in (acc[:mid], acc[mid:]):
            fseg, pseg = periodogram(seg, fs)
            bs = (fseg >= 8) & (fseg <= 12)
            halves.append(np.sqrt(pseg[bs].sum() / len(seg)))
        print(f"  tremor 8-12 Hz: fraction_of_1-30Hz_power={frac:.3f}  RMS 1st half={halves[0]*1e6:.1f}u 2nd={halves[1]*1e6:.1f}u  {'DOWN' if halves[1]<halves[0] else 'UP'}")

        # --- 3. cardiac band (BCG long shot) ---------------------------
        pk, conc = band_peak(f, p, 0.7, 2.5)
        if pk:
            print(f"  cardiac band 0.7-2.5 Hz: peak={pk*60:.0f}/min conc={conc:.2f}")

for path in sorted(glob.glob(sys.argv[1] + "/*.csv"), key=os.path.getmtime):
    try:
        analyze(path)
    except Exception as e:
        print(f"{os.path.basename(path)}: FAILED {e}")
