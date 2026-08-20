# 808 website design system

Rebuilt 2026-08-20 around the app's own tokens, replacing the Lovable-derived
Bricolage/Plex system. The premise of this version: **the site and the app are
one product**, so the site inherits the app's palette and colour grammar
rather than keeping its own.

## Type

Self-hosted in `fonts/`, no third-party requests. All open-licensed.

| Role | Face | File | Notes |
|---|---|---|---|
| Display | Manrope (variable 200-800) | `manrope-var.woff2` | 800 for headlines, -0.02em to -0.025em |
| Body | Hanken Grotesk (variable 100-900) | `hanken-var.woff2` | 17px/1.6 base |
| Label | DM Mono 400/500 | `dmmono-400/500.woff2` | uppercase, 0.1em tracking |

Both variable fonts are preloaded from `index.html`.

## Colour

Straight from `Shared/Assets.xcassets`, dark set. The site is dark-only, a
deliberate commitment: the app defaults dark, the video end cards are dark,
and one warm accent on a near-black ground is the identity.

| Token | Value | Means |
|---|---|---|
| `--bg` | `#13100D` | ground |
| `--card` | `#221E19` | cards |
| `--fg` | `#F5F3EC` | text |
| `--muted` | `#9A9A93` | secondary text |
| `--dim` | `#55534E` | unlit mission words, faint rules |
| `--gold` | `#D4AF37` | **what you achieved**: scores, streaks, awards, CTAs |
| `--teal` | `#73A8A1` | **what your body did**: pain-point labels, signal curves |
| `--ember` | `oklch(62% .10 32)` | cost and loss only, never alarm |

**The grammar is the rule that matters**: gold = achieved, teal = the body's
signals, never both loud in one element, one gold thing per section. If the
site ever gains a light theme, gold splits into fill `#DCB63F` and text
`#8A6D14`; they are not interchangeable (the fill reads 1.78:1 as text).

## Page structure (index.html)

Hero → mission scroll-highlight → reasonable company (WallScreen port, its
two-tier quote rule intact) → testimonials (six real, verbatim, typos theirs)
→ the cost → meditation works → the catch → features as the four pain points
→ who built it + sources → closer → footer.

## Load-bearing implementation notes

- **The mission section ships lit.** JS adds `.dimmable` then lights words
  from scroll position via rAF. With JS off the paragraph simply reads. Same
  principle as the 365-cell grid, which is static HTML painted 114-lost by
  default; the slider only repaints it.
- `prefers-reduced-motion`: no pin, no dimming.
- The pin uses `100svh`, not `100vh`, or iOS Safari's collapsing address bar
  makes it jump.
- `img { height:auto }` is load-bearing: the width/height attributes otherwise
  win over `max-width` and a phone screenshot renders 2622px tall.
- Every form races an **8-second rejecting timer**. AbortController alone was
  tested against a stalled fetch and still hung 18 seconds.
- The footer keeps `id="support"`: the App Store support URL points at it.
- Screenshots in `img/` are real simulator captures (iPhone 17 Pro, dark,
  seeded demo data, status bar overridden to 9:41). Regenerate via the DEBUG
  env hooks; the low-score session is seeded by `DemoData.seedHistory`.

## Copy rules carried over

No em dashes. No invented numbers, testimonials or press. No brain-state
claims. No 23-minute refocus statistic. The positioning claim is the narrow
one: *scores your meditation from your own body*, never "tracks biofeedback"
(Apple's Mindfulness app already logs in-session heart rate). Sources carry
their own disclosures, including the Schneider trial's.

## Deploying

Cloudflare Pages is a **direct-upload** project, not git-connected. Deploy =
drag the `website` folder into Workers & Pages → meditate808 → Create
deployment. Pushing to GitHub changes nothing live.
