# 808 website design system

Rebuilt 2026-08-20 to Melvin and Aziz's structure. The previous Lovable-derived
system (Bricolage Grotesque, IBM Plex, oklch greys) is fully retired.

## Type, self-hosted in `fonts/` (never hotlink)

| Role | Face | File |
|---|---|---|
| Display | Manrope, variable 200-800 | `manrope-var.woff2` |
| Body | Hanken Grotesk, variable 100-900 | `hanken-var.woff2` |
| Label | DM Mono 400/500, uppercase, 0.1em | `dmmono-400/500.woff2` |

## Colour: the app's tokens, one accent

`#13100D` ground · `#221E19` card · `#F5F3EC` text · `#9A9A93` muted ·
`#55534E` dim · **`#D4AF37` gold, the only accent.**

Teal and terracotta are gone. The app removed its two-colour signal grammar
(2026-08-20, Melvin and Aziz jointly) because a colour that needs explaining on
an evidence screen is a cost. The site follows the app, always.

## Page order (do not reshuffle without Melvin)

1. Hero: "Make meditation easy with 808" + waitlist form + real home screenshot
2. Mission, pinned scroll-highlight, words lighting in reading order
3. The four pain points, each with real simulator screenshots
4. Testimonials, six real beta reviews, verbatim including their typos
5. Famous practitioners (two-tier: quoted verbatim vs described, never mixed)
6. The research (sourced figures + citations with disclosures)
7. Closer + waitlist form
8. Footer (only links to things that exist; keep `id="support"`)

Plus the persistent bottom waitlist banner, appearing after the mission,
hidden while the closer's own form is on screen.

## Rules that carried over and still bind

- No em dashes in copy. No invented stats, testimonials, or press.
- Never claim 808 measures a brain state.
- Screenshots are real simulator captures in `img/`, regenerated whenever the
  app's results screen changes. Never mock UI in HTML.
- Words of the mission ship LIT so the page reads with JavaScript off; the
  script dims then relights them. The banner and cells rules from the old site
  (JS-off first) apply to anything new.
- Forms race an 8-second rejecting timer. AbortController alone is not enough.
- Deploy is manual: drag `website/` into Cloudflare Pages. Git deploys nothing.
