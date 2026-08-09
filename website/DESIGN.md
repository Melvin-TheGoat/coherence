# 808 website design system

Handoff for redesign. Everything here is extracted from the live site
(meditate808.com), not from memory. Last updated 2026-08-09.

---

## 1. What the product is

**808 measures your meditation on your Apple Watch and shows you what it did to
your body.** Three signals are read while you sit: how still you were, how your
heart rate drifted, and how slowly you breathed. Nothing is shown during the
session. When you open your eyes there is one score out of 100, three curves,
and a trend line across every session you have done.

It works with 808's own guided track, with its sound library, or with nothing
at all: you can start a session and play a meditation in any other app, and the
Watch keeps measuring.

**Who it is for.** People who have tried meditating, could never tell whether it
was working, and quit. Not beginners looking for calm.

**The one-line positioning.** Meditation gives you calm. 808 gives you
certainty. The emotion it owns is *relief*: it worked, and you weren't
imagining it. It deliberately does not compete on serenity, because every
competitor already does and because the app does not supply the calm, the
meditation does.

**Status.** Pre-launch. The site's only conversion goal is a waitlist email.

---

## 2. The argument the page makes

The order matters more than any single section. It moves from the reader's
problem to the product, not the reverse.

| # | Section | Job |
|---|---|---|
| | Hero | What it is, plus the email capture |
| 01 | The cost | 46.9% of waking hours spent elsewhere, turned into *their* number |
| 02 | Meditation works | The practice has evidence: +16 GRE percentile points, 47 trials |
| 03 | The catch | Almost nobody keeps meditating. 39% drop out, half of Calm subscribers quit |
| 04 | So we gave it a watch | Four steps, then the four charts |
| 05 | What the number means | One score, plainly explained |
| 06 | What you'll sit through | Guided track, then the sound library |
| 07 | Who built it | Two founders, then the sources |
| | Closer | Email capture again |

**Section 01 is the emotional peak** and section 04 is the proof. If a redesign
weakens either, it has cost more than it gained.

Three CTAs: hero, after the charts, and the closer. Never more.

---

## 3. Colour

Dark only. There is no light theme and the design does not assume one.

### Tokens

| Token | Hex | oklch | Role |
|---|---|---|---|
| `bg` | `#090A0D` | `oklch(14.5% .006 260)` | Page background |
| `surface` | `#111316` | `oklch(18.5% .007 260)` | Raised panel |
| `surface-2` | `#1A1C20` | `oklch(22.5% .008 260)` | Inactive cell, chip |
| `border` | `#27292D` | `oklch(28% .008 260)` | Hairline rules. The workhorse |
| `input` | `#2B2E32` | `oklch(30% .008 260)` | Form field outline |
| `grid` | `#2E3034` | `oklch(31% .008 260)` | Chart gridline |
| `muted` | `#96989C` | `oklch(68% .006 260)` | Secondary text |
| `fg` | `#E9EBEE` | `oklch(94% .004 260)` | Primary text |
| `gold` | `#F0C058` | `oklch(83% .132 84)` | **A measured score** |
| `gold-dim` | `#8A6D2C` | `oklch(55% .09 84)` | Gold at rest: focus rings, small numerals |
| `gold-hover` | `#FFD06C` | `oklch(88% .13 84)` | Button hover only |
| `gold-ink` | `#140E06` | `oklch(17% .02 80)` | Text **on** gold |
| `teal` | `#56D1C9` | `oklch(79% .11 189)` | **The body's own signals** |
| `teal-dim` | `#2A706B` | `oklch(50% .07 189)` | Teal at rest |
| `ember` | `#BB6F60` | `oklch(62% .10 32)` | **Cost and loss** |
| `ember-dim` | `#77463C` | `oklch(45% .07 32)` | Ember at rest |

The greys are all hue 260 at very low chroma, so the neutrals read faintly cool
rather than dead. That is deliberate and worth preserving.

### The colour grammar is semantic, not decorative

This is the single most important rule in the system, and it is shared with the
iOS app, so breaking it on the site desynchronises the two products.

- **Gold means a measured score, and nothing else.** Not emphasis, not
  decoration, not "primary brand colour". If it isn't a number the Watch
  measured, or the button that leads to getting one, it isn't gold.
- **Teal means the body's own signals.** Heart rate, breathing, the resonance
  band. Never a score.
- **Ember means cost and loss.** It was alarm red until it made the page read
  like an error state; the hue stayed and the chroma was roughly halved. It is
  never a score and never an error.

**Each section shows exactly one loud thing**, so the page can be audited in a
vertical sweep. If two elements compete in a section, one of them is wrong.

---

## 4. Typography

Three families, each with one job.

| Role | Family | Usage |
|---|---|---|
| Display | **Bricolage Grotesque** 700 | Headlines, big figures, chart readouts |
| Body | **IBM Plex Sans** 400/600 | All prose |
| Label | **IBM Plex Mono** 400/500/600 | Every label, eyebrow, axis, microcopy, button |

All three are Google Fonts. There is no licensed or self-hosted face.

**Display** always runs `letter-spacing: -0.03em` and tight leading (0.96 to
1.0). The negative tracking at large sizes is a signature of the look.

**Mono labels** always run `12px / 0.1em letter-spacing / uppercase / muted`.
This is the connective tissue of the whole site: section markers, chart titles,
axis ends, form microcopy, footer. If you change one thing about the type
system, this is the piece most likely to break the identity.

### Scale in use

```
Display   clamp(44px, 6.1vw, 86px)    h1
          clamp(32px, 4.2vw, 58px)    h2
          clamp(96px, 12vw, 168px)    the "114 days" figure
          clamp(46px, 5vw, 68px)      section figures (+16, 39%)
          26px                        chart readouts, wordmark

Body      18px   lede, section prose
          17px   .prose paragraphs
          15–16px  supporting text, step copy

Mono      13px   buttons
          12px   labels, section markers
          11.5px microcopy, footer
          11px   chart axis
```

**Body prose never exceeds 60 characters per line**, and the legal pages use
68. The page shell is wide but the text column is not: the extra width goes to
layout, never to longer lines.

---

## 5. Layout

```
Shell        max-width 1240px, 40px side padding (20px under 700px)
Prose        max-width 60ch
Legal prose  max-width 68ch
Radius       0 everywhere. There is not a single rounded corner.
```

**Breakpoints.** 1040px (two-column layouts collapse) and 700px (mobile:
padding tightens, grids go single column, buttons go full width).

**Sections** are separated by a 1px `border` rule with 88px top and 96px bottom
padding. The asymmetry is deliberate: it separates a section's closing line
from the next section's heading.

**Section markers** sit in a 64px left margin column on desktop (`01 / THE
COST`) and stack above the heading on mobile.

Structure is built from **hairline rules, not boxes**. There is no elevation
anywhere: zero shadows, zero gradients, zero fills except the gold button and
the year grid's cells. Every division on the page is a 1px line. This is most
of what makes it read as an instrument rather than a wellness app, and it is
the easiest thing to lose in a redesign.

---

## 6. Components

- **Masthead.** Gold wordmark, mono label, ghost link right
- **Section marker.** Mono `NN / NAME`, number in gold
- **Email capture.** Flush input plus gold button, zero gap, square. Mono
  input text. Appears three times
- **Big figure.** Display numeral plus mono unit label, used for `114`, `+16`,
  `39%`
- **Figure row.** Two or three big figures across, hairline separated
- **Step row.** Four numbered steps across, mono index in gold
- **Chart cell.** Mono title, display readout, SVG, mono axis ends, caption.
  2×2 grid
- **Year grid.** 365 cells, 40 columns, ember for lost days. Static HTML, not
  generated
- **Sound library.** Four cells, count chip plus mono label plus waveform
- **Sources disclosure.** Collapsed `[+]`, numbered citations with DOIs

### Charts

Four, all hand-authored SVG paths on a 320×132 viewBox, computed from a real
session. Rules that must survive:

- **Heart rate is never plotted from zero.** A 74 to 63 settle drawn from the
  baseline is a flat line, which is a lie about a real change
- Stillness is always 0 to 1
- The breathing chart always contains the 4.5 to 7 resonance band, shaded teal
- The score chart is bars, with today's bar at full opacity and history at 42%

---

## 7. Non-negotiables

These are brand commitments, not preferences.

**No em dashes. Anywhere.** Not in headlines, not in body, not in captions.
Restructure the sentence instead. This has been raised enough times to be a
standing rule, and the reason is that the em dash is the clearest tell of
machine-written text, which undercuts a product whose pitch is honesty. The
legal pages currently contain 22 and are the exception, pending the attorney.

**Every claim is cited or cut.** Seven sources with DOIs sit behind a
disclosure, plus a closing note stating plainly that none of the research shows
808 works for you specifically. That note is doing sales work, not undermining
it. Do not remove it to save space.

**No invented numbers, ever.** No fake testimonials, no user counts, no "trusted
by" logos, no "first app to" claim. The product has not launched. The one
interactive number on the page is arithmetic on the visitor's own input times a
published constant, with the formula printed beside it.

**Name the subject.** Each block gets read in isolation. A heading like "It
works" or "But" is meaningless alone; both were fixed for this reason.

**It must work without JavaScript.** The 365-cell grid is static HTML because a
JS-generated grid renders as nothing wherever scripts are blocked. The counter
writes its final value from a timer rather than trusting an animation frame.
Any interactive element needs a correct no-JS resting state.

---

## 8. Practical constraints

**One static HTML file per page.** No build step, no framework, no npm. CSS
lives in a `<style>` block in each file. Four pages: `index`, `survey`,
`privacy`, `terms`.

**Deployment is a manual upload to Cloudflare Pages**, drag-and-drop of the
`website` folder. The project is *not* connected to git, so pushing to GitHub
does nothing to the live site.

**A strict CSP is not in place**, but the only external requests are Google
Fonts and the form endpoints. Keep it that way.

**Forms post to Google Apps Script** with an email fallback, and every request
races an 8-second timer. If the layout of a form changes, the field `name`
attributes must not: they map to spreadsheet columns.

---

## 9. Open questions, where your judgement is wanted

**The typeface was never settled.** Bricolage Grotesque came from a Lovable
draft that Aziz preferred to the alternatives, and it is loud and confident.
There was an unfinished exploration toward something calmer and more serene
(Instrument Serif, Newsreader, Spectral were shortlisted) on the theory that
the brand's emotion is relief rather than urgency. The colour moved in that
direction; the type never did. **This is the biggest open call.**

**The hero has no product imagery.** Real app screenshots were tried and Aziz
rejected them as looking bad. The charts currently carry the whole burden of
showing what the product is. A better answer than either probably exists.

**There is no social proof and there cannot be yet**, since nothing has
launched. Standard conversion advice says put it above the fold; we have
citations and a founder note instead.

**Section 01 keeps one accusatory line** ("You will be awake for all of them
and present for none of them"). It has been flagged twice as the harshest
sentence on the site and kept twice. Worth revisiting with fresh eyes.

**The legal pages are restyled but not rewritten.** They match the system;
their prose is pending an attorney.
