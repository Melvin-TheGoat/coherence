# Otto redesign brief: slightly more real, furry (Melvin, 2026-09-20)

Melvin: "he looks a little too childish, make him slightly more realistic
and furry maybe." This is the brief for the next set of poses. It is written
so the new art drops straight into the existing rig and the existing image
sets with no code change.

## What stays the same (the rig depends on it)

- The SAME poses, one PNG each, same names: `otto-talk`, `otto-wave`,
  `otto-sit` (meditating, eyes closed), `otto-awake`, `otto-look`,
  `otto-heart`, `otto-sleep`, `otto-head`. The Rive file swaps the image
  asset by name; the app's `OttoPose.asset` maps to the same image sets.
- Same framing per pose: character fills the canvas, feet at the bottom
  edge, transparent background, no ground shadow, no props. Portrait
  canvases near 400 by 460 px for the body poses (the rig places them by
  their bottom edge, so a taller or wider file is fine; a cropped one is not).
- Same silhouette and the same arm positions per pose. `otto-wave` is the
  right arm raised, `otto-talk` is the same body with the mouth open, so the
  wave animation can cut between them without a jump.
- Same palette: fur in the app's Fur `#C99B72` family with a darker eye mask,
  cream muzzle and belly, cheeks in Blush `#F2AF91`. The palette is sampled
  into the app's colours, so a colder or greyer sloth breaks every screen.
- The face must still read at 24 pt (the chat row and the mark). Eyes and
  the mask carry it; fur detail can vanish at that size and the face still
  works.

## What changes

- Fur: visible soft fur texture on the body, longer at the crown and cheeks,
  short on the face. Rendered, not outlined: think a felted or brushed
  surface with soft edge fuzz, not individual drawn hairs.
- Proportions one step toward a real sloth: the head a little smaller
  against the body (about 40 percent of height, from 50), the muzzle a
  little longer, arms longer with three visible claws, the eyes smaller and
  set in the dark mask rather than huge and glossy. Keep the smile; lose the
  stickers (no round cheek dots as flat circles; a soft warm blush instead).
- Light: one soft top light, gentle shading under the chin and belly, no
  hard outlines. Stroke-outlined "sticker" edges are what read as childish.
- Keep him kind. Realistic is a direction, not a destination: a real sloth
  photo is the wrong end of the line. Aim for a picture-book animal a
  grown-up would have on a mug, not a toy.

## Generation prompt (any image model; run once per pose)

    A gentle three-toed sloth character, soft short fur with visible fuzzy
    texture, warm caramel and cream colouring, dark brown eye mask, small
    kind eyes, long slim arms with three claws, [POSE], full body, facing the
    viewer, centred, feet at the bottom edge, plain transparent background,
    no ground, no shadow, no props, soft top lighting, subtle shading, no
    outlines, picture-book illustration, adult audience, calm, warm.

    [POSE] per file:
    otto-sit    sitting cross-legged, hands resting on knees, eyes closed, serene
    otto-talk   sitting, right hand raised beside the head palm out, mouth open mid sentence, friendly
    otto-wave   sitting, right arm raised in a wave, mouth closed, small smile
    otto-awake  sitting, hands on knees, eyes open, looking at the viewer
    otto-look   sitting, head tilted, eyes open, curious
    otto-heart  sitting, both arms hugging a small heart to the chest, eyes closed, content
    otto-sleep  lying on its side asleep, one arm under the head
    otto-head   head and shoulders only, eyes open, gentle smile

Negative prompt, if the model takes one: cartoon sticker, thick outlines,
huge glossy eyes, toy, plastic, photo, realistic photograph, background,
text, watermark, extra limbs, two characters.

## After generation

1. Check each file against the "stays the same" list, especially the arm
   positions on `otto-talk` versus `otto-wave`.
2. Remove any background, export PNG with alpha at the original sizes.
3. Drop the files over `mockups/otto/` (same names) and over the image sets
   in `Shared/Assets.xcassets/Otto*.imageset`.
4. In Rive, replace the two image assets (Assets panel, right click, Replace)
   with the new `otto-talk` and `otto-wave`; export For Runtime over
   `Coherence/Otto/Otto.riv`. No rig change.
