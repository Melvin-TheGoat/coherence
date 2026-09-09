#!/usr/bin/env python3
"""Score a camera tracked series against a digitized wrist series.

    tools/camera_compare.py wrist.csv|<id>_wrist.json camera_tracked.csv SESSION_SEC [--minutes]

Finds the video-to-session offset (0-180 s) that minimises median |error| over
windows both instruments read, then reports median error and the fraction
within 1.5 breaths/min. Pure Python on purpose: this Mac has no numpy.
"""
import csv, sys, collections

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

def compare(wrist_csv, cam_csv, sess, minutes=False):
    w = load_wrist(wrist_csv); c = load(cam_csv, 't_video_sec', 'rate', 'clarity')
    wd = {int(round(t / 5)) * 5: v for t, v, _ in w}
    best = None
    for off in range(0, 181, 5):
        errs = []
        for t, v, cl in c:
            if cl < 0.30: continue
            st = int(round((t - off) / 5)) * 5
            if st in wd and wd[st] >= 3.5 and 30 <= st <= sess - 30:
                errs.append(abs(v - wd[st]))
        if len(errs) < 20: continue
        errs.sort(); med = errs[len(errs) // 2]; within = sum(e <= 1.5 for e in errs) / len(errs)
        if best is None or med < best[1]: best = (off, med, within, len(errs))
    off, med, within, n = best
    print(f"offset {off:3d}s  n={n:3d}  median|err| {med:.2f}/min  within±1.5 {within*100:3.0f}%")
    if minutes:
        cm = collections.defaultdict(list); wm = collections.defaultdict(list)
        for t, v, cl in c:
            if cl >= 0.30: cm[int((t - off) / 60)].append(v)
        for t, v, _ in w:
            if v >= 3.5: wm[int(t / 60)].append(v)
        med_ = lambda a: (sorted(a)[len(a) // 2] if a else None)
        print("  min  wrist  camera  diff")
        for m in range(0, sess // 60):
            a, b = med_(wm.get(m, [])), med_(cm.get(m, []))
            d = f"{b - a:+5.1f}" if (a is not None and b is not None) else "   --"
            print(f"  {m:3d}  {'   --' if a is None else f'{a:5.1f}'}  {'    --' if b is None else f'{b:6.1f}'}  {d}")
    return best

if __name__ == '__main__':
    a = sys.argv[1:]
    compare(a[0], a[1], int(a[2]), minutes='--minutes' in a)
