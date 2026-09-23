# Otto's seven states: the art brief

> **Delivered 2026-09-22** (CLAUDE.md "OTTO HAS SEVEN STATES"). Two things
> below changed on delivery: the light is baked into the art and the app's
> SwiftUI glow, orbits, sparks and ripples are deleted, so "What NOT to bake
> into the art" no longer applies; and the sheet is cut by
> `tools/otto_aura_cut.swift`, not `otto_split.py` after `otto_unmatte.py`.

Melvin, 2026-09-22. Replaces the three aura drawings (`OttoLow`,
`OttoFrustrated`, `OttoCurious`) and the rig's part in the top stages.

## The one rule this brief exists to enforce

**His state is PHYSICAL, never emotional.** The rejected drawing was a
grouchy sloth glaring off to one side, and a mascot who looks annoyed with
you is a reason to close the app: "seeing him all mad lowkey made me not
care about meditating."

So at the bottom he is not sad about you, he is *worn out and beyond caring*:
head hanging, eyes down, gray, thin, moth-eaten, insects treating him as
furniture, and no opinion about any of it. At the top he is not delighted
with you, he is *lit up*: levitating, aura, chakras, light coming through the
fur. **Never a frown, never a glare, never eyes cut to the side.** Every
state is the same calm animal in a different physical condition.

Read the seven as one shot in time-lapse: decay, baseline, ascension.

## The character, unchanged in all seven

Take the base prompt from `otto-redesign.md` verbatim (the wise old
three-toed sloth, bold rounded shapes, clean silhouette, soft volumetric
shading, matte, no outlines, compact chunky proportions, warm caramel fur,
cream chest and muzzle, dark brown facial mask, level brow, small closed
mouth). Same character, same camera, same scale in frame, seven conditions.
**Except the base prompt's "heavy half-lowered lids"**: they made him look
stoned. Eyes are properly open or properly closed, never between; the
per-state rule is in `otto-v4/PROMPTS.md`.

**Every one:** seated cross-legged, facing the viewer, centred, transparent
background, no ground, no shadow, no text. His feet (or the bottom of his
hover) sit on the frame's bottom edge in 1 to 5, and the whole figure stays
inside the frame in 6 and 7, where the ground he has left has to be visible
as empty space beneath him.

## The seven

| # | name | level | what changed physically |
|---|------|-------|--------------------------|
| 1 | Withered | 0 to 14 | near dead |
| 2 | Faded | 15 to 29 | gray, still hanging on |
| 3 | Stirring | 30 to 44 | colour coming back |
| 4 | Steady | 45 to 59 | the familiar Otto |
| 5 | Bright | 60 to 74 | clean, warm, lit from the edges |
| 6 | Radiant | 75 to 89 | glowing, hovering, chakras lit |
| 7 | Nirvana | 90 to 100 | levitating, full aura |

Paste the base prompt, then ONE of these as the state paragraph.

**1. Withered.** His body is failing and he has stopped minding. Fur gone
ash-gray and dull, matted and moth-eaten with bald patches showing thin skin,
his frame gaunt under it. Shoulders collapsed forward, spine curved, head
hanging so his face points at the ground, eyes closed or nearly, heavy lids,
mouth closed and slack. A few small insects treat him as scenery: a moth on
his shoulder, a beetle on his knee, one fly circling. Cobweb strands between
an ear and a shoulder, a little dust, pale lichen creeping on one arm. One
paw has slipped off his knee and hangs. **Not crying, not frowning, not
looking at anything.** He is a tired old animal who has run out, and he is at
peace with it, which is what makes it land.

**2. Faded.** The same gray, less advanced. Fur ash and patchy but whole, dry
and dusty rather than moth-eaten, some bald at the elbows. Still hunched, head
low, eyes open and round, aimed at the floor in front of him. One moth on his
shoulder and nothing else living on him. A hint of the old caramel shows deep
in the fur at his chest, like colour waiting.

**3. Stirring.** Caramel returning in patches through the gray, unevenly, as
if warmth is spreading from his chest outward. Fur still rough but clean, the
dust coming off him in a few motes. Back straightening, head lifting to
level, eyes open, calm, looking straight ahead at the viewer for the first
time. No insects, no cobwebs.

**4. Steady.** The character exactly as `otto-redesign.md` describes him.
Full warm caramel, cream chest, groomed, seated upright and square,
cross-legged, paws resting on his knees, eyes open, round and clear. No
glow, no effects. This is the neutral reference the other six are measured
against, so draw it first and keep it beside you for the rest.

**5. Bright.** The same healthy animal, better. Fur clean and shining with a
soft warm rim light along his head and shoulders as if a light sits just
behind him, colours a shade richer, posture taller, chest open. A handful of
tiny warm motes of light drift near him. Still sitting on the ground, eyes
open, round and bright.

**6. Radiant.** He has left the ground: hovering a few inches, cross-legged,
with clear empty space under him. Light is coming through him rather than
falling on him, brightest at the chest. Seven small chakra points glow faintly
along his centre line from the base to the crown, in their traditional colours,
soft and small, not a diagram. His fur lifts slightly as if in a rising
current. Motes of warm light orbit him. Eyes gently closed, face serene.

**7. Nirvana.** Full ascension, and this one may be as loud as it wants.
Levitating high inside the frame, cross-legged, a wide empty space beneath
him. His whole body is luminous, backlit, the fur edges dissolving into
light. The seven chakra points burn bright along his centre. A halo or thin
mandala ring behind his head, concentric rings of energy around him, ribbons
and sparks of light swirling upward, a few small lotus petals or leaves caught
in the current. Eyes closed, face utterly serene, a faint smile at most.
Radiating pure light in every direction. **Still unmistakably the same sloth:
if the silhouette stops reading as Otto, pull the effects back.**

## What NOT to bake into the art

The app already draws moving light around him: a glow, one or two orbiting
rings, sparks, ground ripples and a slow rise (`OttoAuraFigure`). Art that
bakes a huge outer glow doubles it and turns to mud on the cream background.

So: **draw the body, the condition and the light ON him. Leave the big
surrounding glow to the app.** Near-body light, chakra points, rim light and
the hover are art. Wide halos of haze are not.

## Sizes and delivery

**One sheet, not seven runs** (2026-09-22): generating a state per chat
drifted, so all seven come from the single prompt in `otto-v4/PROMPTS.md`
and are cut apart here. Same scale in every figure so he does not change
size between states. Sitting height
should fill roughly the same share of the frame in 1 to 5; 6 and 7 sit higher
with room beneath.

    mockups/otto-v4/aura-1-withered.png
    mockups/otto-v4/aura-2-faded.png
    mockups/otto-v4/aura-3-stirring.png
    mockups/otto-v4/aura-4-steady.png
    mockups/otto-v4/aura-5-bright.png
    mockups/otto-v4/aura-6-radiant.png
    mockups/otto-v4/aura-7-nirvana.png

The sheet is cut into those seven by `tools/otto_split.py`, after
`tools/otto_unmatte.py` lifts the white background, then into
`Shared/Assets.xcassets` as `OttoAura1` through `OttoAura7`, and the stage
ladder in `OttoAura.Stage` moves from six bands to the seven above.

## What changes in the app when they land

- `OttoAura.Stage` gains a seventh case and the bands above. The tests that
  pin the promises (first session lifts him a stage, five days reach the top,
  a week away drops him to the bottom) move with it.
- Home, the onboarding "see for yourself" screen and Profile all read the
  same ladder, so they cannot disagree.
- The Rive rig keeps the session screens (Ready, the sit), where he is always
  the same meditating Otto. Home's figure becomes one of these seven, with
  the app's own breathing pulse on it.
- Otto's spoken lines stop referring to moods. His words are about the
  practice; his state is the picture.
