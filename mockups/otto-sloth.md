# Otto the sloth: how the concepts were built, and how to finish them

Companion to `mockups/otto-sloth.html` (Melvin, 2026-09-16: Otto gets a
sloth). These are concepts for the founders to react to, not final art.

## How the concepts were built

- Everything is hand-written inline SVG: paths, ellipses, one circle. No
  tool, no trace, no image. The four drawings live as symbols in a hidden
  `<defs>` block at the top of the page and every artboard is a `<use>`.
- The language is the 808 mark's (`Shared/Theme/LogoMark.swift`): a single
  stroke weight, round caps and joins, ellipses doing most of the work, no
  fills. The one exception is the sloth's eye mask, a 26 percent wash of the
  stroke colour, because outlining it doubles the lines around the eyes and
  turns to mud at 24 pt.
- The face is drawn once in a 64 unit head (`#face-64`): closed eyes, the
  three-toed mask tilted 20 degrees outward and down, a small flat nose, the
  wide low smile. The two figures carry the same face scaled into their own
  coordinates so the stroke stays one weight.
- Symbols set no stroke-width or colour of their own. The page sets both
  from outside (`stroke-width` on the `<svg>`, `color` via a class), which is
  how the same paths serve the 160 px board and the 24 px chat row.
- Stroke ratios: figures 1.5 percent of their artboard (3.6 on a 240 box),
  badge 5 percent of its diameter (3.2 on a 64 box). Board 4 puts the mark
  (0.026 of its size, per the Swift) and the sloth in one 3.6 stroke to show
  they match at the sizes they meet. The badge's heavier ratio is an optical
  size for 24 to 56 pt, where the mark's ratio would be a hairline.
- Verified in a browser at 160, 96, 56, 32 and 24 px, in gold, teal and
  white on the app's dark ground. No console errors, no em dashes.

## What a finishing illustrator needs

- The SVGs themselves: copy the four `<g id="...">` blocks out of the page.
  They are the brief, not a suggestion.
- Palette: ground `#13100D`, card `#1c1915`, teal `#5EB1A8` (the
  recommendation), gold `#D4AF37`, text `#F5F3EC`. Line art only, on dark.
- Stroke: one weight per drawing, round caps and joins, the ratios above.
  The badge must survive at 24 pt with nothing redrawn.
- What must not change: eyes closed, three claws, the mask as the only fill,
  no fur texture, no ears, no shine, no emoji, no photo.
- What may change: the crown of the large figures could take a few tufts;
  the base of the sitting pose could take a cleaner cross; the leaf on the
  branch is optional.
- Deliverables: SVG (the app draws it as a `Path` or an SF-style symbol) at
  the three uses, a 1024 px PNG of each for the store screenshot.

## Two options for the final

(a) In house: refine these SVGs in Figma or Illustrator. Import the page's
    symbols, tidy the curves, keep the constraints above. Half a day of a
    designer's time, zero brief writing, and the drawings already match the
    mark. Best if the founders like a direction here and want it shipped
    with Otto rather than after.

(b) Commission a line-art illustrator (Fiverr, as with the narration): send
    this page and this note as the brief, ask for the three drawings in the
    same language, one round of revisions. More character, a real hand, and
    a small fee. Best if the founders want Otto to be more than a glyph.
    Vet against the constraints, not against taste.
