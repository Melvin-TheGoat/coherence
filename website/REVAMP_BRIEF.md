# Website revamp: the prompt

Paste the block below back to Claude to execute the rebuild. Everything it needs
is either stated in it or named by file path, so it should not have to guess.

Written 2026-08-19, against app version 5.2.0 / commit `680cdf7`.

---

## THE PROMPT

> Rebuild `website/index.html` as a single self-contained static page, replacing
> the current one. Keep `privacy.html`, `terms.html` and `survey.html` working
> and restyle them to match. This is the marketing site for **808**, a meditation
> app for iPhone and Apple Watch.
>
> ### Source material, all of it already in this repo
>
> - **`website/DESIGN.md`** — the existing design system, extracted from the live
>   site rather than remembered.
> - **`PURPOSE.md`** — the mission statement, in Melvin and Aziz's own words. The
>   scroll-highlight section (below) uses this almost verbatim.
> - **`SCIENCE.md`** — every research citation we are allowed to make, with DOIs.
>   **Do not cite anything that is not in here.**
> - **`Coherence/Onboarding/OnboardingPayoff.swift`**, `WallScreen` — the
>   celebrity wall, already written and already tiered. Reuse it exactly.
> - **`Shared/Awards/Award.swift`** — the seventeen awards, for the features
>   section.
> - **`Shared/Guide/MeditationMethod.swift`** — the eight guided methods.
> - Current site sections, for what survives: `01 The cost`, `02 Meditation
>   works`, `03 The catch`, `04 So we gave it a watch`, `05 What you sit
>   through`, `06 Who built it`.
>
> ### Type
>
> Replace Bricolage Grotesque and IBM Plex entirely.
>
> | Role | Face | Use |
> |---|---|---|
> | Display | **Manrope** | headlines, the hero, section titles |
> | Body | **Hanken Grotesk** | all running text |
> | Label | **DM Mono** | eyebrows, section numbers, captions, uppercase at 0.1em |
>
> All three are on Google Fonts and open-licensed. Self-host them in
> `website/fonts/` rather than hotlinking, so the page has no third-party
> request and cannot break when a CDN does. Preload the two display weights.
>
> ### Colour
>
> Keep the app's grammar, because the site and the app must read as one product:
> **gold = what you achieved, teal = what your body did.** Never both loud in the
> same element.
>
> - Gold, dark ground: `#D4AF37`. Gold, light ground: fill `#DCB63F`, text
>   `#8A6D14`. **These are two different tokens and the split is deliberate**:
>   a gold light enough to be a good button is unreadable as text on a light
>   background (measured at 1.78:1). Do not collapse them back into one.
> - Teal `#73A8A1`. Terracotta `oklch(62% .10 32)` for cost and loss only, never
>   as an alarm.
> - The designer's Figma may specify its own palette. **If it does, it wins for
>   the site**, but keep the gold/teal semantic split intact and say in your
>   summary what changed.
>
> ### Page structure, in order
>
> 1. **Hero.** "The most powerful tool you have is your mind." Subhead naming
>    what 808 does. One primary CTA: **Join the waitlist**. A device shot on the
>    right on desktop, stacked on mobile. Use a real screenshot, not a
>    placeholder; if none exists, leave a clearly-marked empty frame rather than
>    inventing UI.
> 2. **The mission, as a scroll-highlight.** See the spec below. This is the
>    centrepiece.
> 3. **The famous-practitioner wall.** Port `WallScreen` exactly, including its
>    two-tier rule: **Tier 1 is quoted verbatim, Tier 2 is described as
>    practising and never quoted.** Kobe Bryant, Oprah Winfrey, Ray Dalio, Jerry
>    Seinfeld, the Seattle Seahawks. **Invent nothing.** If a quote is not
>    already in `WallScreen`, it does not go on the page.
> 4. **User testimonials.** Five-star reviews from real people.
>    **BLOCKED until Melvin supplies the spreadsheet.** Build the section, leave
>    the data in one clearly-marked array at the top of the file, and put three
>    obviously-placeholder entries in it. **Never write a fake testimonial**,
>    not even as filler, and never attribute one to a real name we have not been
>    given.
> 5. **Why meditation works.** The research. Reuse the existing charts and the
>    seven sourced findings; add the AHA cardiovascular statement and the
>    Schneider trial with the disclosures already written in the current
>    sources list. Keep the closing note that none of this research is about 808
>    specifically.
> 6. **Features, in detail.** Three or four blocks, each with a real screenshot:
>    the guided meditation, the score and its three curves, the calendar and
>    streak, the awards shelf, and the guide's eight methods. Say what each one
>    measures rather than what it promises.
> 7. **Who built it.** Keep, lightly restyled.
> 8. **Footer.** See the footer note below, which is important.
>
> ### The scroll-highlight section
>
> The one piece of real motion on the page, modelled on QUITTR's about-page
> effect that Melvin referenced.
>
> - The mission paragraph pins to the centre of the viewport while the page
>   continues to scroll behind it.
> - Words illuminate from `--muted` to `--fg` **one at a time, in reading
>   order**, driven by scroll position rather than by a timer.
> - It releases and scrolls on normally once the last word is lit.
> - Text comes from `PURPOSE.md`, trimmed to roughly 40 to 55 words. The
>   paragraph beginning "We believe the most powerful tool you have is your
>   mind" is the right one.
>
> Requirements, all of them load-bearing:
>
> - **Pure CSS where possible** (`animation-timeline: view()`), with a small
>   `IntersectionObserver` plus `requestAnimationFrame` fallback for Safari.
>   Nothing heavier, and no scroll library.
> - **Every word must be readable with JavaScript disabled.** Ship the text lit,
>   and let the script dim it on load. The 365-cell grid on the current site was
>   built JS-first, rendered as nothing where scripts were blocked, and Aziz saw
>   exactly that. Do not repeat it.
> - **`prefers-reduced-motion`**: no pinning, no dimming, just the paragraph.
> - **Never pin on mobile.** Pinned scroll sections fight iOS Safari's collapsing
>   address bar and feel broken. Below 768px, fade the paragraph in as one block.
>
> ### Mobile
>
> Not an afterthought, and not a media query bolted on at the end. Design the
> narrow layout first and let it widen. Specifically:
>
> - Tap targets 44px minimum.
> - No horizontal body scroll at any width; wide content scrolls inside its own
>   container.
> - Test at 375px, 390px and 768px.
> - The waitlist form must be reachable without scrolling past two screens.
>
> ### The footer
>
> Melvin pasted QUITTR's footer as a structural example. **Take the shape, not
> the content.** It literally contains "App to Quit Porn", and several of its
> links describe things 808 does not have.
>
> Ship only what exists:
>
> - **Product**: Download on the App Store (or Join the waitlist until it is
>   live), Features, The science.
> - **Company**: About 808, Who built it.
> - **Legal**: Terms, Privacy Policy, Subscription terms.
> - **Socials**: Instagram `@808meditate`. Add TikTok or X **only if the
>   accounts exist** — ask before adding either.
> - **Support**: `support@meditate808.com`, and keep the `id="support"` anchor,
>   because the App Store support URL points at it and it silently landed on the
>   top of the page once already.
>
> **Do not create a Blog, Jobs, Extension, Reddit or UGC Army link.** A footer
> link to a page that does not exist is worse than a shorter footer.
>
> ### Rules that are not negotiable
>
> - **No em dashes in any user-facing copy.** Restructure the sentence instead.
>   This is the third time it has been raised. Code comments are exempt.
> - **No invented statistics, testimonials, user counts, press logos or award
>   badges.** If we cannot source it, it does not ship.
> - **No "first app to" claim.** Apple's own Mindfulness app already logs heart
>   rate during sessions, so it is unverifiable.
> - **Never say 808 measures a brain state.** No theta, no brainwaves, no
>   "detects your nervous system". We measure motion and averaged heart rate,
>   and the honest framing already exists in `SCIENCE.md`.
> - **Do not use the 23-minute refocus statistic.** It has no paper behind it.
> - Keep the wellness disclaimer and the "none of this research is about 808"
>   note.
> - Both existing forms keep their **8-second rejecting timer**. AbortController
>   alone was tested against a stalled fetch and still hung for 18 seconds; the
>   first live signup stuck on "Joining" forever.
> - `survey-sheet.gs` writes by **the sheet's header row**, not the file's. Do
>   not touch that reconciliation.
>
> ### Deliverables
>
> 1. Rebuilt `website/index.html`, self-contained apart from `website/fonts/`.
> 2. `privacy.html`, `terms.html`, `survey.html` restyled to match.
> 3. `website/DESIGN.md` updated to the new system, so the next person inherits
>    the truth rather than this brief.
> 4. A short summary of every judgment call you made, and an explicit list of
>    anything you left as a placeholder.
>
> Verify before you hand it over: render it, screenshot desktop and 390px,
> check both themes if the design keeps a light mode, confirm no horizontal
> scroll, and confirm the page still reads with JavaScript off.
>
> **Do not deploy.** Cloudflare Pages is a direct-upload project and is not
> connected to git, so pushing changes nothing live. Melvin deploys by hand.

---

## What is still blocking

| Item | Needed from | Notes |
|---|---|---|
| Figma file | Melvin's designer | Layout, spacing, and whether the palette changes |
| Testimonials spreadsheet | Melvin | Names, ratings, text, and permission to publish each |
| App screenshots | Melvin | Hero, score, calendar, awards, guide. Real ones |
| TikTok / X accounts | Melvin | Only linked if they exist |
