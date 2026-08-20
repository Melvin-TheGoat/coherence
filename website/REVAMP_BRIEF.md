# Website revamp: the prompt

Paste the block under **THE PROMPT** back to Claude to execute. Everything it
needs is stated in it or named by file path.

Written 2026-08-19 against app 5.2.0. Supersedes the first draft.

**Privacy note.** Six real people gave us reviews with their email addresses.
**Their emails are deliberately not in this file**, because this repo is public.
First names only. Before publishing, confirm each person is happy to be quoted
by first name.

---

## THE PROMPT

> Rebuild `website/index.html` as one self-contained static page. Keep
> `privacy.html`, `terms.html` and `survey.html` working, restyled to match.
> This is the marketing site for **808**, a meditation app for iPhone and Apple
> Watch. Tone: professional, sleek, convincing, trustworthy, and calm. It is
> selling proof, so it should feel like evidence rather than like hype.
>
> ### What 808 is, in one line
>
> **The first app that scores your meditation from your own body.** Your Apple
> Watch reads three signals while you sit: how still you were, how your heart
> rate drifted, and how slowly you breathed. Nothing is shown during the
> session. Afterwards you get one score out of 100, three curves, and a plain
> sentence saying what happened.
>
> ### The four pain points, which are the spine of the page
>
> Every feature section answers one of these. Do not add a feature block that
> does not.
>
> | Pain | What we do | Screens to show |
> |---|---|---|
> | **1. You can't tell if you're doing it right** | Graphs of heart rate, stillness and breathing, a score, and a written takeaway. Even a session that felt bad shows what your body actually did | The three curves, the metric tiles, the overall score, the verdict sentence. **Show one high-scoring and one low-scoring session**, because that honesty is the product |
> | **2. Nothing keeps you accountable** | Streaks, a calendar, awards, and people practising alongside you | Streak, month calendar, awards shelf. Instagram for the community |
> | **3. You can't prove you did it** | Share your verified metrics to Instagram, X, anywhere | The "Share your practice" card |
> | **4. Beginners don't know how, advanced want more** | A guide with eight methods, from breath and body scan up to manifestation and blessing the energy centers | The guide roadmap, one method page |
>
> ### Positioning claim: use the narrow version
>
> Melvin wants "the FIRST app that tracks your biofeedback to score your
> meditation."
>
> **Ship this instead: "The first app that scores your meditation from your own
> body."** The broad version says *tracks biofeedback during meditation*, and
> Apple's own Mindfulness app already logs heart rate during a session, so it is
> not defensible and has been left out three times for that reason. **Scoring is
> the genuinely novel part.** The narrow claim keeps the punch and survives
> someone checking it. Do not write "first app to track biofeedback".
>
> ### Source material, all already in this repo
>
> - **`PURPOSE.md`** — the mission, in Melvin and Aziz's words. Drives the
>   scroll-highlight section.
> - **`SCIENCE.md`** — every citation we may make, with DOIs. **Cite nothing
>   that is not in here.**
> - **`website/DESIGN.md`** — the outgoing design system, for what survives.
> - **`Coherence/Onboarding/OnboardingPayoff.swift`**, `WallScreen` — the famous
>   practitioners, already tiered.
> - **`Shared/Awards/Award.swift`** — the 17 awards.
> - **`Shared/Guide/MeditationMethod.swift`** — the 8 methods.
> - Current site sections worth keeping: `01 The cost`, `02 Meditation works`,
>   `03 The catch`, `04 So we gave it a watch`, `06 Who built it`.
>
> ### Type
>
> Replace Bricolage Grotesque and IBM Plex entirely.
>
> | Role | Face |
> |---|---|
> | Display | **Manrope** |
> | Body | **Hanken Grotesk** |
> | Label | **DM Mono**, uppercase, 0.1em tracking |
>
> All three are open-licensed. **Self-host in `website/fonts/`**, do not
> hotlink: no third-party request, and nothing breaks when a CDN does. Preload
> the display weights.
>
> ### Colour: take it from the app
>
> There is no Figma file. Use the app's own tokens so the site and the product
> read as one thing.
>
> | Token | Value | Means |
> |---|---|---|
> | Ground | `#13100D` dark, `#F7F5F0` light | |
> | Card | `#221E19` dark, `#ECEAE3` light | |
> | Text | `#F5F3EC` dark, `#111114` light | |
> | Muted | `#9A9A93` dark, `#6B6B6B` light | |
> | **Gold** | `#D4AF37` on dark. On light: fill `#DCB63F`, text `#8A6D14` | **What you achieved** |
> | **Teal** | `#73A8A1` | **What your body did** |
> | Terracotta | `oklch(62% .10 32)` | Cost and loss only, never alarm |
>
> **The rules that carry meaning, not just taste:**
>
> - **Gold = achieved, teal = the body's signals.** Never both loud in one
>   element. Every section shows exactly one gold thing, so the page can be
>   audited in a vertical sweep. Scores, streaks and awards are gold. Heart
>   rate and breathing curves are teal.
> - **The two golds on light backgrounds are not interchangeable.** A gold light
>   enough to be a good button reads 1.78:1 as text on cream, which is
>   illegible. Fill and text are separate tokens. Do not collapse them.
> - **Lead dark.** The app defaults to dark, the end cards are dark, and the
>   research on wellness palettes points the same way: a true dark ground reads
>   calmer at night and lets one warm accent carry the whole page. Colour drives
>   most of a first impression and it forms in seconds, so the ground doing the
>   calming and a single accent doing the pointing is worth more than a second
>   accent.
> - Warm gold on near-black is the whole identity. Resist adding blue for
>   "trust". The trust here comes from showing real numbers, not from a hue.
>
> ### Page order
>
> 1. **Hero.** "The most powerful tool you have is your mind." Subhead: what 808
>    does, concretely. One CTA, **Join the waitlist**. Device shot right on
>    desktop, stacked on mobile.
> 2. **The mission, as a scroll-highlight.** Spec below. Centrepiece.
> 3. **Famous practitioners.** Port `WallScreen` exactly, including its two-tier
>    rule: **Tier 1 quoted verbatim, Tier 2 described as practising and never
>    quoted.** Kobe Bryant, Oprah Winfrey, Ray Dalio, Jerry Seinfeld, the
>    Seattle Seahawks. If a quote is not already in `WallScreen`, it does not
>    exist. Invent nothing.
> 4. **Testimonials.** Six real ones, below. Card grid, QUITTR's layout is the
>    reference: quote, five gold stars, first name, small label. Three up then
>    two centred, collapsing to one column on mobile.
> 5. **Why meditation works.** The research, the existing charts, the AHA
>    statement and the Schneider trial with their disclosures. Keep the closing
>    note that none of it is about 808 specifically.
> 6. **Features in detail**, structured as the four pain points above.
> 7. **Who built it.**
> 8. **Footer.** See below.
>
> ### The six testimonials, verbatim
>
> Use exactly this text. Do not polish it, do not add any, do not invent
> avatars. First names only. All five stars.
>
> 1. **David** — *Finally know if I'm doing it right*
>    "I've started and quit meditating probably six times. The thing that always
>    got me was having no idea if anything was happening. First session with this
>    showed my heart rate dropped 14 beats when i slowed my breathing down and it
>    showed me where on the graph. I know it sounds small but it's the first time
>    I've had any proof I wasn't just sitting there wasting ten minutes."
> 2. **Julia** — *Use it with my own stuff*
>    "Big one for me is I already have meditations I like on YouTube. This just
>    runs in the background on my watch and measures. Don't have to switch to
>    their library or listen to some voice I don't like. And I love seeing the
>    data, like how my heart responds to different parts of the meditation"
> 3. **Ayush** — *Breathing tracking works*
>    "Skeptical it could pick up breathing from a wrist but it caught me slowing
>    down at the start of a session and then speeding up later on, surprisingly
>    accurate"
> 4. **Maria** — *Love sharing my meditations*
>    "I meditate a lot and always wanted to have a way of sharing that I do, now
>    I send my friend my meditation score everytime"
> 5. **Gabriel** — *Basically Strava for meditation*
>    "I track everything else so figured why not my morning meditation as well. I
>    love the streak, keeps me accountable, and the achievements are also fun to
>    hit"
> 6. **Charlie** — *How to guide was good*
>    "Complete beginner to meditating and tried it out with low expectations, the
>    guide turned out to be incredibly helpful in explaining the purpose and
>    technique to meditating. Cant wait to try out some more advanced meditations"
>
> Note the small typos are theirs. Leave them. Cleaned-up testimonials read as
> written by us.
>
> **Do not publish anyone's email address.** First names only.
>
> ### The scroll-highlight section
>
> The one real piece of motion, modelled on QUITTR's about page. **Melvin
> demoed that effect on mobile Chrome and Safari and it works fine, so it ships
> on mobile too.**
>
> - The mission paragraph pins to the centre of the viewport while the page
>   scrolls behind it.
> - Words light from muted to full, **one at a time in reading order**, driven
>   by scroll position, not a timer.
> - Releases and scrolls on once the last word is lit.
> - Text from `PURPOSE.md`, trimmed to roughly 40 to 55 words. The paragraph
>   opening "We believe the most powerful tool you have is your mind" is right.
>
> Non-negotiable:
>
> - **CSS-first** via `animation-timeline: view()`, with a small
>   `IntersectionObserver` plus `requestAnimationFrame` fallback. No scroll
>   library.
> - **Readable with JavaScript off.** Ship the words lit and let the script dim
>   them on load. The current site's 365-cell grid was built JS-first and
>   rendered as nothing where scripts were blocked. Do not repeat it.
> - `prefers-reduced-motion`: no pin, no dim.
> - On mobile use `100svh` rather than `100vh` for the pin, so iOS Safari's
>   collapsing address bar does not make it jump.
>
> ### Mobile
>
> Design narrow first and let it widen. Tap targets 44px. No horizontal body
> scroll at any width. Test 375, 390 and 768. The waitlist form reachable
> without scrolling past two screens.
>
> ### Footer
>
> Melvin pasted QUITTR's footer as a structural example. **Take the shape, not
> the content**: it literally says "App to Quit Porn" and links to things we do
> not have. Ship only what exists:
>
> - **Product**: Join the waitlist (Download on the App Store once live),
>   Features, The science
> - **Company**: About 808, Who built it
> - **Legal**: Terms, Privacy Policy, Subscription terms
> - **Socials**: Instagram `@808meditate`. TikTok or X **only if the accounts
>   exist**, ask first
> - **Support**: `support@meditate808.com`, and **keep `id="support"`**, because
>   the App Store support URL points at it and silently landed on the top of the
>   page once already
>
> **Do not create Blog, Jobs, Extension, Reddit or UGC Army links.**
>
> ### Rules that are not negotiable
>
> - **No em dashes in user-facing copy.** Restructure instead. Third time raised.
> - **No invented statistics, testimonials, user counts, press logos or badges.**
> - **Never claim 808 measures a brain state.** No theta, no brainwaves. We
>   measure motion and averaged heart rate.
> - **Do not use the 23-minute refocus statistic.** No paper behind it.
> - Keep the wellness disclaimer and the "none of this research is about 808"
>   note.
> - Both forms keep the **8-second rejecting timer**. AbortController alone was
>   tested against a stalled fetch and still hung 18 seconds.
> - `survey-sheet.gs` writes by the **sheet's** header row. Do not touch that.
>
> ### Deliverables
>
> 1. Rebuilt `website/index.html`, self-contained apart from `website/fonts/`.
> 2. `privacy.html`, `terms.html`, `survey.html` restyled.
> 3. `website/DESIGN.md` updated to the new system.
> 4. A summary of every judgment call, and an explicit list of placeholders.
>
> Verify before handing over: render it, screenshot desktop and 390px, confirm
> no horizontal scroll, confirm it reads with JavaScript off, confirm the
> scroll-highlight releases cleanly on a phone.
>
> **Do not deploy.** Cloudflare Pages is direct-upload and not connected to git.
> Melvin deploys by hand.

---

## Still needed from Melvin

| Item | Why |
|---|---|
| App screenshots | Hero, high AND low score, calendar, streak, awards, share card, guide. Real ones. Placeholders otherwise |
| Permission to quote | Confirm the six reviewers are happy to appear by first name |
| TikTok / X | Only linked if the accounts exist |
| Instagram reels | Optional, if the community section should show them |
