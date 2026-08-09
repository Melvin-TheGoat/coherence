#!/usr/bin/env python3
"""Replicates SignalEngine's wrist-breathing passes against a raw capture.

Faithful to the Swift: same 20 Hz decimation, same moving-average band-pass,
same 30 s / 5 s windows, same band-limited DFT scan, same concentration
definition, same per-window gates. The point is to fit the natural-breathing
constants against real signal with a counted rate as the answer key, rather
than tuning by feel on the device.

    python3 tools/breath_probe.py capture.csv [--from SEC] [--to SEC]
"""
import sys, argparse
import numpy as np

FS_ENGINE   = 20.0     # the engine decimates the 100 Hz capture to this
WINDOW_SEC  = 30.0
HOP_SEC     = 5.0
BAND_HI     = 0.5      # Hz

# --- pass A: the shipped slow-breathing tuning ---
A = dict(slow_sec=12.0, band_lo=0.05, min_rate=3.5, amp_floor=0.0005, detrend=False)
# --- pass B: the provisional natural-breathing tuning ---
B = dict(slow_sec=8.0,  band_lo=0.13, min_rate=8.0, amp_floor=0.0005, detrend=True)

SOLO_CONC   = 0.40
PAIR_CONC   = 0.30
ACCEL_RATIO = 1.5
MIN_FRAC    = 0.6
MAX_IQR     = 2.0


def moving_average(y, n):
    if n <= 1:
        return y.copy()
    pad = n // 2
    padded = np.pad(y, (pad, pad), mode='edge')
    ker = np.ones(n) / n
    out = np.convolve(padded, ker, mode='same')
    return out[pad:pad + len(y)]


def band_pass(y, fs, slow_sec):
    fast = moving_average(y, max(1, int(round(fs * 1.0))))
    slow = moving_average(y, max(1, int(round(fs * slow_sec))))
    return fast - slow


def dominant(times, values, f_min, f_max, steps=120):
    if len(values) < 8:
        return 0.0, 0.0, 0.0
    x = values - values.mean()
    total = float(np.sum(x * x))
    if total <= 0:
        return 0.0, 0.0, 0.0
    fs_scan = np.linspace(f_min, f_max, steps + 1)
    ang = 2 * np.pi * np.outer(fs_scan, times)
    re = (np.cos(ang) * x).sum(axis=1)
    im = -(np.sin(ang) * x).sum(axis=1)
    p = re * re + im * im
    k = int(np.argmax(p))
    return float(fs_scan[k]), float(p[k]), total


def detrend(y, t):
    if len(y) < 3 or np.ptp(t) == 0:
        return y
    A_ = np.vstack([t - t.mean(), np.ones(len(t))]).T
    coef, *_ = np.linalg.lstsq(A_, y, rcond=None)
    return y - (A_ @ coef)


def run_pass(t, pitch, roll, accel, cfg, label, verbose):
    pw = band_pass(pitch, FS_ENGINE, cfg['slow_sec'])
    rw = band_pass(roll,  FS_ENGINE, cfg['slow_sec'])

    n_win = int((t[-1] - WINDOW_SEC) // HOP_SEC) + 1
    wins = [(i * HOP_SEC, i * HOP_SEC + WINDOW_SEC) for i in range(max(0, n_win))]

    w_accel = []
    for lo, hi in wins:
        m = (t >= lo) & (t <= hi)
        w_accel.append(float(np.sqrt(np.mean(accel[m] ** 2))) if m.sum() else 0.0)
    gate = float(np.median(w_accel)) * ACCEL_RATIO

    rates, detail = [], []
    for i, (lo, hi) in enumerate(wins):
        m = (t >= lo) & (t <= hi)
        if m.sum() < 8 or w_accel[i] > gate:
            rates.append(0.0); detail.append((lo, 0.0, 0.0, 0.0, 'moved' if m.sum() >= 8 else 'short'))
            continue
        wt, wp, wr = t[m], pw[m], rw[m]
        if cfg['detrend']:
            wp, wr = detrend(wp, wt), detrend(wr, wt)
        fP, pP, tP = dominant(wt, wp, cfg['band_lo'], BAND_HI)
        fR, pR, tR = dominant(wt, wr, cfg['band_lo'], BAND_HI)
        cP = 2 * pP / (tP * len(wp)) if tP > 0 else 0.0
        cR = 2 * pR / (tR * len(wr)) if tR > 0 else 0.0
        f, conc = (fP, cP) if cP >= cR else (fR, cR)
        amp = max(wp.std(), wr.std())
        agree = fP > 0 and fR > 0 and abs(fP - fR) <= 0.25 * max(fP, fR)
        ok = (amp >= cfg['amp_floor'] and f * 60 >= cfg['min_rate']
              and (conc >= SOLO_CONC or (conc >= PAIR_CONC and agree)))
        why = 'ok' if ok else ('amp' if amp < cfg['amp_floor']
                               else 'rate' if f * 60 < cfg['min_rate'] else 'conc')
        rates.append(f * 60 if ok else 0.0)
        detail.append((lo, f * 60, conc, amp * 1000, why))

    r = np.array(rates)
    # median-of-5, matching medianFiltered5
    if len(r) >= 5:
        sm = r.copy()
        for i in range(len(r)):
            a, b = max(0, i - 2), min(len(r), i + 3)
            sm[i] = np.median(r[a:b])
        r = sm
    good = r[r > 0]
    frac = len(good) / len(r) if len(r) else 0
    iqr = (np.percentile(good, 75) - np.percentile(good, 25)) if len(good) else 0
    accepted = frac >= MIN_FRAC and iqr <= MAX_IQR

    print(f'  {label}: windows {len(r)}  readable {len(good)} ({frac:.0%})  '
          f'IQR {iqr:.2f}  mean {good.mean() if len(good) else 0:.1f}/min  '
          f'-> {"ACCEPTED" if accepted else "refused"}')
    if verbose:
        for lo, f, conc, amp, why in detail:
            flag = '' if why == 'ok' else f'   <- {why}'
            print(f'      t={lo:5.0f}s  {f:5.1f}/min  conc {conc:.2f}  amp {amp:.2f} mrad{flag}')
    return accepted, good


def run_combined(t, pitch, roll, accel, verbose):
    """Pick the better-evidenced tuning PER WINDOW instead of per session.

    A real session changes character: this capture starts near 6/min and ends
    at 12/min, so choosing one tuning for the whole thing has to be wrong for
    part of it.
    """
    band = {}
    for name, cfg in (('A', A), ('B', B)):
        band[name] = (band_pass(pitch, FS_ENGINE, cfg['slow_sec']),
                      band_pass(roll,  FS_ENGINE, cfg['slow_sec']))

    n_win = int((t[-1] - WINDOW_SEC) // HOP_SEC) + 1
    wins = [(i * HOP_SEC, i * HOP_SEC + WINDOW_SEC) for i in range(max(0, n_win))]
    w_accel = []
    for lo, hi in wins:
        m = (t >= lo) & (t <= hi)
        w_accel.append(float(np.sqrt(np.mean(accel[m] ** 2))) if m.sum() else 0.0)
    gate = float(np.median(w_accel)) * ACCEL_RATIO

    rates, picks = [], []
    for i, (lo, hi) in enumerate(wins):
        m = (t >= lo) & (t <= hi)
        if m.sum() < 8 or w_accel[i] > gate:
            rates.append(0.0); picks.append((lo, 0.0, 0.0, '-')); continue
        best = (0.0, 0.0, '-')
        for name, cfg in (('A', A), ('B', B)):
            pw, rw = band[name]
            wt, wp, wr = t[m], pw[m], rw[m]
            if cfg['detrend']:
                wp, wr = detrend(wp, wt), detrend(wr, wt)
            fP, pP, tP = dominant(wt, wp, cfg['band_lo'], BAND_HI)
            fR, pR, tR = dominant(wt, wr, cfg['band_lo'], BAND_HI)
            cP = 2 * pP / (tP * len(wp)) if tP > 0 else 0.0
            cR = 2 * pR / (tR * len(wr)) if tR > 0 else 0.0
            f, conc = (fP, cP) if cP >= cR else (fR, cR)
            amp = max(wp.std(), wr.std())
            agree = fP > 0 and fR > 0 and abs(fP - fR) <= 0.25 * max(fP, fR)
            ok = (amp >= cfg['amp_floor'] and f * 60 >= cfg['min_rate']
                  and (conc >= SOLO_CONC or (conc >= PAIR_CONC and agree)))
            if ok and conc > best[1]:
                best = (f * 60, conc, name)
        rates.append(best[0]); picks.append((lo, best[0], best[1], best[2]))

    r = np.array(rates)
    if len(r) >= 5:
        sm = r.copy()
        for i in range(len(r)):
            a, b = max(0, i - 2), min(len(r), i + 3)
            sm[i] = np.median(r[a:b])
        r = sm
    good = r[r > 0]
    frac = len(good) / len(r) if len(r) else 0
    iqr = (np.percentile(good, 75) - np.percentile(good, 25)) if len(good) else 0
    # trend-aware coherence, matching SignalEngine.coherent
    ok = False
    if len(good) >= 6:
        if iqr <= MAX_IQR:
            ok = True
        else:
            x = np.arange(len(r))[r > 0]
            c = np.polyfit(x, good, 1)
            res = good - np.polyval(c, x)
            r2 = 1 - np.sum(res**2) / np.sum((good - good.mean())**2)
            rq = np.percentile(res, 75) - np.percentile(res, 25)
            ok = rq <= MAX_IQR and r2 >= 0.30
    ok = ok and frac >= MIN_FRAC
    print(f'  per-window   : windows {len(r)}  readable {len(good)} ({frac:.0%})  '
          f'IQR {iqr:.2f}  mean {good.mean() if len(good) else 0:.1f}/min  '
          f'-> {"ACCEPTED" if ok else "refused"}')
    if verbose:
        for lo, f, conc, name in picks:
            print(f'      t={lo:5.0f}s  {f:5.1f}/min  conc {conc:.2f}  via {name}')
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('csv')
    ap.add_argument('--from', dest='t0', type=float, default=None)
    ap.add_argument('--to', dest='t1', type=float, default=None)
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()

    d = np.genfromtxt(a.csv, delimiter=',', names=True)
    t = d['t'].astype(float)
    step = max(1, int(round(len(t) / (t[-1] * FS_ENGINE))))   # 100 Hz -> 20 Hz
    d, t = d[::step], t[::step]
    accel = np.sqrt(d['ax'] ** 2 + d['ay'] ** 2 + d['az'] ** 2)

    if a.t0 is not None or a.t1 is not None:
        lo = a.t0 if a.t0 is not None else t[0]
        hi = a.t1 if a.t1 is not None else t[-1]
        m = (t >= lo) & (t <= hi)
        d, t, accel = d[m], t[m] - lo, accel[m]

    print(f'{a.csv.split("/")[-1]}   {t[-1]:.0f}s at ~{len(t)/t[-1]:.0f} Hz (decimated)')
    print(f'  pitch sd {d["pitch"].std()*1000:.2f} mrad   roll sd {d["roll"].std()*1000:.2f} mrad')
    okA, _ = run_pass(t, d['pitch'], d['roll'], accel, A, 'pass A (slow) ', a.verbose)
    okB, _ = run_pass(t, d['pitch'], d['roll'], accel, B, 'pass B (natural)', a.verbose)
    run_combined(t, d['pitch'], d['roll'], accel, a.verbose)
    print(f'  ENGINE WOULD REPORT: {"pass A" if okA else ("pass B" if okB else "nothing")}')


if __name__ == '__main__':
    main()
