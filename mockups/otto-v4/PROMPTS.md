# Seven Ottos in one image

Rewritten 2026-09-22. One state per chat drifted: stage 3 came back with
dust floating around him that no other stage had, and patchier fur than
stage 2, so the progression stopped being linear. **All seven now come from
one image**, like the `sloth_progression.png` sheet that worked the first
time. The earlier per-state prompts are in git history.

## Steps

1. Download your approved **Withered** and **Faded** images from ChatGPT.
2. Start a **new chat** and attach four images:
   - `reference-otto-sitting.png` (this folder)
   - `reference-otto-face.png` (this folder)
   - your Withered
   - your Faded
3. Paste the prompt below.
4. Download the result. Claude takes the newest ChatGPT image from
   Downloads, cuts it into seven and puts them in the app.

Two rows, not one: seven in a single row leaves each Otto about half as
sharp as today's Home art. Four plus three keeps him close to it.

## The prompt

```text
Make ONE landscape image: a character sheet of this sloth in seven physical states, like a time-lapse of his health from worst (1) to best (7).

The attachments: the calm sitting sloth with closed eyes is the character. The close-up of his face shows his open eyes. The gray slumped sloth is figure 1 and the gray sloth looking down is figure 2; match those two closely.

LAYOUT. Plain solid white background. Top row: figures 1, 2, 3, 4. Bottom row: figures 5, 6, 7. Every figure the same size, as if the same sloth were photographed seven times from the same spot: same art style (bold rounded shapes, clean silhouette, soft volumetric shading, matte, no outlines), same camera, straight on, seated cross-legged and facing the viewer. Plenty of white space between figures so nothing touches. A small gray number under each figure, 1 to 7. No other text, no ground, no shadows, no props, no scenery.

THE RULE THAT MATTERS MOST: the change is strictly linear. Each figure is healthier than the one before it in every respect, by about the same step. Nothing ever gets worse from one figure to the next: not the colour, not the fur, not the posture, not what is around him. His state shows in his body, never in his mood: no frowning, glaring, pouting or looking to the side in any figure.

1. Withered. Ash-gray, dull, matted and moth-eaten with bald patches, gaunt. Slumped forward, head hanging, face to the floor, eyes closed. A moth on his shoulder, a beetle on his knee, one fly, a cobweb from ear to shoulder, pale lichen on one arm. At peace with it, not upset.
2. Faded. Ash-gray but whole: dry, dusty, thin at the elbows, no bald patches. Hunched, head low. Eyes open and round, looking down at the floor in front of him. One moth on his shoulder and nothing else. A faint caramel warmth deep in his chest fur.
3. Stirring. Exactly halfway between 2 and 4. His fur is an even blend of gray and caramel, warmest at the chest and grayer toward the edges, a smooth gradient with no blotches and no bare spots. Fur rough but clean. No bugs, no dust, nothing around him. Back straightening, head up level. Eyes open, round and clear, looking at the viewer. Small closed smile.
4. Steady. The attached sitting sloth in full everyday health: rich warm caramel-brown fur, cream chest and muzzle, dark brown eye mask, groomed, upright, paws on his knees, small closed smile. Unlike the attachment, his eyes are open, round and clear, looking at the viewer. No light effects, nothing around him.
5. Bright. Figure 4, one step better: fur deeper and glossier, a soft warm rim light along his head and shoulders, sitting taller with his chest open. Eyes open, round and bright, looking at the viewer. A few tiny warm motes of light near him, the first light in the sheet. Still sitting on the ground.
6. Radiant. Hovering a little off the ground, clear empty space beneath him. Light glows through his fur, brightest at his chest. Seven small chakra points glow softly along his centre line, base of the spine to the crown, in their traditional colours. Fur lifting slightly as if in a rising current. More motes of light around him than figure 5. Eyes fully closed in two smooth curved lines, serene.
7. Nirvana. Levitating higher than figure 6, a wide empty space beneath him, the same size as every other figure. Luminous and backlit, the edges of his fur dissolving into light. The seven chakra points bright. A thin mandala halo behind his head, rings of light around him, sparks and ribbons of light swirling upward, a few lotus petals caught in the current. Eyes fully closed, utterly serene, a faint smile. Still clearly the same sloth.

EYES, the thing that keeps going wrong: every eye is either properly open (round and clear, the whites showing) or properly closed (a smooth curved line). Never half-closed. A lid at half-mast looks sleepy or stoned, and none of these seven may look that way.

Keep all light close to his body. No haze filling the white space, and no sparkles, dust or particles anywhere on figures 1 to 4.
```

## If one figure comes back wrong

Ask in the same chat, so the other six stay put:

- "Keep everything else exactly the same. Only change figure 3: ..."
- Stoned eyes: "Figure N's eyes are half closed. Open them fully, round and
  clear, looking at the viewer."
- Not linear: "Figure N looks worse than figure N-1. Make it one step
  healthier than N-1 and one step less healthy than N+1."
- Washed out: "Make the caramel on figures 4 to 7 deeper and richer."

# Thirteen states: the six in-betweens (2026-09-23)

Melvin: "Can we actually have 13 different Otto state screens, i want it to
be super granular, so like between 6 and 7 you should be able to see the
wheel super faintly, he should have like 1 or 2 leaves, and like 6 comets.
And then between 1 and 2 he should have like one of those scabs on his head,
one extra bug etc."

The seven approved states stay exactly as they are. Only six new BODIES are
needed, one halfway between each pair, drawn CLEAN (no bugs, no light): in the
rig the bugs, motes, comets, rings, leaves and the wheel are their own layers,
so each in-between gets its share of them in Rive, not in the art. One image
for all six, per the rule above; two rows of three keeps each sloth sharper
than the seven-up sheet did.

## Steps

1. Open the ChatGPT chat where you made the CLEAN seven (no bugs, no light).
   If it is gone, start a new one and attach both sheets: the lit seven
   (`sheet.png`) and the clean seven.
2. Paste the prompt below.
3. Download the result. Claude cuts it (`--grid 3,3`), cleans the edges
   (`tools/otto_defringe.swift`) and puts them in the rig between their
   neighbours.

## The prompt

```text
Make ONE landscape image of this same sloth: six NEW states that each sit exactly halfway between two of the seven you already drew. Same art style, same camera, straight on, seated cross-legged facing the viewer, every figure the same size as in the seven-state sheet. Plain solid white background. Two rows of three, plenty of white space so nothing touches. A small gray letter under each figure, A to F. No other text.

Draw them CLEAN, exactly like the clean sheet: no bugs, no motes, no sparkles, no rings, no halo, no wheel, no leaves, no ribbons of light, no shadow, no ground. Just the sloth.

A. Halfway between 1 and 2. Figure 2's ash-gray fur, whole and dusty, but with ONE small bald scab on top of his head like the patches on figure 1. Slumped a little more than figure 2, head low. Eyes open, round, looking down at the floor in front of him.
B. Halfway between 2 and 3. Still mostly gray, with the caramel warmth spreading further out from his chest than on figure 2. Back a little straighter than 2, head a little higher. Eyes open, round and clear, looking just below the viewer.
C. Halfway between 3 and 4. Mostly warm caramel, with only a trace of gray at the edges of his fur. Upright, head level. Eyes open, round and clear, looking at the viewer. Small closed smile.
D. Halfway between 4 and 5. Figure 4's rich caramel, a touch glossier, the faintest warm rim light along the top of his head. Sitting tall. Eyes open, round and clear, looking at the viewer. Small closed smile.
E. Halfway between 5 and 6. Glossier still, a warm rim light along his head and shoulders, a soft warm glow deep in his chest fur. Eyes fully closed in two smooth curved lines, serene, a small smile.
F. Halfway between 6 and 7. Figure 7's body and glowing fur, very slightly less luminous than 7. Eyes fully closed in two smooth curved lines, serene, a faint smile.

THE RULE THAT MATTERS MOST: each letter is healthier than the state before it and less healthy than the state after it, by the same small step, in every respect. His state shows in his body, never in his mood. Every eye is either properly open (round, the whites showing) or properly closed (a smooth curved line), never half-closed.
```

## What Rive adds to each in-between (no art needed)

- **1.5**: figure A's scab is in his body; the rig gives him the moth AND the
  fly (stage 2 has the moth alone, stage 1 all three).
- **5.5 to 6.5**: comets, rings, leaves and the wheel step up in between their
  neighbours: at 6.5 the wheel shows faintly, one or two leaves circle him and
  about six comets run the rings.
- The stills that stand in when the rig cannot load use the nearest of the
  seven lit stills.
