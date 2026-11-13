# The evolution line: five creatures, Chinese folklore

Aziz and Melvin, 2026-10-26. Otto reincarnates up a chain and each form is
grander than the last:

**sloth → red panda → tiger → fenghuang → dragon**

This folder holds the prompt for their NORMAL states only. Once those five
are approved they become the references for every other state, the way
`reference-otto-sitting.png` did for Otto's seven.

**Each creature wears its own natural colours** (Aziz, 2026-10-26). A first
draft put all five in Otto's caramel and cream to tie the line together and
he cut it: they are five different animals and should look it. The only
thing carried across is the dark mask around the eyes, which most of them
have naturally anyway.

## Why one sheet and not five chats

Same lesson as `mockups/otto-v4/PROMPTS.md`: generating one creature per
chat drifts. Stage 3 came back with dust nobody else had and patchier fur
than stage 2, and the progression stopped being linear. **All five come out
of one generation.**

## Steps

This is written as a FOLLOW-UP in the chat that already drew Otto, so it
needs no attachments. Starting fresh instead means attaching
`mockups/otto-v4/reference-otto-sitting.png`, `reference-otto-face.png` and
`sheet.png` first, and naming them in the opening line.

## The prompt

```text
Make ONE landscape image: a character sheet of five creatures that form a single evolution line, the sloth you have been drawing and the four forms he grows into.

Same art style and same camera as the sloth: straight on, facing the viewer, seated in a meditative posture, soft volumetric shading, matte, no outlines.

LAYOUT. Plain solid white background. Top row: creatures 1, 2, 3. Bottom row: creatures 4, 5. Every creature drawn at the same height on the page. Plenty of white space between figures so nothing touches. A small gray number under each figure, 1 to 5. No other text, no ground, no shadows, no props, no scenery.

ALL FIVE ARE IN EVERYDAY HEALTH, AND THIS IS THE WHOLE POINT. This is their ordinary resting state: groomed, upright, calm, seated facing the viewer, eyes open, round and clear, looking straight out, a small closed smile. NO glow, no aura, no halo, no sparkles, no motes, no floating, no fire, no light effects of any kind on any of the five. Every one of them is sitting on the ground.

EACH CREATURE IN ITS OWN NATURAL COLOURS. They are five different animals and they should look it. The only thing carried across all five is a dark mask around the eyes, like the sloth's.

THE RULE THAT MATTERS MOST: each creature is more impressive than the one before it, by about the same step, in size and in bearing. Figure 1 is the smallest and gentlest, figure 5 is the grandest. It should read as one creature's five lives, not five unrelated animals. All five are Chinese folklore creatures, warm and friendly, never fierce or threatening: even the tiger and the dragon are calm and kind.

1. Sloth. Otto exactly as you have been drawing him, sitting cross-legged with his paws resting on his knees, eyes open and round, small closed smile. The smallest and softest of the five.

2. Red panda. Rich rust-red fur with a cream face and chest, a thick ringed tail in rust and cream curled around in front of him, round ears, dark mask around the eyes. Sitting cross-legged, paws resting on his knees. More alert and a little more upright than the sloth.

3. Tiger. A big, calm, friendly tiger in deep orange with black stripes, a white chest and muzzle, dark markings around the eyes. Broad shoulders and heavy paws, sitting cross-legged with its front paws resting on its knees, back straight, completely at ease. Clearly powerful and clearly gentle at the same time. Twice the presence of figure 2.

4. Fenghuang, the Chinese phoenix. A bird in crimson, gold and deep orange plumage with touches of green and blue in the tail feathers, dark markings around the eyes. It sits upright in the same meditative posture with its wings folded forward so the wing-tips rest where the paws would be. A crest of soft feathers on its head and long flowing tail feathers fanned out behind it. Not glowing and never on fire. Graceful and serene, grander than the tiger.

5. Chinese dragon, the long. A serpentine eastern dragon, NOT a western winged lizard: a long body with no wings, deer-like antlers, long whiskers either side of its muzzle, a soft flowing mane. Jade-green scales with a pale gold belly and a darker mask around its eyes. Its body is coiled beneath it into a seated shape so it holds the same meditative posture as the other four, with its front claws resting where the paws would be. The largest and most magnificent of the five, and still unmistakably kind. No clouds, no fire, no pearl, no smoke.

EYES, the thing that keeps going wrong: every eye is properly open, round and clear with the whites showing, looking straight at the viewer. Never half-closed. A lid at half-mast looks sleepy or stoned and none of these five may look that way.

Keep the background pure white and completely empty. Nothing in the air around any figure.
```

## If one comes back wrong

Ask in the SAME chat so the other four stay put:

- "Keep everything else exactly the same. Only change figure 4: ..."
- Western dragon: "Figure 5 has wings and a lizard head. Make it an eastern
  Chinese dragon: long serpentine body, no wings, antlers, whiskers, mane."
- Fierce: "Figure N looks threatening. Soften the face until it reads kind."
- Not escalating: "Figure N is less impressive than figure N-1. Make it one
  step grander."

## After the five are approved

Each creature then needs its own states, on Otto's pattern. Generate one
sheet PER CREATURE, attaching that creature's approved normal state plus
Otto's `sheet.png` so the seven steps match his. The cutter is
`tools/otto_aura_cut.swift`; the canvas numbers are in
`mockups/otto-v4/canvas.json`.

**Five creatures at thirteen states each is 65 drawings.** Seven states each
and no in-betweens is 35. Decide before generating: the count has to be the
same for all five.

---

# The seven states, one creature at a time (2026-10-26)

**Verified against the rig's own bodies, not against the lit stills.** Run
`python3 tools/riv_dump.py Coherence/Otto/OttoAura.riv --bodies DIR` and look
at `otto-clean2-body-1.png` and `-7.png`: those are what the art has to be.
The `OttoAura1...7` image sets are the LIT fallback stills and are a
misleading reference, because they have the rig's work baked into them.

Run this four times: red panda, tiger, fenghuang, dragon. Otto's seven
already exist. One creature per sheet.

## What the art carries, and what the rig adds

Read off the real clean bodies:

**In the art:** the coat's colour and condition (dull, matted, bald patches,
scabs), **cobwebs**, **lichen and moss**, the posture, the eyes, the
expression.

**In the rig, already built and creature-agnostic:** the bugs (moth, beetle,
fly), all the glow and backlight, the mandala halo, the rings and comets, the
motes, the leaves, the ground shadow, **and the hovering**. The rig lifts
S5 by 16, S6 by 30 and S7 by 48 and scales each state itself.

So three things the first draft of this prompt got wrong:

1. **Nothing hovers.** All seven sit on the ground in the same posture at the
   same scale. Drawing figures 6 and 7 floating would double up with the
   rig's lift and break the cutter's baseline.
2. **Nothing glows, not even figure 7.** The clean Nirvana body is just Otto
   with his eyes closed and a serene smile. Every bit of light is the rig.
3. **Cobwebs and lichen stay in the art.** Only the bugs are layers.

And the withered state is **not ash-gray**. It is a desaturated grey-brown
that keeps the cream face and the dark eye mask. A flat gray loses the
character.

## The prompt

Replace `CREATURE` with the animal and `ITS COLOURS` with its own palette.

```text
Make ONE landscape image: a character sheet of this CREATURE in seven physical states, like a time-lapse of its health from worst (1) to best (7).

Figure 4 is the CREATURE exactly as already drawn, in its ordinary health. Every other figure is that same creature, same art style, same camera, one step worse or one step better.

LAYOUT. Plain solid white background. Top row: figures 1, 2, 3, 4. Bottom row: figures 5, 6, 7. Every figure the same size and the same crop, as if the same creature were photographed seven times from the same spot without moving the camera: same art style (bold rounded shapes, clean silhouette, soft volumetric shading, matte, no outlines), straight on, facing the viewer, seated in the same meditative posture, its base resting on the same line. Plenty of white space between figures so nothing touches. A small gray number under each figure, 1 to 7. No other text, no ground, no shadow, no props, no scenery.

EVERY FIGURE SITS ON THE GROUND. None of them hovers, floats or levitates, not even figure 7.

NO LIGHT EFFECTS ON ANY FIGURE, not even figure 7. No glow, no aura, no halo, no backlight, no rim light, no sparkles, no motes, no rings, no ribbons, no leaves, no petals, no dissolving edges. Also no insects of any kind. All of that is added separately afterwards. What you are drawing is the creature's body and nothing else.

ONLY FOUR THINGS CHANGE ACROSS THE SEVEN: the colour of its coat, the condition of its coat, its posture, and its eyes. Nothing else.

THE RULE THAT MATTERS MOST: the change is strictly linear. Each figure is healthier than the one before it in every respect, by about the same step. Nothing ever gets worse from one figure to the next. Its state shows in its BODY, never in its mood: no frowning, glaring, pouting or looking to the side in any figure.

1. Withered. Its colours drained to a dusty, desaturated grey-brown, but it keeps its pale face and its dark eye markings. Coat matted and moth-eaten with bare patches and pale scabs on its head and shoulders, gaunt and thin. A fine cobweb from one ear down to the shoulder, and patches of pale green lichen and moss on its arms. Slumped forward, head hanging, face toward the floor, eyes closed. At peace with it, not upset or in pain.
2. Faded. The same grey-brown but whole: dry and dusty, thin, no bare patches, no scabs, no cobweb, no lichen. Hunched, head low. Eyes open and round, looking down at the floor in front of it. The faintest trace of ITS COLOURS deep in the chest.
3. Stirring. Exactly halfway between 2 and 4. An even blend of grey and ITS COLOURS, strongest at the chest and greyer toward the edges, a smooth gradient with no blotches and no bare spots. Coat rough but clean. Back straightening, head coming up level. Eyes open, round and clear, looking at the viewer. Small closed smile.
4. Steady. The CREATURE exactly as already drawn, in full everyday health: ITS COLOURS rich and true, groomed, upright, small closed smile, eyes open and round, looking at the viewer.
5. Bright. Figure 4, one step better: ITS COLOURS deeper and glossier, the coat fuller and better kept, sitting taller with its chest open. Eyes open, round and bright, looking at the viewer. Still no light of any kind.
6. Radiant. Figure 5, one step better again: the coat at its richest and healthiest, sitting tall and completely settled, shoulders relaxed. Eyes fully closed in two smooth curved lines, serene, a small smile.
7. Nirvana. Figure 6, one final step: perfectly groomed and perfectly still, the deepest and warmest its colours ever get. Eyes fully closed, utterly serene, a faint smile. Still unmistakably the same creature, sitting on the ground like all the others.

EYES, the thing that keeps going wrong: every eye is either properly open (round and clear, the whites showing) or properly closed (a smooth curved line). Never half-closed. A lid at half-mast looks sleepy or stoned, and none of these seven may look that way.

Keep the background pure white and completely empty.
```

## Per-creature notes for figures 1 and 2

The decay language has to suit the animal. Add one line:

- **Red panda:** "matted and moth-eaten" works as written.
- **Tiger:** its stripes fade with the rest of the coat, never stay black on
  a grey body.
- **Fenghuang:** "bedraggled, feathers broken and missing, the long tail
  feathers ragged and drooping" instead of matted fur.
- **Dragon:** "scales dull, cracked and shedding, mane and whiskers thin and
  limp, antlers chipped" instead of matted fur.

## If one figure comes back wrong

Ask in the SAME chat so the other six stay put:

- "Keep everything else exactly the same. Only change figure 3: ..."
- Stoned eyes: "Figure N's eyes are half closed. Open them fully, round and
  clear, looking at the viewer."
- Glowing: "Figure N has light around it. Remove every trace of glow, aura
  and backlight. Just the creature on white."
- Floating: "Figure N is hovering. Put it back on the ground, same posture
  and same size as the others."
- Not linear: "Figure N looks worse than figure N-1. Make it one step
  healthier than N-1 and one step less healthy than N+1."

## No chakra points. Otto has none (Aziz, 2026-10-26)

`mockups/otto-v4/PROMPTS.md` asks for "seven small chakra points" in states
6 and 7. The generator ignored it and no shipping Otto has ever had them.
Do not put them in any creature's sheet, and strike the line from Otto's own
prompt before anyone regenerates his seven.

## Afterwards

The lit stills (`OttoAura1...7`, the widget and shield fallbacks) are a
SECOND set, and Otto's were generated rather than captured. For a new
creature the cheaper route is to render them out of the rig once its clean
bodies are in. Decide that when the clean sets exist; it is not a reason to
generate anything twice now.
