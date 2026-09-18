#!/usr/bin/env python3
"""Score a camera tracked series against a digitized wrist series.

    tools/camera_compare.py wrist.csv|<id>_wrist.json camera_tracked.csv SESSION_SEC [--minutes]

Aligns the two series with the MEASURED offset out of the capture file's own
header, then reports median error and the fraction within 1.5 breaths/min.
Pure Python on purpose: this Mac has no numpy.

**It used to fit the offset instead, and that flattered every result** (Aziz's
first paced sit, 2026-09-17). It swept 0 to 180 s and kept whichever alignment
minimised the median error, which is fitting the thing being measured: on that
sit it chose 115 s and reported 1.43/min, where the true offset of 8.9 s gives
4.70/min. It also only searched POSITIVE offsets, so it could never find the
real one, because the recorder always starts a few seconds AFTER the session.

The capture file has carried the answer all along:

    # session_started_at=1789696516.257
    # recorder_started_at=1789696525.149

so session_time = t_video + (recorder_started_at - session_started_at). The
search survives only as a fallback for a file with no header, and says so.
"""
import csv, sys, collections, os, re

def load(path, tkey, vkey, ckey=None):
    out = []
    for r in csv.DictReader(open(path)):
        try: t = float(r[tkey]); v = float(r[vkey])
        except (ValueError, KeyError): continue
        out.append((t, v, float(r[ckey]) if ckey else 1.0))
    return out

def load_wrist(path):
    """A digitized CSV (t_sec,breath,stillness) or the app's <id>_wrist.json
    (a SessionPayload: result.breathingRateTimeseries on a windowSec/hopSec
    grid). Either way: (t_sec, breath, 1.0) at window centres, zeros dropped."""
    if path.endswith('.json'):
        import json
        j = json.load(open(path)); r = j['result']
        win, hop = r['windowSec'], r['hopSec']
        return [(win / 2 + i * hop, v, 1.0) for i, v in enumerate(r['breathingRateTimeseries']) if v > 0]
    return load(path, 't_sec', 'breath')

def measured_shift(cam_csv):
    """Seconds to ADD to a camera t to get session time, read from the raw
    capture's header. The tracked file has no header, so its sibling is used:
    `<id>_tracked.csv` beside `<id>.csv`. None when there is no header to read.
    """
    raw = cam_csv[:-len('_tracked.csv')] + '.csv' if cam_csv.endswith('_tracked.csv') else cam_csv
    if not os.path.exists(raw): return None
    got = {}
    with open(raw) as f:
        for line in f:
            if not line.startswith('#'): break
            got.update({k: float(v) for k, v in re.findall(r'(\w+)=([\d.]+)', line)})
    if 'recorder_started_at' in got and 'session_started_at' in got:
        return got['recorder_started_at'] - got['session_started_at']
    return None


def fitted_shift(c, wd, sess):
    """Last resort for a headerless capture. Reported as fitted, never as
    measured, because choosing the alignment that minimises the error is
    choosing the answer."""
    best = None
    for off in range(-60, 181, 5):
        errs = []
        for t, v, cl in c:
            if cl < 0.30: continue
            st = int(round((t + off) / 5)) * 5
            if st in wd and wd[st] >= 3.5 and 30 <= st <= sess - 30:
                errs.append(abs(v - wd[st]))
        if len(errs) < 20: continue
        errs.sort(); med = errs[len(errs) // 2]
        if best is None or med < best[1]: best = (off, med)
    return best[0] if best else 0.0


def compare(wrist_csv, cam_csv, sess, minutes=False):
    w = load_wrist(wrist_csv); c = load(cam_csv, 't_video_sec', 'rate', 'clarity')
    wd = {int(round(t / 5)) * 5: v for t, v, _ in w}

    shift = measured_shift(cam_csv)
    how = "measured from the capture header"
    if shift is None:
        shift = fitted_shift(c, wd, sess)
        how = "FITTED, no header found: treat the error below as a best case"

    errs = []
    for t, v, cl in c:
        if cl < 0.30: continue
        st = int(round((t + shift) / 5)) * 5
        if st in wd and wd[st] >= 3.5 and 30 <= st <= sess - 30:
            errs.append(abs(v - wd[st]))
    if not errs:
        print(f"shift {shift:+.1f}s ({how}): no windows both instruments read")
        return (shift, None, None, 0)
    errs.sort(); med = errs[len(errs) // 2]; within = sum(e <= 1.5 for e in errs) / len(errs)
    n = len(errs)
    off = shift
    print(f"shift {shift:+.1f}s ({how})  n={n:3d}  median|err| {med:.2f}/min  within±1.5 {within*100:3.0f}%")
    if minutes:
        cm = collections.defaultdict(list); wm = collections.defaultdict(list)
        for t, v, cl in c:
            if cl >= 0.30: cm[int((t + shift) / 60)].append(v)
        for t, v, _ in w:
            if v >= 3.5: wm[int(t / 60)].append(v)
        med_ = lambda a: (sorted(a)[len(a) // 2] if a else None)
        print("  min  wrist  camera  diff")
        for m in range(0, sess // 60):
            a, b = med_(wm.get(m, [])), med_(cm.get(m, []))
            d = f"{b - a:+5.1f}" if (a is not None and b is not None) else "   --"
            print(f"  {m:3d}  {'   --' if a is None else f'{a:5.1f}'}  {'    --' if b is None else f'{b:6.1f}'}  {d}")
    return (shift, med, within, n)

if __name__ == '__main__':
    a = sys.argv[1:]
    sess = a[2]
    if sess == 'auto':
        import json
        sess = json.load(open(a[0]))['durationSec']
    compare(a[0], a[1], int(sess), minutes='--minutes' in a)
