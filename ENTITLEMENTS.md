# Entitlements: the free tier and what paying unlocks

**BUILT 2026-08-24.** 198 tests green, verified on the simulator. This document
is now the record of what shipped, not a proposal. Read `ONBOARDING.md` for the
flow this sits inside.

What changed between the spec and the build is recorded in "Decided during
implementation" at the end.

---

## What this replaces

**808 is no longer a hard paywall.** The decision logged on 2026-08-11 ("paying
unlocks the ENTIRE app") is reversed by Aziz, 2026-08-24. Three reasons, in
ascending order of weight:

1. Free users cost nothing. There is no backend, every computation runs on the
   Watch and the phone, and storage is the user's own iCloud. The usual argument
   against a free tier does not apply here.
2. A hard paywall throttles the metric we are chasing. Install to paid on a hard
   paywall runs around 12% at the median, so 100 daily actives needs roughly
   eight times the installs.
3. **A hard paywall makes 808 do the thing 808 exists to refuse.** The product's
   whole position is that it does not ask anyone to take a claim on faith. Then
   the build asks for money before the user has seen a single reading. Letting
   someone see their own score and then selling them the evidence behind it is
   the same argument the app makes about meditation.

---

## The rule

> **Free gives you the score. Paid gives you the evidence behind it.**

One sentence so nobody has to memorise a matrix, and so a new feature sorts
itself without a meeting. When something new is built, ask whether it is the
readout or the reasoning.

### The boundary

| | Free | Paid |
|---|---|---|
| Score out of 100 | yes | yes |
| Written verdict | yes, numberless | yes, with the numbers |
| Curves (heart, breath, stillness) | locked | yes |
| Metric tiles and the per-curve readings | locked | yes |
| Resonance chip | yes | yes |
| Practice-score sparkline (home) | yes | yes |
| Streak, calendar, awards, history | yes | yes |
| Nature, frequency, silence | yes | yes |
| Bring your own audio | yes | yes |
| Guided journey | no | yes |
| Share card | the Score card | all five cards |

Three deliberate calls inside that table:

**No session cap.** Considered and dropped. A daily meditator does one session a
day, so a cap creates no purchase pressure on the person we are targeting, and a
12 hour window would block an 8pm-then-7am pair and break the streak we are
selling. The locked metrics do all of the monetisation work.

**Bring your own audio stays free, and this is not negotiable.** It cannot be
enforced, because playing Calm in another app and tapping Begin is
indistinguishable from a Silence session. More importantly it is the reason the
ICP installs 808 at all.

**Skins are the safest thing in the app to charge for.** Everything else paid is
evidence, and charging for evidence carries a small permanent tension with a
product whose pitch is honesty. Nobody feels cheated that a nicer card design
costs money, and the skin is visible to everyone who sees the post.

---

## Where the gate lives

One new file, `Coherence/Store/Entitlements.swift`. Nothing outside it decides
what is locked.

```swift
/// What this person may see. The single answer to "is this locked".
///
/// Views ask this, never `store.entitled` directly: the free tier is a product
/// decision that will move, and it should move in one file.
struct Entitlements {
    let paid: Bool

    var curves: Bool        { paid }
    var metrics: Bool       { paid }   // tiles, resonance chip, readings
    var trend: Bool         { paid }   // home sparkline
    var guidedTrack: Bool   { paid }
    var shareCurves: Bool   { paid }
    func skin(_ s: CardSkin) -> Bool { s == .midnight || paid }
}
```

Provided through the environment beside `Store`, derived once:

```swift
extension Store {
    /// Free is the floor, not a failure state. While the store cannot sell
    /// (`.loading`, `.unavailable`) everyone is treated as PAID, which is what
    /// keeps the pre-billing beta whole and means a network hiccup can never
    /// downgrade someone who paid. Entitlements are cached on device by
    /// StoreKit, so this does not need the network to say yes.
    var entitlements: Entitlements {
        Entitlements(paid: state != .ready || entitled)
    }
}
```

**That inversion is the load-bearing line.** `RootView.locked` today reads
`store.state == .ready && !store.entitled`, and the same reasoning carries over
exactly: the gate only exists while the store is actually selling. Do not
rewrite it as `entitled` alone, or every beta tester loses their curves the day
products go live and before anyone has had a chance to buy.

---

## Changes, file by file

### `Coherence/RootView.swift`

Delete `locked` and the `PaywallScreen` branch. `ContentView()` becomes
unconditional once onboarding is complete. `lockedPlan` goes with it.

The paywall is no longer a wall. It is reached from onboarding and from the
upgrade sheet, both of which present it.

### `Coherence/Session/SessionResultsView.swift`

The main surface. Four edits:

- `tiles(_:)` renders the locked variant when `!entitlements.metrics`: same
  three tile shapes, value replaced by a muted dot row. Do not hide the tiles.
  The shape of what is missing is the sell.
- `graphCard(_:)` renders a `LockedGraphCard` when `!entitlements.curves`:
  the signal name, a gold Locked pill, and an empty recessed plot area.
  **No curve behind the lock, not even faint** (Aziz, 2026-08-24). Nothing to
  squint at and nothing to screenshot around.
- `resonanceChip` and `reading(for:)` are metrics. Locked with the tiles.
- Tapping any locked element presents `UnlockSheet(signal:)`, which names the
  specific thing being withheld rather than saying "upgrade for more features".

Everything above the fold stays fully legible for free users: the score ring,
the verdict, the streak, the meta line. Free 808 has to be worth opening every
day or there is nobody to sell to.

### `Shared/Engine/VerdictEngine.swift`

The verdict embeds numbers: "heart settled 11 beats" (line 57), "breath slowed
to 5.4 a minute" (line 68), "calmer than 8 of your last 10" (line 121).

**This is cheaper than it looks.** The phrase bank already carries a qualitative
variant of every claim family: "heart stayed lively", "body went almost fully
still", "body mostly settled", "breath stayed at its own pace", "your stillest
session yet". Add a `numbers: Bool = true` parameter to `verdict(...)` and route
the numeric branches to their existing qualitative siblings. No new copy.

`hrReading` / `stillnessReading` / `breathReading` (lines 127 to 155) are
entirely numeric and simply do not render when locked.

### `Coherence/Session/ShareCard.swift`

Two changes. The card takes an `Entitlements`, and gains a `CardSkin`.

- Free: score ring, verdict line, streak, Midnight skin, and a dashed
  placeholder where the curves belong reading "Your curves go here".
- **The metrics must stay hidden on the free card.** If a free user could post
  a card carrying their curves, screenshotting their own card becomes the way
  around the in-app lock.
- Skins: `midnight` (free), `goldLeaf`, `still`, `ember`. Skins change the card
  gradient only. They must not change what data appears, or a skin becomes a
  second entitlement axis by accident.

### Home

The sparkline is a trend, so it locks. Replace with the same locked treatment,
tapping through to `UnlockSheet(signal: .trend)`. Streak, calendar and evidence
rows stay free; `EvidenceRow` already shows a score and nothing else, so it
needs no change at all.

### Sound picker

The guided journey row shows a lock and presents the paywall instead of
selecting. Nature, frequency and silence are untouched.

---

## The ladder, and a defect in it

`Coherence/Onboarding/PaywallLadder.swift` already exists (commit `29efb71`,
2026-08-18) and is wired into `PaywallScreen` at line 311. Three rungs:
`trial` → `firstMonthHalf` → `yearReframe`.

**Keep it. The free tier becomes the terminal rung**, replacing today's
`onDone(false)` when `current.next == nil`. So the full descent is:

```
prices → free week → half first month → year reframe → Free 808 screen → free
```

The Free 808 screen is screen 02 in the mockup: what you keep beside what stays
locked, one locked panel underneath, "Start 7 days free" as the primary and
"Continue with free 808" as a quiet secondary.

### The defect, verified

**The `firstMonthHalf` rung promises a discount the purchase will not apply.**

`DownsellSheet`'s take closure sets `plan = current.plan` and calls `advance()`,
which calls `store.purchase(plan)`. Both `trial` and `firstMonthHalf` return
`.monthly` (PaywallLadder.swift, `var plan`). A product carries exactly one
introductory offer, and `808.storekit` gives
`com.lockout.meditate808.monthly` a **free one-week** intro, not a 50% first
month. So a user who declines the free week, reads "Half off your first month,
then $4.99 a month", and taps "Take half off" gets the free week instead. The
copy and the purchase sheet disagree.

No production products exist yet, so the `.storekit` file is the only
configuration there is and this has never been seen by a user. Three ways out:

1. **Drop the rung.** Simplest. The ladder still has three steps with the free
   tier as terminal.
2. **Re-point it at a second product** in the same subscription group carrying
   the half-off intro. Works, and the user stays intro-eligible after declining,
   but it burns a permanent product ID and needs the Organization account.
3. **Reword it** to sell something the monthly product actually offers.

Recommendation is 1 until billing is live, because product IDs are permanent and
this one would exist only to serve a downsell we have not tested.

Related and smaller: `SubscriptionPlan.price` hardcodes `$4.99 / $29.99 /
$49.99` while `808.storekit` uses `5.00 / 30.00 / 50.00`. Harmless today because
`PaywallScreen` prefers Apple's `displayPrice` whenever a product exists, but
the two should be reconciled so design reviews and the simulator agree.

### Trial length

**Seven days everywhere.** The 14 day rung considered on 2026-08-24 was dropped
the same day. One trial length means one intro offer per product and the
existing subscription group works untouched, with no second product to create.

The trial renews into **Monthly**, so Monthly is preselected and every footnote
offering the trial reads "Then $5 a month. Renews automatically. Cancel any time
in Settings." Yearly and Lifetime stay available to anyone who picks them.

*Known trade, accepted:* renewing into monthly gets more trial starts than an
annual default and is worth materially less per user over a year, because it
puts a churn decision in front of them every thirty days. Expect the monthly
churn number to look worse than an annual default would have shown, and do not
read that as the product failing. The free tier catches everyone who lapses, and
they keep using the app and keep sharing cards.

---

## Analytics

`paywall_dismissed` exists in the enum and is still never fired. It has to be,
now that dismissing is a real path rather than a dead end.

Three new events:

| Event | Properties | Question it answers |
|---|---|---|
| `free_tier_entered` | `after_rung` | How far down the ladder people go before settling |
| `locked_metric_tapped` | `signal` | Which locked thing actually sells. My guess is heart rate; worth measuring |
| `skin_locked_tapped` | `skin` | Whether cosmetics convert at all, which decides if skins become a line |

`durationBand` / `streakBand` conventions apply: bands only, no free text, and
**never a biometric**, banded or otherwise. `locked_metric_tapped` carries the
signal's NAME, never its value.

---

## Tests

- `Entitlements` returns paid for `.loading` and `.unavailable`, free only for
  `.ready && !entitled`. This is the inversion that protects the beta and every
  offline payer, so it gets a test of its own.
- The numberless verdict contains no digits, for every claim family, across a
  strong session and a weak one.
- The ladder terminates at the free tier and no rung repeats. Extends the
  existing `PaywallLadderTests`.
- The free share card renders no metric values. Guards the screenshot loophole.
- A locked graph card renders no curve path.

---

## App Review notes

- The paywall keeps its Privacy Policy and Terms of Use links (3.1.2). Nothing
  about the free tier changes that requirement.
- The way out of the paywall must stay plainly visible and plainly worded. It
  does today, at every rung, and the free tier makes that easier rather than
  harder.
- The free tier removes one existing exposure: 5.1.1(v) reasoning about
  registration and purchase gets simpler when the app is usable without either.
- Locked states must not look like errors or like a bug. A gold Locked pill and
  a plain sentence, never a broken-looking empty chart.

---

## Open

- **Skins need artwork.** Three gradients are specified in the mockup and that
  is all they are. If skins become a real line, they deserve better than a
  gradient swap.
- **The 5.1.3 store split means paid users on a second device see no stats**,
  because `MeditationStats` is device-local by design. A user who pays for
  curves and then opens 808 on a new phone sees the existing explanation card.
  That was defensible when everything was paid. It is sharper now that curves
  are the thing being sold, and it sits on top of the unresolved fact that
  CloudKit has never demonstrably synced.

---

## Decided during implementation

Six things moved between the spec and the build. All are in the code with the
reasoning beside them.

**The resonance chip stayed FREE.** The spec locked it with the tiles. It
carries no number, it says "Resonance reached", and it explains why the score is
what it is. That makes it part of the verdict, not part of the evidence, and the
boundary is cleaner for it: free 808 gives the score AND the plain-language
reason, and withholds every measured quantity.

**Skins are the five card layouts that already existed.** `ShareCardStyle`
(`.full`, `.score`, `.verdict`, `.words`, `.receipt`) was already built and
pagered. No parallel gradient system was invented. Free posts `.score`, which
carries the number, the minutes and the streak and no measured values; the other
four are locked, and `.full` and `.receipt` MUST stay locked because they draw
curves and metric values.

**Sharing is never blocked and the locked cards still render in the pager.** The
user swipes onto a card they cannot post, sees it, and gets one button. The want
is specific because the card is theirs.

**The Locked pill is not gold.** The first build made it gold and the results
screen ended up carrying seven gold objects against a rule of one per section. A
lock is neither chosen nor achieved, so it is neutral. Gold on a free results
screen is the score ring and the unlock button.

**The share button steps down to secondary when the screen is locked.** Two gold
buttons stacked read as a form and the user picks neither. Sharing did not become
less important; the screen may only hold one gold call to action, and on a
locked results screen that has to be the unlock.

**`SIMCTL_CHILD_PREVIEW_FREE=1` forces the free tier.** Without it the locked
screens are unreachable on a simulator, because no products load, the store
reports `.unavailable`, and everyone is correctly treated as paid. Five
onboarding screens once shipped without anyone looking at them.

### Verified on the simulator

Locked results screen, the numberless verdict ("Heart settled, breath slowed and
held there, body went almost fully still."), all three locked graph cards, the
locked tiles, the unlock sheet naming the specific signal, and the chain through
to the plans screen.

**The home sparkline lock was REVERSED on-device (Aziz, 2026-08-24).** The
line draws overall scores, and every history row already shows each session's
score to a free user, so the lock was withholding arithmetic on free numbers,
not evidence. The rule is unharmed: the score is free, the measurements behind
it are not, and the sparkline draws scores. `Entitlements.trend`,
`LockedSignal.trend` and the home unlock route are deleted.

**The review build simulates the purchase.** With `Store.previewFreeByDefault`
on, no products exist, so the buy button could not run StoreKit and the
lock → trial → unlock loop was unreviewable. The paywall's CTA now grants
`previewEntitled` (persisted, like a real purchase), every lock opens on the
spot, and Settings > "Free tier (debug)" switches back to free. DEBUG-only,
compiled out of Release. The same switch reveals the paywall's "Not right now"
entry, because a build made to review the free tier must be able to reach it.
Monthly is also now preselected on the paywall, since the trial renews into it.

### Still owed

- The onboarding paywall's own visual pass with `PREVIEW_DOWNSELL=1`, so the
  `FreeTierScreen` is looked at rather than assumed.
- App Privacy labels and the three new analytics events reviewed together before
  the next submission, since the manifest changing re-enters Beta App Review.
