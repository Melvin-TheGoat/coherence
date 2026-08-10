#!/usr/bin/env python3
"""Look at the captures instead of arguing about them.

Every gate in the reader is a decision about a spectrum it never shows anyone.
This draws that spectrum: rate on the vertical, session time on the horizontal,
one panel per attitude axis, with the counted breaths and the shipped engine's
answer laid on top. If a ridge sits at the counted rate the reader has a
selection problem; if there is no ridge, no amount of selection will help.

    python3 tools/breath_spectrogram.py            # every counted capture
    python3 tools/breath_spectrogram.py D89DE1CA
"""
import os
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from breath_lab import (CFG_SHIPPED, HOP_SEC, TRUTH, WINDOW_SEC, band_pass,
                        detrend, find, load, read)

OUT = '/private/tmp/claude-501/-Users-azizmahmud-Documents-Meditation-Manifestation-App/afabbc86-7c2f-4106-9820-f1e50f7a692b/scratchpad'
RATE_LO, RATE_HI = 3.5, 20.0     # breaths/min shown


def spectrogram(t, y, span=45.0):
    """Per-window whitened power of the signal the engine actually scans.

    An earlier version of this plot skipped the band-pass, on the theory that
    it should show the raw signal rather than the engine's view of it. That was
    a mistake: it painted a 2 to 4 per minute drift ridge across every capture
    and made the reader look like it was drowning in something the moving
    average had in fact already removed (drift-to-breath power 0.07 after the
    12 s band-pass, measured on D89DE1CA).
    """
    y = band_pass(y, 12.0)
    n_win = int((t[-1] - WINDOW_SEC) // HOP_SEC) + 1
    rates = np.linspace(RATE_LO, RATE_HI, 200)
    freqs = rates / 60.0
    img = np.zeros((len(rates), n_win))
    centres = np.zeros(n_win)
    for i in range(n_win):
        c = i * HOP_SEC + WINDOW_SEC / 2
        centres[i] = c
        m = (t >= max(t[0], c - span / 2)) & (t < min(t[-1], c + span / 2))
        if m.sum() < 8:
            continue
        wt, wy = t[m], detrend(y[m], t[m])
        wy = wy * np.hanning(len(wy))
        ang = 2 * np.pi * np.outer(freqs, wt)
        re = (np.cos(ang) * wy).sum(axis=1)
        im = -(np.sin(ang) * wy).sum(axis=1)
        p = re * re + im * im
        # Whitened, in dB above this window's own median. Normalising by the
        # maximum instead hides everything under the postural drift peak, which
        # is 10 to 20 dB above the breath and present in every window: the
        # picture then says only "there is drift", which we already knew.
        if p.max() > 0:
            img[:, i] = 10 * np.log10(p / np.median(p) + 1e-12)
    return centres, rates, img


def draw(tag, label, counts):
    t, pitch, roll, accel = load(find(tag))
    res = read(t, pitch, roll, accel, dict(CFG_SHIPPED))

    fig, axes = plt.subplots(2, 1, figsize=(13, 7), sharex=True)
    for ax, (name, sig) in zip(axes, (('pitch', pitch), ('roll', roll))):
        c, rates, img = spectrogram(t, sig)
        ax.pcolormesh(c, rates, img, cmap='magma', shading='nearest',
                      vmin=0, vmax=14)
        live = res['rates'] > 0
        ax.plot(res['centres'][live], res['rates'][live], 'o', ms=3.2,
                color='#56D1C9', label='engine reads')
        if counts:
            ax.plot([w for w, _ in counts], [v for _, v in counts], 'D', ms=9,
                    mfc='none', mew=2.2, color='#F0C058', label='counted')
        ax.axhspan(4.5, 7, color='#56D1C9', alpha=0.10, lw=0)
        ax.set_ylabel(f'{name}   breaths/min')
        ax.set_ylim(RATE_LO, RATE_HI)
        ax.legend(loc='upper right', fontsize=8, framealpha=0.85)
    axes[1].set_xlabel('session time (s)')
    axes[0].set_title(f'{tag}  {label}   engine: {res["frac"]:.0%} readable, '
                      f'mean {res["mean"]:.1f}/min')
    fig.tight_layout()
    path = os.path.join(OUT, f'spec-{tag}.png')
    fig.savefig(path, dpi=110)
    plt.close(fig)
    return path


if __name__ == '__main__':
    tags = sys.argv[1:] or list(TRUTH)
    for tag in tags:
        print(draw(tag, *TRUTH[tag]))
