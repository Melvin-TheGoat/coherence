# CLAUDE.md

## Product

**Coherence** is a guided-meditation app for iPhone + Apple Watch that gives the
user **biometric evidence their practice landed** — measured on the Watch,
shown *after* the session, never as a live score to chase.

The product stance: **evidence, not a training score.** The mid-session screen
deliberately shows **no live biometrics**; evidence comes after, not during.

**The evidence is three motion/heart signals** (not heart coherence — see below):

1. **Stillness** — how physically still the body was, from the Watch
   accelerometer (`CMDeviceMotion.userAcceleration` magnitude / jerk). Low motion
   = deeper settling. Output: a stillness curve + a stillness score.
2. **Heart-rate deceleration** — the downward drift of heart rate as the user
   relaxes, from the ~5 s averaged HR stream (fine for a *trend*; we don't need
   beat-to-beat). Output: an HR curve + a decline metric (start→end / slope).
3. **Belly breathing** (optional, the headline feature) — when the user opts in,
   lies down, and rests the watch wrist flat on the belly, diaphragmatic
   breathing tilts the wrist. From `CMDeviceMotion.attitude` (gravity-tilt pitch)
   we recover the breathing waveform → rate, depth, regularity, and a
   **resonance-match** score vs ~6 breaths/min (0.1 Hz). Motion sensors run at
   tens of Hz, wildly above what breathing needs.

A session combines these into one "your practice landed" summary. **Belly
breathing is opt-in**; most users do a **Regular** session (2 signals: stillness
+ HR). Belly sessions add the third. See the Schema and Session-end sections.

Stack: Swift / SwiftUI / SwiftData / HealthKit / **CoreMotion**. Project defined
via **XcodeGen** (`project.yml` → `xcodegen generate` → `Coherence.xcodeproj`).
Development is done by pasting phase instructions into Claude Code in a terminal
(no IDE integration). The full plan lives in `App_ROADMAP_v2.md`.

**Product name is `808`** (Aziz + Melvin's rebrand, 2026-07-20) — the user-facing
name only: `CFBundleDisplayName`, the in-app titles (iPhone + Watch), and the
Health permission prompts all read **808**. The **internal Xcode targets, folders,
module, and bundle IDs stay `Coherence` / `com.lockout.coherence`** — Swift forbids
a module/type name starting with a digit, and renaming the targets would be
invisible to users while creating a large merge for Melvin, so it was deliberately
NOT done. "Rename the app" = change the display name, not the project.

## Why not heart coherence (do not relitigate)

The original plan was HeartMath-style **heart coherence** — the ~0.1 Hz peak in
beat-to-beat HRV. **It is not achievable on Apple Watch for a third-party app**,
verified on-device (Phase 2) and in research:

- A third-party `.mindAndBody` `HKWorkoutSession` records **averaged HR only**
  (~5 s cadence), **not** an `HKHeartbeatSeriesSample`. No beat-to-beat / RR.
- Coherence needs RR sampled fast enough to resolve 0.1 Hz. By Nyquist you need
  >0.2 Hz just to *detect* it, several× that to characterize it; the watch's
  usable stream tops out ~0.2 Hz. Right at the floor — can't reconstruct the peak.
- Every workaround dead-ends: Mindful/Breathe series is real RR but capped at
  5 min; ECG is a 30-s finger-on-crown snapshot; SensorKit raw PPG is
  research-only; camera PPG can't run long (torch heat/battery/finger-on-lens).
- True coherence remains possible only with an **external BLE HRV sensor** (Polar
  H10 / HeartMath-style ear clip, RR over CoreBluetooth) — parked as a future
  "Pro" tier, not v1.

So we measure resonance breathing **directly via motion** instead of inferring it
from the heart. Backed by peer-reviewed work: Bernardi et al. 2020 (*Sci Rep* —
wrist-accelerometer respiration, MAE ~0.7–1.1 breaths/min, best during
non-activity); Hung 2020 (*Front Physiol* — abdomen placement, best supine);
Steffen 2017 / Shaffer & Meehan 2020 / Laborde 2022 (resonance breathing
~4.5–7 breaths/min); Kox/Kirk 2015 (meditation lowers HR). Full citations in
`belly-meditation-spec.md`.

## Belly breathing — VERIFIED on-device (Phase 2, tag `phase2-motion-verified`)

The core assumption holds: **`CMDeviceMotion` gravity-tilt pitch recovers a clean
breathing waveform from the wrist resting on the belly.** Confirmed on real
hardware — both slow held breaths (~2/min) and resonance pace (~5/min) were
recovered, and the breaths are literally countable in the raw pitch series.

**Placement is decisive** (matches Hung 2020): the watch wrist must lie **flat on
top of the belly**, supine. Wrist on the *side* of the belly / hands interlocked
produced **no readable signal** — and the weak-signal fallback correctly refused
to invent a number rather than guessing. Bad placement is a real failure mode; the
UI must coach it, and the 2-signal degrade path must stay.

**Constraints the Phase-3 engine must honor** (learned the hard way, don't repeat):

- **Rate estimation must be continuous, not integer-crossing.** Counting
  zero-crossings quantizes the rate to `60/windowSec` (2 breaths/min at a 30 s
  window), so it can only ever emit even numbers — it can *never* report 5/min
  even when the user is breathing at exactly 5. Use **FFT + parabolic peak
  interpolation** (or averaged peak-to-peak intervals) for fractional rates.
- **Frequency-domain estimation is shape-agnostic** — a 15 s breath-hold flattens
  the top of the wave but leaves the period unchanged, so the fundamental is still
  the correct rate. Don't special-case holds.
- **Support slow held breaths (~2/min ≈ 0.033 Hz)** — below the nominal 0.05 Hz
  (3/min) band-pass floor. Widen the low cutoff or the rate is thrown away.
- **Trim the first/last ~5 s.** Lying down after Start and getting up before End
  are large transients that otherwise dominate both the analysis and the y-axis.
- **Two-stage movement rejection.** A median filter (~0.45 s) kills *impulse*
  spikes, but **sustained** arm movement (reaching for a phone) is too wide for it
  and reads as a bogus fast rate. Gate on **`userAccel`** — the same signal that
  feeds stillness — and exclude high-motion windows.

## Progress (built + tested)

- **Phases 0–2 done.** Phase 2 belly-breathing verified on-device (above).
- **Phase 3 done** — `SignalEngine` (`Shared/Engine/SignalEngine.swift`), pure
  Foundation. Stillness / HR-decline / belly-breathing metrics with **continuous
  fractional rate** estimation (band-limited DFT scan, *not* integer zero-crossing),
  a breathing band widened to **0.033–0.5 Hz** so ~2/min held breaths survive, two
  stillness methods (`total` vs breathing-band-excluded), and the weak-signal
  fallback. 10 synthetic-signal unit tests.
- **Phase 4 backbone done** — the Codable transfer contract (`SessionParams` /
  `SessionPayload` in `Shared/Connectivity/`; `SignalResult` is Codable) and iOS
  persistence (`SessionStore` in `Shared/Session/`: bootstrap-User fetch-or-create,
  one-transaction idempotent Session+Stats write, streak-date read). 11 tests
  (5 streak + 6 persistence), in-memory store.
- **Phase 4 device-wiring DONE — VERIFIED end-to-end on-device (Regular + Belly).**
  WCSession both sides (`WatchSessionManager`, `Coherence/Session/SessionCoordinator`),
  `startWatchApp` launch, the Watch rewired to receive `SessionParams` → run the
  workout + motion → `SignalEngine` → ship `SessionPayload` → iOS persists via
  `SessionStore`. Temp iOS Begin-Regular/Belly buttons. Params delivered over three
  channels (message / user-info / applicationContext) deduped by sessionID.
  - **Regular sessions VERIFIED end-to-end** on the phone: a still session scored
    stillness ~0.86, `hrDecline +8.8` (HR settled), `overall ~0.74`; a fidgety one
    scored ~0.22 with `hrDecline −20` — the engine clearly discriminates settling
    from motion. `durationSec` is wall-clock; motion now shares the HR clock.
  - **Liveness insight (worth building in):** "good stillness + HR sensed the whole
    session" defeats the take-the-watch-off cheat, since a removed watch loses HR.
  - **Belly breathing: axis fix CONFIRMED on-device ✅.** Real palm-on-belly places
    the breathing tilt in **roll or a pitch+roll mix**, but the engine read **pitch
    only** → rejected → 2-signal fallback (Melvin's diagnosis via `bellyDiagnostics`
    + the `principalComponent` helper). Fix (Aziz): breathing is now read from the
    **PCA principal axis of (pitch, roll)** — placement-tolerant, and it *raises*
    concentration by recombining a split signal, so the 0.30 gate was left as-is.
    Verified: synthetic `test_breathingInRoll` / `test_breathingDiagonalAxis` read
    6/min where pitch-only returned nil (all pitch tests still pass), **and a real
    palm-on-belly session on-device now returns a real breathing rate.**
  - Tagged `phase4-pipeline-verified` — Regular + Belly both verified end-to-end.
  - **Belly axis selection — now by CONCENTRATION, not PCA variance (CONFIRMED
    on-device ✅).** PCA maximizes *variance*, so a large low-concentration sway on
    one axis captured the principal axis and buried a clean breathing peak on the
    other → intermittent `nil` (the "shakiness"). The engine now scores pitch, roll,
    AND their PCA axis and reads from the **cleanest peak** clearing the amp floor
    (`selectBreathingAxis`); `bellyDiagnostics` computes axes the same way (band-pass
    → PCA) and marks the chosen one `←reads`. Regression test
    `test_cleanRollUnderNoisyPitch_selectsRollAxis`; 33 tests pass. On-device: a
    reclined 2-min session read all three axes ~5.5–5.7/min (`breaths 5.6`).
  - **Posture is the real lever (matches Hung 2020 supine).** A **seated** belly
    session mis-reads: postural sway lands on an axis as a clean ~4/min oscillation
    the engine can't distinguish from a slow breath, so it can win over the true
    ~6/min breath on another axis. **Reclined/supine, watch flat on belly** reads
    accurately. Concentration selection can't fix seated — that's physics; the setup
    screen must coach posture. **TODO (product): a dedicated seated belly mode** —
    Aziz wants an option for people who sit up to breathe; needs its own approach
    (tighter stillness gating / calibration), not just the current path.
- **Phase 5 STARTED, then DEFERRED.** Track seeding is done (`TrackSeeder`,
  `Shared/Session/`, 3 tests). The rest of Phase 5 — setup hierarchy, **audio**,
  haptics, mid-session screen — is **deferred** (resequenced 2026-07-19): nail the
  biometric data first. See the RESEQUENCED notes in `App_ROADMAP_v2.md`.
- **Phase 6 (in progress) — the biometric-evidence graphs + logged history.**
  - **Post-session results screen DONE** (`Coherence/Session/SessionResultsView.swift`):
    HR-settling / stillness / belly-breathing curves + summary tiles, read from
    `MeditationStats` by sessionID. `SessionEvidence` (`Shared/Session/`) builds the
    plottable series (window-center timestamps); 4 tests.
  - **History + calendar DONE.** `SessionCalendar` (`Shared/Session/`, pure
    Foundation: practiced-day set + 6×7 month grid, 5 tests). Two screens, split by
    Aziz's request into separate home buttons:
    - **Calendar** (`SessionHistoryView`) — streak (current/longest via
      `StreakCalculator`) + total sessions + a month calendar dotted on practiced
      days. Tapping a practiced day pushes that day's sessions (`DaySessionsView`).
    - **History** (`AllSessionsView`) — the full session log, newest first.
    Both lists share `SessionRow` and navigate to `SessionResultsView` by ID; all
    read storage independently via `@Query` (refresh live when a payload lands).
  - Temp "Begin Regular/Belly" buttons + Calendar/History buttons are the current
    home screen; the real setup hierarchy replaces them later.
- **Recent fixes.** Belly payload was silently dropped (a non-finite Double made
  `JSONEncoder` throw; `SignalEngine.sanitized()` now guarantees finite output and
  the Watch send logs encode errors). Stale application context replayed a finished
  session on cold Watch launch (the phone now clears it on payload receipt).
- **Recent fixes.** Belly payload was silently dropped (a non-finite Double made
  `JSONEncoder` throw; `SignalEngine.sanitized()` now guarantees finite output and
  the Watch send logs encode errors). Stale application context replayed a finished
  session on cold Watch launch (the phone now clears it on payload receipt).

## Toolchain notes (this machine)

- XcodeGen location differs per machine — resolve it with `which xcodegen`
  before invoking, don't hardcode a path:
  - On Melvin's machine it's installed via **Homebrew** at `/opt/homebrew/bin/xcodegen`.
  - On Aziz's (cofounder) machine Homebrew is **not** present; XcodeGen lives at
    `~/.local/bin/xcodegen` (resources in `~/.local/share/xcodegen`), and
    `~/.local/bin` is on PATH.
- No iPhone 15 simulator exists here; use **iPhone 17** as the iOS Simulator
  destination in `xcodebuild` commands.
- Regenerate the project after any `project.yml` change: `xcodegen generate`.
- **Close Xcode before `xcodegen generate`** (or reopen the project after) — regen
  while it's open yields "the active scheme has no targets."
- **Signing is per-developer and LOCAL (never committed).** The repo commits
  `DEVELOPMENT_TEAM: ""` and `com.lockout.coherence`. But the two cofounders have
  **separate individual Apple Developer accounts**, and one bundle ID can't be
  registered to both once HealthKit (an explicit App-ID capability) is enabled — so
  each dev sets their own `DEVELOPMENT_TEAM` **and** a unique bundle-ID prefix in
  their own uncommitted `project.yml` (+ the Watch `WKCompanionAppBundleIdentifier`
  in `CoherenceWatch/Info.plist`). Aziz's local values: team `H5ZH6P56Q8`, IDs
  `com.azizmahmud.808*`. Keep these out of commits. Proper fix later: an Org account.

## Architecture decisions (baked in — do not relitigate)

- **The phone is the only persistence layer.** SwiftData lives on iOS. The Watch
  holds **no** store; it captures motion + heart data, computes stats, and ships
  the result to the phone over WatchConnectivity. The phone performs every write.
  "One writer per object" is a *logical* rule: the Watch is the logical author of
  session data; the physical write happens on the phone when the payload lands.
- **Phone-triggered start = `HKHealthStore.startWatchApp(with:)`.** You cannot
  launch a watchOS app from the phone via WatchConnectivity. Therefore the iOS
  target carries the HealthKit entitlement + usage strings **only** to issue the
  launch command — it reads zero biometric data. All sensor/analysis *logic* is
  on the Watch.
- **Foreign keys are plain `UUID?` properties, not SwiftData `@Relationship`.**
  Honors "screens read independently" and avoids CloudKit relationship-optionality
  constraints.
- **CloudKit-safe modeling from day one, CloudKit enabled in Phase 7.** Every
  stored property is optional or defaulted; no `@Attribute(.unique)`; no
  non-optional relationships. Uniqueness is enforced in code, never in schema.
  Phases 0–6 run on a **local** store (`Persistence.local()`, `cloudKitDatabase:.none`)
  under free provisioning; Phase 7 flips `CoherenceApp` to `Persistence.cloudKit()`
  — a one-line change because the models were already compatible.
- **Auth is Sign in with Apple only (v1).** No passwords, no Google. This removes
  `auth_provider`, `provider_user_id`, `password_hash`, `email_verified` from
  User and eliminates cross-provider account collision. Re-addable later.
- **Pre-account users.** Accounts don't exist until Phase 7. From Phase 4 the app
  creates a single local **bootstrap** User on first launch with `appleUserID == ""`
  (plus its Preferences), so `Session.userID` is never nil. First Sign in with
  Apple **adopts** that row (fills in appleUserID/email/displayName) rather than
  creating a second User — pre-account test sessions (and the streak derived from
  them) survive into the real account. Never create a second User while
  `appleUserID == ""`.
- **Timed sessions are clocked by the Watch** (it fires the authoritative
  end-haptic). The phone runs a parallel timer only to stop audio. Open-ended
  sessions end from a Watch button.
- **Signals are analyzed with overlapping sliding windows.** Each per-window
  metric (breathing rate, stillness, HR) is computed on a `windowSec` window that
  advances by a small `hopSec` (5 s), producing smooth curves instead of one
  point per minute. The three resampled timeseries share one `windowSec`, one
  `hopSec`, and one index/length. Both values are stored on every result so old
  sessions stay interpretable if the parameters change. (`windowSec` default 30 s
  — long enough to estimate a slow breathing rate; there is no longer a 60 s
  coherence constraint.)

**HARD GATE:** Phase 0 runs on a free Apple ID with a local store. Phase 1 onward
requires the paid Apple Developer Program ($99/yr) — HealthKit on device,
CloudKit, and Sign in with Apple are unavailable under free provisioning.

## Bundle IDs

- iOS app: `com.lockout.coherence`
- Watch app: `com.lockout.coherence.watchkitapp`
- iCloud container (Phase 7): `iCloud.com.lockout.coherence`

## Entitlements timeline

Phase 0 entitlements files are empty (`<dict/>`). Add later:

- **Phase 1** (both targets): `com.apple.developer.healthkit` = true
- **Phase 7** (iOS): `com.apple.developer.applesignin` = ["Default"];
  `com.apple.developer.icloud-container-identifiers` = ["iCloud.com.lockout.coherence"];
  `com.apple.developer.icloud-services` = ["CloudKit"]; `aps-environment` = "development"

**Info.plist usage strings:** the Watch needs `NSMotionUsageDescription`
(CoreMotion drives stillness + belly-breathing) alongside the HealthKit strings.
**HealthKit scope is minimal:** the Watch requests heart-rate **READ** + workout
**SHARE** only — no HRV/heartbeat-series read (those were for the dropped
coherence path).

## Schema (5 SwiftData models, `Shared/Models/`)

All properties optional or defaulted; enums stored as String with computed
accessors; FKs as plain `UUID?`.

- **User** — id, appleUserID (""=bootstrap), email?, displayName?, marketingOptIn,
  createdAt, updatedAt, deletedAt?
- **Preferences** — id, userID?, onboardingComplete, defaultDurationSec? (nil=open-ended),
  remindersEnabled, reminderTime?, theme, hapticsEnabled, createdAt, updatedAt
- **MeditationTrack** — id, type (guided/frequency/nature), title, trackDescription?,
  audioURL, durationSec?, sortOrder, isActive, createdAt, updatedAt
- **Session** — id, userID?, trackID? (nil=silence), mode, **bellyBreathing (Bool,
  default false)**, startedAt, durationSec, createdAt. **Immutable — no updatedAt.**
  `bellyBreathing` is captured at setup and is authoritative for which signals a
  reader expects and which stillness method was used.
- **MeditationStats** — id, sessionID?, **immutable**. Fields:
  - HR: `heartRateTimeseries[]`, `meanHR`, `startHR?`, `endHR?`, `hrDecline?`
  - Stillness: `stillnessTimeseries[]`, `stillnessScore?`, `stillnessMethod`
    (String: `"total"` for regular, `"breathingExcluded"` for belly)
  - Breathing (belly only; empty/nil otherwise): `breathingRateTimeseries[]`,
    `breathDepthTimeseries[]`, `meanBreathingRate?`, `breathingRegularity?`,
    `resonanceMatchScore?`
  - Summary: `overallScore?` (the combined "practice landed" number)
  - `windowSec` (30), `hopSec` (5), `algorithmVersion`, `createdAt`
  The resampled timeseries (HR, stillness, breathing-rate) share one
  windowSec/hopSec and one index and are the same length. Point i's timestamp =
  `session.startedAt + i*hopSec + windowSec/2` (window center). When a belly
  session's breathing signal can't be read, breathing fields stay empty/nil and
  the session degrades to a 2-signal (Regular) result — see Session-end.

**Streak is not stored.** It is derived at read time via `StreakCalculator`
(`Shared/Engine/StreakCalculator.swift`, pure Foundation) over the user's
Session `startedAt` dates — Sessions are the single source of truth.

Enums (`Shared/Models/Enums.swift`): Theme (system/light/dark), TrackType
(guided/frequency/nature), SessionMode (guided/frequency/nature/silence).
`bellyBreathing` is a separate Bool on Session (orthogonal to audio mode), not a
SessionMode case — a Guided or Silence session can each be belly or regular.

## Session-end sequence

1. During the session the Watch runs an `HKWorkoutSession` (`.mindAndBody`) to
   stay active and stream averaged HR, and captures `CMDeviceMotion` continuously
   (gravity-tilt pitch + userAcceleration, 10–25 Hz).
2. Watch `end()`: finish the workout, assemble the raw capture (motion waveform +
   HR samples), and run
   `SignalEngine.analyze(motion:hr:bellyBreathing:windowSec:hopSec:)`:
   - **Always**: stillness curve + score, HR curve + decline, overall score.
   - **Belly only**: breathing rate/depth/regularity/resonance, and stillness from
     the **breathing-band-excluded** residual (not total motion).
   - **Belly fallback**: if the breathing signal is too weak/absent (bad wrist
     placement), leave breathing fields empty and score stillness the **regular
     (total-motion)** way — the session degrades to a 2-signal result and the UI
     says "we couldn't read your breathing this time."
3. Watch assembles a `SessionPayload` (actual elapsed duration; `bellyBreathing`
   flag; `discard=true` if too short) and sends it via `transferUserInfo`.
4. Phone, in ONE ModelContext transaction: if not discarded, insert Session +
   MeditationStats. No HeartbeatSeries. No streak write — the streak is derived
   at read time from Session dates via `StreakCalculator`.

## Conventions (enforced every phase)

- **Never hardcode a hex value.** Every color routes through `AppColor` /
  `Shared/Assets.xcassets`. Named colors: BackgroundPrimary, BackgroundSecondary,
  AccentGold, TextPrimary, TextSecondary (each with light + dark variants).
- **All sensor / HealthKit / CoreMotion code lives in the Watch target only.**
  The one exception: iOS calls `startWatchApp` to trigger, reading no biometric
  data.
- **The resampled timeseries share one windowSec, one hopSec, one index.** Never
  hardcode either in the UI — read them from the stored MeditationStats row.
- **Read which signals a session has from `Session.bellyBreathing` + populated
  Stats fields.** Regular sessions have 2 signals (stillness + HR); belly
  sessions may have 3, or degrade to 2 if breathing couldn't be read.
- **Screens read storage independently and pass only IDs** (a sessionID or a
  date), never fetched objects. Sessions and Stats are immutable.
- **Uniqueness enforced in code:** one Stats per session, one User per
  appleUserID, one bootstrap User while appleUserID is "".

## Targets & layout

- `Coherence/` — iOS app sources (bundle `com.lockout.coherence`, embeds the Watch)
- `CoherenceWatch/` — watchOS app sources (no ModelContainer)
- `Shared/` — compiled into both apps + the test target: `Models/`, `Engine/`
  (`SignalEngine.swift` — breathing/stillness/HR analysis — plus `StreakCalculator`),
  `Connectivity/` (`SessionPayload.swift` — the Codable Watch↔phone transfer
  contract), `Session/` (`SessionStore.swift` — iOS persistence helpers),
  `Theme/AppColor.swift`, `Persistence.swift`, `Assets.xcassets`
- `CoherenceTests/` — iOS unit tests (host app Coherence)

## Build

```
xcodegen generate
xcodebuild -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme CoherenceWatch -destination 'generic/platform=watchOS Simulator' build
xcodebuild test -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 17'
```
