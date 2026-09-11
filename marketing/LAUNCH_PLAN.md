# 808 launch plan: first 60 days

Written 2026-09-11, the day App Review approved 1.0. The app goes live within
24 hours of release for distribution. This is the working plan; the numbers
in the Assumptions section get replaced by our own after week 2.

Principle, from the app's own stance: **demonstrate, don't adjective.** Every
piece of content shows a real graph, a real score, a real session. Copy rules
in CLAUDE.md apply to every caption, post and brief (no em dashes, never tell
the reader what they lack, no invented numbers, no health-outcome claims).

## 1. The math that sets the budget

Prices: $7.99/month, $29.99/year, 7-day free trial, $99.99 lifetime. Free
tier gives the score; paid gives the curves.

| Assumption | Value | Source |
|---|---|---|
| Install → paid, freemium meditation | 2–4 % (7.8 % is the hard-paywall Health & Fitness benchmark) | Adapty 2026 |
| First-year net revenue per payer, after Apple's 15 % | ~$30 | our price mix |
| Revenue per install | **$0.60–1.20** (up to $2.30 at 7.8 %) | derived |
| iOS CPI, average, Q1 2026 | $5.84 | Admiral Media |
| CPI, meditation keywords, competitive | $4–15 | SEM Nexus |
| Apple Search Ads CPI, global average | ~$2.96 | Admiral Media |

**Conclusion: paid installs do not pay back in year one at our prices and
benchmark conversion.** Calm and Headspace bid on multi-year LTV; we cannot.
So for the first 60 days, paid money buys **learning** (which message, which
format, which keyword) and **high-intent search**, not scale. Organic is the
growth engine.

By week 3 we replace every assumption above with our own: install → trial and
trial → paid from App Store Connect (Analytics → Subscriptions) and PostHog
(`paywall_viewed` → `trial_started` → `purchase`). Every gate below reads
those numbers, not the benchmarks.

## 2. Budget: $1,500–2,500 for 60 days, hard cap $3,000

| Line | When | Amount | Purpose |
|---|---|---|---|
| Apple Search Ads | day 1, always on | $15–25/day, ~$1,000 | the only channel with intent; reports installs with no SDK |
| Boost tests | weeks 1–4 | $100–150 total | cold-audience creative validation, nothing else |
| UGC creators | weeks 3–4 | $500–900 | 4–6 videos on the two proven formats |
| Meta Advantage+ App test | weeks 5–8, gated | $0 or $500–700 | one 14-day test, only if the gate passes |

**Hard cap $3,000 until one channel shows two consecutive weeks with cost per
trial start under $10.** Then scale that channel 20–30 % per week. Kill any
line that runs two weeks above twice its target.

## 3. Channels, what each one is, and how we use it

### Apple Search Ads (ASA)

The ads at the top of App Store search results, marked "Ad". Someone types
"meditation apple watch", we appear first. It is the highest-intent channel
that exists for an app: the person is already in the store, already searching
for the thing, one tap from installing. Pay per tap, not per install.

Setup: ads.apple.com → Basic or Advanced. **Use Advanced** so we choose exact
keywords; Basic lets Apple pick and spends on broad terms.

Keywords, exact match only, one ad group:

- meditation apple watch
- apple watch meditation
- meditation tracker
- meditation tracker apple watch
- mindfulness apple watch
- meditate with apple watch
- meditation heart rate
- track meditation

Leave competitor names (calm, headspace, balance) off until week 3; their
taps cost $2–4 and the person was looking for something else. Daily budget
$15, max CPT $2.00, raise to $25/day only if cost per install stays under $4.

Reporting: ASA shows installs itself (it is the App Store). It cannot see
trials or purchases without an SDK; read those in aggregate from App Store
Connect and compare weeks.

### App Store Connect campaign links (attribution with no SDK)

App Store Connect → App Analytics → Campaigns → create one link per surface.
Each looks like `https://apps.apple.com/app/id6806785308?pt=<our token>&ct=<campaign>&mt=8`.

Make one each for: `ig-bio`, `tiktok-bio`, `website`, `reddit`, `press`,
`yt-shorts`. Put the right one in each bio and post. App Analytics then shows
installs, and downstream proceeds, per campaign. This is how we learn which
platform actually sends people, before any paid attribution exists.

### Organic short-form (the engine): 1 reel + 1 carousel per day, two weeks

Post every reel to Instagram, TikTok and YouTube Shorts. Same file, three
distributions, zero extra cost.

Test **formats**, not topics. Candidates, each a demonstration:

1. The results screen filling in after a real session, score last.
2. A low-scoring session beside a high one, same person, what changed.
3. "My heart rate didn't settle, and the app told me." The honest read.
4. The onboarding practice: two minutes, then a real score on a first try.
5. Bring-your-own-audio: meditating to a YouTube teacher, Watch measuring.
6. A 7-day streak calendar filling, day by day.

What "working" means: **saves + shares per view**, and **profile visit →
install** on the campaign link. Views are noise. A reel that holds a cold
audience when boosted is a UGC brief.

### Boosting reels

A boost is a Meta ad: same auction, same billing. The difference is that the
in-app Boost button cannot use the app-install objective and locks most
targeting; it optimises for reach, engagement or profile visits, and paid
distribution does not lift the reel's organic reach afterwards.

Use: **creative testing only.** $20–30 on the best reel of the week, objective
"profile visits". Read two numbers: watch-through and profile-visit rate.
Never expect installs from a boost. Total boost spend stays under $150.

### Reddit

r/AppleWatch allows app posts and is exactly our audience. One post, launch
week, written by a person: what it measures, one real screenshot, the honest
limits (needs a Watch; breathing reads slow breathing best), and a promo
code offer in the comments. Reply to every comment for 48 hours.

Not r/Meditation (bans promotion). Later candidates: r/Mindfulness (check
rules), r/QuantifiedSelf, r/Biohackers.

### Press and creators

Tip lines, all free, pitch the Watch angle not the meditation angle:
9to5Mac (tips@9to5mac.com), MacRumors (tips@macrumors.com), AppleInsider
(tips@appleinsider.com), iMore, Cult of Mac. Two paragraphs, one screenshot,
a promo code, the App Store link. **Never claim "first"** (CLAUDE.md: Apple's
own Mindfulness app logs heart rate; the claim is unverifiable).

Apple Watch YouTubers and reviewers: gift a lifetime promo code with no ask.
App Store Connect issues 100 promo codes per version.

### Featuring nomination

App Store Connect → Featuring Nominations. Apple asks for 2–3 weeks' notice,
so nominate for a moment three weeks out and say so in the form. Apple Watch
apps are a category Apple features actively. The story: a Watch app that
measures a habit nobody has ever had feedback on.

### Product Hunt

A site where people post new products on a given day and others upvote and
comment; the top products of the day get a badge and a burst of traffic from
founders, early adopters and press who browse it. For consumer iOS apps the
result is usually modest: a few hundred visits, some ratings, a backlink,
and one good day. Worth one launch, not a strategy.

Do it on a Tuesday–Thursday in week 3–4, once the app has 10+ ratings. Post
at 12:01 AM Pacific, have a maker comment ready, and ask friends to comment
rather than just upvote (comments rank).

### UGC creators (weeks 3–4)

Brief 4–6 micro-creators on the two best-performing organic formats. Give
each the exact hook, a promo code, and the rule that they show a real
session. Billo runs ~$99–150 per video with no subscription; direct
micro-creators run $75–150. Skip Insense ($500/month) at this scale.

### Meta Advantage+ App campaigns (gated, weeks 5–8)

Meta's app-install product. Requires the Meta SDK (or an MMP) in the app,
meaning a 1.0.1 build, a review, and updated App Privacy labels. Needs ~50
installs per ad set per week to leave the learning phase, and 8–10 creative
variants at a time; most apps fail here by shipping three creatives a month.

Gate to run it: a format with proven organic retention AND measured
install → trial ≥ 5 %. If passed: $40/day for 14 days, one campaign, 8–10
variants cut from UGC and organic winners. If not passed: keep the money and
double organic output.

## 4. Timeline

**Live day**
- Verify the store page renders; make one real purchase to see live prices.
- Generate promo codes (App Store Connect → Promo Codes).
- Create the six campaign links; update every bio.
- Deploy the website with the App Store button (the repo is ready; drag
  `website/` into Cloudflare Pages).
- Submit the featuring nomination.
- Start ASA, $15/day, exact match.

**Week 1–2: organic**
- 1 reel + 1 carousel daily, tri-posted. Six formats, rotated.
- Reddit r/AppleWatch post, launch week.
- Press tips sent day 2.
- Boost one reel per week, $25, profile visits.
- Friday review: saves/shares per view by format, installs per campaign
  link, ASA cost per install, App Store conversion rate.

**Week 3–4: UGC from what won**
- Brief creators on the two winning formats.
- Product Hunt launch.
- ASA: add competitor terms only if exact-match CPA is under $10.
- Replace every benchmark in section 1 with our numbers.

**Week 5–8: one paid test, gated**
- If the gate passes: 1.0.1 with the Meta SDK, one Advantage+ campaign.
- If not: double organic, keep ASA, revisit at day 60.

## 5. Product moves that help marketing

- **Rating prompt after a great session.** Shipped 2026-09-11: fires from
  the results screen, third completed session or later, never inside
  onboarding, unconditional on how the session went (routing only happy
  users to the prompt is ratings manipulation and a rejection reason).
  Ratings move App Store conversion more than any screenshot.
- **No-Watch churn.** If campaign links show installs from people without a
  Watch churning, the answer is the camera-vision session (branch
  `camera-vision`), not a subtitle warning.
- **Website waitlist repurposed** for the no-Watch audience: it now offers to
  tell people when a session works without a Watch.

## 6. Weekly scorecard

| Metric | Where | Target by day 30 |
|---|---|---|
| App Store product page conversion | ASC Analytics | ≥ 30 % (search traffic) |
| Installs per campaign link | ASC Campaigns | know the top surface |
| Install → trial | ASC Subscriptions / PostHog | ≥ 5 % |
| Trial → paid | ASC Subscriptions | ≥ 35 % |
| ASA cost per install | ads.apple.com | ≤ $4 |
| Saves + shares per 1,000 views | IG / TikTok insights | top format ≥ 2× median |
| Ratings | ASC | 25+ |
| `result_missing` (sessions with no stats) | PostHog | < 5 % |

## Sources

Admiral Media 2026 benchmarks · SEM Nexus CPI by category · Adapty Apple Ads
2026 · AppTweak Apple Ads benchmarks · Metricool on boosting · Instagram Help
"Boost a Reel" · SEM Nexus Meta app-install playbook · Social Outline on the
learning phase · Billo vs Insense · Spark UGC rates 2026 · Apple "Promoting
your apps" · AppTweak on featuring.
