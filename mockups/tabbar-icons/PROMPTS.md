# Tab bar icons: ChatGPT prompts (2026-09-25, Melvin)

Ten directions for the bottom bar (Home, Block, the gold plus, Friends,
Profile). Paste the base prompt once in a new ChatGPT chat, then send one
concept per message, so every sheet comes out in the same format and can be
compared side by side.

## Base prompt (paste first)

> I'm designing the bottom tab bar for 808, an iPhone meditation app. Its
> world is a calm cartoon valley: soft blue sky, layered blue-green hills, a
> sage-green meadow (#99BB82) with small flowers, and a warm sun. The mascot
> is Otto, a friendly brown sloth drawn in a soft, slightly furry,
> picture-book style. Palette: cream #FEF9F2, warm gold #F0C47B (only ever
> the main action), sky blue #3F80AD, deep teal #3E8175, brown ink #413024.
> Type is rounded, like SF Pro Rounded.
>
> The bar has five tabs, left to right: Home; Block (Otto holds your
> distracting apps until you meditate); a larger centre button that starts a
> meditation, which is the only gold element; Friends; Profile. Each side tab
> has an icon and a label: Home, Block, Friends, Profile. The centre button
> has no label.
>
> For each concept I send, make ONE design sheet, flat on a plain cream
> background, no phone frame:
> 1. top: the full-width tab bar (iPhone width) with Home selected;
> 2. below it: the same bar with Friends selected;
> 3. bottom row: the five icons large, each shown unselected and selected.
>
> Every icon must still read at 28 points. Use only the four labels, no
> other words. Reply with just the image.

## The ten concepts (one per message)

1. **The bar is the meadow.** The bar itself is a strip of grass and
   flowers, like a little hill. Each tab is a small object standing in the
   grass: a cottage (Home), a wooden gate (Block), a rising sun half behind
   the hill as the centre button, two tree stumps side by side (Friends), a
   signpost with a name board (Profile). The selected object stands in a
   soft beam of sunlight.
2. **Otto is every icon.** Tiny Otto figures in simple poses: Otto sitting
   in his house (Home), Otto holding up one paw like "wait" (Block), Otto's
   meditating silhouette inside the gold centre circle, two Ottos shoulder to
   shoulder (Friends), Otto wearing a name badge (Profile). Selected is full
   colour; unselected is a soft single-colour silhouette. Think Finch, whose
   world is its pet.
3. **Chunky and lifted, Duolingo style.** Bold, rounded, filled icons with a
   thick darker "lip" underneath so they look pressable, like the app's gold
   buttons. The selected tab sits in a rounded square with a 2pt outline in
   its own colour. Playful, confident, very readable.
4. **Liquid Glass.** iOS 26 style: the bar is a floating translucent glass
   capsule over the valley scene, with thin, crisp monoline icons. The
   selected tab is a brighter glass bubble inside the capsule. The centre
   button is its own separate glowing gold glass orb, floating just right of
   the capsule like a sun.
5. **Ensō brush.** Japanese sumi-e ink brush marks on cream, each icon one or
   two strokes: an ensō circle with a roof line (Home), a smooth river stone
   (Block), a brushed sun ensō in gold (centre), two stacked stones in a
   cairn (Friends), a single leaf (Profile). The selected icon fills with a
   soft watercolour wash.
6. **Sky phases.** The icons are the sky at different times: sun over two
   hills (Home), a crescent moon, rest and holding (Block), a rising sun as
   the gold centre button, two stars joined by a faint line like a tiny
   constellation (Friends), one bright star (Profile). Unselected are pale
   outlines; the selected one glows softly.
7. **Garden that grows.** A plant at different stages: a sprout in a small
   clay pot (Home), a little fence around a flower (Block), a seed or a water
   drop in the gold centre, two flowers leaning together (Friends), a young
   tree (Profile). Unselected icons are closed buds or greyed; the selected
   one blooms into full colour. Think Forest, where focus grows a tree.
8. **Game tiles that lift.** Like Clash Royale's bottom bar: each tab is a
   square tile, and the selected tile grows taller, rises above the bar, and
   shows a bigger, richly illustrated icon with its label, while the others
   stay small and flat. Rich, slightly 3D icons: a cottage (Home), a shield
   with an open paw (Block), a glowing gold gem-sun (centre), two banners
   (Friends), a round crest with a leaf (Profile).
9. **Sticker book.** Every icon is a die-cut sticker with a thick white
   border and a small drop shadow, each tilted a few degrees: a cottage, a
   raised paw, a sun, two smiling faces, Otto's head. The selected sticker
   straightens, grows slightly and gains a colour background; the others
   stay tilted and slightly faded.
10. **Soft clay 3D.** Chunky, rounded, matte clay-like 3D objects with soft
    lighting, like hand-made toys: a little house, a hand held up, a gold
    sun, two pebbles with faces, a small sloth head. Selected objects are
    full colour; unselected are pale, same-colour clay.

## When one lands

Ask ChatGPT: "Make concept N as ten separate icons, 1024 by 1024 each,
transparent background: the five icons, each unselected and selected, no
labels." Send the pick to Claude. The standing rule applies: an HTML mockup
of the bar in the app goes first, then Swift. Flat or line concepts (3, 4,
5, 6) redraw well as vector; illustrated ones (1, 2, 8, 9, 10) ship as image
assets at 1x, 2x and 3x.

## What the research found

- **Duolingo**: a filled icon per tab; the selected one sits in a rounded
  square with a coloured outline. It has taken criticism for icons nobody
  can decode, so every concept above keeps its labels.
  ([Duolingo blog](https://blog.duolingo.com/core-tabs-redesign),
  [case study](https://medium.com/@nehita.ilogienboh/redesigning-the-duolingo-app-case-study-c22718b54a1a))
- **Finch**: skeuomorphic icons from the pet's own world, and a centre plus
  that opens the practice features, the same shape as 808's bar.
  ([Pratt design critique](https://ixd.prattsi.org/2024/09/design-critique-finch-ios-app/),
  [Finch wiki](https://finch.fandom.com/wiki/Finch_App))
- **iOS 26 Liquid Glass**: the system tab bar floats over the content, is
  translucent, and can shrink to the active tab while scrolling.
  ([WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/),
  [Donny Wals](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/))
- **Pattern libraries** for more: [Mobbin tab bars](https://mobbin.com/explore/mobile/ui-elements/tab-bar).
