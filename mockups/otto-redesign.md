# Otto: how to draw him again, and how to get the result into the app

Standing brief. Otto has been redrawn twice (the generated set, then the
furrier one on 2026-09-20) and Melvin still does not like how he looks, so
this is written for a loop that runs again rather than for one more round.

Two halves: the prompt, which is Melvin's side, and the import, which is one
command each.

## The import, so the generating side knows what to aim at

**Hand over one PNG per pose, transparent background, any resolution.**
Name them exactly:

    otto-wave.png    Home, and the pose the Rive rig animates
    otto-sit.png     session rows, the calendar, anywhere he is meditating
    otto-awake.png   avatars and rows, eyes open, looking at you
    otto-sleep.png   lying down, wider than it is tall
    otto-head.png    the mark: chat rows, anything under about 40pt
    otto-talk.png    optional; without it the waving art stands in

Drop them in `mockups/otto-v3/` (or v4, v5) and run:

    python3 tools/otto_import.py mockups/otto-v3

That writes every image set at the sizes the app already uses. **Every pose
is normalised to a longest edge of 200 points**, so they sit together as one
character instead of a character and some friends. Then, with the Rive
editor open on the Otto file:

    python3 tools/otto_swap.py mockups/otto-v3/otto-wave.png

which puts the new art inside the animated rig and writes
`Coherence/Otto/Otto.riv`. The rig itself never changes.

**Transparency is the one thing the repo cannot fix.** This Mac has no
ImageMagick and no PIL, so nothing here cuts a background out; the importer
refuses a file that arrives on white rather than shipping a white box. Ask
the image model for a transparent background. A flat single-colour
background can be stripped by hand if it comes to that, but it is a step
nobody should be doing twice a week.

**A sheet of four poses in one image is how the last round arrived**
(`mockups/otto-v2/sheet.png`, 1254 square, opaque). It then had to be cut
and alpha'd by hand before any of it was usable. One pose per image, with
transparency, skips all of that.

## What is wrong with the current one, and the levers

The 09-20 set is soft, caramel, fuzzy-edged, sitting cross-legged with a
wide open smile. It answered "furrier, more realistic, older" and still
reads childish. The things actually carrying that, in rough order of how
much each one costs:

1. **The face is a mascot's.** Big closed-arc smile, blush ovals on the
   cheeks, eyes drawn as large glossy dots. Real sloths have a small mouth
   line, a long snout with visible nostrils, and small eyes set deep in the
   dark mask.
2. **The head is too big for the body**, which is the single strongest
   childishness cue in any drawn character. A real three-toed sloth's head
   is about a third of its standing height, not a half.
3. **The edges are sticker edges.** An even silhouette with a uniform fuzzy
   rim reads as a die-cut. Fur that breaks the outline unevenly, longer at
   the crown and shoulders, reads as an animal.
4. **The shading is flat.** One soft top light with real form shadow under
   the chin, the belly and the arms is most of the difference between a
   sticker and an illustration.

**What must NOT change, because the app is built on it:** the caramel and
cream palette. Every colour on every screen was sampled out of Otto, so a
grey or green-brown sloth, however true to life, means repainting the whole
app. Keep him warm. Keep him kind: this is a meditation app and the point of
him is that he is calm, not that he is accurate.

## Prompt to paste, one run per pose

Swap the pose line each time and keep everything else identical, or the set
will not look like one character.

    A calm three-toed sloth, illustrated for an adult audience. Soft dense
    fur with uneven strands breaking the silhouette, longer at the crown and
    shoulders. Warm caramel and cream colouring, a dark brown facial mask
    with soft edges, small eyes set inside the mask, a long snout with small
    nostrils, a small closed mouth. Realistic sloth proportions: the head
    about a third of the body height, long slim arms, three visible claws.
    One soft light from above with gentle form shadow under the chin and
    belly. Painterly picture-book illustration, no outlines, no cel shading.
    POSE HERE. Full body, facing the viewer, centred, feet at the bottom
    edge of the frame. Transparent background, no ground, no shadow on the
    ground, no props, no text.

    Pose lines:
      wave    sitting upright, one arm raised in a small wave, calm and awake
      sit     sitting cross-legged, hands resting on the knees, eyes closed, serene
      awake   sitting, hands on the knees, eyes open, looking at the viewer
      sleep   lying on one side asleep, one arm tucked under the head
      head    head and shoulders only, eyes open, a faint smile
      talk    sitting, one hand raised beside the head, mouth slightly open, mid sentence

    Negative: cartoon sticker, thick outlines, big glossy eyes, blush
    cheeks, chibi, toy, plastic, 3D render, photograph, background, text,
    watermark, extra limbs.

**If it is still not right, change one thing at a time.** The four levers
above are separable, and a prompt that moves all of them at once produces a
different animal rather than a better one.
