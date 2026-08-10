#!/usr/bin/env python3
"""Variant bench for the wrist-breathing reader.

breath_probe.py answers "what does the shipped engine say about this capture".
This answers "would a change to the engine say something closer to the truth",
which needs the counted rates as an answer key and every variant run over the
same captures in one pass.

Faithful to SignalEngine: 20 Hz decimation, the same moving-average band-pass,
the same 30 s / 5 s window grid, the same concentration definition and gate
stack. Everything a variant touches is a keyword in CFG, so the shipped
behaviour is one config among several and stays runnable.

    python3 tools/breath_lab.py                 # every variant, every capture
    python3 tools/breath_lab.py --only hann     # one variant
    python3 tools/breath_lab.py -v              # per-window detail
"""
import argparse
import os
import sys

import numpy as np

CAPTURES = os.path.expanduser('~/Desktop/captures')

FS = 20.0          # the engine decimates the 100 Hz capture to this
WINDOW_SEC = 30.0  # the shared output grid: never change, other series use it
HOP_SEC = 5.0
BAND_HI = 0.5

# Counted by Aziz during the session, at the minute marks named. These are the
# only ground truth that exists; every number below is judged against them.
# A count is "breaths in that minute", so it lands at the minute's midpoint.
TRUTH = {
    '00F5873B': ('S1 normal, counted at the end', [(270, 12)]),
    '39F2003D': ('S2 read nothing at all', []),
    'ACF453B2': ('S3 slowing down', [(30, 12), (150, 8), (270, 6.5)]),
    'E1711EEE': ('S4 mid counts', [(90, 10), (210, 8.5)]),
    'D89DE1CA': ('S5 steady slow', [(30, 7), (150, 7), (270, 6)]),
    '9442AD1A': ('S6 uncounted', []),
}

# The two tunings the shipped engine races per window.
SLOW = dict(slow_sec=12.0, band_lo=0.05, min_rate=3.5, detrend=False)
NATURAL = dict(slow_sec=8.0, band_lo=0.13, min_rate=8.0, detrend=True)

AMP_FLOOR = 0.0005    # rad
SOLO_CONC = 0.40
PAIR_CONC = 0.30
ACCEL_RATIO = 1.5
DISPLAY_FRAC = 0.35
CONFIDENT_FRAC = 0.6
MAX_IQR = 2.0
MIN_TREND_FIT = 0.30


# --------------------------------------------------------------------------
# primitives, mirroring the Swift

def moving_average(y, n):
    if n <= 1:
        return y.copy()
    half = n // 2
    # Swift shrinks the window at the edges rather than padding; a cumulative
    # sum with clipped bounds reproduces that exactly.
    c = np.concatenate([[0.0], np.cumsum(y)])
    i = np.arange(len(y))
    lo = np.maximum(0, i - half)
    hi = np.minimum(len(y) - 1, i + half)
    return (c[hi + 1] - c[lo]) / (hi - lo + 1)


def band_pass(y, slow_sec):
    fast = moving_average(y, max(1, int(round(FS * 1.0))))
    slow = moving_average(y, max(1, int(round(FS * slow_sec))))
    return fast - slow


def butter_band(y, fc, fs=FS, q=0.7071):
    """Zero-phase 2nd-order Butterworth high-pass, run twice, then the same 1 s
    low-pass the engine already uses.

    The difference of two moving averages rolls off at about 6 dB per octave,
    so its corner has to be pushed up to 12 s (5/min) to suppress postural
    drift, and that puts maximum attenuation exactly where a 5 or 6 per minute
    breath lives. A steeper filter can sit its corner at 3.6/min and still
    reject the drift harder, which is the whole point: not more rejection, but
    rejection that does not eat the signal.
    """
    w0 = 2 * np.pi * fc / fs
    c, s = np.cos(w0), np.sin(w0)
    al = s / (2 * q)
    b = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2]) / (1 + al)
    a = np.array([1.0, -2 * c, 1 - al]) / (1 + al)

    def once(x):
        out = np.zeros_like(x)
        x1 = x2 = y1 = y2 = 0.0
        for i, v in enumerate(x):
            o = b[0] * v + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
            x2, x1 = x1, v
            y2, y1 = y1, o
            out[i] = o
        return out

    hp = once(once(y[::-1])[::-1])
    return moving_average(hp, max(1, int(round(fs * 1.0))))


def detrend(y, t):
    """Ordinary least squares slope removal, computed the way Swift does it.

    np.linalg.lstsq on a 30 s window of millirad data overflows: the time
    column runs to 300 while the signal is 1e-3, and the normal equations blow
    up. The closed form is what SignalEngine.linearDetrended actually runs.
    """
    if len(y) < 3:
        return y
    dt = t - t.mean()
    den = float(np.sum(dt * dt))
    if den <= 0:
        return y
    slope = float(np.sum(dt * (y - y.mean()))) / den
    return y - (y.mean() + slope * dt)


def spectrum(t, y, f_min, f_max, taper='none', steps=240):
    """Band-limited DFT scan. Returns (freqs, power, total_energy).

    Kept as a spectrum rather than just its peak so variants can ask about
    harmonics and second peaks without rescanning.
    """
    if len(y) < 8:
        return None, None, 0.0
    x = y - y.mean()
    if taper == 'hann':
        w = np.hanning(len(x))
        # Preserve energy so the concentration ratio stays comparable across
        # tapers: without this a Hann window drops total power ~62% and every
        # concentration reads high for the wrong reason.
        w = w / np.sqrt(np.mean(w ** 2))
        x = x * w
    total = float(np.sum(x * x))
    if total <= 0:
        return None, None, 0.0
    fs = np.linspace(f_min, f_max, steps + 1)
    ang = 2 * np.pi * np.outer(fs, t)
    re = (np.cos(ang) * x).sum(axis=1)
    im = -(np.sin(ang) * x).sum(axis=1)
    return fs, re * re + im * im, total


def peak(fs, p, interp=False):
    """Peak frequency and power, optionally parabola-refined on the scan grid."""
    k = int(np.argmax(p))
    f, pk = float(fs[k]), float(p[k])
    if interp and 0 < k < len(p) - 1:
        a, b, c = p[k - 1], p[k], p[k + 1]
        den = a - 2 * b + c
        if den != 0:
            shift = 0.5 * (a - c) / den
            if abs(shift) <= 1:
                f = float(fs[k] + shift * (fs[1] - fs[0]))
                pk = float(b - 0.25 * (a - c) * shift)
    return f, pk


def median5(y):
    if len(y) < 5:
        return y
    out = y.copy()
    for i in range(len(y)):
        out[i] = np.median(y[max(0, i - 2):min(len(y), i + 3)])
    return out


def iqr(y):
    return float(np.percentile(y, 75) - np.percentile(y, 25)) if len(y) else 0.0


def coherent(rates):
    ys = rates[rates > 0]
    xs = np.arange(len(rates))[rates > 0]
    if len(ys) < 6:
        return len(ys) > 0
    if iqr(ys) <= MAX_IQR:
        return True
    c = np.polyfit(xs, ys, 1)
    res = ys - np.polyval(c, xs)
    denom = np.sum((ys - ys.mean()) ** 2)
    r2 = 1 - np.sum(res ** 2) / denom if denom > 0 else 0
    return iqr(res) <= MAX_IQR and r2 >= MIN_TREND_FIT


# --------------------------------------------------------------------------
# the reader, with every variant behind a flag

CFG_SHIPPED = dict(
    taper='none',        # 'none' | 'hann'
    span=30.0,           # seconds of signal per estimate (output grid stays 30/5)
    interp=False,        # parabolic refinement of the scan peak
    steps=120,           # DFT scan resolution
    harmonic=False,      # prefer a fundamental whose 2nd harmonic is present
    amp_floor=AMP_FLOOR,
    solo_conc=SOLO_CONC,
    track=True,          # Viterbi over candidates instead of per-window argmax
    peaks=3,             # candidates kept per channel when tracking
    lam=0.45,            # cost per breath/min of jump between windows
    track_floor=0.10,    # clarity below which a candidate is not worth a state
    axis_sum=False,      # average the two axes' spectra instead of racing them
    butter=None,         # Hz: replace the slow tuning's filter with a Butterworth
    track_gated=True,    # only track inside windows the shipped gates accept
)


def read(t, pitch, roll, accel, cfg, verbose=False):
    def filt(sig, tune):
        fc = cfg.get('butter')
        if fc and tune is SLOW:
            return butter_band(sig, fc)
        return band_pass(sig, tune['slow_sec'])

    banded = {}
    for name, tune in (('slow', SLOW), ('natural', NATURAL)):
        banded[name] = (filt(pitch, tune), filt(roll, tune))

    n_win = int((t[-1] - WINDOW_SEC) // HOP_SEC) + 1
    grid = [(i * HOP_SEC, i * HOP_SEC + WINDOW_SEC) for i in range(max(0, n_win))]

    # The accel gate is judged on the output window, not the analysis span, so
    # a longer span cannot quietly change which windows count as movement.
    w_accel = []
    for lo, hi in grid:
        m = (t >= lo) & (t < hi)
        w_accel.append(float(np.sqrt(np.mean(accel[m] ** 2))) if m.sum() else 0.0)
    gate = float(np.median(w_accel)) * ACCEL_RATIO

    tunings = [('slow', dict(SLOW, **cfg.get('slow_over', {}))),
               ('natural', dict(NATURAL, **cfg.get('nat_over', {})))]
    half = cfg['span'] / 2
    rates, detail, pool = [], [], []
    for i, (lo, hi) in enumerate(grid):
        centre = (lo + hi) / 2
        a, b = max(t[0], centre - half), min(t[-1], centre + half)
        m = (t >= a) & (t < b)
        if m.sum() < 8 or w_accel[i] > gate:
            rates.append(0.0)
            pool.append([])
            detail.append((centre, 0.0, 0.0, 'moved' if m.sum() >= 8 else 'short'))
            continue

        wt = t[m]
        best = (0.0, 0.0, 'none')
        here = []
        for name, tune in tunings:
            bp, br = banded[name]
            wp, wr = bp[m], br[m]
            if tune['detrend']:
                wp, wr = detrend(wp, wt), detrend(wr, wt)
            amp = max(wp.std(), wr.std())
            cand, shapes, mine = [], [], []
            for ch in (wp, wr):
                fs, p, tot = spectrum(wt, ch, tune['band_lo'], BAND_HI,
                                      cfg['taper'], cfg['steps'])
                if fs is None:
                    cand.append((0.0, 0.0))
                    continue
                shapes.append((fs, p / tot, len(ch)))
                f, pk = peak(fs, p, cfg['interp'])
                if cfg['harmonic']:
                    f, pk = prefer_fundamental(fs, p, f, pk, tune['band_lo'])
                cand.append((f, 2 * pk / (tot * len(ch))))
                if cfg['track'] and not cfg['axis_sum'] and amp >= cfg['amp_floor']:
                    for cf, cc in local_maxima(fs, p, tot, len(ch), cfg['peaks']):
                        if cf * 60 >= tune['min_rate'] and cc >= cfg['track_floor']:
                            mine.append((cf * 60, cc))
            if cfg['axis_sum'] and len(shapes) == 2:
                # Pitch and roll are two projections of one wrist rotation, so
                # the breath is in both while the postural noise that beats it
                # is not. Treating them as rivals and keeping the clearer
                # throws away half the evidence; averaging the two normalised
                # spectra is the ordinary incoherent average and costs nothing.
                fs, n = shapes[0][0], shapes[0][2]
                p = (shapes[0][1] + shapes[1][1]) / 2
                f, pk = peak(fs, p, cfg['interp'])
                cand = [(f, 2 * pk / n), (f, 2 * pk / n)]
                if cfg['track'] and amp >= cfg['amp_floor']:
                    for cf, cc in local_maxima(fs, p, 1.0, n, cfg['peaks']):
                        if cf * 60 >= tune['min_rate'] and cc >= cfg['track_floor']:
                            mine.append((cf * 60, cc))
            (fP, cP), (fR, cR) = cand
            f, conc = (fP, cP) if cP >= cR else (fR, cR)
            agree = fP > 0 and fR > 0 and abs(fP - fR) <= 0.25 * max(fP, fR)
            ok = (amp >= cfg['amp_floor'] and f * 60 >= tune['min_rate']
                  and (conc >= cfg['solo_conc'] or (conc >= PAIR_CONC and agree)))
            if ok and conc > best[1]:
                best = (f * 60, conc, name)
            # Gated tracking: a tuning offers candidates only for windows it
            # would already have read. Ungated, the tracker can rate a window
            # every existing gate rejected, and the readable fraction quietly
            # rises for junk as well as for signal, loosening both the display
            # and the score gates as a side effect nobody asked for.
            if ok or not cfg['track_gated']:
                here.extend(mine)
        # Candidates within a third of a breath are the same peak seen through
        # two tunings; keep the clearer sighting rather than two trellis states.
        here.sort(key=lambda c: -c[1])
        merged = []
        for f, c in here:
            if all(abs(f - g) > 0.35 for g, _ in merged):
                merged.append((f, c))
        pool.append(merged)
        rates.append(best[0])
        detail.append((centre, best[0], best[1], best[2]))

    if cfg['track']:
        rates = list(track(pool, cfg['lam']))
    r = median5(np.array(rates))
    good = r[r > 0]
    frac = len(good) / len(r) if len(r) else 0.0
    if verbose:
        for (c, f, conc, via), sm in zip(detail, r):
            print(f'      t={c:5.0f}s  raw {f:5.1f}  smoothed {sm:5.1f}  '
                  f'conc {conc:.2f}  via {via}')
    return dict(rates=r, centres=np.array([d[0] for d in detail]),
                frac=frac, iqr=iqr(good),
                mean=float(good.mean()) if len(good) else 0.0,
                shown=frac >= DISPLAY_FRAC,
                confident=frac >= CONFIDENT_FRAC and coherent(r))


def local_maxima(fs, p, tot, n, k=3):
    """Top-k spectral peaks, not just the winner.

    The winner-takes-all read throws away the answer: on the counted captures a
    candidate sits at the true rate in ~95% of windows but is the single
    clearest peak in only about half of them. A tracker cannot choose what it
    was never shown.
    """
    out = []
    for i in range(1, len(p) - 1):
        if p[i] >= p[i - 1] and p[i] > p[i + 1]:
            out.append((float(fs[i]), float(p[i])))
    if not out:
        i = int(np.argmax(p))
        out = [(float(fs[i]), float(p[i]))]
    out.sort(key=lambda c: -c[1])
    return [(f, 2 * pw / (tot * n)) for f, pw in out[:k]]


def track(windows, lam):
    """Viterbi over per-window candidates: clarity, minus a cost for jumping.

    Consecutive windows share 25 of their 30 seconds, so a real rhythm is
    almost forced to give the same answer twice while a spurious peak is not.
    Scoring the whole sequence spends that redundancy; scoring each window
    alone throws it away. Standard practice in pitch tracking, where the same
    winner-takes-all read produces the same octave and side-peak errors.
    """
    dp, back = [], []
    for i, cands in enumerate(windows):
        if not cands:
            dp.append([])
            back.append([])
            continue
        prev = None
        for j in range(i - 1, -1, -1):
            if dp[j]:
                prev = j
                break
        row, ptr = [], []
        for f, clarity in cands:
            if prev is None:
                row.append(clarity)
                ptr.append(None)
            else:
                # A gap costs no more than one hop: a gated stretch is missing
                # evidence, not evidence of a jump.
                best, arg = -1e9, 0
                for k, (pf, _) in enumerate(windows[prev]):
                    v = dp[prev][k] - lam * abs(f - pf)
                    if v > best:
                        best, arg = v, k
                row.append(clarity + best)
                ptr.append((prev, arg))
        dp.append(row)
        back.append(ptr)

    last = next((i for i in range(len(dp) - 1, -1, -1) if dp[i]), None)
    if last is None:
        return np.zeros(len(windows))

    out = np.zeros(len(windows))
    i, j = last, int(np.argmax(dp[last]))
    while True:
        out[i] = windows[i][j][0]
        step = back[i][j]
        if step is None:
            break
        i, j = step
    return out


def prefer_fundamental(fs, p, f, pk, band_lo):
    """If half the detected frequency is also a peak, the lower one is the rate.

    A sway at 4/min and a breath at 8/min are not related, but a breath read at
    its own second harmonic is a real failure mode for asymmetric waveforms
    (a fast inhale and a slow exhale put real energy at 2f). Only accept the
    subharmonic when it carries a substantial share of the peak.
    """
    half = f / 2
    if half < band_lo:
        return f, pk
    k = int(np.argmin(np.abs(fs - half)))
    lo, hi = max(0, k - 2), min(len(p), k + 3)
    sub = float(p[lo:hi].max())
    if sub >= 0.5 * pk:
        return float(fs[lo + int(np.argmax(p[lo:hi]))]), sub
    return f, pk


# --------------------------------------------------------------------------

def load(path):
    d = np.genfromtxt(path, delimiter=',', names=True)
    t = d['t'].astype(float)
    step = max(1, int(round(len(t) / (t[-1] * FS))))
    d, t = d[::step], t[::step]
    accel = np.sqrt(d['ax'] ** 2 + d['ay'] ** 2 + d['az'] ** 2)
    return t, d['pitch'].astype(float), d['roll'].astype(float), accel


def find(tag):
    for f in os.listdir(CAPTURES):
        if tag in f and f.endswith('.csv'):
            return os.path.join(CAPTURES, f)
    return None


def error_at(res, when):
    """The reported rate nearest a counted minute, or None if nothing there."""
    live = res['rates'] > 0
    if not live.any():
        return None
    idx = np.where(live)[0]
    k = idx[int(np.argmin(np.abs(res['centres'][idx] - when)))]
    if abs(res['centres'][k] - when) > 45:
        return None
    return float(res['rates'][k])


VARIANTS = {
    'shipped': dict(),
    # v3.2: per-window argmax, before continuity tracking. The baseline every
    # number in the CLAUDE.md BREATHING v3 block is quoted against.
    'argmax': dict(track=False),
    'hann': dict(taper='hann'),
    'interp': dict(interp=True, steps=120),
    'span45': dict(span=45.0),
    'span60': dict(span=60.0),
    'hann+span45': dict(taper='hann', span=45.0),
    'hann+interp': dict(taper='hann', interp=True),
    'hann+span45+interp': dict(taper='hann', span=45.0, interp=True),
    'harmonic': dict(harmonic=True),
    'slow_detrend': dict(slow_over=dict(detrend=True)),
    'track.05': dict(track=True, lam=0.05),
    'track.10': dict(track=True, lam=0.10),
    'track.20': dict(track=True, lam=0.20),
    'track.40': dict(track=True, lam=0.40),
    'track.10+slowdt': dict(track=True, lam=0.10, slow_over=dict(detrend=True)),
    'track.20+slowdt': dict(track=True, lam=0.20, slow_over=dict(detrend=True)),
    'butter.05': dict(butter=0.05, slow_over=dict(band_lo=0.045, min_rate=3.0)),
    'butter.06': dict(butter=0.06, slow_over=dict(band_lo=0.055, min_rate=3.5)),
    'butter.07': dict(butter=0.07, slow_over=dict(band_lo=0.065, min_rate=4.0)),
    'butter.06+track.40': dict(butter=0.06, track=True, lam=0.40,
                               slow_over=dict(band_lo=0.055, min_rate=3.5)),
    'gtrack.45': dict(track=True, track_gated=True, lam=0.45),
    'gtrack.30': dict(track=True, track_gated=True, lam=0.30),
    'gtrack.60': dict(track=True, track_gated=True, lam=0.60),
    'axis_sum': dict(axis_sum=True),
    'axis_sum+track.20': dict(axis_sum=True, track=True, lam=0.20),
    'axis_sum+track.40': dict(axis_sum=True, track=True, lam=0.40),
    'axis_sum+track.40+slowdt': dict(axis_sum=True, track=True, lam=0.40,
                                     slow_over=dict(detrend=True)),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='run one variant by name')
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()

    names = [a.only] if a.only else list(VARIANTS)
    loaded = {}
    for tag in TRUTH:
        p = find(tag)
        if not p:
            print(f'missing capture {tag}', file=sys.stderr)
            continue
        loaded[tag] = load(p)

    for name in names:
        cfg = dict(CFG_SHIPPED, **VARIANTS[name])
        print(f'\n=== {name} ===')
        errs, hdr = [], f'{"capture":9} {"cov":>5} {"IQR":>5} {"mean":>6} {"state":>10}  counted -> read'
        print(hdr)
        for tag, (label, counts) in TRUTH.items():
            if tag not in loaded:
                continue
            t, pitch, roll, accel = loaded[tag]
            res = read(t, pitch, roll, accel, cfg, a.verbose and bool(counts))
            pairs = []
            for when, truth in counts:
                got = error_at(res, when)
                if got is None:
                    pairs.append(f'{truth:g}->  --')
                else:
                    errs.append(abs(got - truth))
                    pairs.append(f'{truth:g}->{got:4.1f}')
            state = ('confident' if res['confident']
                     else 'shown' if res['shown'] else 'refused')
            print(f'{tag:9} {res["frac"]:4.0%} {res["iqr"]:5.2f} '
                  f'{res["mean"]:6.1f} {state:>10}  ' + '  '.join(pairs))
        if errs:
            e = np.array(errs)
            print(f'  ERROR  n={len(e)}  mean {e.mean():.2f}  median '
                  f'{np.median(e):.2f}  worst {e.max():.2f}  '
                  f'within 1/min: {(e <= 1).sum()}/{len(e)}')


if __name__ == '__main__':
    main()
