#!/usr/bin/env python3
"""Offline lab for the camera breathing engine: WHY is there a rate ceiling?

    tools/camera_lab.py ~/Desktop/captures/camera [--jump 0.45] [--floor 0.10]
                        [--hi 26] [--hp 15] [--candidates] [--snr]

A faithful Python replica of `CameraSignal.breathing` (high-pass, per-window
linear detrend, band-limited DFT scan, clarity = peak power over the sum of
independent bins, pooled candidates, Viterbi tracker with a jump cost), run
over every in-app capture beside its wrist result, aligned by the capture
header's own clocks (never fitted). Constants are sweepable from the command
line so hypotheses can be tested in seconds rather than by rebuilding the app.

Replicas drift (CLAUDE.md), so this decides WHERE to look; the real engine in
`tools/camera_harness.swift` decides what ships.

Two diagnostics the harness does not have:
  --candidates  per window in the natural phase, list every candidate peak
                (rate, clarity) beside the wrist's rate, so we can see whether
                the fast rate is ever offered to the tracker at all.
  --snr         per window, the DFT power at the wrist's true rate over the
                power at the camera's chosen rate: is the truth even in the
                signal, and by how much is it being out-shouted?
"""
import csv, json, math, os, re, sys, statistics as st
from collections import defaultdict

# Engine constants (CameraSignal.swift), overridable below.
K = dict(highpassSec=15.0, loRate=3.5, hiRate=26.0, scanStep=0.1, edgeMargin=0.15,
         trackJumpCost=0.45, trackPeaks=3, trackFloor=0.10, candidateMerge=0.35,
         readClarity=0.30, motionGateRatio=4.0, minWindowSamples=8,
         windowSec=30, hopSec=5,
         # Lab-only alternatives to the engine's tracker, see jump_cost().
         costModel='abs', dominance=None)

def load_capture(path):
    hdr, rows = {}, []
    with open(path) as f:
        for line in f:
            if line.startswith('#'):
                hdr.update({k: float(v) for k, v in re.findall(r'(\w+)=([\d.]+)', line)})
                continue
            break
    with open(path) as f:
        body = [l for l in f if not l.startswith('#')]
    for r in csv.DictReader(body):
        try:
            rows.append({k: float(v) for k, v in r.items()})
        except (ValueError, TypeError):
            pass
    return hdr, rows

def sample_rate(t):
    return (len(t) - 1) / (t[-1] - t[0]) if len(t) > 1 and t[-1] > t[0] else 10.0

def highpass(x, sps, seconds):
    if not x: return x
    half = max(1, int(seconds * sps / 2))
    prefix = [0.0]
    for v in x: prefix.append(prefix[-1] + v)
    out = []
    n = len(x)
    for i in range(n):
        lo, hi = max(0, i - half), min(n - 1, i + half)
        out.append(x[i] - (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1))
    return out

def detrend(y, t):
    n = len(y)
    if n < 3: return y
    mt, my = sum(t) / n, sum(y) / n
    num = sum((t[i] - mt) * (y[i] - my) for i in range(n))
    den = sum((t[i] - mt) ** 2 for i in range(n))
    if den <= 0: return [v - my for v in y]
    slope = num / den
    return [y[i] - (my + slope * (t[i] - mt)) for i in range(n)]

def windows(total, w, h):
    if total < w: return []
    count = int((total - w) // h) + 1
    return [(i * h, i * h + w) for i in range(count)]

def dft_power(seg, t, rate):
    f = rate / 60.0
    re_ = im = 0.0
    for s, tt in zip(seg, t):
        ph = 2 * math.pi * f * tt
        re_ += s * math.cos(ph); im += s * math.sin(ph)
    return re_ * re_ + im * im

def window_reads(raw, times, wins):
    sps = sample_rate(times)
    sig = highpass(raw, sps, K['highpassSec'])
    binStep = 60.0 / K['windowSec']
    out, cursor = [], 0
    for lo, hi in wins:
        while cursor < len(times) and times[cursor] < lo: cursor += 1
        end = cursor
        while end < len(times) and times[end] < hi: end += 1
        n = end - cursor
        if n < K['minWindowSamples']:
            out.append(dict(peaks=[], spectrum=None)); continue
        t = [times[i] - lo for i in range(cursor, end)]
        seg = detrend(sig[cursor:end], t)
        rates, pows = [], []
        r = K['loRate']
        while r <= K['hiRate'] + 1e-9:
            rates.append(round(r, 3)); pows.append(dft_power(seg, t, r)); r += K['scanStep']
        total, b = 0.0, K['loRate']
        while b <= K['hiRate'] + 1e-9:
            total += dft_power(seg, t, b); b += binStep
        maxima = []
        for k in range(len(rates)):
            p = pows[k]
            left = pows[k - 1] if k > 0 else -1.0
            right = pows[k + 1] if k < len(rates) - 1 else -1.0
            if p > left and p >= right:
                edge = rates[k] <= K['loRate'] + K['edgeMargin'] or rates[k] >= K['hiRate'] - K['edgeMargin']
                maxima.append((rates[k], 0.0 if edge else (p / total if total > 0 else 0.0)))
        maxima.sort(key=lambda x: -x[1])
        out.append(dict(peaks=maxima[:K['trackPeaks']], spectrum=(rates, pows, total)))
    return out

def pool(reads_for_window):
    allp = [p for r in reads_for_window for p in r['peaks'] if p[1] >= K['trackFloor']]
    allp.sort(key=lambda x: -x[1])
    out = []
    for c in allp:
        if not any(abs(o[0] - c[0]) < K['candidateMerge'] for o in out):
            out.append(c)
    return out

def jump_cost(a, b):
    """The price of moving the path from rate a to rate b between hops.

    abs:  the engine's cost, per breath/min of difference. Moving 5 → 18
          costs 5.85, more than any clarity can be, so a clear fast peak can
          never win. This is the ceiling.
    log:  per natural-log unit of the RATIO, so doubling costs the same
          wherever it happens and 5 → 18 costs what 5 → 1.4 does. Breathing
          rates are ratio-like, not difference-like.
    Either way, `dominance` lets a candidate that is clearer than the current
    path's by at least that margin jump for free: evidence that plain should
    not be refused for being far away.
    """
    if K['costModel'] == 'log':
        return K['trackJumpCost'] * abs(math.log(max(b, 0.1) / max(a, 0.1)))
    return K['trackJumpCost'] * abs(b - a)

def track(pooled):
    dp, back = [], []
    for i, cands in enumerate(pooled):
        if not cands: dp.append([]); back.append([]); continue
        prev = next((j for j in range(i - 1, -1, -1) if dp[j]), None)
        row, ptr = [], []
        for c in cands:
            if prev is None: row.append(c[1]); ptr.append(None); continue
            best, arg = -1e300, 0
            for k, q in enumerate(pooled[prev]):
                free = K['dominance'] is not None and (c[1] - q[1]) >= K['dominance']
                v = dp[prev][k] - (0.0 if free else jump_cost(q[0], c[0]))
                if v > best: best, arg = v, k
            row.append(c[1] + best); ptr.append((prev, arg))
        dp.append(row); back.append(ptr)
    n = len(pooled)
    rates, clar = [0.0] * n, [0.0] * n
    last = next((i for i in range(n - 1, -1, -1) if dp[i]), None)
    if last is None: return rates, clar
    i, j = last, max(range(len(dp[last])), key=lambda k: dp[last][k])
    while True:
        rates[i], clar[i] = pooled[i][j]
        step = back[i][j]
        if step is None: break
        i, j = step
    return rates, clar

def window_means(y, times, wins):
    out, cursor = [], 0
    for lo, hi in wins:
        while cursor < len(times) and times[cursor] < lo: cursor += 1
        s, n, k = 0.0, 0, cursor
        while k < len(times) and times[k] < hi: s += y[k]; n += 1; k += 1
        out.append(s / n if n else 0.0)
    return out

def run_capture(csv_path, wrist_json, candidates=False, snr=False):
    hdr, rows = load_capture(csv_path)
    shift = hdr['recorder_started_at'] - hdr['session_started_at']
    times = [r['t'] for r in rows]
    total = times[-1] if times else 0
    wins = windows(total, K['windowSec'], K['hopSec'])
    channels = [[r[k] for r in rows] for k in ('dy', 'dx', 'luma', 'rdy', 'rdx', 'rluma')]
    reads = [window_reads(ch, times, wins) for ch in channels]
    motion = window_means([r['rmotion'] for r in rows], times, wins)
    gate = st.median(motion) * K['motionGateRatio']
    pooled = [[] if motion[w] > gate else pool([rd[w] for rd in reads]) for w in range(len(wins))]
    tracked, clar = track(pooled)
    rates = [r if c >= K['readClarity'] else 0.0 for r, c in zip(tracked, clar)]

    # Doorway survival: any change to the tracker must keep the paced opening.
    # Loosely the engine's rule: a run of at least 7 consecutive read windows
    # (60 s with window bleed) at <= 9/min whose first window starts inside
    # the first 90 s of SESSION time. All-or-nothing, so this is the one line
    # that says whether a sweep broke the product.
    door = None
    run_start, run_len = None, 0
    for w, (lo, hi) in enumerate(wins):
        ok = rates[w] > 0 and rates[w] <= 9.0
        if ok:
            if run_start is None: run_start = w
            run_len += 1
            if run_len >= 7 and (wins[run_start][0] + shift) <= 90 and door is None:
                door = (wins[run_start][0] + shift, st.median(rates[run_start:w + 1]))
        else:
            run_start, run_len = None, 0
    name0 = os.path.basename(csv_path)[:8]
    print(f"[{name0}] doorway: " + (f"YES  start {door[0]:.0f}s  rate {door[1]:.1f}/min" if door else "NO"))

    r = json.load(open(wrist_json))['result']
    ww, wh = r['windowSec'], r['hopSec']
    wd = {ww / 2 + i * wh: v for i, v in enumerate(r['breathingRateTimeseries'])}
    def wrist_at(ts):
        c = min(wd, key=lambda k: abs(k - ts))
        return wd[c] if abs(c - ts) <= wh and wd[c] >= 3.5 else None

    pairs = []
    for w, (lo, hi) in enumerate(wins):
        t_cam = lo + K['windowSec'] / 2
        ts = t_cam + shift
        truth = wrist_at(ts)
        if truth is None or rates[w] <= 0: continue
        pairs.append((ts, truth, rates[w], w))

    name = os.path.basename(csv_path)[:8]
    if candidates:
        print(f"\n[{name}] candidates in the NATURAL phase (session t > 180 s): wrist truth | offered (rate@clarity) | chosen")
        for ts, truth, chosen, w in pairs:
            if ts <= 180: continue
            offered = ' '.join(f"{p[0]:.1f}@{p[1]:.2f}" for p in pooled[w][:6]) or '(none)'
            near = any(abs(p[0] - truth) <= 1.0 for p in pooled[w])
            print(f"  t={ts:5.0f}  truth {truth:5.1f} | {offered:<46} | chose {chosen:4.1f}  {'TRUTH OFFERED' if near else 'truth absent'}")
    if snr:
        print(f"\n[{name}] power at the wrist's true rate vs at the camera's chosen rate, best channel, natural phase")
        for ts, truth, chosen, w in pairs:
            if ts <= 180: continue
            best_ratio, best_ch = 0.0, '-'
            for ch_i, ch_name in enumerate(('dy', 'dx', 'luma', 'rdy', 'rdx', 'rluma')):
                spec = reads[ch_i][w]['spectrum']
                if spec is None: continue
                rates_, pows, tot = spec
                def p_at(rate):
                    k = min(range(len(rates_)), key=lambda i: abs(rates_[i] - rate))
                    return pows[k]
                pt, pc = p_at(truth), p_at(chosen)
                ratio = pt / pc if pc > 0 else 0
                if ratio > best_ratio: best_ratio, best_ch = ratio, ch_name
            print(f"  t={ts:5.0f}  truth {truth:5.1f} chosen {chosen:4.1f}   power(truth)/power(chosen) = {best_ratio:6.2f}  ({best_ch})")
    return pairs

def summarize(all_pairs):
    bands = [(3.5, 6), (6, 7.5), (7.5, 9), (9, 11), (11, 30)]
    print(f"\n{'wrist band':>12} {'n':>4} {'wrist':>6} {'camera':>7} {'med err':>8}")
    for lo, hi in bands:
        sel = [(t, c) for _, t, c, _ in all_pairs if lo <= t < hi]
        if not sel: continue
        errs = sorted(abs(c - t) for t, c in sel)
        print(f"{lo:5.1f}-{hi:<5.1f} {len(sel):4d} {st.median([t for t, _ in sel]):6.1f} "
              f"{st.median([c for _, c in sel]):7.1f} {errs[len(errs) // 2]:8.2f}")
    e = sorted(abs(c - t) for _, t, c, _ in all_pairs)
    if e: print(f"ALL          {len(e):4d}                  median {e[len(e)//2]:.2f}   within±1.5 {sum(x<=1.5 for x in e)/len(e)*100:.0f}%")

if __name__ == '__main__':
    a = sys.argv[1:]
    folder = a[0]
    def opt(flag, cast=float):
        return cast(a[a.index(flag) + 1]) if flag in a else None
    for flag, key in (('--jump', 'trackJumpCost'), ('--floor', 'trackFloor'), ('--hi', 'hiRate'), ('--hp', 'highpassSec'), ('--dominance', 'dominance')):
        v = opt(flag)
        if v is not None: K[key] = v
    if '--cost' in a: K['costModel'] = a[a.index('--cost') + 1]
    print(f"constants: cost={K['costModel']} jump={K['trackJumpCost']} dominance={K['dominance']} "
          f"floor={K['trackFloor']} hi={K['hiRate']} hp={K['highpassSec']}")
    all_pairs = []
    for f in sorted(os.listdir(folder)):
        if not f.endswith('.csv') or f.endswith('_tracked.csv') or f.endswith('_wrist.csv'): continue
        wj = os.path.join(folder, f[:-4] + '_wrist.json')
        if not os.path.exists(wj): continue
        all_pairs += run_capture(os.path.join(folder, f), wj,
                                 candidates='--candidates' in a, snr='--snr' in a)
    summarize(all_pairs)
