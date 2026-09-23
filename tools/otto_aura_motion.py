"""Motion data for Otto's aura rig: positions relative to his baseline centre
(332, 649 on the canvas), y up is negative. Times in seconds; the build turns
them into frames at 60 fps."""
import math, random

# Motes: three groups, shown from stage 5 (A), 6 (A+B), 7 (A+B+C).
MOTES = {
    "A": [(-235, -430), (215, -455), (-255, -250), (250, -275), (0, -625)],
    "B": [(-175, -545), (165, -560), (-280, -140), (285, -150), (-120, -330)],
    "C": [(95, -610), (-60, -640), (300, -380), (-300, -390)],
}
MOTE_LOOP = 8.0

def mote_keys(i, x, y):
    """Twinkle and drift: invisible, swell to full, fade, rising 22 units."""
    t0 = (i * 1.37) % MOTE_LOOP
    life = 2.6
    keys = []  # (t, opacity, y)
    def at(t): return t % MOTE_LOOP
    # keep keys inside [0, loop]: if the life wraps, split it
    pts = [(0.0, 0, y), (life * 0.45, 100, y - 10), (life, 0, y - 22)]
    for dt, o, yy in pts:
        keys.append((at(t0 + dt), o, yy))
    keys.sort()
    return keys

# Rings round his middle (front arc in front of him, back arc behind).
RINGS = [
    # (rx, ry, centre y, tilt degrees, loop seconds, stages)
    (270, 60, -175, -7, 3.2, (6, 7)),
    (240, 52, -95, 9, 4.6, (7,)),
]

# Leaves spiral up round him at Nirvana: start low, swing round, rise, fade.
LEAF_LOOP = 9.0
def leaf_keys(i, n=6):
    phase = i / n
    keys = []
    for s in range(9):
        u = s / 8.0                       # 0..1 through one rise
        t = (phase * LEAF_LOOP + u * LEAF_LOOP * 0.8) % LEAF_LOOP
        ang = 2 * math.pi * (u * 1.25 + phase)
        x = 285 * math.cos(ang)
        y = -40 - 560 * u + 40 * math.sin(ang)
        front = math.sin(ang) > 0
        op = 0 if s in (0, 8) else (100 if front else 45)
        sc = 100 if front else 78
        rot = (u * 540 + i * 60) % 360
        keys.append((round(t, 3), round(x, 1), round(y, 1), op, sc, round(rot, 1)))
    return sorted(keys)

# The fly at stage 1: in from the right, circles his head, rests, leaves left.
FLY_LOOP = 11.0
def fly_keys():
    random.seed(8)
    head = (-10, -470)
    keys = [(0.0, 400, -560, 0), (1.0, 400, -560, 0), (1.01, 360, -560, 100)]
    t = 2.0
    keys.append((t, 150, -520, 100))
    for k in range(12):
        t += 0.42
        ang = k * 1.1
        keys.append((round(t, 2), round(head[0] + 150 * math.cos(ang) + random.uniform(-25, 25), 1),
                     round(head[1] - 20 + 70 * math.sin(ang * 1.3) + random.uniform(-20, 20), 1), 100))
    keys.append((round(t + 0.6, 2), 20, -590, 100))       # lands on his head
    keys.append((round(t + 1.8, 2), 20, -590, 100))       # sits a moment
    keys.append((round(t + 2.9, 2), -420, -640, 100))     # away up and left
    keys.append((round(t + 2.91, 2), -420, -640, 0))
    keys.append((FLY_LOOP, 400, -560, 0))
    return keys

if __name__ == "__main__":
    for g, pts in MOTES.items():
        for i, (x, y) in enumerate(pts):
            print("mote", g, i, mote_keys(i + ord(g), x, y))
    print("leaf0", leaf_keys(0))
    print("fly", fly_keys()[:6], "...", len(fly_keys()), "keys")
