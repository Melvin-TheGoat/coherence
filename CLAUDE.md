# CLAUDE.md

## Product

**Coherence** is a heart-coherence meditation app for iPhone + Apple Watch.

The product stance: **coherence as evidence, not a training score.** During a
guided (or silent/frequency/nature) meditation the Apple Watch records
beat-to-beat heart data; afterward the phone computes an FFT-based coherence
score targeting the ~0.1 Hz peak and shows the coherence *trajectory* over the
session. The number is real biometric evidence of what happened in the body —
not a gamified target to chase. The mid-session screen deliberately shows **no
live biometrics**; evidence comes after, not during.

Stack: Swift / SwiftUI / SwiftData / HealthKit. Project defined via **XcodeGen**
(`project.yml` → `xcodegen generate` → `Coherence.xcodeproj`). Development is
done by pasting phase instructions into Claude Code in a terminal (no IDE
integration). The full plan lives in `App_ROADMAP_v2.md`.

## Toolchain notes (this machine)

- XcodeGen is installed at `~/.local/bin/xcodegen` (resources in
  `~/.local/share/xcodegen`) — Homebrew is not present. `~/.local/bin` is on PATH.
- No iPhone 15 simulator exists here; use **iPhone 17** as the iOS Simulator
  destination in `xcodebuild` commands.
- Regenerate the project after any `project.yml` change: `xcodegen generate`.

## Architecture decisions (baked in — do not relitigate)

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
  (plus its Preferences), so `Session.userID` is never nil. First Sign in with
  Apple **adopts** that row (fills in appleUserID/email/displayName) rather than
  creating a second User — pre-account test sessions (and the streak derived from
  them) survive into the real account. Never create a second User while
  `appleUserID == ""`.
- **Timed sessions are clocked by the Watch** (it fires the authoritative
  end-haptic). The phone runs a parallel timer only to stop audio. Open-ended
  sessions end from a Watch button.
- **Coherence is analyzed with overlapping sliding windows.** A 60 s window is
  needed to resolve the ~0.1 Hz peak, but non-overlapping windows would give one
  point per minute. The window advances by a small `hopSec` (5 s) instead,
  producing a smooth trajectory (~109 points for a 10-minute session). `windowSec`
  and `hopSec` are both stored on every result so old sessions stay interpretable
  if the parameters change.

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

## Schema (6 SwiftData models, `Shared/Models/`)

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
  A *reference* to the HealthKit sample; we never store raw biometrics.
- **MeditationStats** — id, sessionID?, coherenceScore? (nil=too short),
  coherenceTimeseries[], hrvTimeseries[], heartRateTimeseries[], windowSec (60),
  hopSec (5), meanHR, rmssd, peakFrequencyHz?, algorithmVersion, createdAt.
  **Immutable.** The three timeseries share one windowSec/hopSec and one index and
  are always the same length. Point i's timestamp = `session.startedAt + i*hopSec
  + windowSec/2` (window center).

**Streak is not stored.** It is derived at read time via `StreakCalculator`
(`Shared/Engine/StreakCalculator.swift`, pure Foundation) over the user's
Session `startedAt` dates — Sessions are the single source of truth.

Enums (`Shared/Models/Enums.swift`): Theme (system/light/dark), TrackType
(guided/frequency/nature), SessionMode (guided/frequency/nature/silence).

## Session-end sequence

1. Watch `end()`: finish `HKLiveWorkoutBuilder`, query the recorded
   `HKHeartbeatSeriesSample`, convert per-beat timestamps to RR intervals (sec),
   capture the sample UUID and beat count → `CapturedSeries`.
2. Watch runs `CoherenceEngine.analyze(rrIntervals:windowSec:hopSec:)`.
3. Watch assembles a `SessionPayload` (actual elapsed duration; `discard=true` if
   elapsed < 60 s) and sends it to the phone via `transferUserInfo`.
4. Phone, in ONE ModelContext transaction: if not discarded, insert Session +
   HeartbeatSeries + MeditationStats. No streak write — the streak is derived
   at read time from Session dates via `StreakCalculator`.

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
- **Uniqueness enforced in code:** one Stats per session, one User per
  appleUserID, one bootstrap User while appleUserID is "".

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
