#!/usr/bin/env python3
"""Which measurable property separates a capture we read right from one we don't?

Accuracy on the counted captures splits them cleanly: E1711EEE and D89DE1CA
land within about a breath, ACF453B2 is out by 3 or 4, and 39F2003D had no
breath in it at all yet currently passes the confidence gate. Coverage and
spread do not tell those apart, so the gate cannot either. This scores several
candidate properties on every capture and prints them side by side.

    python3 tools/breath_conf.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from breath_lab import (ACCEL_RATIO, BAND_HI, HOP_SEC, NATURAL, SLOW, TRUTH,
                        WINDOW_SEC, band_pass, detrend, find, load, spectrum)

# How the shipped engine actually did on each, from breath_lab.
GRADE = {
    'E1711EEE': 'good  (10->9.3, 8.5->7.5)',
    'D89DE1CA': 'ok    (7->9.3, 7->6.2, 6->4.6)',
    '00F5873B': 'ok    (12->10.8)',
    'ACF453B2': 'BAD   (12->8.4, 8->4.8, 6.5->9.3)',
    '39F2003D': 'NONE  (no breath, reads confident)',
    '9442AD1A': '?     (uncounted)',
}


def window_peaks(t, pitch, roll, accel):
    """Per window: the peak rate on each axis under each tuning, plus accel."""
    banded = {n: (band_pass(pitch, c['slow_sec']), band_pass(roll, c['slow_sec']))
              for n, c in (('slow', SLOW), ('natural', NATURAL))}
    n_win = int((t[-1] - WINDOW_SEC) // HOP_SEC) + 1
    rows = []
    for i in range(n_win):
        lo, hi = i * HOP_SEC, i * HOP_SEC + WINDOW_SEC
        m = (t >= lo) & (t < hi)
        if m.sum() < 8:
            continue
        wt = t[m]
        row = {'accel': float(np.sqrt(np.mean(accel[m] ** 2)))}
        for name, cfg in (('slow', SLOW), ('natural', NATURAL)):
            bp, br = banded[name]
            for axis, ch in (('pitch', bp[m]), ('roll', br[m])):
                y = detrend(ch, wt) if cfg['detrend'] else ch
                fs, p, tot = spectrum(wt, y, cfg['band_lo'], BAND_HI, 'none', 120)
                if fs is None:
                    row[f'{name}.{axis}'] = (0.0, 0.0)
                    continue
                k = int(np.argmax(p))
                row[f'{name}.{axis}'] = (float(fs[k] * 60),
                                         float(2 * p[k] / (tot * len(y))))
                row[f'{name}.{axis}.amp'] = float(y.std() * 1000)
        rows.append(row)
    return rows


def agree(a, b, tol=0.15):
    return a > 0 and b > 0 and abs(a - b) <= tol * max(a, b)


def main():
    print(f'{"capture":9} {"verdict":34} {"axisAgr":>8} {"tuneAgr":>8} '
          f'{"conc50":>7} {"amp50":>7} {"accelCV":>8} {"step50":>7}')
    for tag, (label, counts) in TRUTH.items():
        t, pitch, roll, accel = load(find(tag))
        rows = window_peaks(t, pitch, roll, accel)
        gate = np.median([r['accel'] for r in rows]) * ACCEL_RATIO
        quiet = [r for r in rows if r['accel'] <= gate]
        if not quiet:
            continue

        # Do the two axes see the same rhythm? One wrist rotation should show
        # in pitch and roll alike; two unrelated peaks are two noises.
        axis_agr = np.mean([agree(r['slow.pitch'][0], r['slow.roll'][0])
                            for r in quiet])
        # Do the two filter tunings see the same rhythm? A real oscillation
        # survives a different band edge; a filter artefact moves with it.
        tune_agr = np.mean([agree(r['slow.roll'][0], r['natural.roll'][0])
                            or agree(r['slow.pitch'][0], r['natural.pitch'][0])
                            for r in quiet])
        conc = np.median([max(r['slow.pitch'][1], r['slow.roll'][1]) for r in quiet])
        amp = np.median([max(r['slow.pitch.amp'], r['slow.roll.amp']) for r in quiet])
        a = np.array([r['accel'] for r in rows])
        accel_cv = float(a.std() / a.mean()) if a.mean() > 0 else 0
        best = np.array([r['slow.pitch'][0] if r['slow.pitch'][1] >= r['slow.roll'][1]
                         else r['slow.roll'][0] for r in quiet])
        step = float(np.median(np.abs(np.diff(best)))) if len(best) > 1 else 0

        print(f'{tag:9} {GRADE[tag]:34} {axis_agr:7.0%} {tune_agr:8.0%} '
              f'{conc:7.2f} {amp:7.2f} {accel_cv:8.2f} {step:7.2f}')


if __name__ == '__main__':
    main()
