# CLAUDE.md

## Product

**Coherence** is a heart-coherence meditation app for iPhone + Apple Watch.

The product stance: **coherence as evidence, not a training score.** During a
guided (or silent/frequency/nature) meditation the Apple Watch records the
**heart-rate stream** during a workout session (see the ARCHITECTURE UPDATE
below — this was originally beat-to-beat RR data); afterward the phone computes
an FFT-based coherence score targeting the ~0.1 Hz peak and shows the coherence
*trajectory* over the session. The number is real biometric evidence of what
happened in the body — not a gamified target to chase. The mid-session screen
deliberately shows **no live biometrics**; evidence comes after, not during.

Stack: Swift / SwiftUI / SwiftData / HealthKit. Project defined via **XcodeGen**
(`project.yml` → `xcodegen generate` → `Coherence.xcodeproj`). Development is
done by pasting phase instructions into Claude Code in a terminal (no IDE
integration). The full plan lives in `App_ROADMAP_v2.md`.

### Product copy (marketing / in-app content)

- `SCIENCE.md` — the evidence-based "Science of Coherence" page. Peer-reviewed
  sources only; all citations verified. **Firewall rule:** the science page stays
  strictly peer-reviewed — no HeartMath big claims, no influencers (e.g. Dispenza).
- `PURPOSE.md` — the brand / "why we built this" page (aspirational identity &
  manifestation voice: meditation as a tool to rewrite the subconscious identity
  and ease the friction between the user and their goals). Not a place for
  scientific claims.

## Toolchain notes (this machine)

- XcodeGen is installed at `~/.local/bin/xcodegen` (resources in
  `~/.local/share/xcodegen`) — Homebrew is not present. `~/.local/bin` is on PATH.
- No iPhone 15 simulator exists here; use **iPhone 17** as the iOS Simulator
  destination in `xcodebuild` commands.
- Regenerate the project after any `project.yml` change: `xcodegen generate`.

## Architecture decisions (baked in — do not relitigate)

> **⚠️ ARCHITECTURE UPDATE (2026-07-14) — supersedes the RR-interval design in the
> Session-end sequence & Schema below.**
>
> **Coherence's data source changed from beat-to-beat RR intervals to the Apple Watch
> heart-rate stream.** We confirmed (Apple Developer Forums; Marco Altini / HRV4Training)
> that the Apple Watch does **not** expose continuous beat-to-beat (RR / inter-beat)
> intervals from its optical sensor to third-party apps. During a workout, apps get only
> **averaged heart rate (BPM)** (~every 1–5 s via `HKLiveWorkoutBuilder`) plus sparse HRV
> SDNN. `HKHeartbeatSeriesBuilder` only records beats you *supply* (e.g. from an external
> BLE chest strap), not the optical sensor; true RR appears only during the built-in
> Breathe app, in short bursts we cannot trigger or control.
>
> **Decision — "Option A":** compute coherence from the continuous **heart-rate (BPM) time
> series** the Watch streams during the workout session, not RR intervals. This preserves
> the **Apple-Watch-only, no-extra-hardware** promise. Rejected: external BLE chest strap
> (research-grade but breaks the hardware story) and Breathe-app HRV (too sparse for a
> per-session trajectory). The product stance ("evidence after, not during") is unaffected —
> a slightly coarser post-session trajectory is still real biometric evidence.
>
> **OPEN ITEM — validate on-device in Phase 1:** the actual HR sample rate from
> `HKLiveWorkoutBuilder`. ~1 Hz → resolves the 0.1 Hz peak cleanly; ~5 s → too coarse, will
> need interpolation and/or a wider `windowSec`. The `HeartbeatSeries`/`MeditationStats`
> models and the Session-end sequence below are annotated to reflect Option A; finalize the
> exact field semantics once the sample rate is measured.

- **The phone is the only persistence layer.** SwiftData lives on iOS. The Watch
  holds **no** store; it captures heartbeat data, computes stats, and ships the
  result to the phone over WatchConnectivity. The phone performs every write.
  "One writer per object" is a *logical* rule: the Watch is the logical author of
  heartbeat data; the physical write happens on the phone when the payload lands.
- **Phone-triggered start = `HKHealthStore.startWatchApp(with:)`.** You cannot
  launch a watchOS app from the phone via WatchConnectivity. Therefore the iOS
  target carries the HealthKit entitlement + usage strings **only** to issue the
  launch command — it reads zero biometric data. All heartbeat *logic* is on the
  Watch.
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
  (plus its Preferences + Streak), so `Session.userID`/`Streak.userID` are never
  nil. First Sign in with Apple **adopts** that row (fills in appleUserID/email/
  displayName) rather than creating a second User — pre-account test sessions and
  streak survive into the real account. Never create a second User while
  `appleUserID == ""`.
- **Timed sessions are clocked by the Watch** (it fires the authoritative
  end-haptic). The phone runs a parallel timer only to stop audio. Open-ended
  sessions end from a Watch button.
- **Coherence is analyzed with overlapping sliding windows.** A 60 s window is
  needed to resolve the ~0.1 Hz peak, but non-overlapping windows would give one
  point per minute. The window advances by a small `hopSec` (5 s) instead,
  producing a smooth trajectory (~109 points for a 10-minute session). `windowSec`
  and `hopSec` are both stored on every result so old sessions stay interpretable
  if the parameters change. The analysis **input** is the resampled Watch
  heart-rate stream (per the ARCHITECTURE UPDATE), not RR intervals.

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

## Schema (7 SwiftData models, `Shared/Models/`)

All properties optional or defaulted; enums stored as String with computed
accessors; FKs as plain `UUID?`.

- **User** — id, appleUserID (""=bootstrap), email?, displayName?, marketingOptIn,
  createdAt, updatedAt, deletedAt?
- **Preferences** — id, userID?, onboardingComplete, defaultDurationSec? (nil=open-ended),
  remindersEnabled, reminderTime?, theme, hapticsEnabled, createdAt, updatedAt
- **MeditationTrack** — id, type (guided/frequency/nature), title, trackDescription?,
  audioURL, durationSec?, sortOrder, isActive, createdAt, updatedAt
- **Session** — id, userID?, trackID? (nil=silence), mode, startedAt, durationSec,
  createdAt. **Immutable — no updatedAt.**
- **HeartbeatSeries** — id, sessionID?, healthkitUUID, beatCount, createdAt.
  A *reference* to the source HealthKit workout/sample; we never store raw
  biometrics. (Option A: `healthkitUUID` references the workout and `beatCount`
  becomes the heart-rate sample count — finalize field semantics once the on-device
  sample rate is measured; see the ARCHITECTURE UPDATE.)
- **MeditationStats** — id, sessionID?, coherenceScore? (nil=too short),
  coherenceTimeseries[], hrvTimeseries[], heartRateTimeseries[], windowSec (60),
  hopSec (5), meanHR, rmssd, peakFrequencyHz?, algorithmVersion, createdAt.
  **Immutable.** The three timeseries share one windowSec/hopSec and one index and
  are always the same length. Point i's timestamp = `session.startedAt + i*hopSec
  + windowSec/2` (window center). NOTE (Option A): coherence, `peakFrequencyHz`,
  `heartRateTimeseries` and `meanHR` derive directly from the HR stream. True
  RR-based HRV metrics (`rmssd`, and an RR-derived `hrvTimeseries`) **cannot** be
  computed from BPM samples — under the HR-stream design these are approximated from
  HR-stream variability or deferred (decide in Phase 3). Fields stay in the schema
  for CloudKit stability.
- **Streak** — id, userID?, currentDays, longestDays, lastSessionDate? (local
  day-start), createdAt (immutable), updatedAt

Enums (`Shared/Models/Enums.swift`): Theme (system/light/dark), TrackType
(guided/frequency/nature), SessionMode (guided/frequency/nature/silence).

## Session-end sequence

1. Watch `end()`: finish `HKLiveWorkoutBuilder` and collect the **heart-rate (BPM)
   samples** streamed during the session (the live workout builder's heart-rate
   quantity type), each with its timestamp → `CapturedSeries`. (Superseded: we no
   longer query `HKHeartbeatSeriesSample` or convert to RR intervals — see the
   ARCHITECTURE UPDATE. Apple does not expose optical-sensor RR to third-party apps.)
2. Watch resamples the heart-rate series onto an even time base and runs
   `CoherenceEngine.analyze(heartRateSamples:windowSec:hopSec:)`.
3. Watch assembles a `SessionPayload` (actual elapsed duration; `discard=true` if
   elapsed < 60 s) and sends it to the phone via `transferUserInfo`.
4. Phone, in ONE ModelContext transaction: if not discarded, insert Session +
   HeartbeatSeries + MeditationStats, then update Streak (local-calendar-day
   comparison: same day → no change; +1 day → currentDays += 1; gap → reset to 1;
   longestDays = max(longestDays, currentDays)).

## Conventions (enforced every phase)

- **Never hardcode a hex value.** Every color routes through `AppColor` /
  `Shared/Assets.xcassets`. Named colors: BackgroundPrimary, BackgroundSecondary,
  AccentGold, TextPrimary, TextSecondary (each with light + dark variants).
- **All heartbeat / HealthKit code lives in the Watch target only.** The one
  exception: iOS calls `startWatchApp` to trigger, reading no biometric data.
- **The three timeseries share one windowSec, one hopSec, one index.** Never
  hardcode either in the UI — read them from the stored MeditationStats row.
- **Screens read storage independently and pass only IDs** (a sessionID or a
  date), never fetched objects. Sessions and Stats are immutable.
- **Uniqueness enforced in code:** one Streak per user, one Stats per session, one
  User per appleUserID, one bootstrap User while appleUserID is "".

## Targets & layout

- `Coherence/` — iOS app sources (bundle `com.lockout.coherence`, embeds the Watch)
- `CoherenceWatch/` — watchOS app sources (no ModelContainer)
- `Shared/` — compiled into both apps + the test target: `Models/`, `Engine/`
  (pure-Swift coherence engine, Phase 3), `Theme/AppColor.swift`, `Persistence.swift`,
  `Assets.xcassets`
- `CoherenceTests/` — iOS unit tests (host app Coherence)

## Build

```
xcodegen generate
xcodebuild -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme CoherenceWatch -destination 'generic/platform=watchOS Simulator' build
xcodebuild test -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 17'
```
