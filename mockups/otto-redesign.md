# Otto: how to draw him again, and how to get the result into the app

Standing brief, rewritten 2026-09-20 for the third attempt. Two halves: the
prompt, which is Melvin's side, and the import, which is one command each.

## Where this has got to, so the same ground is not walked again

- **The generated set (September).** Sticker-cute. Rejected: "too
  childish."
- **The furrier, more realistic set (09-20).** Answered "furrier, older,
  more realistic proportions" and still read childish, because realism went
  into the FUR and never into the face. Rejected.
- **The lying-down pose, same set.** Rejected outright, Melvin: "the lying
  down looks very weird." It is gone from the app as well as the brief.
  Evening sessions now show him settled instead of asleep.

**The target is now Duolingo's owl** (Melvin: "more similar to the duolingo
bird, like slightly more 3D, shrunk but still old and wise"). That means a
compact, rounded, softly dimensional character with a clean silhouette, not
a textured animal. The previous brief argued the opposite way, toward
realistic proportions and fur breaking the outline. **Ignore it; it is
superseded.**

**The tension to hold, and it is the whole job:** chunky and simple almost
always reads young, which is exactly why Duo reads as a child's character.
**Age has to come from the face and the posture, never from the
proportions.** So: keep him short, round and heavy, and put every year of
him into heavy lids, a brow, a closed mouth and a settled weight. A big
round body with big round eyes is a toddler. A big round body with lowered
lids and a level brow is an elder.

## The five poses

    otto-wave.png    Home, and the pose the Rive rig animates
    otto-sit.png     session rows, the calendar, anywhere he is meditating
    otto-awake.png   avatars and rows, eyes open, looking at you
    otto-head.png    the mark: chat rows, anything under about 40pt
    otto-talk.png    optional; without it the waving art stands in

There is no lying-down pose and nothing in the app asks for one.

## Prompt to paste, one run per pose

Swap only the pose line between runs. Everything else has to stay identical
or the set will not look like one character.

    A wise old three-toed sloth character for a meditation app, in the style
    of a modern mobile game mascot: bold rounded shapes, clean silhouette,
    soft volumetric shading and gentle gradients that give it dimension
    without being a photoreal render, matte finish, no outlines, no fur
    texture noise. Compact chunky proportions, short limbs, a heavy settled
    body. Warm caramel fur with a cream chest and muzzle, a dark brown
    facial mask. He is OLD AND WISE, and that is carried entirely in the
    face: heavy half-lowered eyelids over small calm eyes, a level brow
    ridge above them, a small closed mouth, and paler grizzled cream around
    the muzzle and brows. Serene, unhurried, grounded. POSE HERE. Facing the
    viewer, centred, feet at the bottom edge of the frame, the whole
    character inside the frame. Transparent background, no ground, no
    shadow on the ground, no props, no text. Must read clearly at 40 pixels
    tall.

    Pose lines:
      wave    sitting upright, one arm raised in a small calm wave
      sit     sitting cross-legged, hands resting on the knees, eyes fully closed, serene
      awake   sitting, hands on the knees, eyes open under heavy lids, looking at the viewer
      head    head and shoulders only, eyes open, the faintest smile
      talk    sitting, one hand raised beside the head, mouth slightly open, mid sentence

    Negative: cute, chibi, baby, cartoon sticker, thick outlines, big glossy
    eyes, wide open smile, blush cheeks, toy, plastic, photorealistic,
    background, ground shadow, text, watermark, extra limbs.

**If it is still wrong, change one thing per run.** The levers, in order of
how much each moves the result: the eyes (lid height), the brow, the mouth,
then the body mass. A prompt that moves all four at once produces a
different animal rather than a better one.

**The one thing that cannot change: the palette.** Every colour on every
screen was sampled out of Otto, so a grey or green-brown sloth, however
true to life, means repainting the whole app. He can get older. He cannot
get grey.

## The import

Drop the files in `mockups/otto-v3/` (or v4, v5) named exactly as above,
then:

    python3 tools/otto_import.py mockups/otto-v3

That writes every image set at the sizes the app already uses, normalising
each pose to a longest edge of 200 points so they sit together as one
character. Then, with the Rive editor open on the Otto file:

    python3 tools/otto_swap.py mockups/otto-v3/otto-wave.png

which puts the new art inside the animated rig and writes
`Coherence/Otto/Otto.riv`. The rig itself never changes.

**A sheet is fine now.** Image models return the whole set as one picture
and the first two rounds were cut up by hand, so `tools/otto_split.py` does
it: it finds the poses by their transparency, splits on the gaps between
them, and writes one cropped PNG per pose in reading order.

    python3 tools/otto_split.py ~/Downloads/sheet.png --dry-run
    python3 tools/otto_split.py ~/Downloads/sheet.png

It is pure Python, since this Mac has no PIL and no ImageMagick, and it
refuses to write a set whose cell count does not match the names rather
than guessing. `--dry-run` prints the cells first, and `--gap` widens or
narrows what counts as a break between poses if a cut comes out wrong.

**Transparency is still the one thing nothing here can fix.** Alpha is how
the poses are found and how they sit on the app's cream, so a sheet on a
white background is unusable: the splitter would see one big rectangle and
the importer refuses it anyway. Ask for it up front and check before
running either command.

## The aura poses (2026-09-21): three more of TODAY's Otto

For the aura progression (`mockups/otto-aura.html`): 60 percent is today's
`otto-sit.png` and Rive draws the glow for 80 and 100, so only three new
poses are needed. **The previous prompt above describes an "old and wise"
Otto that never shipped; the art in `mockups/otto-v3/` is today's Otto, so
these runs attach it as the reference instead of describing him.**

Attach `mockups/otto-v3/otto-awake.png` and `mockups/otto-v3/otto-sit.png`,
then one run per pose in the same chat, swapping only the pose line:

    The attached images are Otto, the sloth mascot of my meditation app.
    Draw the SAME character: identical art style, colours, proportions, fur,
    face shapes, eye mask, nose, claws and soft 3D shading. Do not redesign
    him, do not change his colours, and do not make him more realistic or
    more cartoony. Only his pose and expression change.

    Pose: POSE LINE HERE

    Full body, facing the viewer, centred, the whole character inside the
    frame with a little space around him, lit the same way as the reference.
    Transparent background (PNG with alpha). No ground, no shadow, no glow,
    no sparkles, no props, no text. One character only.

    otto-low         Sitting slumped on the ground, cross-legged, back
                     rounded, head drooping forward, arms hanging limp with
                     his hands resting on the ground beside him. Heavy
                     half-closed eyes looking down, brows tilted up in the
                     middle, a clear frown. Tired and defeated.
    otto-frustrated  Sitting cross-legged but slouched, shoulders hunched and
                     rounded forward, arms hanging limp in his lap. Eyes half
                     open under lowered brows, glancing to one side, a small
                     grumpy frown. Grumpy, not angry.
    otto-curious     Sitting cross-legged and upright, hands resting in his
                     lap. Big round eyes wide open, looking up and to one
                     side, a small hopeful smile. Curious and a little eager.

Melvin, same day: no lying down at all. At his lowest he is still sitting,
slumped and defeated, head drooping.
