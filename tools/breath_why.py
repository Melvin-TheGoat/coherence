#!/usr/bin/env python3
"""Why did a window read what it read?

The variant bench says the shipped reader scatters around the counted rate.
That has two very different causes and they need different fixes: either the
breath is not in the spectrum at all (a filtering problem), or it is there and
loses the winner-takes-all contest to something else (a selection problem).

For each window this prints every candidate the engine considers, ranked as it
ranks them, and marks the one nearest the counted truth. If truth is usually
present but rarely first, selection is the bug.

    python3 tools/breath_why.py D89DE1CA 7
"""
import sys

import numpy as np

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from breath_lab import (BAND_HI, FS, HOP_SEC, NATURAL, SLOW, WINDOW_SEC,
                        band_pass, detrend, find, load, spectrum)


def main():
    tag = sys.argv[1]
    truth = float(sys.argv[2])
    t, pitch, roll, accel = load(find(tag))

    banded = {n: (band_pass(pitch, c['slow_sec']), band_pass(roll, c['slow_sec']))
              for n, c in (('slow', SLOW), ('natural', NATURAL))}

    n_win = int((t[-1] - WINDOW_SEC) // HOP_SEC) + 1
    print(f'{tag}  {t[-1]:.0f}s   truth ~{truth:g}/min')
    print(f'{"t":>5}  ' + '  '.join(f'{n}.{a:<10}' for n in ('slow', 'nat')
                                    for a in ('pitch', 'roll')))

    hit_rank, present, total = [], 0, 0
    for i in range(n_win):
        lo, hi = i * HOP_SEC, i * HOP_SEC + WINDOW_SEC
        m = (t >= lo) & (t < hi)
        if m.sum() < 8:
            continue
        wt = t[m]
        cands = []
        for name, cfg in (('slow', SLOW), ('natural', NATURAL)):
            bp, br = banded[name]
            for axis, ch in (('pitch', bp[m]), ('roll', br[m])):
                y = detrend(ch, wt) if cfg['detrend'] else ch
                fs, p, tot = spectrum(wt, y, cfg['band_lo'], BAND_HI, 'none', 120)
                if fs is None:
                    cands.append((0.0, 0.0, name, axis, None, None))
                    continue
                k = int(np.argmax(p))
                conc = 2 * p[k] / (tot * len(y))
                # Is there any local maximum near the counted rate, and how
                # much of the peak's power does it carry?
                near = np.abs(fs * 60 - truth) <= 1.5
                share = float(p[near].max() / p[k]) if near.any() else 0.0
                cands.append((float(fs[k] * 60), float(conc), name, axis,
                              share, float(y.std() * 1000)))
        cands_sorted = sorted(cands, key=lambda c: -c[1])
        best = cands_sorted[0]
        total += 1
        if any(c[4] and c[4] >= 0.5 for c in cands):
            present += 1
        rank = next((j for j, c in enumerate(cands_sorted)
                     if abs(c[0] - truth) <= 1.5), None)
        if rank is not None:
            hit_rank.append(rank)
        cells = []
        for f, conc, name, axis, share, amp in cands:
            mark = '*' if abs(f - truth) <= 1.5 else ' '
            win = '<' if (f, conc, name, axis) == (best[0], best[1], best[2], best[3]) else ' '
            cells.append(f'{f:5.1f}/{conc:.2f}{mark}{win}')
        print(f'{lo + 15:5.0f}  ' + '  '.join(cells))

    print(f'\ncandidates carrying a near-truth peak (>=50% of their own max): '
          f'{present}/{total} windows')
    if hit_rank:
        r = np.array(hit_rank)
        print(f'when a candidate IS at truth, its clarity rank: 1st {(r == 0).sum()}  '
              f'2nd {(r == 1).sum()}  3rd {(r == 2).sum()}  4th {(r == 3).sum()}  '
              f'(of {total} windows)')
    else:
        print('no candidate ever peaked at the counted rate')


if __name__ == '__main__':
    main()
