#!/usr/bin/env python3
"""Turn a raw respiration waveform (a belt, thermistor, or impedance trace,
which is what every public dataset ships) into the ground-truth CSV our
camera tools already consume: `t_sec,breath,stillness` on the engine's
30 s / 5 s grid, one rate per window centre.

    tools/resp_reference.py belt.csv --time-col t --value-col resp --out ref.csv
    tools/resp_reference.py belt.txt --hz 32 --out ref.csv          # one column, fixed rate
    tools/resp_reference.py belt.csv ... --plot                     # ASCII sanity check

The rate is found by COUNTING BREATHS, not by a spectrum: band-pass the trace
to 2-40 breaths/min, then detect inhale peaks with a hysteresis threshold at a
fraction of the window's peak-to-peak range, and rate = 60 * (peaks - 1) /
(time from first to last peak). Deliberately a different method from the
engine's DFT scan, so a reference produced here cannot share the engine's
harmonic mistakes: a belt trace at 8/min with a strong second harmonic still
has eight inhales in it. Pure Python on purpose (no numpy on this Mac).

Zeros mean "could not count" (fewer than two peaks, or a window with almost
no excursion), and the consumers drop them, the same convention as the
wrist's own series.
"""
import csv, math, sys, statistics as st

WINDOW, HOP = 30.0, 5.0
LO_BPM, HI_BPM = 2.0, 40.0

def load(path, time_col, value_col, hz):
    t, v = [], []
    with open(path) as f:
        head = f.readline()
        f.seek(0)
        if ',' in head and any(c.isalpha() for c in head):
            for r in csv.DictReader(f):
                try:
                    v.append(float(r[value_col]))
                    t.append(float(r[time_col]) if time_col else None)
                except (KeyError, ValueError):
                    continue
        else:
            for line in f:
                s = line.strip().split(',')[0]
                try: v.append(float(s))
                except ValueError: continue
            t = [None] * len(v)
    if not t or t[0] is None:
        if not hz: sys.exit("no time column found; pass --hz for a fixed-rate trace")
        t = [i / hz for i in range(len(v))]
    # Some references count time from an arbitrary epoch; start at zero.
    t0 = t[0]
    return [x - t0 for x in t], v

def sample_rate(t):
    return (len(t) - 1) / (t[-1] - t[0])

def moving_average(x, n):
    n = max(1, n)
    out, s, q = [], 0.0, []
    for val in x:
        q.append(val); s += val
        if len(q) > n: s -= q.pop(0)
        out.append(s / len(q))
    # centre it
    shift = n // 2
    return out[shift:] + [out[-1]] * shift

def bandpass(v, sps):
    """Subtract a slow moving average (drift below 2/min) and smooth away
    anything faster than 40/min. Two boxcars, which is crude and adequate for
    counting peaks in a clean belt trace."""
    slow = moving_average(v, int(sps * 60 / LO_BPM))
    hp = [a - b for a, b in zip(v, slow)]
    return moving_average(hp, int(sps * 60 / HI_BPM / 2))

def count_rate(seg_t, seg_v):
    """Inhale peaks with hysteresis: a peak counts once the trace has fallen
    back by `hyst` from it, and the next one cannot start until the trace has
    risen `hyst` from the intervening trough. Returns 0 when it cannot count."""
    if len(seg_v) < 8: return 0.0
    rng = max(seg_v) - min(seg_v)
    if rng <= 0: return 0.0
    hyst = 0.25 * rng
    peaks = []
    state, ext, ext_t = 'rising', seg_v[0], seg_t[0]
    for tt, val in zip(seg_t, seg_v):
        if state == 'rising':
            if val > ext: ext, ext_t = val, tt
            elif ext - val >= hyst:
                peaks.append(ext_t); state, ext = 'falling', val
        else:
            if val < ext: ext = val
            elif val - ext >= hyst:
                state, ext, ext_t = 'rising', val, tt
    if len(peaks) < 2: return 0.0
    span = peaks[-1] - peaks[0]
    if span <= 0: return 0.0
    return 60.0 * (len(peaks) - 1) / span

def reference(t, v):
    sps = sample_rate(t)
    x = bandpass(v, sps)
    total = t[-1]
    rows = []
    n = int((total - WINDOW) // HOP) + 1 if total >= WINDOW else 0
    cursor = 0
    for i in range(n):
        lo, hi = i * HOP, i * HOP + WINDOW
        while cursor < len(t) and t[cursor] < lo: cursor += 1
        end = cursor
        while end < len(t) and t[end] < hi: end += 1
        rate = count_rate(t[cursor:end], x[cursor:end])
        if not (LO_BPM <= rate <= HI_BPM): rate = 0.0
        rows.append((lo + WINDOW / 2, round(rate, 2)))
    return rows

def ascii_plot(rows):
    vals = [r for _, r in rows if r > 0]
    if not vals: print("(nothing counted)"); return
    hi = max(vals)
    for tc, r in rows:
        bar = '#' * int(40 * r / hi) if r > 0 else '.'
        print(f"{tc:6.0f}s {r:5.1f} {bar}")

if __name__ == '__main__':
    a = sys.argv[1:]
    if not a: sys.exit(__doc__)
    def opt(flag, default=None):
        return a[a.index(flag) + 1] if flag in a else default
    t, v = load(a[0], opt('--time-col'), opt('--value-col', 'resp'), float(opt('--hz', 0)) or None)
    rows = reference(t, v)
    out = opt('--out', a[0].rsplit('.', 1)[0] + '_reference.csv')
    with open(out, 'w', newline='') as f:
        w = csv.writer(f); w.writerow(['t_sec', 'breath', 'stillness'])
        for tc, r in rows: w.writerow([f"{tc:.1f}", f"{r:.2f}", ''])
    counted = [r for _, r in rows if r > 0]
    print(f"{len(rows)} windows, {len(counted)} counted, "
          f"median {st.median(counted):.1f}/min, range {min(counted):.1f} to {max(counted):.1f}" if counted
          else f"{len(rows)} windows, nothing counted")
    print(f"wrote {out}")
    if '--plot' in a: ascii_plot(rows)
