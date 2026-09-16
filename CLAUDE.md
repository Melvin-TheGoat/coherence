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
module, and bundle IDs stay `Coherence` / `com.lockout.meditate808`** — Swift forbids
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
from the heart. Backed by peer-reviewed work: **Leube et al. 2020** (*Sci Rep* 10:14530
— wrist-accelerometer respiration, outperforms ECG-derived, 223 subjects); **Hughes,
Liu & Zheng 2020** (*Front Physiol* 11:823 — accelerometer respiration, abdomen
placement, error <2 breaths/min, best supine); resonance breathing ~4.5–7 breaths/min
(Vaschillo 2006, Lehrer & Gevirtz 2014); meditation → elevated theta EEG (Lomas 2015,
Lagopoulos 2009, Aftanas & Golocheikine 2001). **Full verified citations (author, year,
journal, DOI) live in `SCIENCE.md`.** NOTE: earlier notes here misattributed refs 1–2
as "Bernardi 2020" and "Hung 2020" — corrected to Leube and Hughes after verifying the
primary sources (2026-07-20).

## Belly breathing — VERIFIED on-device (Phase 2, tag `phase2-motion-verified`)

The core assumption holds: **`CMDeviceMotion` gravity-tilt pitch recovers a clean
breathing waveform from the wrist resting on the belly.** Confirmed on real
hardware — both slow held breaths (~2/min) and resonance pace (~5/min) were
recovered, and the breaths are literally countable in the raw pitch series.

**Placement is decisive** (matches Hughes et al. 2020): the watch wrist must lie **flat on
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
  - **Posture is the real lever (matches Hughes et al. 2020, supine).** A **seated** belly
    session mis-reads: postural sway lands on an axis as a clean ~4/min oscillation
    the engine can't distinguish from a slow breath, so it can win over the true
    ~6/min breath on another axis. **Reclined/supine, watch flat on belly** reads
    accurately. Concentration selection can't fix seated — that's physics; the setup
    screen must coach posture. **TODO (product): a dedicated seated belly mode** —
    Aziz wants an option for people who sit up to breathe; needs its own approach
    (tighter stillness gating / calibration), not just the current path.
- **Phase 5 (partial) — setup hierarchy STARTED; audio/haptics/mid-session still
  deferred.** Track seeding was done earlier (`TrackSeeder`, `Shared/Session/`, 3
  tests). Now the **pre-session setup screen is built** (`Coherence/Session/
  SessionSetupView.swift`): pick Regular vs Belly, pick a length (2/5/10/15/Open +
  a **typed Custom** field, number-pad, capped 600 min), and — for belly — inline
  **posture coaching** (lie back, watch flat on belly, ~6/min, stay still) grounded
  in Hughes et al. 2020 (supine ≫ seated). Begin triggers the Watch via the
  coordinator (`effectiveMinutes` → `plannedDurationSec`). The home screen's two
  temp Begin buttons are replaced by one **"Begin session"** → this sheet; the
  belly diagnostic box + Calendar/History buttons stay. Haptics + the mid-session
  screen are still deferred. See `App_ROADMAP_v2.md`.
- **Phase 5 — AUDIO started (frequency tones), phone-side synthesis.**
  `Coherence/Audio/ToneEngine.swift` synthesizes all tones at runtime via
  `AVAudioEngine` — **no audio files, no licensing** (this is why frequencies went
  first). `FrequencyCatalog` = 7 MVP presets: 3 brainwave-entrainment states
  (Deep Meditation θ~6 Hz, Calm α~8 Hz, Deep Rest δ~2.5 Hz) + 4 pure "frequency"
  tones (Harmony 432, Manifest 528, Visualize 852, Awaken 963). The **Sound section
  in `SessionSetupView`** lets you pick one + Speaker(isochronic)/Headphones(binaural)
  and **Preview** it. Playback during the live session is NOT wired yet (preview only).
  - **Key facts (don't relitigate):** the *pulse rate* IS the brainwave rate (must
    stay in-band; 6 Hz theta is the best-*demonstrated* entrainment rate per the PLOS
    2023 review); the *carrier pitch* is purely aesthetic (no entrainment effect).
    Pure tones are built from octave-locked layers only (no detuned voices → no
    beating) and skip the delay + octave-up + heavy reverb (those caused a "ring"
    behind 852); entrainment tones keep the detuned pad + delay (pulse masks it).
    Solfeggio tones are labeled tradition-only (subtitles like "natural tuning"), not
    claimed as proven — matches the SCIENCE.md honesty line.
  - **ElevenLabs hybrid — WORKING, all 7 beds in.** AI music (ElevenLabs Music v2,
    commercial license on paid tiers) can't produce an exact frequency, so: Aziz makes
    lush ambient **beds** on ElevenLabs; the `ToneEngine` tones are the **exact frequency
    layer mixed underneath**. Pro sound + honest frequency claim. `FrequencyPreset.bedResource`
    names a bundled bed; `ToneEngine` loops it via `AVAudioPlayer` (streams, low memory)
    alongside the synth engine and mixes at the hardware output. **Every tone has a bed,
    each keyed to its tone** so it doesn't clash (`Coherence/Audio/Beds/*.m4a`):
    Deep Meditation (E), Calm (F#), Deep Rest (C — the *tone* was retuned C#→C to match),
    Manifest (C/528), Harmony (A/432), Visualize (G#/852), Awaken (B/963).
    - **Mix levels** (`mainMixerNode.outputVolume`, bed via `AVAudioPlayer.volume` 0.85):
      isochronic tone 0.6, binaural 0.3 (drier→louder), pure tone 0.4, **high pure tone
      (852/963) 0.22** — the high solfeggio tones ring, so they also lead with the warm
      sub-octave (fundamental gain 0.55 < sub 0.85) and use a drier chain (reverb 20%).
    - **Binaural (headphones) is nearly DRY:** reverb mixes L+R back together, which
      reintroduces a *physical* amplitude throb (Melvin's "annoying back-and-forth") —
      but a real binaural beat is *perceptual*, not physical, so minimal reverb (8%) =
      subtler pulse AND a truer effect; the bed supplies the ambience. Binaural also has
      NO delay. Isochronic (speaker) keeps the delay + big hall (pulse masks it). Pure
      tones: reverb + a low-pass just above the carrier, no delay. (Binaural tone level
      0.22.) **Don't relitigate:** binaural need not be loud/noticeable to work.
    - **Bed import recipe (per bed), scripted:** `scratchpad/process_bed.py` (pure Python,
      `wave`+`audioop`) does: trim first ~6 s (quiet intro) → **pitch-align via
      `ratecv`** to the exact Hz (432 −32¢, 528 +16¢, 852 +44¢, 963 −44¢; entrainment
      beds already on-note) → **gentle block compressor** (reduces crest factor so wavy
      beds reach full loudness without peak-clipping) → **normalize to the Deep Meditation
      bed's RMS** (`ref_rms≈5869` @ int16, peak-safe) → `afconvert` to **AAC m4a** (~6 MB
      vs ~53 MB WAV — never commit raw WAV). xcodegen auto-bundles files under `Coherence/`.
      The 4 pure-tone beds are now the "wavy" versions (gentle undulating pads, still no
      melody/rhythm); the compressor is what lets them match the others' loudness. Prompt
      generations with **"continuous / always present, never dropping to silence"** — a
      too-dynamic take (long silent gaps) can't reach full loudness even compressed.
    - **Live-session playback DONE.** `SessionCoordinator` owns a `ToneEngine`; on Begin
      (after `startWatchApp` succeeds) it plays the chosen tone+bed on the phone while the
      Watch measures. Stops on the parallel timer (timed) or when the payload lands (open;
      `stopAudio()` in `persist`, idempotent). Selecting a sound sets `Session.mode =
      "frequency"`. **Background audio:** iOS Info.plist gains the `audio` UIBackgroundMode
      and the session category is `.playback` (no `mixWithOthers`) so it keeps playing when
      the screen locks mid-meditation. `ToneEngine.stop()` stops the engine before detaching
      nodes (guards a rapid-teardown race).
    - **NATURE section DONE — all 4 in.** Second sound category alongside Frequency:
      looping ambient recordings played on their own (no tone). `NaturePreset` /
      `NatureCatalog` (Coherence/Audio/Nature/`*.m4a`); `ToneEngine.playNature` loops via
      `AVAudioPlayer` at `natureVolume` (**0.15** — nature reads loud, keep it soft).
      **Rain, Ocean, Forest, Campfire** all in, normalized to one file level so they're
      even. Nature sets `Session.mode = "nature"`. The setup Sound picker is **tabbed:
      Silence / Frequency / Nature** — the lit tab shows its options; switching tabs
      auto-selects the first item. `SessionCoordinator.begin(soundID:)` looks up
      FrequencyCatalog first, then NatureCatalog.
    - **Nature import recipe:** `scratchpad/loop_nature.py` — pick the most UNIFORM window
      (min per-second RMS variance → dodges swells/events the SFX generator inserts) →
      **equal-power crossfade the tail into the head** (gapless loop, any clip/cut point) →
      **gentle block compressor** (macro dynamics) → **tanh soft-limiter** (rounds transient
      peaks so peaky sounds like fire crackle reach the same level without clipping — fire
      was ~10 dB quiet otherwise; rain/ocean/forest are near-transparent) → normalize to
      `REF≈2500` (matches peaky rain's peak-safe ceiling) → m4a. Prompt SFX for **steady,
      uniform, no events**.
    - **Still TODO:** persist *which* track played (needs an optional `Session.frequencyID`
      — mode is recorded but not the specific preset); compression pass for the two ~2 dB-
      quiet beds (Manifest, Awaken).
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
  - Home screen is now: **Begin session** (→ `SessionSetupView`), Calendar, History,
    plus the temp belly-diagnostic box. Full setup hierarchy still fills in later.
- **Recent fixes.** Belly payload was silently dropped (a non-finite Double made
  `JSONEncoder` throw; `SignalEngine.sanitized()` now guarantees finite output and
  the Watch send logs encode errors). Stale application context replayed a finished
  session on cold Watch launch (the phone now clears it on payload receipt).
- **Recent fixes.** Belly payload was silently dropped (a non-finite Double made
  `JSONEncoder` throw; `SignalEngine.sanitized()` now guarantees finite output and
  the Watch send logs encode errors). Stale application context replayed a finished
  session on cold Watch launch (the phone now clears it on payload receipt).
- **Phase 7 DONE — accounts, settings, CloudKit (v1 feature-complete).**
  - **Onboarding + Sign in with Apple** (`Coherence/Onboarding/`): full Purpose →
    Science → SIWA. The Purpose/Science pages render the **real bundled
    `PURPOSE.md` / `SCIENCE.md`** via a small `MarkdownView` (single source of
    truth). `RootView` gates the app on `Preferences.onboardingComplete`.
  - **Bootstrap-User adopt** (`SessionStore.signIn`): match existing appleUserID →
    else adopt the bootstrap row (pre-account sessions + streak survive) → else
    create. Reactivates a soft-deleted user on re-sign-in. 4 `AuthAdoptTests`.
  - **Settings** (`Coherence/Settings/SettingsView.swift`): profile (display name,
    product-emails), theme (applied app-wide via `RootView.preferredColorScheme`),
    haptics, default length, daily reminder (`NotificationScheduler`), re-read
    Purpose/Science, sign out, delete account.
  - **Account deletion + purge**: `softDeleteCurrentUser` stamps `deletedAt`;
    `purgeExpired` (run on launch) hard-deletes users soft-deleted >30 days ago +
    all FK'd rows. 5 `AccountLifecycleTests`.
  - **CloudKit ON**: `CoherenceApp` uses `Persistence.cloudKit()` (per-user PRIVATE
    DB sync — since the 5.1.3 split below, of User/Preferences/Track/Session/
    Reflection only, NOT MeditationStats). `cloudKit()` falls back to
    `local()` if the container can't init (simulator / unprovisioned) so it never
    crashes. Entitlements: `icloud-container-identifiers = [iCloud.$(CFBundleIdentifier)]`
    (per-dev, matches the local bundle-ID override), `icloud-services = CloudKit`,
    `aps-environment = development`. **NOT yet verified cross-device** (no second
    device on hand). Marketing-list export still stubbed.
- **Phase 8 (in progress) — polish + launch prep.**
  - **Guided meditation SHIPPED.** Script (`Meditations/NarratorScript.md`, v3,
    ~25 min identity-shift arc) narrated by Donny Baarns (Fiverr, commercial
    license, music included); master at `Coherence/Audio/Guided/guided-identity.m4a`
    (AAC, 25:30). `GuidedPreset`/`GuidedCatalog` in `ToneEngine.swift`; setup sheet
    has a Guided tab (4 sound tabs: Silence/Guided/Frequency/Nature); guided
    selection fixes the session length to the track. `Meditations/` (54 MB: the
    dormant ElevenLabs TTS pipeline + working audio) stays UNTRACKED — don't commit.
    The AI-narration route is retired for guided tracks; don't re-propose it.
  - **Legal drafted (attorney review later, Aziz's call).** ToS: AAA individual
    arbitration + class/jury waiver + 30-day opt-out (§14); anti-recording/ripping
    of app audio (§5/§7). Privacy: WA-MHMDA-style consumer-health-data section.
    Both mirrored in `website/`. OPEN: `[CONTACT EMAIL]`/`[GOVERNING STATE]`
    placeholders, DRAFT banners, hosting.
  - **App Review 5.1.3(ii) store split.** `MeditationStats` lives in a separate
    device-local store (named config `"HealthLocal"`, never CloudKit); everything
    else syncs. Trade-off: health results do NOT roam devices — a synced session
    without local stats shows an explanation card on the results screen.
    Onboarding gained an explicit health-data consent step before sign-in.
  - **Health-stats rescue (the split's aftermath).** The split orphaned pre-split
    stats in `default.store` → every old session read "no results". One-time
    launch rescue (`Persistence.rescueOrphanedHealthStatsIfNeeded` +
    `completeRescue`): copy `default.store` (+WAL sidecars), mount the COPY as the
    HealthLocal side of a production-shaped temp container, pull detached copies,
    dedupe-insert by sessionID; flag `healthStatsRescueDone.v1` set only on
    success. Verified: the split-open does NOT destroy orphaned rows.
    **HARD-WON SWIFTDATA FACT (don't relitigate): entity→store binding is
    process-global.** Every container in a process must use the SAME store
    shape/names for shared entities — a single-config "old layout" container
    throws "store does not contain the object's entity" (this is also why
    `inMemory()` mirrors the split). 4 `HealthRescueTests`.
  - **Session sharing (Strava-style) DONE** (`Coherence/Session/ShareCard.swift`).
    9:16 branded card (360×640 pt, `ImageRenderer` ×3 = 1080×1920, forced dark
    palette), score ring + stat tiles + hero curve + streak flame; share icon +
    button on the results screen → preview sheet. Instagram: NO account
    connection exists or is needed (Strava works the same way). Two paths:
    direct Stories pasteboard handoff (`instagram-stories://share`) — REQUIRES a
    Meta app ID in `InstagramShare.metaAppID`, verified on-device that Instagram
    refuses without one — and the current fallback, save-to-Photos (add-only
    permission) + `instagram://story-camera`, user picks the card from the
    gallery. System `ShareLink` always offered. The button auto-upgrades to the
    direct handoff once `metaAppID` is set. Meta dev registration was
    geo-blocked for Aziz (2026-07-28); plan: Melvin (or a friend) creates the
    Meta app + adds both as admins, then paste the ID.
  - **DEBUG env hooks** (simctl automation: prefix `SIMCTL_CHILD_`):
    `SKIP_ONBOARDING=1`, `PREVIEW_RESULTS=1` (seed + open demo results),
    `PREVIEW_SHARE=1` (auto-open the share sheet), `DEMO_NAME`.
  - 53 tests green.
- **Phase 9 — camera coherence, the no-Watch path (9a/9b/9c DONE, verified
  on-device).** Before/after finger-on-camera PPG snapshots (45 s, torch on)
  scored for heart-rhythm coherence; the differential is the evidence. Does
  NOT relitigate the "no coherence" verdict above — that was *continuous
  in-session*; short snapshots are validated territory (Plews 2017).
  - **9a engine** — `Shared/Engine/CoherenceAnalyzer.swift`, pure Foundation:
    detrend → light smoothing (0.1 s) → **autocorrelation period estimate with
    octave-error (subharmonic) guard** setting the peak-detector refractory to
    0.7×period → parabolic peak timing → intervals filtered vs a **rolling
    5-interval median (±30%)**, NOT vs neighbor → 4 Hz tachogram → Hann + DFT
    scan → coherence = peak/total power (0.04–0.26 Hz band), meanHR, RMSSD,
    validBeatFraction; nil over invention. `diagnose()` returns a per-gate
    verdict string (shown on-screen in DEBUG when a read is refused).
  - **FIELD-CALIBRATED via 4 on-device failure rounds (each is now a
    regression test — don't weaken these):** (1) dicrotic notch double-fired
    the detector → autocorrelation refractory; (2) alternating pulse amplitude
    made the 2-beat lag win the scan (~37 bpm from a 74 bpm heart) →
    subharmonic guard; (3) 30 fps peak-timing jitter shredded intervals under
    neighbor-comparison → rolling-median rule; (4) auto-exposure hunting
    dwarfed the pulse → exposure/WB LOCK during the read. The analyzer is
    testable OFFLINE: `swiftc CoherenceAnalyzer.swift + harness` (pure
    Foundation) — iterate there, not on-device. **First real read on Aziz's
    phone: coherence 35, HR 71, RMSSD 108 ms (sane resting values).** Note:
    camera RMSSD reads high vs chest straps (frame-timing jitter) — fine for
    self-comparison, don't present as absolute.
  - **9b capture** — `Coherence/Session/CoherenceCapture.swift` +
    `CoherenceMeasureView`. FIRST phone-side sensor code (deliberate
    exception). Camera+torch(0.6) live on open (placement mode: live preview
    circle glows red when placed), explicit Start gated on finger detection
    (hysteresis: strict enter/exit — per-frame detection flickers), every
    frame kept for uniform sampling (coverage judged at end), signal NEGATED
    (transillumination: systole = dip), finger-off ~1.5 s → restart to
    placement, exposure locked during read. DEBUG: live r/g/b line + diagnose
    verdict on failure — device debugging without Xcode.
  - **9c flow** — opt-in "Coherence check" toggle in setup (AppStorage);
    Begin → BEFORE read (never blocks: session starts even if read
    fails/cancelled) → coordinator carries snapshot keyed by sessionID →
    persisted with stats; payload lands → AFTER read prompt → results show a
    Heart coherence card (BEFORE → AFTER + gold delta chip). Stats fields
    pre/postCoherence{Score,HR,RMSSD} — device-local; post attach is the one
    sanctioned amendment to the immutable row (write-once, tested).
  - **Watch-timer fixes that came out of testing:** Watch sends a started-ack
    (`WCKeys.started`, "<id>|<epoch>") when the workout truly begins — the
    phone re-anchors its countdown + audio-stop to it (startWatchApp's
    callback fires seconds early; timed sessions used to freeze at 0:00);
    at 0:00 the phone shows "Finishing on your Watch…"; silent startWatchApp
    failure now raises `StartFailure.watchUnreachable` (blocking screen w/
    steps — was invisible); Watch `.sent` no longer swallows new params.
  - **Two session-pipeline bugs found via live device-log debugging (guided
    audio cut out after one word; both verified fixed on-device 2026-08-03):**
    (1) **Cancelled `Task.sleep` fell through to its action.** The audio-stop
    timer was `try? await Task.sleep(...); tone.stop()` — cancelling it (which
    the started-ack re-anchor does ~1 s in) makes the sleep THROW, `try?`
    swallows it, and the stop RUNS immediately. Every `try? await Task.sleep`
    followed by an action needs `guard !Task.isCancelled else { return }`.
    (2) **Stale WC queue flushes sabotaged new sessions.** Launching the watch
    app flushes its queued `transferUserInfo` backlog, so payloads/failures
    from OLD sessions land seconds into a NEW one; `persist`/failure handling
    stopped audio + tore down the live screen unconditionally. Now everything
    destructive matches `currentAttemptID` first (stale payloads still persist,
    silently; startFailure carries "<id>|<failure>"). Same family as the stale
    application-context bug — treat EVERY WC arrival as possibly stale.
    Debugging pattern that cracked it (reusable): `ToneEngine.lastEvent` +
    `stop(reason:)` naming every caller in os_log, an AVAudioSession
    interruption observer (with auto-resume — kept as a feature), and
    `xcrun devicectl device process launch --console` streaming the phone's
    logs to the Mac — the log showed `stop(planned timer)` 0.7 s after
    `play=true`, which named the killer. No Xcode needed.
  - **The camera is not merely a fallback.** A still finger on a lens resolves
    **true beat-to-beat intervals**, so HRV is reachable on this path — which
    the third-party Watch workout stream cannot do at all (see "Why not heart
    coherence"). It is also the only RR source we have short of an external BLE
    strap. Different instrument, better in one respect; don't present it as the
    consolation prize.
  - **OPEN — skin tone + lighting validation. NOT DONE.** PPG is optical and
    melanin absorbs green/red light; published pulse-oximetry work shows worse
    performance on darker skin. Our read is validated on two people. Until it's
    tested across a real range of skin tones we don't know that 808 works
    equally well for everyone — a correctness *and* equity problem. **Blocks
    external TestFlight.**
  - **NOT yet done:** 9d (privacy policy camera wording, SCIENCE.md PPG
    citations), true phone-only sessions (no-Watch timer path), paired-device
    end-to-end pass (Aziz's watch install pending), skin-tone validation.
    *(The duplicate "Phase 9 (PARKED)" section in `App_ROADMAP_v2.md` was
    reconciled 2026-08-03 — one Phase 9 record now, and camera PPG SHIPS in v1.
    Stage 2 work lives in `STAGE2_ROADMAP.md`.)*
- **UI REDESIGN — every screen rebuilt (2026-08-03, `67b9854`).** Design review
  with Aziz produced one visual language; same wiring, same stores, new face.
  Screens: Home, Begin sheet, Evidence, Journey, Settings, mid-session,
  coherence read. 73 tests green. Verified on simulator (light + dark) and
  installed on-device.
  - **COLOR GRAMMAR (hold this everywhere): gold = chosen / achieved, teal
    (`calmAccent`) = the body's signals + guidance.** So: HR curve teal, the
    breathing resonance band teal, stillness + scores + deltas gold; belly
    posture coaching teal, selection states gold. Never both loud in one
    element. Every section shows exactly ONE gold thing, so a screen can be
    audited in a vertical sweep.
  - **`Coherence/DesignKit.swift`** — the shared vocabulary: `ScoreRing`,
    `EvidenceRow` (THE session row, identical on Home and Journey),
    `MetaChip`, `MonthCalendar`, plus `SessionListSupport` (relative day
    titles, metric lines). One way to show a score, one way to show a session.
  - **Home = proof + practice hybrid.** Streak headline → gold sparkline of
    recent overall scores ("Practice score · last N sessions") → live month
    calendar → evidence rows → Begin pinned via `safeAreaInset`. The
    "streak's on the line" nudge shows only on days with no session yet.
  - **Calendar + History merged into `JourneyView`** (same file as the old
    `SessionHistoryView`): stats row incl. total hours, browsable month,
    full log; tapping a dotted day filters the log. `AllSessionsView` /
    `DaySessionsView` / the old `SessionRow` are GONE — don't reintroduce.
  - **Begin sheet, v4**: practice cards state the science ("2 signals" vs
    "3 signals · + breath wave"), length = one chip row (⋯ = custom pad),
    the four sound worlds live in an always-visible 2×2 grid, and the chosen
    category's tracks fill a flex box between the grid and the PINNED
    coherence row + CTA, scrolling internally when they overflow. Belly
    posture is a one-line teal reminder above Begin (full steps behind ⓘ).
  - **`Shared/Engine/VerdictEngine.swift` — the spoken verdict is RULES, not
    AI.** Thresholds over the measured metrics pick true claims from a phrase
    bank ("heart settled 11 beats, breath found the resonance zone…") plus
    per-curve readings ("74 → 63 bpm", "settled by min 3"). Deliberate: it's
    instant, offline, free, App-Review-safe, and can never hallucinate a
    claim the numbers below it don't support. **Rules to keep:** never
    mention breath on a non-belly session; weak sessions get honest coaching,
    never shame. 8 `VerdictEngineTests` lock both.
  - **Charts:** every curve carries real X (session minutes) and Y axes.
    **Never let an `AreaMark` fill from zero on heart rate** — it flattens a
    74→63 settle into a straight line; each signal gets a padded `yDomain`
    (stillness keeps 0–1, breath always includes the 4.5–7 resonance band).
  - **SWIFTUI GOTCHA (cost a QA cycle): stacking several `.sheet` modifiers on
    ONE view is fragile — only one presents.** Home now routes every modal
    through a single `.sheet(item:)` over a `HomeSheet` enum; the AFTER
    coherence read chains into results via `onDismiss`. Do the same anywhere
    a screen needs more than one modal.
- **MVP CUT + ONBOARDING (2026-08-05/06). Work is on the `mvp` branch.**
  `full-feature-set` and tag `v1-full-feature-set` preserve everything removed.
  - **The MVP is one promise: your Watch tracks your meditation and scores it.**
    Melvin cut ~3,000 lines — belly breathing, camera PPG (`CoherenceAnalyzer` /
    `CoherenceCapture` / `CoherenceMeasureView` all deleted), The Method and its
    in-session cues, and the length picker. Every session is open-ended. New
    session is one screen: "Ready when you are", one Begin, and `Open · Silence`
    as a tappable line.
  - **SwiftData properties were deliberately NOT removed.** `Session.bellyBreathing`
    and the breathing/coherence fields on `MeditationStats` stay in the schema and
    still render — dropping stored properties is a migration hazard and old history
    must keep displaying. We just stopped writing them. `SignalEngine`'s breathing
    path and its tests are intact; the Watch always passes `bellyBreathing: false`.
  - **VERIFIED ON HARDWARE (Aziz, 2026-08-05) — the core promise works.** A full
    session ran end to end, and mid-session he left 808 entirely and played a Joe
    Dispenza meditation in another app. It kept tracking; results landed. That's
    "bring your own audio, we measure it" proven on real devices. Melvin's new
    30-second HR watchdog did not false-fire.
  - **Sound SURVIVES, and the sheet was redesigned.** The guided journey leads
    with its own card (art, kicker, runtime) — it's the only original content we
    own. Silence sits under it badged DEFAULT, outside the scroll, subtitled
    "or your own audio". Then three groups, each stating its own ordering:
    nature by familiarity, brainwave **deepest-first** (delta 2.5 → theta 6 →
    alpha 8), tones **low-to-high** (432 → 963). Sorting is derived from
    `beatHz`/`carrierHz`, so a new preset lands correctly with no UI change.
    Every row previews, and previewing selects.
  - **Silent data bug fixed:** `begin()` hardcoded `mode: "frequency"` for
    anything non-silent, filing nature and guided sessions under the wrong mode.
    `SoundCatalog.mode(for:)` now derives it from the owning catalog.
  - **ONBOARDING BUILT — the full flow from `ONBOARDING.md`.**
    - `Shared/Onboarding/OnboardingModel.swift` — questions, answers, and the
      arithmetic. Pure Foundation, 10 tests. Projection dates are hand-checked in
      the tests (30 days at 5/week lands Sept 16) so a rounding change can't
      quietly move the date we print at someone.
    - `OnboardingKit.swift` — the ground as a modifier. Screens declare a
      SECTION, never a colour; no screen hand-rolls a background. **The
      per-section colour arc (amber → sage → red → gold) was RETIRED 2026-08-29
      (Aziz): every section now grounds in the same warm gold.** The section
      enum survives so an arc could return as a one-line change.
    - Interview is now **12 questions**: baseline · why · stress · alone-with-
      thoughts · doing-nothing · restarts · how-long · causes · watch gate ·
      anchor · you · attribution.
    - **Departures from the spec, deliberate:** commitment moved BEFORE the
      projection (the projection is arithmetic *from* the committed days/week);
      the progress rail shows during the interview only; paywall position is one
      constant, `paywallInsideOnboarding`.
  - **NEVER TELL THE READER WHAT THEY LACK, AND NEVER SET UP A LOSER FOR THE
    COPY TO BEAT** (Melvin, 2026-09-01, after correcting it four times in one
    sitting). The failures all looked different and were the same thing:
    "Watch the habit take hold" told a reader who already meditates that they
    had not started; "Share the proof, not a caption" invented a behaviour
    nobody recognises and then argued with it; "small and often beats long and
    rare" made a loser of anyone who sits long and rarely; and listing award
    thresholds ("ten straight days, a score of 90") read as chores rather than
    reasons. **State the positive. If a sentence needs a foil to make its
    point, the point is not strong enough yet.**
    A full sweep of the website, the store description and the app on
    2026-09-01 found five more and fixed them; what survived, and why, is
    recorded there. The legitimate exceptions are narrow: the relief screen may
    exonerate a fear the user actually arrived with ("You just never got told
    whether it was working"), the verdict may report a poor session honestly,
    and legal lines like "not a medical device" stay. Naming the reader's pain
    in THEIR words, as the website's "Am I even doing this right?" labels do,
    is the Schwartz move and is correct. Telling them what they are missing in
    OUR words is not.
  - **NEVER BOAST THAT EARNED AWARDS ARE KEPT. It is not a feature** (Melvin,
    2026-09-01, third time he has cut it). No app in history has ever taken back
    an award someone earned, so saying "yours for good, even if a streak breaks"
    answers a question nobody asked. Worse, defending against a fear the reader
    did not have is what plants it: the sentence's only achievement is making
    them wonder whether some app somewhere confiscates trophies.
    **The ENGINE rule stays** and is still load-bearing (`AwardEngine` derives
    from "did this ever happen", and `test_brokenStreakKeepsTheAward` locks it,
    because taking an award back would punish exactly the person we want to
    bring back). What stops is TELLING the user about it. Behaviour yes,
    bragging no.
    Same family as the general rule: **do not sell the absence of a problem the
    reader never imagined having.** It reads as defensive and spends words that
    could carry a real claim.
    Still live in two places at the time of writing, both fair game to cut:
    `AwardsView` ("Earned awards are yours for good, even if a streak breaks.")
    and `website/index.html` ("An award never expires: break a streak and what
    you earned stays earned.").
  - **NO EM DASHES IN USER-FACING COPY. EVER.** (Aziz, 2026-08-06, third time
    he has raised it: website, DM scripts, now permanently.) The em dash is the
    clearest tell that text was machine-written, and for a product whose pitch is
    honesty about what it measures, prose that reads as generated undercuts the
    claim before anyone reaches the substance. **Restructure the sentence rather
    than swapping in another mark** — most em dashes hide a decision the writer
    avoided making. Usually two sentences, sometimes a colon, often just delete
    it. 27 were swept out of the app's strings on 2026-08-06; the count in
    user-facing `"..."` literals should stay at zero. Code comments are exempt
    (not user-visible). Same rule applies to anything written to Aziz directly.
  - **COPY RULES THAT COST US A CYCLE EACH — hold them:**
    - **Name the subject.** Four headlines assumed context the user hadn't been
      given ("You're not bad at this" — at what?). Screens are met in isolation;
      each one must stand alone. Same applies to App Store screenshot captions.
    - **THE GOLD RING MEANS A MEASURED SCORE, NOWHERE ELSE.** Calculating
      originally used a ring with a percentage. That's the results screen's exact
      object — reusing it for progress teaches people to read one as the other,
      and then the real score arrives looking like something that means nothing.
    - **We ask, we never tell.** We may ask whether someone's attention has
      slipped; asserting it is a claim about their brain we cannot measure. Same
      line the theta copy must respect.
    - **Don't ask for data the user never collected.** A "how many of the last
      seven days were you present for" question was cut for this: people don't
      track it, so they guess or feel tested.
    - **No invented number about the user.** The reference flow assigns a "64%
      suited" score. We refuse: our only score is measured off a wrist, and a
      fabricated one here would cost us the right to be believed later.
    - **Tap-to-advance** on single-select (7 screens), with a **320 ms dwell** —
      without it the tick never registers and it feels like the app jumped past
      your answer. Multi-select and the slider keep Continue; so does the Watch
      gate, because it branches and its button label warns you where it goes.
  - **NOT wired: StoreKit.** No products configured. The trial button advances
    the flow; nothing claims a charge occurred.
  - **Workflow Aziz set (2026-08-06): design first, always.** Every screen gets an
    HTML mockup for review *before* any Swift — including revisions to already-
    approved screens.
- **HRV (SDNN) — INVESTIGATED 2026-08-07, parked with precision (don't re-park it
  wrong).** The old note "no HRV / heartbeat-series — those were for the dropped
  coherence path" CONFLATED two different things and cost us this investigation:
  - **SDNN is readable by third parties.** It's a single number Apple computes
    on-watch; it needs none of the beat-to-beat access coherence needed. Now in
    the Watch read scope; full pipeline exists (`HRVRecorder`, `HRVSnapshot`,
    4 fields on MeditationStats) — committed, tested, dormant. `heartbeatSeries`
    remains genuinely unavailable; that part of the old note was right.
  - **Verified on Aziz's hardware:** the Watch does NOT generate an SDNN sample
    during our sessions (samples come ~every 2 h at rest + during Apple's own
    Breathe sessions; no API can trigger the sensor). Per-session HRV on Apple
    Watch is not buildable by ANYONE — competitor apps (Core, HRV Tracker) chart
    Apple's passive samples phone-side; their timestamps show the 2 h cadence.
  - **The Watch's local HealthKit store only holds a few days** (n=4 over a
    30-day query). Real baselines require PHONE-side HealthKit reads — an
    architecture + privacy-policy + App-Review decision (today the phone reads
    zero biometric data), not a refactor.
  - Per-session paths that DO exist, ranked: camera PPG (built, cut, in
    `full-feature-set`), BLE strap (Pro tier), user-run Breathe minute,
    SensorKit research entitlement. Aziz's constraint: free + frictionless →
    all rejected for v1. HRV *trend* correlation with practice is scientifically
    weak per-person (few-ms effect inside ±15 ms daily noise) — don't ship a
    causal claim.
- **MOTION EXPERIMENTS — pilot VERIFIED on-device 2026-08-07 (4 sessions,
  Aziz).** DEBUG builds capture raw 100 Hz CMDeviceMotion (attitude + accel
  vector) and ship CSV to the phone (`Documents/MotionCaptures`, Files-visible;
  pull via `devicectl device copy from --domain-type appDataContainer`).
  Engine buffer stays decimated to 20 Hz so shipped analysis is unchanged.
  Analysis: `tools/analyze_motion.py` (numpy). Findings:
  - **Posture-free breathing WORKS for deliberate slow breathing.** Paced 6/min
    recovered as 6.0 seated (roll conc 0.53, 85% of engine-shaped windows) and
    5.9 reclined-on-bed (conc 0.86 — cleanest of the night). Posture didn't
    matter; hands resting on legs is enough. This is the belly-breathing
    headline WITHOUT the belly placement/posture failure modes that got it cut.
  - **Calibration required before it ships:** wrist amplitudes are millirads
    (reclined: 2.6 mrad sd), 4–13× smaller than belly — the engine's amplitude
    floor (~10 mrad) would reject clean signals. A slow arm shift reads as a
    fake clean ~2/min (accel only ~1.6× session median — under the coarse
    gate); fix = relative per-window accel gate (~1.5× median) + median-filter
    the rate curve. Natural quiet breathing (counted 11/min, found ~10/min) is
    present but 6–15× below drift power → needs drift suppression; found in
    ~2/3 of windows on pitch. Deliberate slow breathing is the feature.
  - **Wrist BCG (heartbeat from 100 Hz accel) is a live lead:** cardiac-band
    peak matched actual HR in BOTH still natural sessions (72 vs ~74; 73 vs
    ~73) and missed in all three paced/movement sessions — paced 6/min
    breathing throws harmonics into the cardiac band (10th harmonic ≈ 1 Hz), so
    BCG needs quiet natural breathing. If it holds, that's beat-to-beat (real
    HRV) with no camera, no strap, no Apple cooperation. Next: dedicated ~3-min
    maximum-stillness session, then beat-segmentation offline.
  - Also fixed en route: Watch→phone payload now dual-channel (sendMessage when
    reachable + transferUserInfo backstop) — End on Watch used to leave the
    phone's live screen up for tens of seconds while the payload sat in the
    userInfo queue. Persist is idempotent by sessionID so double delivery is
    safe. Same family as the stale-WC-queue bugs: the queued channel is never
    prompt.
- **CAMERA VISION (no-Watch sessions) — PAUSED on branch `camera-vision`
  (2026-08-24, Melvin: "a future update, far down the line").** The pilot was
  POSITIVE on two real videos before it was parked, so do not re-derive it:
  `tools/camera_probe.swift` on that branch reads stillness and breathing from
  a propped phone camera, and the full findings live in that branch's CLAUDE.md
  section. Ground-truth videos stay in `~/Desktop/captures/video/` (never
  commit — public repo). Not to be worked on while launch is in flight.
- **WRIST BREATHING SHIPPED — posture-free, VERIFIED on-device across 8 live
  sessions (2026-08-07, field-calibrated in 5 rounds like the camera was).**
  Every non-belly session gets a breathing attempt automatically: no mode, no
  placement, no coaching — sit or lie anyhow, hands anywhere. Deliberate slow
  breathing (~4–9/min) reads; quiet automatic breathing degrades to silence.
  Engine: the wrist path in `SignalEngine.analyze` (belly path untouched).
  Verdict/tile/graph/share-card all key on data presence (VerdictEngine's
  breath gate moved off the belly flag — nil is still absolute silence).
  - **Wrist breath is EVIDENCE, never a grade.** Belly was opt-in, so scoring
    resonance was the user's own ask; the wrist path runs unasked, so it never
    moves `overallScore` (locked by test). Scores stay comparable with all
    prior sessions.
  - **The gate stack, each constant a measurement (don't retune by feel):**
    band 0.05–0.5 Hz (settling drift lives at ~2.1/min and out-powers breath
    6–15×); amp floor 0.5 mrad (the STILLER the body the SMALLER the wave —
    a settled user's real breath measured 1.1–1.5 mrad, session 3, and 9/min
    shallow breathing 0.4–0.9 mrad, session 5); per-window accel gate 1.5×
    session median (a slow arm shift is only ~1.6× and fakes a clean slow
    breath); rate floor 3.5/min (drift leaks power at the band edge); believe
    the CLEANEST axis at conc ≥0.40, or 0.30 with pitch/roll agreeing ±25%;
    median-of-5 the curve; require ≥60% windows readable AND rate-IQR ≤2.0
    (a true breath is ONE coherent track — even drifting 6.6→9.5 held IQR
    ≤1.6; junk assembles plateaus at different rates, IQR 2.5).
  - **Two selection principles that beat their alternatives on data:** clarity
    picks the true axis, amplitude picks drift (the belly-era PCA-by-variance
    mistake in new clothes — "biggest movement = breath" was tried and refuted
    on session 5, where the correct axis was the QUIETER one). And a
    whole-file concentration gate assumes a stationary rate — a real breath
    that drifts smears it; window-level gates only.
  - Validation: 8/8 live captures correct through the real engine (9/min reads
    9.3, four 6/min sessions read 5.9–6.1, drift reads 7.9, the known-junk
    session refuses, deep-stillness reads a tight 5.5). Offline harness:
    `swiftc -parse-as-library SignalEngine.swift + harness` on the captured
    CSVs — iterate there, not on-device. 100 tests green.
  - **Product framing:** the breath section is the reward for SLOW breathing
    practice (~4–7/min, the resonance zone) — at 9/min resonance ≈0.27, so the
    verdict reports the rate without the resonance claim, which is correct.
    Copy should say "breathe slow and 808 reads it", not promise a rate-meter
    for all breathing.
- **WATCH APP REBUILT + WATCH-INITIATED SESSIONS (2026-08-08).** Sessions can
  now start on the wrist: the Watch composes its own `SessionParams` (open-ended,
  mode from the shared `SoundMenu`) and runs the identical pipeline; the phone
  persists idempotently as always. `WCKeys.watchBegin` invites a reachable phone
  to join (live screen + chosen sound); `WCKeys.ending` fires the moment End is
  tapped so the phone drops its live screen BEFORE the seconds of scoring, HRV
  settle and shipping. **Both are sendMessage-ONLY** — a queued join or ending
  replaying later would resurrect a dead session's screen (the stale-WC-queue
  family, now bitten three times). Phone unreachable = session still runs, live
  screen says "iPhone out of reach · silent".
  - **`SoundMenu` (Shared) is the catalog as the Watch sees it** — names and ids
    only, because every bed/track lives in the iOS bundle (~50 MB) and audio
    always plays phone-side. `SoundMenuTests` locks it against the phone
    catalogs BOTH directions plus mode agreement, so a preset added phone-side
    can't vanish from the wrist or file wrist sessions under the wrong mode.
  - **`WatchPalette` — do NOT use `AppColor` in the Watch target.** The shared
    colorsets carry light+dark variants and **watchOS resolves the LIGHT one**:
    `TextSecondary` resolved to 0.42 grey (invisible on black) and `CalmAccent`
    washed the breathing orb out to a bare outline. The Watch has one
    appearance, so it gets one set of literal values.
  - Screens: start (mark, gold Begin, sound row) → live (elapsed inside a teal
    orb breathing at 6/min, the resonance pace, so a glance is a pacing cue) →
    sending (dots into a phone outline) → sent ("Delivered" only when the
    payload went over the immediate channel; else "Saved… back in range" —
    tracked via `deliveredImmediately`, not guessed).
  - **First-Begin race:** `WCSession` activation/reachability settle async, so
    on the first Begin after launch `isReachable` is routinely false and the
    invite was silently dropped (second attempt worked). `invitePhone` now polls
    ~14 s and sends the instant the link comes up.
  - Watch elapsed derives from the wall clock (a sleep-loop counter drifted
    seconds behind); both sides now compute from the same clock.
  - **Dark is the default theme** for new installs (`Preferences.theme`).
  - **THE WATCH PLAYS NO HAPTICS. NONE. Do not add one back** (Melvin,
    2026-09-01, pre-submission). A buzzing wrist reads as an interruption in a
    product whose entire promise is settling down, and it is a reason someone
    puts the app down rather than a reason they keep it. The 6s-in / 6s-out
    breath pacer (`startBreathPacing`, `WKInterfaceDevice.current().play`) is
    DELETED along with the `paceBreathing` field it was gated on, which the
    walkthrough had already set false. `grep WKInterfaceDevice CoherenceWatch/`
    must stay empty. Any wrist buzz a user still feels during a session is
    watchOS's own workout start/stop haptic or a mirrored iPhone notification,
    neither of which a third-party app can suppress; do not go hunting in our
    code for it.
  - **The Settings "Haptics" toggle now governs the award celebration**
    (`AwardUnlockView`), which is the only haptic left outside onboarding. It
    was left driving nothing when the pacer went, and a settings control that
    does nothing is a small lie in a product selling honesty.
  - Cosmetic, not a bug: a one-second flash of the previous build's screen at
    launch is watchOS replaying the old install's snapshot.
- **SCORE v3 — evidence-weighted, time-capped, back-filled (2026-08-08).**
  Meaning, in the app's own words: **"How deep you got, and how long you held
  it."** Explained in-app by a quiet "?" on the results ring →
  `ScoreMeaningSheet` (two modes: stress vs recovery, the subconscious only
  opens in the second; then Breath / Heart / Stillness / Time). **Never says
  brainwaves, theta, HRV, or health outcomes.**
  - **Weights follow researched evidence, not intuition** (full citations in
    the 2026-08-08 research pass): breath **.45** / heart **.35** / stillness
    **.20**, renormalising to **.60/.40** when no breath is read.
    - *Breath leads* because resonance breathing IS the intervention in
      HRV-biofeedback trials, which carry the largest effects in this
      literature (Hedges g ≈ 0.8, Goessl 2017), and RSA/HRV peaks at ~6/min via
      the baroreflex (Russo 2017). **We measure the driver directly** rather
      than inferring it from HRV this hardware won't give us.
    - *Heart* is replicated but modest (g ≈ 0.24–0.37) and confounded by how
      wound up the user was at minute zero.
    - *Stillness* has **NO literature grading meditation depth by motion** — it
      is a superb VALIDITY check and a poor depth measure. v2 spent 55% of the
      score on it, and across eight real sessions it ran 0.84–0.97 (0.22 for a
      fidgety one), i.e. over half the score was a constant saying "you sat".
  - **THETA AS A SCORE IS REFUSED, on scientific grounds not just policy.** The
    literature contradicts itself on direction: a 2021 depth-graded study found
    theta *inversely* related to depth (positive with hindrances). Combined with
    the onboarding screen that admits "we can't see that from a wrist", a theta
    probability would be picking a side in an unresolved argument and selling it
    as fact. Don't relitigate.
  - **Time is a CEILING, never a bonus:**
    `score = depth × (0.4 + 0.6 · √(min(1, minutes/20)))`. Thirty restless
    minutes still lose to five settled ones. The 0.4 floor is why "two minutes
    still counts" (onboarding copy updated); the √ is why the first ten minutes
    buy more than the second ten. 2 min → .59, 5 → .70, 10 → .82, 20+ → 1.0.
  - **Two component fixes the weights alone wouldn't have solved:** stillness is
    rescaled from [0.80, 0.98] so real sessions spread again; and the heart term
    stopped being start−end (which measured how agitated you were at minute
    zero — a 68→68 sit is *good* with no room to fall and scored zero). It's now
    **60% holding at/below your opening** (the fairness floor a calm person can
    always earn) **+ 40% the size of the drop** (headroom only an agitated body
    can claim).
  - Validated against the eight real captures: 22–52 for the 1–4 min sessions,
    30/40/77–86 at the same quality run 20 min. The two genuinely poor sessions
    sit at the bottom.
  - **All history is back-filled** (`ScoreMigration`, one-time, UserDefaults
    flag, health-rescue pattern). `SignalEngine.score()` is the SINGLE entry
    point `analyze` and the migration share, so the back-fill is exactly
    equivalent to a fresh computation. Rewriting an "immutable" stats row is
    defensible because no MEASUREMENT is touched — only a number derived from
    them by an older formula (locked by test). Rationale: a history graph is a
    comparison, and a comparison across two formulas is a lie told with a line
    chart.
  - **OPEN: `VerdictEngine` thresholds (0.75/0.55/0.35) are stale** — they were
    tuned to the v2 distribution and will fire "Your practice landed" far less
    often. Retune once a few real v3 sessions exist.
- **WEBSITE REBUILT (2026-08-08/09) — live on meditate808.com.** Four pages,
  one design language, deployed by MANUAL UPLOAD to Cloudflare Pages.
  - **Cloudflare Pages is a DIRECT-UPLOAD project, not connected to git.**
    Pushing to GitHub does nothing to the live site. Deploy = drag the
    `website` folder into Workers & Pages → meditate808 → Create deployment.
    This cost an hour of confusion: the live privacy page was older than every
    branch in the repo, which is only possible if git was never the source.
  - **Design came from Lovable, ported by hand** (Aziz preferred it to both our
    version and Figma's). Extracted off the live page rather than eyeballed:
    Bricolage Grotesque 700 at -0.03em display, IBM Plex Sans body, IBM Plex
    Mono for every label at 0.1em uppercase, `--radius: 0` almost everywhere,
    background `oklch(14.5% .006 260)`. Their React build became our single
    static file; we kept the citations, the wellness disclaimer and the real
    chart geometry, none of which their version had.
  - **Alarm red retired for terracotta** `oklch(62% .10 32)`: same hue so it
    still reads as cost, chroma roughly halved so 114 lit cells stop reading as
    an error state. Gold and teal unchanged.
  - **The argument is pain-first**: 46.9% of waking hours elsewhere
    (Killingsworth & Gilbert 2010) turned into the reader's own number via a
    slider, drawn as 365 cells. Then meditation works, then almost nobody keeps
    doing it, then the four charts. The turn is Cearns & Clark 2023: across
    280,000 sessions consistency predicted improvement and session length did
    not. Seven sources with DOIs, plus a note stating plainly that none of it
    shows 808 works for you.
  - **DON'T USE THE 23-MINUTE REFOCUS STAT.** It is the most-quoted focus
    statistic on the internet and it has NO paper behind it: it traces to a
    2006 Gallup interview, and the Mark et al. paper everyone cites found the
    opposite (interrupted work finished *faster*, just more stressed).
  - **The "first app to..." claim was left out three times**, deliberately.
    Apple's own Mindfulness app already logs heart rate during sessions, so
    it's unverifiable. Aziz can add it if he and Melvin confirm no competitor
    scores a meditation from body signals.
  - **Two Google Sheets, two Apps Script deployments**, both verified end to
    end. `waitlist-sheet.gs` (new, its own sheet, dedupes by email) and
    `survey-sheet.gs` (renamed to "808 survey"). The questionnaire is rebuilt
    around 11 questions aimed at churn rather than general friction.
  - **`survey-sheet.gs` now writes by the SHEET'S header row, not the file's.**
    Changing HEADERS against a sheet with existing responses silently files
    every answer under the wrong column. It reconciles instead, appending
    unknown columns on the right, so old rows and the old `blockers` column
    survive.
  - **Every form races a rejecting timer** (8 s). The first live signup stuck on
    "Joining" forever. AbortController alone is NOT enough: tested against a
    fetch stub that never settles, the abort version still hung after 18 s.
  - **The 365 year-cells are static HTML, not JS-generated.** A JS-built grid
    renders as nothing wherever scripts are blocked, which is exactly what Aziz
    saw. Same principle as the counter always writing its final value from a
    timer.
- **BREATHING v2 — reads natural breathing, shows everything, scores little
  (2026-08-09). NOT FINE-TUNED. Aziz wants another pass.**
  - Calibrated against five live captures, four with counted rates (`tools/
    breath_probe.py` replicates the engine offline against a raw CSV; iterate
    there, never on-device). Captures live in `~/Desktop/captures`.
  - **Two tunings, chosen PER WINDOW.** The shipped slow-breathing calibration
    plus a natural-breathing one (band-pass low edge 8 s not 12 s, per-window
    least-squares detrend) that suppresses postural drift so quiet breathing
    can win its own peak. One tuning per session is wrong: a verified capture
    halved its rate (counted 12 → 8 → 6.5) in five minutes. Per-window reads
    78% of it against 64% and 44% for either alone.
  - **Coherence is judged by TRAJECTORY, not spread.** The old gate rejected
    anything wider than 2.0, which threw away a session that was right in every
    window. A curve now qualifies if it is tight OR coherent once a straight
    line is removed. Measured: real sessions fit a line at R² ≈ 0.57, the two
    junk ones at 0.05.
  - **Display is lax, scoring is strict (Aziz's call).** A rate shows whenever
    a third of windows read it; it reaches the score only at 60% readable AND
    coherent AND ≤ 9/min. **Reason it must stay split:** at minute 2 of a
    counted session the engine reported 3.9/min at clarity 0.76 while Aziz
    counted 10, because a 4/min postural sway carried 14× the power of his
    breath. Clean sway and clean breath are the same shape and no gate can
    separate them. Showing it costs a wrong number; scoring it corrupts the
    product.
  - **Resonance credit stops at 9/min.** Reading a normal rate without this
    would PUNISH normal breathing: resonance is 45% of the score and a bell
    curve on 6/min, so a session read at 14/min scores zero on its largest
    component (72 → 40 modelled on a real session).
  - **Zero in the breathing series means UNREADABLE, not zero breaths.** It is
    no longer plotted: it drew a collapse that never happened and dragged the
    y-domain to the floor, squashing the real curve. Empty HR likewise yields
    no series rather than a flat line on the axis.
  - **Two hypotheses died; do not retry them.** Local smoothness does not
    separate real from junk (the session that read nothing had the SMOOTHEST
    median step). And the 6-vs-12 pattern is NOT octave error, unlike the
    camera path: power at double the detected frequency is only 5–22% of peak.
  - **BREATHING HISTORY CANNOT BE BACK-FILLED.** When the old gate refused, the
    curve was never assigned, so past rows hold nothing to rescore. Unlike the
    v3 score back-fill, whose inputs were all already on the row. Only DEBUG
    sessions could be recovered, from the raw CSVs keyed by sessionID.
  - **OPEN, and Aziz knows:** accuracy is roughly ±1/min at best (counted 7/7/6
    read 6.9/6.0/4.6) with a consistent slight undershoot, and one outright
    miss when sway dominated. Needs more counted sessions, especially a
    Dispenza one, which still refuses and is unexplained.
- **BREATHING v3 — the curve is now chosen as a whole, not window by window
  (2026-08-10).** Nine variants were built and measured against the counted
  captures. One shipped. **Accuracy did not improve and could not be improved
  from this data; read that as a finding, not a to-do.**
  - **The diagnosis: selection, not filtering.** `tools/breath_why.py` ranks
    every candidate the engine considers against the counted rate. A candidate
    sits at the counted rate in **~95% of windows** (52/55, 53/55, 50/51) but is
    the single clearest peak in only about **half**. The answer was usually
    present and usually discarded. Everything else follows from that.
  - **SHIPPED: continuity tracking** (`trackRates`, `SignalEngine` 3.3.0).
    Viterbi over the top three spectral peaks per channel, scoring clarity minus
    `wristTrackJumpCost` (0.45) per breath/min of jump. Windows advance 5 s and
    span 30, so consecutive windows share 25 s: a real rhythm is nearly forced
    to repeat and a spurious peak is not. Reading each window alone spends none
    of that redundancy. Standard pitch-tracking practice, for the same reason.
    Measured over eleven captures: displayed spread falls hard on five (one from
    4.55 to 1.25/min), the three verified paced sessions come back identical
    (6.1, 6.1, 5.2), readable fraction moves nowhere.
  - **Two design rules inside it, both of which cost a wrong first attempt:**
    - **Gated tracking.** A tuning offers candidates only for windows it would
      already have read. Ungated, coverage rose 75→79% (and 76→93% on the
      no-breath session), which quietly loosens the display AND score gates as
      a side effect of choosing better. Never let an estimator move a gate.
    - **The score gate is judged on the UNTRACKED curve.** `coherent` grades a
      curve by how little its rate moves, and the tracker's whole job is to move
      it as little as the evidence allows. Judge the tracked curve with it and
      the gate grades its own homework: one capture flipped to "confident"
      purely from being smoothed. Displayed curve = tracked; scored decision =
      raw. Locked by `test_wristSession_trackingDoesNotSmoothItsWayIntoTheScore`.
  - **REFUSED, all measured, do not retry** (baseline mean error 1.90/min over
    9 counted points): Hann taper (coverage 75%→36%, error 2.35); parabolic peak
    interpolation (error unchanged, and the 121-point scan is already finer than
    a 30 s window's resolution, so there is nothing to refine); 45 s and 60 s
    analysis spans (coverage collapses to 12–49% for at best 0.3/min); harmonic
    and subharmonic preference (error 2.09 — unlike the camera path, wrist
    breathing has no octave problem, already established); detrending the slow
    tuning (no change); averaging the two axes' spectra instead of racing them
    (error unchanged AND it corrupts verified paced reads, 7.6→9.4).
  - **The filter is NOT the problem, and the earlier suspicion that it was came
    from a bad plot.** A spectrogram without the band-pass paints a 2–4/min
    drift ridge across every capture. Measured after the shipped 12 s
    moving-average band-pass, drift-to-breath power is **0.07**; a 4th-order
    Butterworth at 0.06 Hz gets 0.04 and reads no better (error 1.94). The
    moving average is a poor filter that is nonetheless good enough here.
    `tools/breath_spectrogram.py` now band-passes before plotting.
  - **The continuity penalty sits in a flat region, not on a cliff.** Swept
    0–0.55: 0.35 through 0.50 behave identically; at 0.55 a verified 6.9/min
    capture drags to 5.3. Accuracy across the sweep is non-monotonic (1.90 →
    2.29 → 1.58), which is the tell that the accuracy differences between
    variants are noise at n=9. Do not pick a constant off that column.
  - **SCORE GATE REPLACED — clarity, not smoothness (Aziz approved 2026-08-10).**
    Breath reaches the score when the readable fraction ≥ 0.6 **and mean clarity
    along the tracked path ≥ 0.60** (`wristMinPathClarity`). The old test, curve
    spread with a straight-line-trend fallback (`coherent`, `wristMaxRateIQR`,
    `wristMinTrendFit`), is DELETED. Do not reintroduce it.
    - **Measured over fourteen captures, ten with a known answer: every read
      that was right scores 0.65–0.94, every read that was wrong or off scores
      0.37–0.55.** 0.60 sits in the empty gap. The old gate got two of the ten
      wrong: it refused the counted 4.5/min session the engine had read
      correctly at 4.6, and it passed 39F2003D, which Aziz confirmed had no
      breathing in it. The new gate gets all ten right. 6 of 14 now score,
      against 9 of 14 before, so it is stricter overall.
    - **Why spread was the wrong thing to measure: the tracker minimises it.**
      Gating on it means the gate reads the estimator's own output. Clarity runs
      the opposite way — picking each window's clearest peak maximises mean
      clarity by construction, so the tracker can only ever spend clarity to buy
      continuity. **A measure an estimator can only push DOWN is safe to gate
      on. Apply that test before gating on anything else.**
    - Demonstrated synthetically, and it is worse than it sounds: a leaky random
      walk with **no breathing in it at all** produces a tidy curve (one seed
      holds 7/min then 4/min, another sits on 8/min throughout) and the v3.2
      gate **scored both**. Locked by `test_driftWithNoBreathIsShownButNeverScored`
      and `test_smoothnessAloneDoesNotReachTheScore`, with
      `test_breathUnderHeavyDriftStillScores` as the counterpart so the gate
      can't be "fixed" by refusing everything.
    - **Deliberate reversal:** a clearly-read rate that CHANGES now scores. The
      old rule treated disjoint plateaus as a misread, but a verified capture
      ran 12 → 6.5/min in five minutes, so "the rate moved" was never evidence
      of anything. `test_wristSession_clearlyChangingRateStillScores`.
    - **FITTED, not validated.** Ten sessions, five of them slow deliberate
      breathing where clarity is naturally highest. Revisit as counted
      natural-breathing captures accumulate.
    - **Synthetic junk must be a random walk, not white noise.** White noise
      sits above the breathing band and the filter removes it, so a "noisy" test
      built from it reads exactly as clean as a silent one. Postural drift is
      in-band and wandering. The `wander` helper in SignalEngineTests builds it.
    - **NOT back-fillable, and this is the second time.** `ScoreMigration`
      recomputes from stored fields and passes `row.meanBreathingRate`
      ungated, so every back-filled row already scores breath unconditionally.
      Clarity is not stored on `MeditationStats`, so no migration can apply the
      new gate to old rows. History therefore steps slightly at 2026-08-10.
      Accepted because the app is pre-launch and every real user's history will
      begin after this. Same family as "BREATHING HISTORY CANNOT BE
      BACK-FILLED" above: a gate whose inputs aren't persisted can't be redone.
  - **Tools.** `tools/breath_lab.py` runs every variant over every capture
    against the counted rates in one pass (`--only NAME`). `tools/breath_why.py`
    dumps per-window candidate rankings. `tools/breath_conf.py` scores candidate
    confidence properties. `tools/breath_harness.swift` compiles the REAL engine
    against a CSV (`swiftc -parse-as-library -O -o /tmp/breath
    Shared/Engine/SignalEngine.swift tools/breath_harness.swift`) — the Python
    is a replica and replicas drift, so confirm there before installing.
  - **What would actually move accuracy: better ground truth.** Nine
    self-counted points across four sessions cannot distinguish 1.6/min from
    1.9/min error. A metronome-paced session at a known rate, or a chest strap,
    would be worth more than another month of tuning.
  - **VALIDATED OUT OF SAMPLE, on-device, same day (capture `6FE7FF9B`).** Aziz
    ran 2 min of deliberate slow breathing on the new build and counted **4.5
    then 5**. The old engine read **5.7/min, spread 3.82**; the new one reads
    **4.6/min, spread 0.22**, and its curve rises 4.4 → 5.5 across the second
    minute, matching the direction of his count. This capture was not in the
    calibration set, so it is the first honest out-of-sample test of the change.
  - **Why the old engine missed, and a correction to an earlier note.** Deep
    slow breathing is asymmetric (quick in, slow out), so it puts real energy at
    **twice** the rate: measured here the second harmonic carried **0.74 of the
    fundamental's power**, on roll, whose amplitude was 3× pitch's. The
    per-window argmax hopped onto it for five straight windows. So the
    BREATHING v2 note "the 6-vs-12 pattern is NOT octave error, power at double
    the detected frequency is only 5–22% of peak" is **true of natural
    breathing and false of deliberate deep breathing.** Both stand; they
    describe different signals. **The engine still has no harmonic rule** —
    continuity resolves it, because only the fundamental is present in every
    window. Locked by `test_wristSession_deepBreathIsReadAtItsFundamentalNotItsHarmonic`.
  - **Three counted sessions on the new build, 2026-08-10, all out of sample.**
    `6FE7FF9B` counted 4.5 then 5, read 4.6. `8F85AEA4` counted 6 then 6, read
    5.7 (6.1 across minute 1, 5.3 across minute 2, resonance 0.99, 100%
    readable). `6B0D92D1` uncounted, read 6.9 on a curve settling 9 → 5. Mean
    absolute error over the four counted points: **~0.3/min**, against 1.9/min
    on the older captures.
  - **That gap is the regime, not the fix.** Everything today ran at 4.5–6/min,
    which is what the engine is built for; the older captures were natural
    breathing at 7–12/min. Do not quote 0.3/min as the engine's accuracy. Quote
    it as its accuracy on slow breathing, which is the only thing the product
    claims. Tracking changed nothing on the two clean captures (identical to
    v3.2) because there was no competing peak to lose to, which is what a
    selection fix should do.
  - **Worth knowing about the operator: Aziz's "breathing normally" is ~6/min.**
    He is a meditator and his resting rate sits at resonance. The older sessions
    where he counted 10–12 were a different state, not his baseline. Any future
    ground truth needs the state named alongside the count.
- **BREATH SCORES THE DOORWAY, NOT THE SESSION (v4.0.0, 2026-08-14).** Aziz's
  insight: slow breathing is an ENTRY technique, a few minutes at ~6/min to
  shift into parasympathetic dominance, after which attention moves elsewhere
  and breathing returns to natural. Nobody paces 6/min for twenty minutes;
  that is HRV biofeedback, not meditation. Scoring the session MEAN punished
  correct practice twice: if the natural phase was readable the mean dragged
  5 → 11 and credit collapsed; if it wasn't, whole-session coverage failed and
  breath left the score entirely.
  - **`breathDoorway`** finds the contiguous stretch (≥60 s, ≤9/min) whose mean
    rate maximises `breathCredit`. `breathCredit` is UNCHANGED, and note it is
    **not "slowest wins" but "closest to 6 wins"** — a 4/min sway scores 0.88
    against a real 6/min doorway's 1.00, which is free anti-sway defence.
  - **The first design FAILED validation and was thrown away.** Gating on the
    STRETCH's own clarity produced a 6.5/min "doorway" at clarity 0.65 held
    90 s inside `39F2003D`, the session Aziz confirmed has no breathing in it.
    Selecting by max clarity instead gave the same false positive. No threshold
    separates it: real reads span 0.61–0.96, straddling 0.65. **Searching
    sub-runs for the best-looking stretch finds a good-looking one in junk.**
  - **The fix was smaller than the first design.** The SESSION clarity mean
    works precisely BECAUSE it cannot be searched: junk carries many
    readable-but-unclear windows that drag it down, so `39F2003D` sits at 0.49
    against the 0.60 bar. **Clarity was never the bug. COVERAGE was.** So:
    `wristConfidentFraction` deleted, `wristMinPathClarity` untouched, and the
    doorway rate scored in place of the mean.
  - **`wristDisplayFraction = 0.35` also blocked it** — `readWrist` returned nil
    before anything else ran, and a 3-min doorway in a 20-min sit is 0.15
    coverage. Now `fraction >= wristDisplayFraction || doorway != nil`.
  - **NO dwell ramp.** The first design scaled credit from 60 s to 150 s held.
    Every capture is 2–5 min so none can validate that curve, and applying it
    drove three VERIFIED paced sessions to 0.11 / 0.67 / 0.78. Revisit only
    when counted sessions longer than the ramp exist.
  - **Validated across all 14 captures, real engine** (`tools/breath_harness`):
    5E0FF154 6.0, FEFAD3C6 6.1, 45D06F9F 5.9, 6FE7FF9B 4.8, 8F85AEA4 6.0,
    6B0D92D1 6.0 all SCORE (truths 6, 6, 5, 4.5–5, 6, ~6.9). **39F2003D
    computes a 6.1 doorway and is REFUSED by the clarity gate** (0.83 → 0.00).
    The eight natural-breathing captures score no breath, which is the intended
    consequence: **if you never slow your breath, your score is heart and
    stillness.**
  - **Window bleed, learned from a failing test:** a 30 s window centred on a
    burst still contains it, so a stretch reads across ~`windowSec` more than
    it lasted. 45 s of breath legitimately yields the seven windows the floor
    asks for. Synthetic "too short" tests must go well under that.
  - **Do NOT score natural-breathing regularity** (Aziz asked; answer is no).
    The engine cannot reliably read quiet breathing, and postural sway — the
    artefact it confuses for breath — is MORE regular than breath. That metric
    would reward the enemy. `breathingRegularity` stays computed, unscored.
  - **Belly asymmetry fixed:** `scoredBreathingRate` was only ever assigned in
    the wrist branch, so opting into belly mode silently cost 45% of the score.
    The belly loop's per-window `conc` is now kept and fed to the same doorway.
  - **The coupling line** (Aziz's idea): when a doorway exists AND heart rate
    fell, results say "Breath slowed to 5.4, and your heart followed, down 9."
    Descriptive on purpose — we read motion and averaged HR, not vagal tone.
    **Presence is evidence; absence means nothing**, since people reach the
    same state without slowing their breath, so the line is never negated.
  - Migration `scoreBackfillDone.v3` recomputes doorways from the stored curve.
    Per-window clarity was never persisted before v4, so history is scored as
    though its reads were clear: historical breath credit is more permissive
    than live, and that decays as sessions accumulate. Now persisted as
    `breathClarityTimeseries` so this cannot recur.
- **BREATH IS BINARY, WEIGHTED LEAST, AND MUST OPEN THE SESSION (v5.0.0,
  2026-08-14).** Weights are now **breath .20 / heart .50 / stillness .30**,
  down from .45/.35/.20, and the breath term is 1.0 whenever a doorway exists
  rather than a curve on how close it sat to 6/min.
  - **The rate curve was doing almost nothing, measured.** A doorway can only
    exist between 3.5 and 9/min, and across that whole reachable slice
    `breathCredit` spans 0.77–1.00 — under **two points** of a 20-minute score
    for any realistic doorway of 5 to 7.5. The gate had already made the
    decision; the bell was decoration on top of it. Meanwhile "did they
    deliberately slow their breath" is right **14 of 14** captures while the
    rate carries ±0.3/min on slow breathing and ±1.9/min on natural. **Score
    what the instrument measures well.**
  - **`breathCredit` survives as SELECTION ONLY.** It still decides which
    qualifying stretch becomes the doorway, so a 4/min sway loses to a real
    6/min breath. Do not delete it; do not let it back into the score.
  - **Why the demotion.** Breath is the least reliable of the three signals and
    covers the smallest part of the session. At .45 a restless sit with a
    CLIMBING heart rate scored 51 for a minute of pacing; it now scores 28.
    Researched 2026-08-14: slow breathing at the outset is standard practice
    and its immediate parasympathetic effect is measured, but **no study
    establishes how long the shift persists after you stop pacing** (studies
    measure during, plus 5–10 min recovery windows). So paying breath for the
    whole session was never supportable. Heart and stillness run the whole
    session, so if the doorway really did open the state, they already measure
    the carryover. Also: resonance frequency is individual and not even stable
    within a person over time (Sci Rep 2021, s41598-021-87867-8), so a fixed
    6.0 target was an approximation twice over.
  - **Absence can never subtract, and this is the load-bearing rule.** A silent
    breath signal is ambiguous between "very settled" (quiet shallow breathing
    below the motion floor) and "we missed it". You cannot punish a state you
    cannot distinguish from the best one. Absent breath therefore keeps the
    hardcoded **0.60/0.40** heart/stillness split rather than renormalising
    0.50/0.30, so **silent sessions rescore to exactly what they already
    showed** and only doorway sessions move.
  - **A doorway must BEGIN within the first 5 minutes** (`breathDoorwayMaxStartSec`).
    Aziz's reasoning: pacing late means thinking about your breathing to move a
    number, which raises heart rate and costs the state you are being scored
    on. Fixed minutes, not a fraction, because opening the state does not take
    longer in a 25-minute sit. **NO capture can test this** — every one is under
    5.1 minutes and the latest real doorway starts at 65 s — so it is a design
    decision pinned only by `test_lateSlowBreathingIsNotADoorway`.
  - **A refused doorway is no longer persisted at all.** It used to be stored
    ungated for display while `scoredDoorway` was gated. The graph now
    highlights the doorway as the thing that earned credit, so a displayed one
    that earned none would be the graph contradicting the score. `39F2003D`
    (confirmed no breathing) computes a tidy 6.1 and must show nothing.
  - **Validated through the real engine** (`tools/breath_harness`, now printing
    doorway rate, start and held): all six verified slow sessions keep their
    doorway — 5E0FF154 6.0@35s, FEFAD3C6 6.1@5s, 45D06F9F 5.9@5s, 6FE7FF9B
    4.8@65s, 8F85AEA4 6.0@5s, 6B0D92D1 6.0@35s — and 39F2003D, E1711EEE and
    the six natural-breathing captures are all refused. 163 tests green.
  - **A fixture trap that hid three vacuous tests.** `motion(accel: 0)` scores a
    perfect 1.0 stillness, and **a binary term worth 1.0 cannot raise a session
    already at 1.0**, so three "breath reaches the score" assertions compared a
    number to itself. They only ever passed because breath used to be
    continuous. Fixtures now pass `restingAccel` (stillness ≈ 0.90) and
    `assertNotAlreadyPerfect` fails loudly if one drifts back. **Any test
    asserting a signal moved the score must leave the score room to move.**
  - Migration `scoreBackfillDone.v4`. Most rows will not move, by construction.
  - **GRAPH: the full-width 4.5–7 teal band is GONE**, on both the results
    screen and the share card. It marked a rate range the score no longer
    grades against, and a narrow "good" zone under a score that ignores it
    teaches people to read one as the other. Replaced by a floor-to-ceiling
    teal band over exactly the doorway's time span (`breathDoorwayStartSec`,
    new persisted field). Floor-to-ceiling rather than clipped to a rate range
    because the curve climbs out of any such box while the doorway is still
    running, which reads as failing during the thing being credited. No label
    on the band (Aziz). `ResonanceBand` in ShareCard.swift is deleted; the
    share card takes a normalised `highlight` fraction instead.
  - **There is no "resonance zone" anymore.** The only threshold left is the
    9/min doorway ceiling, and inside it every rate is worth the same. Copy
    must not reintroduce a target band.
  - **`DemoData` drew 90 seconds of curve under a "10 min" header** (`n` was a
    flat 18). Now derived from the real window grid, and shaped as a slow
    opening into natural breathing so the screenshot shows what the score is
    built for.
  - **OPEN, unchanged by this pass:** held time is still worth nothing — a
    60-second doorway and a 15-minute one score identically. That is the one
    thing genuinely worth adding, and it still cannot be fitted, because every
    capture is 2–5 minutes. Needs long counted sessions first. Do not guess a
    dwell curve; the last attempt drove three verified paced sessions to
    0.11/0.67/0.78.
- **THE SESSION-CLARITY GATE IS DEAD — start time is the gate (v5.1.0,
  2026-08-14, hours after v5.0.0).** Aziz's first long session on the new
  build exposed it: a 6.6-minute sit opening with NINE consecutive windows at
  4.8–5.5/min and clarity 0.91–1.00 — the cleanest doorway in the capture
  library — was REFUSED, because 5.5 minutes of natural breathing after it
  dragged the session clarity mean to 0.51 against the 0.60 bar. **Any
  whole-session statistic punishes a short opening inside a long sit, and a
  short opening inside a long sit is the practice.** Same disease as the
  deleted coverage gate, different axis. `wristMinPathClarity` deleted;
  `WristRead.confident` deleted; the doorway function is now the entire gate.
  - **Clarity cannot REFUSE, measured.** Two same-day 2-minute sessions Aziz
    confirmed were slow breathing read stretch clarity 0.58 and 0.70; the
    confirmed no-breathing capture reads 0.65. Real doorways span 0.58–0.96,
    sway's span 0.57–0.79, interleaved. One real session sits BELOW the
    no-breathing one on every clarity measure. No bar separates them.
  - **Clarity CAN ADMIT: sway has never reached 0.85.** 227 Monte-Carlo drift
    sessions (leaky random-walk wrist motion, no breathing): forged-doorway
    stretch clarity median 0.61, max 0.79. Real paced breathing reads
    0.85–0.96.
  - **The shipped hybrid:** a doorway starting ≤90 s scores on start time
    alone (all nine confirmed real doorways start ≤65 s — people who slow
    their breath do it when they sit down); starting 90 s–5 min it must
    average stretch clarity ≥0.85, the bar sway cannot forge, so a
    fidget-then-pace user still scores when the read is unmistakable; after
    5 min nothing scores however clear (Aziz: late pacing is chasing a
    number, and chasing raises heart rate). Locked by pure-function boundary
    tests on `breathDoorway`.
  - **Known residual, accepted with eyes open: 62% of pure-drift sits forge
    an early doorway**, independent of length (only the first 90 s matter
    now). The synthetic walk is the adversarial worst case, and the two
    confirmed 45-second starters — CC436767 (real) and 39F2003D (no
    breathing) — are indistinguishable on everything measured, so any gate
    refusing the fake refuses the real. Accepted because breath is .20 and
    binary: a forged doorway buys ~3 points. At the old .45 it bought 18 and
    this trade would have been wrong. Do NOT re-tune clarity to fix this; it
    does not carry the information.
  - `maxStartSec` on `breathDoorway` is a diagnostics-only override (bypasses
    every start rule) for tools sweeping the constants. Never pass it from
    product code.
  - Migration key `scoreBackfillDone.v5`. Pre-v4 rows store no clarity and
    are treated as clarity 1.0, so their late starts up to 5 min are
    admitted: history stays more permissive than live, the same documented
    stance as before.
  - Validation, real engine: all 9 confirmed slow sessions score (starts 5,
    5, 5, 5, 30, 35, 35, 45, 65 s); the three mid-session spurious captures
    (starts 115, 135, 235 s) are refused; late drift doorways in the
    Monte-Carlo runs all blocked.
- **GRAPHS DRAW AT A FIXED MAGNIFICATION, SMOOTHED (2026-08-14, Aziz).** The
  y-axis used to zoom to whatever the curve did, so 2 bpm of ordinary wobble
  in a calm session drew the same mountains as a 12-beat settle, and no two
  graphs meant the same thing by "up and down". Now every heart graph spans
  **30 bpm** and every breath graph **12 breaths/min**, centred on the
  session; stillness stays 0–1; if a session genuinely moves more than the
  window, the window GROWS (never clip, and never anchor heart rate at zero —
  the heart rule survives inside `fixedSpan`; breathing is the one deliberate
  exception, a shared absolute **0–20** ruler per Aziz, safe because a breath
  curve is not a settle whose slope must survive). The drawn curve is
  `EvidenceSeries.smoothedPoints`, a 9-point weighted moving average (~45 s),
  **display only** — stored data, scores and the doorway all read the raw
  points. Share card uses the identical rules so the shared image teaches the
  same reading.
- **TIME RESHAPED — linear ceiling to 10 min, S-shaped bonus to 40 (v5.2.0,
  2026-08-14, Aziz's design).** Replaces the v3 sqrt ceiling (which capped
  10 min at 82 and needed 20+ for 100). Under ten minutes the cap is
  **50 + 5·minutes**, so an excellent 10-minute sit reaches 100. Past ten,
  a smoothstep bonus (flat at 10, inflection 25, plateau 40) multiplies depth
  by up to **+8%** (was 15% for a day; Aziz's first real long session scored
  99 from depth 0.89 and he called it egregious, so the plateau came down —
  same session now reads 94); `score` clamps at 1.0. Factors: 2 min → .60,
  5 → .75, 10 → 1.00, 20 → 1.02, 25 → 1.04, 40+ → 1.08. Migration
  `scoreBackfillDone.v7`.
  - **The bonus multiplies depth, never adds points** — the v3 principle
    (thirty restless minutes lose to five settled ones) survives the
    redesign: a restless 40-minute sit gains ~2 points, a settled one ~12.
  - Boundary values pinned exactly in `test_score_durationShape`. Migration
    key `scoreBackfillDone.v6` rescores all history to 5.2.0 on next launch.
- **ANALYTICS FACADE BUILT, INERT (2026-08-17, Aziz's call to add tracking at
  LAUNCH).** `Coherence/Analytics/Analytics.swift`: one enum of ~20 behavioral
  events (onboarding funnel via the single `go()` line, watch gate, session
  started/completed/start-failed, result viewed/missing, paywall
  viewed/dismissed, trial/purchase/restore/entitlement-lost, share, guide,
  reminders, awards, account-deleted), wired at every call site. **The sink is
  a no-op** only while the key is empty. **ACTIVATED 2026-08-17, Aziz's call
  to have dashboards DURING the beta:** PostHog live behind `Analytics.sink`
  (key in Analytics.swift, a publishable client key, committed on purpose;
  US Cloud, free tier; autocapture/replay/heatmaps OFF both client- and
  server-side — manual named events only). Same pass updated: iOS
  `PrivacyInfo.xcprivacy` (ProductInteraction / Analytics / not linked /
  not tracking), `PRIVACY_POLICY.md` + `website/privacy.html` (new "Usage
  analytics" section naming PostHog; Aziz must REDEPLOY the site by hand).
  STILL OWED: App Privacy labels in App Store Connect flip from "Data Not
  Collected" to Product Interaction at the next submission, and the next
  TestFlight upload re-enters Beta App Review (manifest changed).
  - **NEVER track a biometric.** No scores, HR, or breathing values, even
    banded: HR arrives via HealthKit and 5.1.3 bans third-party disclosure;
    scores inherit it. Engine-tuning analytics would need a first-party
    endpoint with consent. No free text, no identity; bands only
    (`durationBand`, `streakBand`).
  - Benchmarks researched 2026-08-17 for targets: health/fitness medians D1
    ~27% / D7 10–18% / D30 4–8%; meditation targets D1 ≥30 / D7 ≥20 / D30 ≥9;
    trial→paid median ~35–40%; hard paywalls ~12% install→paid median. The
    unique-to-808 metric is `result_missing` (sessions that produce no stats).
  - Not yet wired: `notification_opened` (no UNUserNotificationCenter
    delegate exists), `paywall_dismissed` (paywall flow still moving; wire
    when placement is settled).
  - **POSTHOG DASHBOARD "808 Beta" BUILT 2026-09-12 (Aziz + Claude, driving
    the browser).** 14 tiles: Day-zero funnel (install → first score, 1-day
    window, the number the research says predicts everything); Insight A/B
    retention pair (first-ever `session_completed`, B filtered to cohort
    "Two sessions in week one" = ≥2 sessions in 90 days, the closest this
    project's cohort builder offers to "second session within a week");
    Money funnel; Watch gate by outcome; Which lock gets tapped; Downsell
    ladder; ALARM tile (`result_missing` + `session_start_failed`, with a
    daily email alert to Aziz when `result_missing` > 0); Why sessions fail
    to start (by `reason`); and three onboarding views: users completing
    each screen (bar), drop-off 1 (interview, universal screens only),
    drop-off 2 (payoff screens → `onboarding_completed`). Branch screens
    (aloneWithThoughts, doingNothing, restarts, intendedFor, bodyCuriosity,
    bodyProof, blindSpot, watchSetup, waitlist, the walkthrough) are left
    out of the strict funnels on purpose: a persona who never sees a screen
    would read as churn.
    - **PROPERTY NAMES, exactly as sent (two tiles were built wrong first):**
      `onboarding_step` carries `step` (NOT `id`); `free_tier_entered`
      carries `after_rung` (NOT `afterRung`). `award_unlocked` is the one
      that uses `id`. The mapping is `Analytics.Event.properties`; read it
      before building a breakdown.
    - **Readable names, same evening (Aziz: "it's all super vague").**
      `onboarding_step` ALSO sends `screen`, a numbered human name from
      `Analytics.onboardingScreenName(for:)` ("12 Do you have an Apple
      Watch?"; letters mark branch screens a persona may skip:
      "06a Alone with your thoughts? (not regulars)"). Old funnels keep
      working on `step`; new ones should break down by `screen`. Both
      funnel tiles already show the numbered names as step labels.
      `AnalyticsScreenNamesTests` fails if a Step case ships unnamed.
    - **Team-device switch (ships with 1.0.1):** seven taps on the version
      line at the bottom of Settings flag the phone; every event then
      carries the super property `team_device = true` and the PostHog
      filter rule `team_device ≠ true` drops it. Off by default. This is
      the founders' answer to reinstalling constantly: flip it once per
      install. Until 1.0.1 is on their phones, their App Store installs
      still count in every tile. **Note: 1.0.1 was already "Waiting for
      Review" when this landed, so the screen names and the switch ship in
      the build after it.**
    - **Google Sheet, live from PostHog: `tools/posthog_sheet.gs`.** Six
      tabs (Overview with 7d/30d/all-time KPIs and the plan's benchmark
      rates, Daily, Screens in order with drop-off, Failures by reason,
      Purchases, Watch gate by week), refreshed hourly by an Apps Script
      trigger through the HogQL query API. Setup is in the file header;
      the read-only personal API key lives in Script Properties, never in
      the repo. Every query was run against the live project before
      committing.
      **The hourly trigger did not exist until 2026-09-14**: `installTrigger`
      is a setup step nobody ran, so every refresh for two days was the
      menu, and the sheet sat on Friday night's numbers while Apple showed
      Saturday's. Created from the Apps Script Triggers page (refresh,
      time-based, every hour). Check the Triggers page, not the stamp, when
      the sheet looks stale. Its internal-user rule matches PostHog's plus
      `$is_sideloaded` (Melvin's cable-installed betas; the two
      `result_missing` events on 2026-09-12 came from one).
      **Pasting the script into Apps Script: `pbcopy` follows the shell's
      locale, and the default here is not UTF-8.** A plain
      `pbcopy < tools/posthog_sheet.gs` mangled all thirteen non-ASCII
      characters (the arrows in "Install → first session" pasted as
      "‚Üí"), which reaches the sheet as visible garbage on the next
      refresh. Use `LC_ALL=en_US.UTF-8 pbcopy < tools/posthog_sheet.gs`,
      and check the arrow on line 2 of the editor before saving.
    - **A failed refresh costs one tab, not six (2026-09-15).** PostHog
      answers a query with a 504 "max execution time" now and then; it
      says nothing about the query. `refreshAll` writes each tab inside
      its own try and rethrows at the end, `query` retries a 429 or 5xx
      twice while the run is under 200 seconds old (Apps Script kills
      anything past six minutes), and `stamp` names any tab still holding
      last hour's numbers. Before this, a timeout in `writeDaily` left the
      five tabs after it silently stale with a stamp an hour old.
    - **Internal-user filter (project setting, default ON):** `$app_build`
      ≠ 1 (locally built installs) AND `$is_testflight` ≠ true. A postal-code
      rule (Melvin 11211, Aziz 48073) was tried and REMOVED the same day:
      friends in those areas may be real users. Founders' App Store installs
      therefore still count; read small numbers accordingly.
    - Field finding from the first read: 16 strangers reached `relief` in
      30 days, 12 left `breath`, everyone who reached `calculating` finished
      onboarding, and 2 of 12 finishers ever pressed Begin. The leak is at
      the very first screens and after onboarding, not inside the payoff.
- **STILL TO DO (picked up 2026-08-06):**
  - **Onboarding gaps:** the cost screen is passive where the reference flow has
    the user *select* symptoms across four lenses (we dropped the selection along
    with the fake score — they're separable); **theta on Proof 1**; the App Store
    **rating prompt** (Aziz approved; `SKStoreReviewController`, no setup needed).
  - **Paywall placement — needs Melvin + Aziz.** The spec's flow puts it at screen
    23; its own open-questions section argues for after the first session. One
    constant either way.
  - **Onboarding answers barely change the app.** Only the anchor does (it sets the
    reminder time). Motivation, stress, restarts and causes are used once for the
    reflection screens then dropped — which is the documented "decorative
    questions" failure. Cheap fix: home screen and verdict reference what they
    said they were chasing.
  - **`PURPOSE.md` and `SCIENCE.md` rewritten for the MVP (2026-08-11).** Both
    are bundled and rendered inside onboarding, so they were telling first-time
    testers to lie back with the Watch on their belly. Now: wrist breathing with
    no posture, a positive statement that slow breathing (4–7/min) is what it
    reads best, the bring-your-own-audio promise, a closing note that none of
    the cited research is about 808, and the wellness disclaimer. Hughes 2020
    dropped: it justified supine belly placement only. 18 em dashes swept.
  - **Do NOT state the breathing failure mode in user-facing copy** (that quiet
    natural breathing often can't be separated from postural sway, and the app
    then says nothing). A draft of `SCIENCE.md` carried it and a line was
    proposed for the website's breathing chart; Aziz cut both, 2026-08-11. The
    engineering constraint is real and documented above — this is a decision
    about what the product SAYS, not about what it does. Copy states what it
    reads best; it must still never claim breathing always works.
  - **The website was NOT stale after all.** Checked 2026-08-11: `index.html`
    contains no belly or camera copy, the sound-library counts match the app
    (4 nature / 3 brainwave / 4 pure tones / silence), the guided track's 25
    minutes is right, and the privacy claim matches `PRIVACY_POLICY.md`. An
    earlier note here claimed otherwise; it was wrong. Melvin's how-to guide
    and persona-branched onboarding are deliberately NOT on the pre-launch
    landing page (Aziz: the argument is tight, features dilute it).
  - **Do not add a "the theta literature disagrees on direction" caveat to
    `SCIENCE.md`.** A draft carried one; Aziz cut it 2026-08-11. We have no
    verified citation for the depth-graded study, and an uncited claim is the
    one thing that page cannot carry. The reason 808 refuses to SCORE theta is
    recorded above and does not need arguing in front of the user.
  - Paired-device test of the **Watch app install** is done; a **timed** belly
    session no longer exists, so that old test is moot.
  - Business: **Delaware C-corp EXISTS and is D-U-N-S registered (2026-08-24).**
    The lawyer advised a DE corporation over the MI LLC for hiring/investors/exit
    — it ADDS an entity, it does not fix a mistake; the LLC and its EIN stay
    valid. D&B case 10747633 resolved.
    - **Exact legal name: `Lock Out Inc.`** — a SPACE, and `Inc.`, not the
      `LockOut LLC` that the policy, ToS and website footer currently name. The
      two strings are not interchangeable and the entity swap must use this one
      character for character.
    - **D-U-N-S 149914479.** Registered at 8 The Green Ste A, Dover DE 19901;
      2 employees; start year 2026; legal form Corporation. Melvin A Van Cleave
      is CEO / primary principal, Aziz Mahmud is listed Prin, **stock 50/50**.
      Telephone 818-422-1140.
    - The D-U-N-S is what an Apple **Organization** account needs, so the
      blocker on the org account is now the D-U-N-S no longer. Everything the
      org account gates still stands: the permanent `com.lockout.meditate808`
      bundle IDs, the StoreKit product IDs, the real iCloud container, and the
      legal-entity swap below.
    - **STILL OPEN for the attorney:** the LLC→corp assignment of the app and
      the user data (which entity actually owns 808 on the day we swap the
      name), and whether the LLC stays alive or is wound down.
    Lawyer redlines pending on the four docs in `~/Desktop/808-legal-review/`.
    Meta app ID still needed for zero-tap Instagram Stories.

## APPROVED AND LIVE (2026-09-11): the launch marketing plan

App Review approved 1.0 on 2026-09-10 after the 2.1 information request;
released for distribution the same day, live within 24 hours. The full plan
is `marketing/LAUNCH_PLAN.md`; these are the decisions, so nobody re-derives
them.

- **Organic is the engine, paid is for learning.** At our prices ($7.99 /
  $29.99, free tier) and benchmark freemium conversion (2–4 % install → paid),
  revenue per install is roughly $0.60–1.20 against a $4–15 CPI for meditation
  keywords. Paid installs do not pay back in year one. So: two weeks of one
  reel + one carousel per day (tri-posted to IG, TikTok, Shorts) to find
  formats that hold, THEN UGC creators on the winners, and Meta only behind a
  gate. Replace the benchmark numbers with our own by week 3 (App Store
  Connect Subscriptions + PostHog funnel).
- **Budget $1,500–2,500 for 60 days, hard cap $3,000** until a channel shows
  two consecutive weeks with cost per trial start under $10. Scale a winner
  20–30 % per week; kill anything two weeks above twice its target.
- **Apple Search Ads is the one always-on paid line** ($15–25/day, Advanced,
  exact match on "meditation apple watch" and its siblings, no competitor
  names until week 3). Highest intent that exists, reports installs with no
  SDK, lowest CPI of any iOS channel.
- **A boost is a Meta ad** (same auction, same billing) that cannot use the
  app-install objective and does not lift organic reach afterwards. Use it
  ONLY to test whether a reel holds a cold audience ($20–30, objective
  "profile visits"), total under $150. Never expect installs from it.
- **Meta Advantage+ App campaigns are gated:** they need the Meta SDK or an
  MMP in the app (a 1.0.1 build, a review, new App Privacy labels), ~50
  installs per ad set per week to leave learning, and 8–10 creatives at a
  time. Run one 14-day test at $40/day only once a format has proven organic
  retention and install → trial ≥ 5 % is measured.
- **App Store Connect campaign links** (App Analytics → Campaigns,
  `?pt=…&ct=<name>&mt=8`) are our attribution: one per surface (ig-bio,
  tiktok-bio, website, reddit, press, yt-shorts). This is how we learn which
  platform sends installs before any SDK exists.
- **Launch-week moves:** r/AppleWatch post written as a person (not
  r/Meditation, bans promotion); tip lines at 9to5Mac, MacRumors,
  AppleInsider, iMore, Cult of Mac, pitched on the Watch angle, never "first";
  featuring nomination in App Store Connect aimed three weeks out; promo
  codes (100 per version) gifted to Watch YouTubers with no ask; Product Hunt
  one Tuesday–Thursday in week 3–4 once 10+ ratings exist, worth one day, not
  a strategy.
- **Rating prompt SHIPPED** (`ReviewPrompt`, `Shared/Session/`): fires from
  the results screen on the third completed session or later, never inside
  onboarding (double-gated on `onboardingComplete` and the tour environment),
  90-day cooldown, and takes no score or sentiment by construction; the
  signature is the guarantee and `ReviewPromptTests` locks it.
- **No-Watch churn is answered by the camera-vision session, not a subtitle
  warning** (Melvin, 2026-09-11). If campaign links show installs churning at
  the Watch gate, that is the signal to ship branch `camera-vision`.
- **Website at launch:** hero and banner point at the App Store
  (`https://apps.apple.com/app/id6806785308`, swap in the `website` campaign
  link once created); the waitlist form is repurposed for the no-Watch
  audience ("we'll tell you when a session works without a Watch"). Deploy is
  still manual: drag `website/` into Cloudflare Pages.
- Still live on the site and worth a look: the hero says "the first app
  that scores your meditation from your body", the very claim this file
  records leaving out three times. Aziz's call.

## FIVE-TAB LAYOUT + USERNAME (2026-09-12, Melvin: "familiar, Strava vibes")

The root after onboarding is a bottom bar: **Home · Guide · [gold plus] ·
Search · Profile** (`MainTabBar`, `ContentView` as the host). Mockup in
`mockups/tabbar.html`, reviewed before any Swift, per the standing rule.

- **The plus is the only way to start a session** and the only gold object
  on the bar; selected tabs read in the text colour. The old Begin button
  and Home's two top-right icons are gone (their jobs became tabs).
- **Home** keeps the greeting (Melvin's call), the streak, the sparkline,
  THIS month's calendar and the three most recent sessions. Tapping a dotted
  day switches to Profile with the log filtered to that day.
- **Guide** is `GuideView(embedded: true)`: no Done button; its Begin opens
  the setup sheet directly.
- **Search** was an honest placeholder; it became the **Friends** tab on
  2026-09-14 (see the FRIENDS section below). `PREVIEW_TAB=search` still works.
- **Profile** is what Journey was, minus the month picker (Home's calendar
  took the job): initials avatar, display name, `@username`, "Practicing
  since", the four stats, the awards shelf, the full log, settings in the
  gear. `JourneyView` is now `ProfileTab` (same file). Do not bring the
  month picker back; the calendar must not appear twice.
- **Every app-wide modal still lives on `ContentView`** (live session cover,
  start failure, award unlock, setup, results, settings) through the single
  `HomeSheet` presenter. Tabs are content; the modals are the app.
- **Tour anchors moved with their targets:** `.begin` is the plus, `.guide`
  is the Guide tab item, `.streak` stays on Home.
- **Username.** `User.username: String?` (optional, CloudKit-safe, lightweight
  migration). Asked on the onboarding "Last thing" screen beside the name,
  OPTIONAL like everything on that screen (5.1.1); editable in Settings.
  `Username.normalize` (Shared) lowercases, strips a leading @, keeps
  `[a-z0-9_.]`, clips to 20, and returns nil for empty so "" is never stored.
  **It is cosmetic until a backend enforces uniqueness**; do not present it as
  reserved. `UsernameTests` locks the normaliser.
- **Settings gained a Membership section:** Restore purchases (the gap the
  App Review audit flagged: reviewers look for Restore in Settings) and
  Redeem a code (`AppStore.presentOfferCodeRedeemSheet`, for the offer codes
  in `marketing/LAUNCH_PLAN.md`). The redeemed transaction lands on
  `Transaction.updates`, which `Store` already listens to.
- `PREVIEW_TAB=guide|search|profile` (DEBUG) opens the app on a tab.

## LAUNCH WEEK, DAYS 3 TO 5 (2026-09-12 to 09-14): what happened and what it taught

- **1.0.1 shipped as ONE build with the Watch fixes.** Melvin's 1.0.1
  (202609121757) was pulled from review and replaced by 202609130259,
  archived from Aziz's Mac on the org team, then pulled once more to swap
  store screenshots 3 and 6 for the five-tab layout. Approved and released
  2026-09-14. **Screenshots are locked while a version is in review**; changing
  them means Remove from Review, which costs queue position.
- **Media Manager orders screenshots by upload COMPLETION.** Upload one file at
  a time in listing order; recorded in `marketing/README.md`.
- **Reading App Store Connect sources:** App Referrer = a link opened inside
  another app (Instagram's browser, but ALSO iMessage, so a founder texting the
  link to friends lands here); App Store Search = typed a query (founders
  reinstalling inflate it); App Store Browse = found without typing (Apps tab,
  charts, categories). Apple counts downloads, PostHog counts first launches:
  expect Apple to run ~10 to 20% higher, and subtract App Review's Cupertino /
  Sunnyvale installs from ours. Apple's overview cards show ONE day.
- **Analytics sheet:** new Installs tab (one row per install: when, where,
  phone, Version, onboarding, Watch gate, package, sessions) and the hourly
  trigger that was never installed now exists. Sheets parses "1.0" as the
  number 1 through `setValues`; prefix version strings with an apostrophe.
  GeoIP moves on a phone: read city, state and country from ONE event.
- **Waitlist launch email SENT** 2026-09-13 1:16 PM EDT, 33 people, from
  Aziz's Outlook, campaign `ct=waitlist` (`marketing/LAUNCH_EMAIL.md`).
- **Reddit (`marketing/REDDIT.md`):** rules read directly from each sub's
  `about/rules.json`. **r/AppleWatch bans self-promotion** (the launch plan
  was wrong). Openings: r/apple Sundays (5 organic contributions that month),
  r/iosapps once per 30 days (10 local karma + Transparency path),
  r/SideProject, r/QuantifiedSelf Monday megathread. r/Mindfulness,
  r/Biohackers, r/AppleWatchFitness, r/Meditation ban promotion. First post
  live on r/SideProject from u/No_Shelter5464 (new, 1 karma).
  **Founder posts disclose.** Claude will not write or post content that
  presents a founder as an unaffiliated customer; the disclosed version of
  the same story is fine and was posted.
- **Deleted the questionnaire sheet's tab of six pre-written 5-star App Store
  reviews.** Handing people review text is review manipulation (3.2.2). Ask
  happy users to review in their own words; the rating prompt does the rest.
- **The in-app no-Watch waitlist never sent anything.** Its email stayed on
  the person's phone (an export that was never built), so every address from
  1.0 and 1.0.1 is lost. `WaitlistClient` now posts to the "808 no watch
  waitlist" sheet via `tools/nowatch-waitlist.gs` (verified end to end). This
  is the first personal data the app sends us: manifest, both policies and the
  App Privacy label must move together (`RELEASE_CHECKLIST.md`).
- **The no-Watch share is rising:** Watch gate answers the week of 09-13 were
  7 no Watch to 5 has Watch. Camera vision is the next product question after
  activation, not a someday item.
- **Where the business stands (09-14):** ~26 real installs, ~19 strangers,
  zero strangers with a completed session (all on the broken 1.0), two
  strangers reached the paywall, three trials all founders or family ending
  09-19, one Lifetime (family). The test of the product starts with 1.0.1.

## STREAK FORGIVENESS: one rest day per seven (2026-09-16, Melvin)

`StreakCalculator.runs` is THE rule and `AwardEngine.streakRuns` delegates
to it, so the headline and "ten straight days" cannot disagree. A single
missed day between practised days bridges a run when no other rest day was
taken in the previous seven (`restDaySpacing`); two missed days break it.
Rest days do not count as practised days: the number is days actually sat.
The current streak is alive on a rest day too (missed yesterday, nothing
yet today, day before practised, rest available), reported as
`restDayUsed` so Home can say the streak is on the line today. Rest days
are derived, never stored, like the streak itself. Do not add a stored
"freeze" inventory; the rolling seven-day rule needs none.

## OTTO v1 (2026-09-15): the premium on-device chat, behind a flag

Melvin: "an AI chatbot, part of the premium version, always available to
interpret your score, your meditation, your data, offer advice, answer a new
meditator's questions." Built on `otto`, merged to `mvp`, `Coherence/Otto/`.
Mockup `mockups/otto.html` came first (Aziz's rule).

- **On-device only.** Apple's Foundation Models framework (`import
  FoundationModels`, iOS 26, Apple Intelligence phones: iPhone 15 Pro and
  newer). No network call exists; the review answers ("no server, no AI
  service") stay true, and heart-rate data never leaves the phone (5.1.3).
  Phones without the model get "Otto needs an iPhone with Apple Intelligence
  and iOS 26."
- **What it knows is ours.** `OttoBrief` builds the system prompt from the
  v5 score rules, the voice rules, the method list and the last ten sessions
  (score, minutes, HR, stillness, doorway, technique) as a compact table
  under a 6,000-character budget; the opening line is rule-written from
  `VerdictEngine`, never generated. A regex medical pre-filter returns the
  one decline line before the model sees the question. Em dashes are
  stripped from replies. `OttoBriefTests` (11) lock all of it, including
  that the two analytics events carry nothing.
- **Gate:** `Entitlements.otto = paid` (the invite grant does not open it),
  AND `FeatureFlags.otto` (ON in DEBUG, OFF in Release via `ottoInRelease`,
  tripwire in `FeatureFlagTests`). With the flag off no row appears
  anywhere: a locked row would sell what the build does not contain.
- **Small-model reality:** answers are plain and a little stiff; the first
  build parroted its own instruction line and was fixed. Before the flag
  flips, Melvin and Aziz read a dozen answers on a phone, and the paid
  tier's store description, the App Privacy answers and the review notes
  are updated to name it.
- **The simulator on this Mac can run the model** (Apple Intelligence on
  the host makes `SystemLanguageModel.default` available in the iOS 26.5
  simulator), so Otto can be exercised without a phone.

## THE PAYWALL COMES AFTER THE FIRST MEDITATION (2026-09-15, Melvin)

"Let them see their scores and graphs and everything, and then lock it
behind a paywall once they try to leave." Onboarding sells nothing now
(`paywallInsideOnboarding = false`, the `.paywall` step routes on to
sign-in). The flow for a Watch owner: interview → wall → sign in
(optional; Create your profile on Friends builds) → tour home → "Put your
Watch on" with **Begin** → onboarding finishes and Home opens the setup
sheet by itself (`OnboardingHandoff`) → a real session → results **fully
unlocked** (`FirstSessionOffer.covers`, a "Your first session. Everything
is open this once." chip) → leaving the results screen opens the paywall
from ContentView (`HomeSheet.paywall`, placement `first_session`, the same
screen and ladder) → bought or declined, `markShown()` → the free tier
applies everywhere, including that session when they come back. A
no-Watch user still never meets a paywall.

- **The practice sit and its demo results are gone from the tour.** Two
  thirds of interview finishers left on them and nobody reached the demo
  results. `Step.breathe` / `.sessionResults` stay as cases (resume records,
  ONBOARDING_STEP) and route to `finish()`.
- **The grant is a device flag, not a synced field**
  (`paywall.firstSessionShown.v1` in UserDefaults). A reinstall gets its
  first session unlocked again, which is generous rather than wrong, and it
  keeps the CloudKit schema out of a monetisation change. It is applied on
  the results screen only (`entitlements.granting(covered || firstUnlocked)`),
  never app-wide, and never while a tour stage is set or for a payer.
- **`FirstSessionHooks` lives off ContentView's chain** (the FriendsHooks
  precedent). Adding the hook inline plus one more DEBUG env check sent the
  type checker over its limit; the DEBUG preview hooks are now a function,
  `debugPreviewHooks()`. `PREVIEW_FIRST_PAYWALL=1` opens the cover on a
  simulator.
- Locked by `FirstSessionOfferTests`. Analytics: `paywall_viewed` with
  placement `first_session`; the tour's two cut screens and the onboarding
  paywall carry "(cut 1.0.2)" / "(after the first session since 1.0.2)".

## DELETE A SESSION, AND THE WRIST COUNTDOWN (2026-09-15)

- **Sessions are immutable; deleting one is not an edit.** `SessionStore.
  deleteSession(id:in:)` removes the Session, its MeditationStats and its
  SessionReflection in one save. Everything derived (streak, awards, the
  Home sparkline, the calendar) reads the sessions at render time, so
  nothing else needs touching. The Watch's workout and mindful minutes in
  Health are deliberately left alone: that is the user's Health record, and
  the confirmation says so. One dialog, `DeleteSessionDialog`
  (`Coherence/Session/DeleteSession.swift`), shared by the results screen's
  ellipsis menu and the long-press menu on Home's recent rows and the
  Profile log; `SessionDeletion.delete` also takes down a Friends post when
  the reflection says the session was posted (and only then, because
  `unpost` on a never-posted session would surface a CloudKit "not found"
  in the Friends tab). **After a delete the results screen must not flush
  its reflection** (`deleted` flag): `flushReflection` in `onDisappear`
  would otherwise upsert an orphan reflection for a session that is gone.
- **A wrist-started session counts down five seconds first**
  (`WatchSessionManager.countdown`), the same "Get comfortable." the phone
  shows, because the first half-minute of a session started the instant
  Begin is tapped is the motion of settling in. Cancel returns to the start
  screen with nothing sent; params arriving from the phone cancel it. It is
  numbers on a screen and nothing else: the no-haptics rule for the Watch
  is not suspended for a countdown.

## SAVE SESSION REBUILT, AN IN-APP CAMERA, AND A PHOTO FOR EVERY SIT (2026-09-15 evening)

Aziz: "take a look at the strava UI for sharing a session and copy that, i
dont like the UI here for after the meditation" ... "review it again under
intense scrutiny, imagine you are a SENIOR UI/UX designer" ... "go on the
internet and look because i want the UI to look clean" ... "you should still
have an option to take pictures after the meditation even if its a private
one and then those pictures can be shown in the calendar". Mockups v3 to v7
in `mockups/save-session-v*.html`; v6 and v7 are what shipped. 312 tests.

- **What was actually wrong with the old screen, so nobody re-fixes the
  wrong thing:** the CONTENT was already in Strava's order. Every field was a
  filled rounded box with an uppercase label floating above it, five slabs on
  a dark ground. Two research passes over fourteen apps (Strava, Hevy,
  Strong, Gentler Streak, Nike Run Club, Whoop, Oura, Apple Fitness,
  Letterboxd, Calm, Headspace, Balance, Day One, Bevel, Flighty, Things 3),
  most read off real screenshots at pixel level, agree on the fix: **no
  boxes, no labels. Bare text on a 0.5pt hairline, full bleed between
  sections, inset to the text within one; the placeholder does the
  labelling; section headers bold sentence case, larger than body; one
  filled object on the screen, the primary action.** Letterboxd's log sheet
  (zero boxes, zero corner radii) is the closest analogue and the model.
- **Strava on iOS was misremembered twice in v3, corrected from captures:**
  nothing top right, Cancel top left, a full-width filled button pinned at
  the bottom (the top-right SAVE is Android); and its fields are outlined
  rectangles with the value inside, not list rows. Aziz chose Strava's iOS
  behaviour (kept) and then the bare skin over Strava's outlined one (B, from
  `v6.html`, where both are drawn side by side).
- **Layout, top to bottom:** the score as the one big gold number with time
  and streak small beside it; **who can see this FIRST**, because it decides
  whether the description and selfie exist (cause above effect; this is the
  one knowing departure from Strava's order); the title, bold not boxed;
  the description friends read (Friends only); the photo tile; then Details:
  technique and private notes inline (Aziz: inline). Only you hides the
  fields that address a reader who does not exist. **The button is never
  dead:** Friends with no selfie reads "Take your selfie" and opens the
  camera, then "Save session". **Skip** (new sessions) keeps the session as
  Only you under the default title, because it is already stored and a
  sheet with no exit is hostile. Gold lands three times, once per section:
  score, tile when a selfie is required, button. Cancel stays neutral where
  Strava paints it orange, for that rule.
- **A portrait photo in a landscape slot was the blocking find** of the
  senior-review pass: the old 320pt full-width tile cropped a 3:4 selfie's
  face every time. `PhotoTile` is 78 by 104 with the words beside it.
- **`SelfieCamera` replaces `UIImagePickerController` for the selfie**
  (`Coherence/Community/SelfieCamera.swift`): black, the mark centred, a
  rounded viewfinder that is not full bleed, one unfilled white ring, flash
  top right when the device offers a screen flash, Retake / Use this one.
  **No flip button**: front camera only, always, because a back-camera shot
  taken privately could be shared later by changing visibility, and the
  "you, meditating" rule would break silently. Capture is mirrored to match
  the preview. No gold anywhere on it: a coloured ring reads as a record
  button. SweatMates, which Aziz named, forces a front-and-back dual shot
  and it is the most complained-about thing in its reviews (photographing
  bystanders at the gym); not copied. `CameraPicker` survives for the
  profile photo only.
- **`SessionPhoto`** (`Shared/Models/`, in BOTH `Persistence.schema` and
  `cloudSyncedSchema`): one per session, `jpeg` external storage at 1080px,
  `thumbnail` inline at 240px so a month view never decodes a full image,
  upserted by `SessionStore.savePhoto`, deleted with the session
  (`deleteSession`) and with the account (`purgeExpired`), primed by
  `CloudSchemaPrimer`. **In the synced store on purpose:** a photo is not
  health data, so it may survive a new phone with the sessions and die with
  the account. **Optional for Only you, still required for Friends.** The
  post path always sends the bytes when there are any (about 200 KB), so a
  photo taken privately and shared later, or a post whose picture was lost,
  both come out right. **Release gate:** one more record type to promote
  Development to Production on `iCloud.com.lockout.meditate808` before 1.1
  (RELEASE_CHECKLIST.md). Privacy policy, both copies, names the photo and
  says it is shared only when the session is posted to friends.
- **Where photos show:** `MonthCalendar` draws the day's photo, 24 by 26,
  where the dot was (`photos:` is declared before `onDayTap` so the trailing
  closure call sites keep working; rows grow only in a month that has one,
  so an empty calendar is pixel-identical); `EvidenceRow` takes a 32 by 42
  `thumbnail` before the chevron; the results screen shows it whole above
  the reflection card, tapping opens Save session for Retake.
  `PhotoThumbs` caches decoded thumbnails by id plus takenAt. Every photo
  surface is behind `FeatureFlags.friends`, so the Release build is
  unchanged.
- **Hide the score on a post? Recommended no** (per-post hiding tells every
  friend what the score was, adds a decision at the worst moment, and the
  score is what makes an 808 post an 808 post; Strava never lets you hide
  distance or time). If real posts show people choosing Only you on low
  days, the shape is a once-set profile preference. In BACKLOG.md.
- Also that day, from the same list: `PendingSave` reopens the save screen
  when the phone is picked up after a sit (the in-memory hand-off died with
  the app, which is how nearly every session ends), "Silence / my own
  practice" as a technique (`MeditationMethod.silenceID`, distinct from
  `ownID`), and a Done key above the keyboard on both note fields.

## ONBOARDING CUT (2026-09-15, Melvin): seven screens out, the wall moved

"We think the onboarding is too crowded." The data agreed on cause but not
on place: the proof and plan screens lost nobody, the length did. Cut, all
routed past rather than deleted: `doingNothing`, `bodyProof` and `anchor`
left `InterviewStep` (the model never asks them; `asks()` no longer knows
them); `proofBody`, `proofYourWay`, `week` and `rating` are `Color.clear`
hops in the routing. **Every `Step` case and every answer field stays**, so
Aziz's resume records decode and ONBOARDING_STEP indices hold; a resumed
record on a cut step simply moves on. The wall (celebrity quotes) is kept
at Melvin's request and now sits after the walkthrough, immediately before
the paywall (`afterWalkthrough` → `.wall` → `afterWall`), with no chevron
back into the live session behind it.

- **The reminder time is picked, not inferred.** The anchor question set
  `reminderTime`; with it gone, `PermissionScreen` carries a compact time
  picker (`OnboardingAnswers.reminderTime`, 8 AM default), and
  `persistAnswers` stores the time unconditionally while `remindersEnabled`
  still follows the permission answer only. Without that change the
  reminder block was nested under `if let anchor` and would never have run.
- **Not done: the tour.** Two thirds of people who finish the interview
  leave on the tour's two-minute demo and nobody has reached its results
  screen. The proposal (end the tour after "put your Watch on" with a real
  Begin) is recorded in BACKLOG.md and awaits Melvin's yes.
- Analytics screen names carry "(cut 1.0.2)" so the sheet reads honestly
  across versions; the wall is "31b".

## ONBOARDING ROUND 2 (2026-09-14): one tester, thirteen fixes, one root cause

A no-Watch tester walked the interview and narrated it. `BACKLOG.md` holds
the full list sorted by cost; this is what shipped and what it taught.

- **The root cause of half the visual notes was the colour scheme.**
  `RootView` read the theme from the first Preferences row, and no row
  exists until onboarding finishes, so onboarding ran in the SYSTEM scheme.
  On a light-mode phone the entire flow was light and the app flipped dark
  on completion. "Black text", "whiter cards", "colours bleeding", a blue
  caret: all one bug. `Preferences.defaultTheme` now applies from the first
  frame. **Any screen shown before a Preferences row exists must be checked
  in light mode too**, because that is what a light-mode phone showed.
- **Back onto an answered single-select shows Continue.** Tap-to-advance
  (one affordance, Aziz) stays for a fresh screen; a screen that appears
  already answered shows the button, because re-tapping a lit tick is not an
  obvious move. `answeredOnAppear` in `OnboardingScreen`.
- **Haptics are prepared, not created per tap.** An unprepared
  `UIImpactFeedbackGenerator` can drop a pulse while the Taptic Engine spins
  up, which is why the tester felt it on some taps and not others. Two
  static generators, `prepare()` after every fire.
- **Multi-select rows draw squares** (`OnboardingOption(multi:)`); rows
  are full-strength surfaces with a hairline (contrast); scroll indicators
  hidden on the scaffold; the ScoreRing insets its stroke by half the line
  so it never clips (`DesignKit`, app-wide); the star screen has a legend;
  the wall's quote cards share one style; "Fried" is "Burnt out";
  "reasonable company" is "good company"; "meaning to start" gained "I
  haven't, honestly" and lost the overlapping "Years"; the waitlist field is
  a grey "email" field with a gold caret.
- **The $400 hardware screen left the interview and became the paywall
  ladder's first rung** (`PaywallRoute.anchor`): "Not right now" → the
  hardware anchor with 808's live price → "See the plans" back to the
  paywall, or "Not for me" → trial rung → year rung → free tier. It sells
  nothing itself (no purchase CTA, no disclosures needed); both exits lead
  to screens that carry them. `Step.hardware` and `HardwareScreen` remain
  for ONBOARDING_STEP jumps. Melvin's reasoning: an anchor belongs in front
  of the person who just declined, not mid-interview in front of someone
  who may not own a Watch.
- **Watch gate is Yes / No / Not yet.** Both no answers reach the
  waitlist; analytics `watch_gate.outcome` gains `notYet` so a planned
  purchase is a different lead from a never. Aziz's sheet maps the old two.
- **"How did you find us?" opens the interview** (`InterviewStep.referral`
  first). It sat last, and only 42% finish, so most installs never answered.
  The analytics screen name is "02b How did you find us?" from 1.0.2.
- **Not done, deliberately, awaiting Melvin + Aziz:** stating "needs an
  Apple Watch" before the interview; splitting the "Last thing" screen;
  moving the proof screens into the tour; animation; design polish. No
  HTML mockup was made for this round (revisions to approved screens, all
  small); the next new screen still gets one.

## RELEASE_CHECKLIST.md GATES EVERY SUBMISSION (2026-09-14)

Aziz: "before we push, make sure you tell us to check if these are done."
**Before archiving, uploading or submitting any build, read
`RELEASE_CHECKLIST.md` aloud with the user and walk its OPEN and ALWAYS
lists.** Do not press "Add for Review" with an OPEN item unticked unless the
user explicitly says to ship without it. `tools/archive.sh` prints the OPEN
items at the end of every run. Anything learned mid-session that must happen
at submission goes into OPEN the moment it's learned, not into a summary.

## RESUME HERE (end of 2026-09-14): state of play in one screen

Read this first after a context reset; the sections below carry the detail.

- **Branch `mvp`, pushed, clean.** 295 tests green. Release build compiles.
- **App Store:** 1.0.1 is live. 1.0.2 build 202609141719 was uploaded and is
  HELD (predates everything below; the next release needs a NEW archive).
  Do not submit anything until Aziz says so, and walk RELEASE_CHECKLIST.md
  with him first (it now lists what the next build contains and the CloudKit
  schema promotion it requires).
- **Next App Store build ships:** onboarding without the screen-one sign-in
  link, onboarding resume, the no-Watch waitlist pipe, the Watch fixes,
  Melvin's onboarding round 2. **Friends is compiled in but OFF**
  (`FeatureFlags.friendsInRelease = false`).
- **Friends (1.1) is feature-complete in DEBUG / 808 Dev:** data layer
  (CloudKit public DB, no server), Friends tab, Save session after every
  meditation (Friends / Only you, front-camera selfie required for Friends),
  Create your profile (photo + reserved @username), existing-user prompt,
  Strava-style cards and profile, invite reward, moderation (text filter,
  photo screening scaffold, report emails scaffold). Two bug sweeps done
  (22 bugs fixed; rules recorded under "FRIENDS, SECOND PASS").
- **Aziz asked for a THIRD bug sweep** after a context compaction. Areas the
  first two sweeps did not exercise deeply, so start there:
  `CreateProfileView` + `FriendsIntroView` (every door: onboarding step,
  Friends tab, Save session sheet, Edit profile), `OnboardingView` routing
  with `.profile` + resume + sign-out, `SaveSessionView` edit mode and
  offline behaviour, `ContentFilter` false positives on real names and
  handles, `RewardLedger` across sign-out / account deletion / a second
  device, `CommunityModel.load()` being called concurrently from several
  views, and anything that differs between `MemoryCommunityDatabase` and
  real CloudKit (indexes, `creatorUserRecordID`, asset URLs expiring).
- **Still owed for 1.1** (RELEASE_CHECKLIST.md "OPEN for 1.1"): CloudKit
  public record types and indexes, the Sensitive Content Analysis
  entitlement, deploying `tools/community-reports.gs`, age rating, privacy
  labels, policy and terms, store screenshots, flipping the flag, TestFlight
  on two real phones. Nothing but the username claim has run on real iCloud.
- **Short sessions (2026-09-14):** PostHog showed two "broken" sessions; they
  were Aziz tapping Begin then End within seconds. The Watch already discards
  anything under `SessionStore.minDurationSec` (30 s), but the phone showed
  nothing and logged nothing, so a start with no ending looked broken. Now
  `SessionCoordinator.lastDiscard` opens `SessionTooShortView` (via
  `DiscardHook`, after the live cover is gone) and `session_discarded` is
  tracked with reason `too_short` (an accident, never a failure) or
  `unreadable`. `tools/posthog_sheet.gs` gained both rows on the Overview;
  paste the updated script into Apps Script for the sheet to show them.
- **808 Dev on Aziz's phone** is from before the selfie change; rebuild with
  the plist-swap recipe (display name "808 Dev", restore plists after) if he
  wants to try it.

## FRIENDS (1.1, IN PROGRESS, 2026-09-14): where it stands

Aziz: a Strava-style community. Friends, not followers; post a session with
a photo; incentivise inviting. **Design record: `COMMUNITY.md`.** Mockups:
`mockups/friends.html` (v1, approved) and `mockups/friends-v2.html` (v2,
AWAITING AZIZ'S REVIEW). Ships as **1.1, separate from 1.0.2**, which is
still HELD. The 1.1 submission list is in `RELEASE_CHECKLIST.md`.

**Built and committed (feature by feature, 264 tests green):**
1. `CommunityStore` (`Coherence/Community/`) over the CloudKit PUBLIC
   database of the existing container. **No Supabase, no server** (Aziz
   asked; the answer is no). Six record types: Profile, FriendEdge, Post,
   Reaction, Block, Report. A friendship is TWO edges, each written by its
   own person, because only a record's creator can modify it in the public
   DB. Blocks are honoured both ways on every read and write. Tests run on
   `MemoryCommunityDatabase` (also the `PREVIEW_FRIENDS=1|claim` demo).
2. The **Friends tab replaced Search**: feed, search by @username, requests,
   a person page with Remove / Report / Block, report sheet, invite share
   sheet (`ct=invite` campaign link), first-run username claim, and an
   honest card when iCloud is unavailable. Reaction word is **"Nice sit"**
   with 🙏 (Aziz cut "Respect"; still a placeholder).
3. **Post to friends** from the results screen (`PostComposerView`). **Every
   post is a front-camera selfie, BeReal style (Aziz): no photo library, no
   selfie no post**, enforced in the store too. 140-char caption optional.
   First post asks one Agree to a one-line rule (Aziz: "chill on the what not
   to post thing"; the Agree stays for guideline 1.2). Invite text is Aziz's:
   "Add me on 808 Meditate, the social media for meditation: @user" + link.
   `NSCameraUsageDescription` names the selfie.
4. **Invite reward** (`Shared/Community/InviteReward.swift`): a friend I
   asked accepts AND sits once, then I get 3 sessions of full evidence
   (stacking, capped at 15; was 10 and 50 until 2026-09-15, Aziz: "10
   sessions is too much") plus the "Brought a friend" award. Per SESSION,
   only sessions started after the grant, a covered session stays covered,
   never unlocks guided or skins. Four defaulted fields on `Preferences`.
   Nothing for the invitee (Apple rejects that). The Circle skin reward was
   DROPPED: `CardSkin` has no drawing behind it.
5. v2 data groundwork: profile photo (`setAvatar`), posts gain `title` and
   `sound`, a post's record name derives from its session (saving again
   updates; Only you deletes that one), reflection gains `title`,
   `publicNote`, `visibility` (default "private" so old sessions stay private).

**Rules learned building it (do not relitigate):**
- **A post carries only the free share card's data**: score, minutes,
  streak, technique, title, sound, description, photo. Never HR, breath,
  stillness or a curve, even for paid users (5.1.3 + the free tier).
  `test_postCarriesOnlyTheFreeCardFields` pins it.
- **Anything that fetches a Shared SwiftData model and is tested against
  `Persistence.inMemory()` must live in `Shared/`.** The test target compiles
  Shared/ into itself, so an app-module class fetching `Preferences` gets a
  different class than the test inserted and SwiftData traps ("Failed to
  cast model Coherence.Preferences"). This produced the "Coherence quit
  unexpectedly" popups on Aziz's Mac; moving `RewardLedger` to Shared fixed it.
- A ModelContext does not retain its container in tests; hold it.

**NEXT, when Aziz is back (v2 asks, 2026-09-14):** nickname and @username
as separate things; username + profile photo in a Create your profile step
right after Sign in; a one-time required prompt for existing users without
a username; a Strava-style **Save session** screen that opens when a session
lands (title, description, photos, technique, **Friends / Only you**, private
notes) then results; feed card and profile in Strava's shape. **Open
decisions for Aziz before building those screens:** score shown on Save
session or saved for the results reveal; default visibility Friends or Only
you; required username (built as required per Aziz, with the unavoidable
no-iCloud exit, and a flagged 5.1.1(v) review risk with a one-switch "Not
now" fallback); private notes stay separate from the public description.
Then feature 5, moderation: caption word filter, on-device Sensitive
Content Analysis on photos, `tools/community-reports.gs` emailing reports.
Nothing has run on real iCloud yet: needs the Console record types and a
TestFlight on two phones.

## FRIENDS IS BEHIND A SWITCH; THE NEXT BUILD SHIPS WITHOUT IT (2026-09-14)

Aziz wanted the onboarding fixes in the next App Store build, and `mvp` also
holds the unfinished Friends feature. `Coherence/FeatureFlags.swift`:
`FeatureFlags.friends` is ON in DEBUG (808 Dev, simulator) and OFF in Release
until `friendsInRelease` is flipped for the 1.1 archive (`FeatureFlagTests`
fails if it is flipped early). Off means the pre-Friends app exactly: the tab
reads Search with the restored "Friends are coming" `SearchTab`, results have
no Post to friends, the app never touches the public database, the reward
sheet never shows, and "Brought a friend" is filtered off the award shelf.
**Anything new built for Friends must check the flag at its entry point.**

Known leftover while off: `NSCameraUsageDescription` (the selfie) stays in
Info.plist though nothing in a Release build opens the camera. No prompt can
appear; decide at 1.1 whether that matters, and keep the App Privacy label
free of Photos until Friends ships.

**Schema gate for the next build:** the new defaulted fields on
`Preferences` and `SessionReflection` sync through CloudKit, so Development
→ Production must be promoted before release (RELEASE_CHECKLIST.md OPEN).

The Friends section above still describes where 1.1 stands. Since it was
written: every post is a front-camera selfie (BeReal style, no library),
the rules are one line, the invite text is Aziz's, usernames are reserved
by record name (`username-<handle>`, fetched, never queried) after the
query-based claim silently failed on his phone, and a simulated run caught
and fixed two layout bugs (wide photos, the invite hidden under the tab bar).

## FRIENDS, SECOND PASS (2026-09-14 evening): the v2 asks are built

Status and decisions are in `COMMUNITY.md` → "Build status". The short
version, and the traps that cost time:
- **Save session** (`SaveSessionView`) replaces Post to friends; it opens from
  `FriendsHooks` in ContentView when `coordinator.lastSessionID` changes and
  chains into results through `pendingSheet`. The reflection's `note` is the
  PRIVATE note; `publicNote` is what friends read. Every session saved before
  this build has visibility "private".
- **Create your profile** is one view with four doors (onboarding's last step
  after Sign in, the Friends tab, Save session, Edit profile) plus
  `FriendsIntroView` for pre-Friends users. `OnboardingView.Step.profile` is
  appended after `signIn` so saved resume records keep their raw values.
- **ContentView hit the type-checker limit** when Friends modifiers were
  chained on it. They live in the `FriendsHooks` modifier; add new root-level
  Friends behaviour there, never on ContentView's chain.
- **Moderation is enforced in `CommunityStore`, not only in views**, so no
  screen can post filtered text. `ContentFilter` is deliberately blunt; do not
  add mild words (damn, hell) or substring matching (Scunthorpe).
- The photo-screening entitlement and the report endpoint are intentionally
  absent until 1.1 so the Friends-off build does not change entitlements or
  send anything; both are on the 1.1 checklist.
- **Bug sweep, same night. Two rules came out of it; hold them:**
  - **Never trust an author field in the public database.** Anyone can create
    a record and put any profile in `author` / `from`. `CommunityStore
    .authored(_:by:)` checks it against CloudKit's own `creatorUserRecordID`
    (`__defaultOwner__` for your own records) on every post, edge, reaction
    and block that is read. New record types that carry an author must use it.
  - **`CKDatabase.save` is not an upsert.** A freshly built record whose name
    already exists fails. `CloudKitCommunityDatabase.save` uses
    `modifyRecords(savePolicy: .allKeys)`. `MemoryCommunityDatabase` never
    modelled the conflict, so tests could not catch it: think about real
    CloudKit semantics, not only the fake.
  - Also fixed: re-sending a request no longer resets its date (it decides
    the invite reward); a friend's first session is stamped even if sat
    before their profile existed; the entitled-payer paywall skip moved into
    `go()` (the view version double-advanced after a purchase); Save session
    is usable before iCloud answers and can't post a scoreless session; the
    block dialog's "undo" now has a Blocked list under Requests; a failed
    profile save releases the handle it reserved; the reward ledger always
    uses the oldest Preferences row.
  - **Second sweep.** Rules to keep: **never present from ContentView while
    another cover is up or animating away** (Save session waits in
    `FriendsHooks` for the live session and any award unlock to clear, then
    700 ms); **"brought a friend" means their first session is AFTER my
    request** (otherwise adding a veteran farmed the reward); **every store
    method that calls `authored` must call `me()` first**. Also fixed: reporting
    a post from a profile reported the person; deleting your own post leaves
    the session's chip honest (`onPostRemoved`); an unrated reflection no
    longer puts 5/10 on the share card; a free user's grant is re-decided when
    the store finishes loading; a network error while claiming no longer reads
    as "taken"; Share profile needs a reserved handle; profile pages load
    uncached people; a friend's streak shows only if their last post is recent.

## NO SIGN-IN BEFORE THE END OF ONBOARDING; ONBOARDING RESUMES (2026-09-14)

**Found in PostHog, Aziz asked for both fixes.** Every one of the four people
who finished onboarding without seeing the paywall (plus Apple's two
reviewers) got there through "Already have an account?" on screen one, which
jumped straight to Sign in and skipped about 25 screens including the
paywall. One was a real stranger (Wednesbury): they answered everything,
reached the tour, left the app, came back to SCREEN ONE because progress was
not saved, and used the link to escape.

- **The link is gone. You cannot sign in until onboarding is done** (Aziz:
  "literally cannot sign in on that screen"). Sign-in exists only after the
  paywall, still optional (5.1.1). Researched: Quittr asks for sign-up early
  but it skips nothing and its paywall still stands; Cal AI's ~32-screen quiz
  ends at its paywall; the pattern is that nothing reaches the app without
  passing the offer, and payers get in through Restore Purchases because the
  entitlement rides the Apple ID. `test_firstScreenHasNoSignInLink` locks it.
- **Returning users lose nothing:** iCloud brings back `onboardingComplete`
  and their sessions, which skips onboarding by itself once the import
  lands; a subscriber who does go through onboarding is waved past the
  paywall (`store.entitled`, the on-device StoreKit record, never `.loading`
  alone) and can Restore on it. Accepted cost: someone who SIGNS OUT is sent
  back through onboarding to sign in again.
- **Onboarding resumes where it was left** (`Shared/Onboarding/
  OnboardingResume.swift`, UserDefaults `onboarding.progress.v1`): step,
  history, answers, plan, waitlist email, rating and reminder choice are
  saved on every advance and every Back, restored on the next launch,
  cleared when onboarding completes or on sign-out, and discarded after 14
  days. The live practice session and its results cannot be resumed (they
  died with the app) and reopen on the Watch connect screen. New event
  `onboarding_resumed` (with `step` and `screen`). Verified on the simulator:
  quit mid-interview, relaunch, same question, Back works, earlier answer
  still selected. Named `OnboardingResume` because `OnboardingProgress` is
  already the progress-bar view.

## BACKLOG.md IS THE LIST (2026-09-12)

Melvin: "I am saying a lot and not finishing much." Every decision, request
and open thread now lands in `BACKLOG.md` (decided / in flight / done), and a
session that hears a new one adds it there first. Two that live there and
are easy to lose: **Otto**, the on-device data-interpreter chat (Foundation
Models, iOS 26, "the data suggests", never a medical claim); and the guided
sessions in 10/15/20 minutes (Donny cuts now, the ElevenLabs voice library
on hold because it "is not there yet").

**Side-by-side beta crash, solved TWICE:** `CloudStatus.read()` (DEBUG
launch probe) derived `iCloud.<bundle id>` instead of reading the
entitlement, and `CKContainer(identifier:)` traps on a container the process
does not hold (2026-09-12). Then the friends store did the same thing by a
different road (2026-09-15): `CloudKitCommunityDatabase.ifEntitled()` trusted
`Persistence.mode == .cloudKit` and called `CKContainer.default()`, which
traps identically, and SwiftData reports sync active on the beta because it
resolves its container lazily. Both now go through `CloudEntitlement`
(`Coherence/CloudEntitlement.swift`), which reads the binary's own
`embedded.mobileprovision`; no profile (an App Store build) means trust the
App ID. **Never construct a CKContainer, default or by identifier, without
`CloudEntitlement.mayHoldContainer`. `Persistence.mode` is not proof.**
**And `CKContainer.default()` is not the entitled container:** Apple names
the default after the BUNDLE ID (`iCloud.` + bundle id), which only
coincides with our entitlement on the production bundle. The `.dev` beta
asked for `iCloud.com.lockout.meditate808.dev` and got "couldn't get
container configuration" (2026-09-16). The friends store now builds its
container from `CloudEntitlement.container` and falls back to `default()`
only when no profile exists.
The beta strips the iCloud entitlement on purpose, so on the beta friends
show the honest "iCloud unavailable" card and the rest of the app runs.

## FIRST USER FEEDBACK, ROUND 1 (2026-09-12) and what shipped for it

Eight items from the first outside testers, the day after launch. Six are in
the app; two are decisions recorded below.

- **"Save reflection" lost a note.** The tester typed a note, never saw the
  grey button, left, and it was gone. Now every edit on the reflection card
  saves itself 0.8 s after the last change (`markDirty` → `persistReflection`),
  dismissing the keyboard saves, leaving the screen saves (`flushReflection`),
  and the button is gold like Share, confirmation rather than the only exit.
  The note field's editing state now follows keyboard FOCUS (`noteFocused`),
  which also closes a latent trap where typing into an empty note could flip
  it to read-only after the first character.
- **Nobody knew the ring was tappable.** "How is this scored?" sits under it
  as a visible link to the same `ScoreMeaningSheet`.
- **"Guided meditation" is a technique option** (`MeditationMethod.guidedID`,
  first in the picker), and a guided session arrives pre-tagged with it.
  "First time meditating?" lost its question mark everywhere the title shows.
- **Do Not Disturb.** iOS has no API to switch Focus on from an app, and the
  `App-prefs:` deep links are private and rejected. The setup screen carries
  a one-line tip pointing at Control Center. Do not build a "block
  notifications" toggle that cannot do what it says.
- **Sharing leads with the system sheet** ("Share", gold): that is where the
  icons people expect appear (Messages, Instagram, Facebook, Photos). "Add
  to Instagram Story" is secondary and only when Instagram is installed.
- **Fitness / Activity sharing.** Third-party apps cannot post into Apple's
  Fitness sharing feed. But every 808 session is already an `HKWorkout`
  (.mindAndBody), and friends who share Activity already see those workouts
  with the app name; verify on a friend's phone rather than build anything.
  New: the Watch writes each session as **mindful minutes**
  (`HKCategoryTypeIdentifier.mindfulSession`, share permission added in
  `HealthKitAuth`), so it shows in Health > Mindfulness beside Apple's own.
  The privacy policy (both copies) names it. **Existing users will see one
  new Health permission prompt** on their next session.
- **Shorter guided sessions and a choice of voice (10/15/20 min, man or
  woman).** The tester loved the 25-minute journey and wanted shorter. Two
  paths, deliberately separated: (a) cheap and honest now, commission Donny
  for 10/15/20-minute cuts of the same script, no product change beyond a
  length picker on the Guided card; (b) the "AI coach" Melvin wants as the
  wedge. If (b) is built, the FIRST version must be a pre-generated library
  (ElevenLabs offline, bundled or downloaded, chosen by length and voice),
  NOT runtime generation: it keeps the App Review answers true (no AI service,
  no server), keeps sessions offline, and costs nothing per session. A truly
  adaptive coach is a backend + a privacy policy + a new review, and belongs
  behind the library. The earlier "AI narration retired" note stands for the
  flagship track only; the library is a different product from the same
  pipeline. Needs Aziz's and Melvin's go, not a unilateral build.
- **The coach's name** is open; candidates were offered, nothing decided.

## TestFlight (first build 2026-08-11; build 202608120358 — all eleven
## compliance passes — APPROVED for external testing 2026-08-13)

- **Beta App Review took ~1–2 days and approved on the first attempt.** No
  rejection, no queries. Apple sends no reliable email for beta approval: the
  build's STATUS field in App Store Connect is the only source of truth.
  Subsequent builds of the same version skip review unless entitlements,
  privacy strings or marketing copy change.
- **A development build will NOT reach the Watch after a TestFlight one,
  unless you stamp its build number.** `project.yml` hardcodes
  `CURRENT_PROJECT_VERSION: "1"`, and only `tools/archive.sh` overrides it, so
  a plain `xcodebuild ... build` installs build 1 over a TestFlight build
  numbered like 202608120358. iOS compares versions and correctly concludes
  the Watch already has something far newer, so the iPhone Watch app offers no
  update and nothing is visibly wrong. Pass the same stamp the archive script
  uses: `CURRENT_PROJECT_VERSION=$(date -u +%Y%m%d%H%M)`.
- **Never side-load the Watch app with `devicectl`.** It puts the app on the
  wrist but does NOT register it as the iOS app's companion, so
  `startWatchApp` fails and the phone reports "808 isn't on your Watch yet".
  Reinstalling the phone app then orphans it, and the iPhone Watch app refuses
  with "could not install at this time" while the stale copy is there. Cost
  most of an afternoon. **TestFlight installs the Watch app correctly and
  automatically** — verified on Aziz's hardware. So does the iPhone Watch app.
- **The beta ships under a PERSONAL bundle ID** (`com.azizmahmud.808`), not
  `com.lockout.meditate808`. A bundle ID consumed by an App Store Connect
  record can never be reused, so the production one stays untouched until the
  Organization account exists. Same for the StoreKit product IDs.
- **`./tools/archive.sh` archives, exports and checks the ipa** (distribution
  signature, push environment, CloudKit environment, Watch app present) before
  you upload. Archives land in Xcode's Organizer folder. Upload by hand from
  Organizer, or headless: a second `xcodebuild -exportArchive` on the same
  archive with `destination = upload` in the options plist uploads through
  Xcode's signed-in account, no password or API key needed (done for build
  202609130259, 2026-09-12).
- **Archiving for the App Store from Aziz's Mac works, with a swap** (first
  done 2026-09-12). His `project.yml` and `CoherenceWatch/Info.plist` carry
  the personal-team overrides and are skip-worktree, so: back both up, write
  the committed versions over them (`git show HEAD:project.yml > project.yml`,
  same for the plist), set `DEVELOPMENT_TEAM` to `WLZQLLHUB3`, `xcodegen
  generate`, `TEAM=WLZQLLHUB3 ./tools/archive.sh`, then copy the backups
  back and regenerate. `-allowProvisioningUpdates` created the org
  distribution certificate and profiles on its own; nothing had to be made
  in the portal first.
- Rejections hit so far, each visible only at upload: **90474**, the bundle
  claimed iPad support with portrait only. Fixed by `TARGETED_DEVICE_FAMILY: "1"`,
  since 808 is iPhone + Watch and no iPad layout exists.
- **A TestFlight build is a Release build, so the DEBUG raw-motion CSV capture
  is compiled out.** Breathing-engine work needs a development build over the
  cable; TestFlight sessions produce no captures.

## App Review compliance pass (2026-08-11, before the second TestFlight build)

Audited against the current App Store Review Guidelines. Fixed:

- **5.1.1 data minimization: the name screen no longer requires anything.**
  It asked for a required "First name" (typed name gated Continue) plus age.
  Apps may not require personal information the core function doesn't need,
  and 808 measures a session identically either way. Now: "What should we call
  you?" (`.nickname`, not `.givenName`), age tap selects instead of advancing,
  Continue always enabled, subtitle says both are optional. Downstream copy
  already handled empty ("Your practice profile").
- **Review gating REMOVED, do not reintroduce.** RatingScreen called
  `requestReview` only for 4–5 star answers — routing happy users to Apple's
  sheet is ratings manipulation and a live rejection reason. The sentiment
  question stays (internal signal only). If the store prompt returns it must
  be unconditional where it fires, and after a completed session, not inside
  onboarding.
- **3.1.2: the paywall now carries functional Privacy Policy and Terms of Use
  links** (sheets over the bundled docs), required on the purchase screen
  itself. Purchase/restore are actually wired to `Store` now: Continue calls
  `store.purchase(plan)` when selling and only advances on `.bought`.
- **`didPurchase` reflects reality.** The beta paywall's Continue used to set
  it unconditionally, which removed the sign-in skip and forced every tester
  to create an account for a purchase that never happened (5.1.1(v) exposure).
  `PaywallScreen`'s single exit `onDone(purchased:)` reports what StoreKit
  confirmed; beta users can now skip sign-in.
- **The no-Watch waitlist no longer holds onboarding hostage for an email**
  (second pass, same day). ctaEnabled demanded a valid address; the only other
  way forward was backing up and claiming to own a Watch. Same 5.1.1 pattern
  as the name screen. "Continue without joining" added; declining clears the
  field. Two more finds while in there: the typed email was NEVER PERSISTED
  (bound to a @State and dropped — it now lands on the local user row +
  `marketingOptIn`, where the stubbed Phase-7 export will read), and the
  paywall gate keyed on `didJoinWaitlist` where it meant "has no Watch" — now
  keyed on `answers.hasWatch`, so no-Watch users never see the paywall whether
  or not they joined.
- **Watch `NSMotionUsageDescription` rewritten** — still described belly
  breathing (cut). Same class as the removed camera string: a permission
  prompt describing a feature that doesn't exist. Committed via the index
  (file is skip-worktree).

- **Sign-in is optional for BUYERS too (third pass, same day).** The skip was
  hidden once someone purchased, on the theory that a purchase needs an
  account to attach to. False: StoreKit entitlements ride the Apple ID and
  survive a new phone with no account of ours, and 5.1.1(v) is explicit that
  registration after a non-account-based purchase must be optional — a
  documented rejection. The bootstrap-adopt flow already folds pre-account
  sessions into whatever account is made later, so nothing is lost by
  skipping. `didPurchase` is gone from OnboardingView entirely; do not
  reintroduce a forced-sign-in path.
- Verified clean in the same pass: no silent-audio background abuse (Silence
  sessions play nothing, the `audio` mode is only active while a chosen track
  plays); Instagram share degrades to save-to-Photos when Instagram is absent
  (canOpenURL-gated); METHODS.md has no breath-retention or safety-adjacent
  content; no TEMP/diagnostic UI reachable in release; `808.storekit` is not
  bundled into the app; Watch requirement disclosed in both the beta
  description and the review notes, which is what the hardware-requirement
  rule asks for.

- **Privacy manifests ADDED (fourth pass): `PrivacyInfo.xcprivacy` in both
  targets.** Neither existed, and both binaries use `UserDefaults`, a
  required-reason API Apple has enforced declarations for since 2024
  (ITMS-91053). Declared: UserDefaults/CA92.1 only; tracking false;
  **collected data EMPTY, deliberately** — Apple's "collect" means transmitted
  off device where the developer can read it, and 808 transmits nothing we can
  read (health stays on device; account/session log goes to the user's
  PRIVATE CloudKit DB we cannot access; no analytics, no server). The App
  Privacy labels at submission must therefore say "Data Not Collected", and
  if we ever add analytics or a backend, manifest and labels change together.
  `tools/archive.sh` now checks the manifest is in the ipa.

- **SIWA credential revocation handled (fifth pass).** Apple's Sign in with
  Apple rules require verifying the credential at launch; nothing did, so a
  user who revoked 808 in iOS Settings stayed signed in forever. RootView now
  checks at launch and signs out on an explicit `.revoked` only — `.notFound`
  fires transiently on simulators and fresh installs and must never sign
  anyone out. Also fixed: Settings showed "Signed in with Apple" for the
  bootstrap user; it now says "Not signed in".
- Verified this pass: built with Xcode 26.6 / iOS 26.5 SDK, past the April
  28 2026 minimum (why the upload validated); no UIRequiredDeviceCapabilities
  over-restriction. **The updated age-rating questionnaire (in-app controls,
  capabilities, medical/wellness topics) is an App Store Connect action at
  submission** — the banner on the Apps page is that questionnaire waiting.

- **HRV named in the privacy policy (seventh pass).** The Watch requests HRV
  (SDNN) read permission — it is on the permission sheet a reviewer sees —
  and `HRVRecorder` + `SessionStore` persist four HRV fields, but all three
  of the policy's health-results enumerations omitted it. Fixed in both
  copies (bundled + website), all three enumerations. The pipeline itself is
  the deliberate parked investigation; if review ever objects to the unused
  permission, the fallback is dropping the read type in `HealthKitAuth`, one
  line.
- **The changed onboarding screens were verified VISUALLY on the simulator**
  (name, waitlist, paywall, sign-in; `SIMCTL_CHILD_ONBOARDING_STEP=<n>`
  jumps straight to a screen). Every compliance edit rendered as intended.
  Worth repeating after future onboarding edits: five screens were changed
  blind across these passes before anyone looked.

- **Reminder consent now follows the ANSWER (eighth pass, policy-vs-app
  audit).** The policy says a daily reminder is sent "only if you enable it",
  but `persistAnswers` enabled it from the anchor alone: tap "Not right now"
  on the permission screen and reminders flipped on anyway (undelivered while
  unauthorized, but Settings showed ON, and a later OS-level grant would start
  firing them). `remindersEnabled` now requires the permission screen's yes
  AND the OS dialog's grant. Picking a time of day is not consent to be
  notified at it.
- **Paywall says "renews automatically" in words (3.1.2)** — "cancel any
  time" only implied it and paywalls get rejected for implying. And the
  Lifetime plan no longer promises a free week: it is a one-time
  nonconsumable with no introductory offer, so its CTA is "Buy Lifetime" and
  its footnote "charged today, nothing renews". Both strings only render once
  something is on sale.
- **Policy-vs-app audit verified TRUE at code level:** zero networking code of
  ours in any target (Apple frameworks only), zero ad/tracking APIs, zero
  now-playing reads (the "we don't know what you listen to" claim), health
  store split intact, account deletion present.
- **OPEN AND SHARP: the policy and the sign-in screen both promise sessions
  "survive a new phone" via private-iCloud sync, and CloudKit has never
  synced once.** A user who trusts that promise and wipes their phone loses
  everything. Fix CloudKit before external TestFlight or soften the promise;
  internal testers are told sync doesn't work in the What to Test notes.

- **Ninth pass: the support URL's anchor didn't exist.** The App Store
  support URL is `meditate808.com/#support` and nothing on the page carried
  that id, so it silently landed on the top of the page instead of the
  contact address. The footer (which holds `support@meditate808.com`) now has
  `id="support"`. And on an iPad running the app in compatibility mode, where
  `WCSession.isSupported()` is false, Begin used to skip the preflight and
  end in "Your Watch didn't answer" with advice to bring the Watch closer;
  it now shows the honest "No Watch is paired" screen. Also audited clean:
  the ToS makes no product-behavior claims that could contradict the paywall
  (its "trial" is the jury kind), and every user-facing Watch string.

- **Tenth pass found NOTHING to fix — the first clean one.** Verified: the
  health-consent screen's four claims are each true of the code; the daily
  reminder's notification copy is plain and guilt-free; no "first app to"
  claims anywhere; no ATS exceptions; and the zero-data home screen renders
  honestly on a fresh install (screenshot-verified). Ten passes total, finds
  in nine of them; the reading-based scan is at the bottom of the well.

## Passes 11–14 (2026-08-31/09-01, pre-submission): the well is DRY

Eleven was the free-tier build audit; twelve through fourteen ran in the
final three days with nine parallel reviewers plus two instruments no code
read can replace. Recorded here so nobody re-runs a fifteenth: **another
pass produces noise, not safety.** The remaining rejection risk lives in
App Store Connect and on the wrist, not in this repo.

- **Twelfth (3 agents: payments, onboarding claims, config/privacy).** The
  big ones: the downsell rungs and FreeTierScreen initiated purchases from
  screens with no price/renewal/legal links (classic 3.1.2), and the
  free-tier CTA bought WHATEVER PLAN WAS LAST SELECTED, so "Start 7 days
  free" could charge $99.99 for a Lifetime tapped minutes earlier. Fix was
  structural: **taking any offer preselects the plan and returns to the
  paywall; one screen owns every purchase and every disclosure.** Also:
  trial rung skipped for lapsed subscribers; the caption stopped
  contradicting Lifetime's "charged today"; the demo stopped implying the
  score shows nervous-system state; the hardware screen claims the wish,
  never similarity to named EEG devices; the policy's HealthKit bullet
  gained the HRV (SDNN) read it omitted (both copies); DEBUG launches no
  longer pollute production PostHog.
- **Thirteenth (fixes-verification + metadata + surfaces).** All twelve-pass
  fixes held. New: APP_STORE.md gained the missing SUBSCRIPTION INFORMATION
  block (title/price/renewal/ToU link — the most-rejected 3.1.2 item) and
  review notes that route a Watch-less reviewer (answer YES at the gate,
  three "Check again" taps reveal the escape); UnlockSheet stopped promising
  the free week to lapsed subscribers; USD unit-notes never render beside
  Apple's localized prices; a partial product fetch counts as not-selling;
  Release fallback copy is "Plans aren't loading" with retry, never "Free
  while we're testing"; guide breath-holds carry a skip-if-light-headed
  clause; the reminders toggle flips off when the OS denies.
- **Release-binary proof (strings(1) on compiled Release products):** every
  DEBUG marker — beta paywall copy, simulated purchase, free-tier switch,
  CloudKit panel, demo seeds, all PREVIEW_*/SKIP_ONBOARDING/ONBOARDING_STEP
  hooks, the Watch CSV capture — is provably ABSENT from both Release
  binaries. The #if DEBUG boundary holds empirically, not just by read.
- **Fourteenth (never-read files + a 22-screen human walk of the Release
  build).** The sweep's blocker: PersonalPlan promised "challenges and group
  sits" — features that DO NOT EXIST — to the user who quit over
  accountability; now answers with the streak and the share card (the
  people-not-data test still passes, honestly). Also: the resonance sheet
  stopped claiming the calm outlasts the pacing (no study supports a
  duration); the dead 7-day heart-history probe was deleted before any
  caller could break the policy's live-only promise; citations added
  (Holzel 2011, Cearns and Clark 2023). The WALK — fresh Release install
  tapped end to end exactly as the review notes instruct, declining name,
  notifications and Watch — reached the paywall with no dead ends and
  caught what no code read could: "I'll practice 5 days a week, with YOUR
  morning coffee" (person splice; anchors now carry `firstPersonPhrase`).
- **Melvin's parallel prep, reviewed and correct:** paste sheet for Connect
  (now carrying the subscription block + reviewer route), age-rating
  answers (UGC No / Social No / Wellness Yes / Medical None, with the
  guardrail that any condition-targeted guide entry flips Medical to
  Infrequent), Watch-side ITSAppUsesNonExemptEncryption, Mercury address
  log, "808 Meditate" name registered.

**What review CANNOT clear, the actual submission-day gate:** CloudKit
Production schema promotion (or the sync promise ships false); products
created at $7.99/$29.99/$99.99 with 7-day intros and ATTACHED to the
version (else the reviewer meets the fallback paywall); privacy labels →
Product Interaction (+ check whether PostHog's anonymous id needs an
Identifiers entry); age answers + copyright `© 2026 Lock Out Inc.` entered;
Muse/HeartMath ≈ prices verified the week of submission; and one real
session on a wrist with the final build.

**REVERSED 2026-08-24 — see the FREE TIER section below. The paragraph that
follows is the superseded 2026-08-11 decision, kept because its reasoning about
the `.ready` guard survived the reversal intact.**

**DECIDED (Aziz, 2026-08-11): paying unlocks the ENTIRE app — hard paywall.**
Implemented at the ROOT, not in onboarding: `RootView` locks to `PaywallScreen`
whenever `store.state == .ready && !store.entitled`, so a lapsed subscription
re-locks by itself (StoreKit's cached entitlements flip `entitled` offline).
While products can't load (beta, network) the app stays OPEN — that keeps
every pre-billing tester in with no flag, and a network hiccup can never lock
out a payer. The paywall is also trial-eligibility-aware (`store.trialEligible`
via `isEligibleForIntroOffer`): someone who already used the free week sees
"Welcome back." / "Subscribe" and a footnote without the trial promise, never
a free-week claim the purchase sheet would contradict. VERIFY with
`808.storekit` in Xcode (Edit Scheme → Run → StoreKit Configuration) before
products go live: buy → unlock, refund/expire → re-lock.
**Open tension, Aziz's call later:** the onboarding deliberately never sells
to no-Watch users (waitlist path skips the paywall), but the root gate locks
them like everyone else once billing is live — selling to someone the app
cannot measure for. Options when it matters: exempt `hasWatch == false`, or
let the waitlist copy handle it. Also noted: Accessibility Nutrition
Labels exist in App Store Connect and are OPTIONAL — declare only features
actually verified (VoiceOver etc.), never aspirationally; and "808" as a name
is fine for App Review but Roland's TR-808 mark is worth one question to the
lawyer already reviewing the four documents. Other items owed at submission: **the legal-entity swap** — the policy, ToS
and website footer named LockOut LLC. **SWAPPED 2026-08-25 (Aziz's call, no
attorney): every user-facing doc now names `Lock Out Inc.` and the ToS
governs under Delaware, matching the corp that will hold the Organization
account.** Owed by that decision: a papered LLC→corp IP assignment (one page,
both members sign — NOT a launch gate per Aziz 2026-08-25, mandatory only at
the first diligence event, cheapest in a quiet week) and the LLC's
dormant-vs-wound-down call; see LEGAL_ACTION_ITEMS.md. The website needs a manual Cloudflare redeploy to
carry it live. When the org account goes live, and ask the attorney
about the LLC→corp assignment of the app and user data (ToS assignment
clause + the policy's material-change notice). Also: App Privacy labels
matching the policy; the new age-rating questionnaire; EULA placement in App
Store Connect metadata (attorney question); StoreKit must be live or the
paywall absent — "Free while we're testing" copy must never reach an App
Store build (it flips itself once products exist, but verify).

## FREE TIER — 808 is no longer a hard paywall (BUILT 2026-08-24)

Full spec and the file-by-file record live in **`ENTITLEMENTS.md`**. 198 tests
green, verified on the simulator. The short version:

- **The rule: free gives you the score, paid gives you the evidence behind it.**
  One sentence, so a new feature sorts itself. Free keeps the score, the written
  verdict, the streak, calendar, awards, history, the home practice-score
  sparkline, nature/frequency/silence, and bring-your-own-audio. Paid unlocks
  the three curves, the metric tiles and readings, the guided journey, and four
  of the five share cards. (The sparkline was locked at first and REVERSED
  on-device same day: it draws overall scores, and every history row already
  shows each session's score to a free user, so the lock was withholding
  arithmetic on free numbers, not evidence.)
- **Why the reversal**, ascending: free users cost nothing because there is no
  backend; a hard paywall needs roughly 8x the installs at median conversion;
  and asking for money before anyone has seen a single reading contradicts the
  one thing 808 sells, which is not being asked to take a claim on faith.
- **`Entitlements` is the single gate** (`Coherence/Store/Entitlements.swift`).
  Views ask it, never `store.entitled`. **The load-bearing line is now
  `paid: entitled || state == .loading`** (changed 2026-09-12, day one on
  the App Store). Until then any state but `.ready` unlocked everyone, which
  kept the pre-billing beta open, and with products live it was a hole:
  launch in airplane mode, the store reports `.unavailable`, the curves
  unlock for anyone. A payer never needed that clause, because
  `Transaction.currentEntitlements` is cached on device; `load()` now reads
  it BEFORE fetching products, `.loading` is the only grace state (one
  product fetch long), `.unavailable` is free, and the app retries `load()`
  on every return to the foreground so an offline launch can still buy.
  Locked by `EntitlementsTests`.
- **The real paywall is the first results screen**, not onboarding. Ten minutes
  in they have their own score and three locked panels about their own body,
  which is maximum desire and an honest sell because the claim is now proven.
- **The verdict has a numberless variant** (`verdict(for:numbers:)`). Every
  phrase is its numbered sibling with the quantity removed, never a softer
  claim, because "heart settled 11 beats" IS evidence and would walk straight
  through the lock below it. `NumberlessVerdictTests` asserts no digit escapes.
- **The ladder is `trial` → `yearReframe` → `FreeTierScreen`.** One trial
  length, 7 days everywhere, renewing into Monthly, so the existing
  subscription group works untouched with no second product.
- **A `firstMonthHalf` rung was DELETED, and do not add it back without its own
  product.** It shipped 2026-08-18, sold `.monthly`, and a product carries
  exactly ONE introductory offer, which for the monthly product is the free
  week. So the screen promised a discount the purchase sheet would contradict:
  an App Review 3.1.2 problem and a plain lie. Never seen by a user (no
  production products exist). `test_noTwoRungsSellTheSameProductWithDifferentOffers`
  is the tripwire, because the mistake is invisible until a real purchase runs.
- **Sharing is NEVER locked; the CARD is.** Free posts `.score` (number,
  minutes, streak, no measured values); the other four layouts lock, and
  `.full`/`.receipt` must stay locked because they draw curves and metric
  values. **A free card showing curves would make screenshotting your own card
  the way around the in-app lock.** Every post carries the 808 mark, and that
  loop is the only organic acquisition 808 has.
- **Colour grammar held against pressure:** the Locked pill is NOT gold. A lock
  is neither chosen nor achieved. The first build made it gold and the results
  screen carried seven gold objects against a rule of one per section. For the
  same reason the share button steps down to secondary when the screen is
  locked, so the one gold CTA is the unlock.
- **Reviewing the free tier on a dev build:** flip `Store.previewFreeByDefault`
  (or launch with `PREVIEW_FREE=1`). It forces the free tier AND reveals the
  paywall's "Not right now" entry (otherwise hidden when nothing is on sale, so
  the whole ladder is invisible on dev builds). The paywall's buy button then
  SIMULATES the purchase (`previewEntitled`, persisted) so the
  lock → trial → unlock loop reviews end to end; Settings > "Free tier (debug)"
  switches back to free. All DEBUG-only. Monthly is preselected on the paywall,
  since the 7-day trial renews into it.
- New analytics: `free_tier_entered`, `locked_tapped`, `skin_locked_tapped`,
  and `paywall_dismissed` is finally fired. **Signal NAMES only, never values.**
- **Sharper now than it was:** the 5.1.3 store split keeps `MeditationStats`
  device-local, so a PAID user on a second device sees no curves at all. That
  was defensible when everything was paid. Curves are now the thing being sold,
  and it sits on top of CloudKit never having demonstrably synced.

## iCloud / CloudKit — diagnosed working; fix is Console-side (2026-08-25)

**The 2026-08-14 freeze is effectively over, because the fix turned out to
need no app change at all.** The freeze existed because touching entitlements
or privacy strings forces a new Beta App Review; the diagnosis below showed
the entitlements were fine all along and the missing piece is a CloudKit
Console schema promotion, which Apple never reviews. The freeze rule itself
still stands for any change that WOULD touch entitlements or Info.plist.

**OWED NEXT, in order (first two are Aziz's, minutes each):** (1) run the
schema primer from Settings > CloudKit (debug) on a dev build; (2) CloudKit
Console > `iCloud.com.azizmahmud.808` > deploy schema Development →
Production; (3) verify on a fresh TestFlight install that signed-in sessions
reappear, then delete the "sync doesn't work" line from What to Test.

**ORG-ACCOUNT-DAY CHECKLIST (Lock Out Inc. was APPROVED to submit,
2026-08-29; sequence for the shippable version, no app changes anywhere):**

1. **Container-collision check: DONE 2026-09-01, CLEAN.** The org's
   Identifiers list shows `iCloud.com.lockout.meditate808` and it is ticked on
   the `com.lockout.meditate808` App ID, so the personal-team registration
   never blocked it and NO config change is needed. The entitlement is written
   `iCloud.$(CFBundleIdentifier)`, which expands to exactly that container.
   (`iCloud.com.lockout.coherence` also sits in the list, a leftover from the
   old project name. Unused, and containers can never be deleted.)
   **One residual check for step 4:** confirm the container appears under Lock
   Out Inc. in the CloudKit Console. If it turns out to live under the personal
   team, the Production promotion has to happen there instead.
2. **DONE 2026-09-01.** `com.lockout.meditate808` registered under the org with
   HealthKit, Sign in with Apple, iCloud and Push all ticked (In-App Purchase
   too), and `com.lockout.meditate808.watchkitapp` exists with HealthKit.
3. **Primer NOT needed, verified 2026-09-12.** Development had all five
   `CD_` types with every field, optionals included (Melvin's dev builds had
   written them all: 17/17/16/15/15 fields = model fields + CloudKit's 7).
4. **DONE 2026-09-12 (Aziz, with Melvin's Console login).** Deployed
   Development → Production on `iCloud.com.lockout.meditate808`; Production
   Record Types now lists the five `CD_` types plus the built-in `Users`.
   **This was the gap found AFTER launch:** 1.0 went live 2026-09-10 with a
   Production environment that had NO record types, so every App Store
   sign-in's export failed silently for two days. No data was lost (it all
   lives on the phone) and pending exports retry on later launches, so
   affected users self-heal with no update. Lesson, so it never repeats:
   **a CloudKit promotion is a release step, not a follow-up.** Put it on
   the same checklist as "attach the products" for every future container.
5. **VERIFIED 2026-09-12, by accident and by instrument.** Melvin set up
   a fresh App Store install on a second phone at ~10:50 EDT, signed in,
   and within 30 minutes of the 11:30 schema promotion his sessions from
   the other phone appeared. We know because he tapped two of them and the
   new PostHog `result_missing` alarm fired (no local stats on the new
   phone, by 5.1.3 design), which is the trail that proved the sync.
   The promise covers account, sessions, streak, history; curves never
   roam. **Copy gap this exposed, for 1.0.1:** the sign-in screen promises
   sessions "survive a new phone" without saying measurements stay on the
   phone that recorded them, and `missingStatsCard` explains the rule but
   gives no next step ("your next session on this phone shows
   everything"). Neither is a code change; both are one sentence.
6. Agreements, Tax, and Banking: sign Paid Applications, enter Lock Out
   Inc.'s bank + W-9. **Mercury cleared 2026-09-01, so this is unblocked;
   the W-9 was filed the same day (C corporation, exempt payee, EIN, Dover
   address to match the IRS record).** **Nothing in the app carries or needs banking info.**
   Enroll in the **Small Business Program** the same sitting (15% vs 30%).
7. Create the products EXACTLY as compiled:
   `com.lockout.meditate808.{monthly,yearly,lifetime}`, monthly + yearly as
   auto-renewables in ONE subscription group at **$7.99 / $29.99**, both
   carrying the **7-day free intro**; lifetime as a non-consumable at
   **$99.99**, no intro (its CTA says "charged today" on purpose). The app
   flips itself when products load (`state == .ready`): real sell copy, free
   tier live, no build change and no flag.
8. At submission: App Privacy labels flip to Product Interaction (PostHog),
   the new age-rating questionnaire, and a `808.storekit` rehearsal in Xcode
   (buy each plan once; the config mirrors the real stack exactly).

Where it actually stands, so nobody re-derives it:

- **Melvin's container now exists and is correctly entitled.** He created
  `iCloud.com.lockout.meditate808` in Xcode; the provisioning profile for
  `WLZQLLHUB3.com.lockout.meditate808` grants it, verified by reading the
  profile. Xcode showing the container in **red is stale UI**, not an error.
  This is his personal dev container and is unrelated to the beta, which ships
  from Aziz's account under `com.azizmahmud.808`.
- **The schema was never deployed and must not be yet.** Deploying is a
  CloudKit Console action rather than an app change, so it would not itself
  trigger review, but it is pointless before we know sync works and it belongs
  to whichever container actually ships.
- **`CloudSchemaPrimer` exists for when we do deploy** (`Shared/`, DEBUG only).
  CloudKit builds the Development schema **lazily from what the app writes**,
  and a nil attribute writes no field: the five synced models carry 13
  optionals, so ordinary use would leave most fields out, and Production is
  additive and manual with no lazy creation. Core Data's
  `initializeCloudKitSchema()` does this job and SwiftData does not expose it,
  so the primer writes one row of every synced model with every attribute
  non-nil. Deploy, then delete the rows: deleting records never removes fields.
- **DIAGNOSED 2026-08-25, on-device: SYNC WORKS on dev builds and always
  has.** `CloudSyncProbe` (DEBUG, `Coherence/Settings/`) prints the whole
  story to the cabled launch console: mode "CloudKit sync active", container
  `iCloud.com.azizmahmud.808`, account available, setup + repeated import
  AND export events all `succeeded=true` on Aziz's phone. The silent
  fallback never fired; the Development schema had built itself lazily from
  real writes. The readout just had never been read.
  - **The real defect: TestFlight talks to CloudKit PRODUCTION, and the
    Production schema has never been deployed.** Development builds schema
    lazily; Production only ever gets schema by manual promotion in the
    CloudKit Console. So cabled dev builds sync perfectly while every
    TestFlight install exports into an environment with no record types and
    fails. That one difference explains every "sync never worked" report.
  - **The fix sequence (Console actions, no app change, no new review):**
    (1) run `CloudSchemaPrimer` from Settings > CloudKit (debug) on a dev
    build so the Development schema carries ALL fields (13 optionals write
    no field until primed; Production promotion is additive and manual);
    (2) CloudKit Console > `iCloud.com.azizmahmud.808` > deploy schema
    Development → Production; (3) fresh TestFlight install, sign in, check
    sessions appear on a second install. The same promotion must later be
    repeated on `iCloud.com.lockout.meditate808` when the Organization
    account exists — put it on the org-account-day checklist.
  - Remaining honesty gap even after promotion: `MeditationStats` is
    device-local BY DESIGN (5.1.3 split), so curves never roam. The sync
    promise covers sessions and the streak, and the results screen already
    explains a synced session without local stats.
- **The promise is now backed by evidence on dev builds** (see the diagnosis
  above). It becomes true for TestFlight the day the schema is promoted to
  Production; until then the What to Test note stays. Verify a real
  second-install round-trip before deleting that note.

## Marketing, advertising, and persuasion copy (standing rule, Melvin 2026-08-20)

**Always apply Eugene Schwartz's *Breakthrough Advertising* when working on
anything marketing-, advertising- or psychology-adjacent**: the website,
onboarding, the paywall and its downsell ladder, App Store copy, reels,
end cards, and any ad or social content. The parts that matter most here:

- **Channel existing desire, never manufacture it.** People already want a
  calmer mind, proof they're improving, a habit that sticks. Copy's job is to
  aim that at 808, not to argue people into wanting it.
- **Meet the prospect at their stage of awareness.** Someone who has never
  meditated needs the problem named; someone who quit needs the mechanism
  (why THIS works when the last app didn't); someone who practises daily needs
  only the new claim (scored, verified, shareable). The onboarding personas
  map to awareness stages; use them.
- **The headline's only job is the felt effect.** A number without a feeling
  attached is trivia (this is why the research section leads "A sharper mind"
  before "+16 points").
- **Intensify by demonstration, not adjectives.** Show the low-scoring session
  next to the high one; show the real graph. 808's whole position is proof,
  so the copy must never out-claim the instrument.
- Schwartz never licenses invention. Every claim stays sourced and honest;
  the em-dash rule and the no-invented-numbers rule still bind.

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
- **Signing: ONE org team since 2026-09-01.** The Organization conversion
  **preserved the Team ID**, so Lock Out Inc. is `WLZQLLHUB3`, the same string
  Melvin's individual account used. Nothing had to be repointed, and every
  build made before the conversion was already signed by what is now the org.
  Archive with `TEAM=WLZQLLHUB3 ./tools/archive.sh`; the override exists so
  nobody edits a tracked file to ship. Aziz switches from `H5ZH6P56Q8` /
  `com.azizmahmud.808` to the org team and the production bundle IDs when he
  next builds for release. The paragraph below describes why the two-account
  split existed and is kept for the beta's history:
- **Signing WAS per-developer and LOCAL (never committed).** The repo commits
  `DEVELOPMENT_TEAM: ""` and `com.lockout.meditate808`. But the two cofounders have
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

- iOS app: `com.lockout.meditate808`
- Watch app: `com.lockout.meditate808.watchkitapp`
- iCloud container (Phase 7): `iCloud.com.lockout.meditate808`
- StoreKit products: `com.lockout.meditate808.{monthly,yearly,lifetime}`

**Renamed from `com.lockout.coherence` on 2026-08-11, before anything was
registered.** Chosen over `com.lockout.808` because Apple documents the
identifier's character set as letters, dot and hyphen only; digits are
everywhere in practice but an all-numeric component is not worth gambling a
permanent identifier on. `meditate808` also matches the domain.

**These are permanent. Both the bundle IDs and the product IDs.** A bundle ID
consumed by an App Store Connect record can never be reused, even after the
app is deleted, and App IDs are unique across all developer teams. Do NOT
register these under either cofounder's personal account to try something out;
they belong to the Organization account when it exists. The pre-Org internal
TestFlight uses a personal identifier instead (Aziz: `com.azizmahmud.808`).

## Entitlements timeline

Phase 0 entitlements files are empty (`<dict/>`). Add later:

- **Phase 1** (both targets): `com.apple.developer.healthkit` = true
- **Phase 7** (iOS): `com.apple.developer.applesignin` = ["Default"];
  `com.apple.developer.icloud-container-identifiers` = ["iCloud.com.lockout.meditate808"];
  `com.apple.developer.icloud-services` = ["CloudKit"]; `aps-environment` = "development"

**Info.plist usage strings:** the Watch needs `NSMotionUsageDescription`
(CoreMotion drives stillness + belly-breathing) alongside the HealthKit strings.
**HealthKit scope:** the Watch requests heart-rate **READ**, **HRV (SDNN)
READ** (the dormant baseline pipeline, added 2026-08-07; up to 30 days of
Apple's passive samples) + workout **SHARE**. No heartbeat-series read (that
was the dropped coherence path). The privacy policy's scope bullet names all
three; keep them in lockstep.

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

- `Coherence/` — iOS app sources (bundle `com.lockout.meditate808`, embeds the Watch).
  `DesignKit.swift` holds the shared UI vocabulary (ScoreRing / EvidenceRow /
  MetaChip / MonthCalendar) — reach for it before writing a new card or row.
  `Onboarding/` is the 26-screen flow: `OnboardingKit` (colour arc, CTA, option
  rows, the screen scaffold), `OnboardingInterview` (the 12 questions),
  `OnboardingPayoff` (calculating → projection), `OnboardingOffer` (paywall,
  exit offer, sign-in), `OnboardingView` (routing + persistence).
- `CoherenceWatch/` — watchOS app sources (no ModelContainer)
- `Shared/` — compiled into both apps + the test target: `Models/`, `Engine/`
  (`SignalEngine.swift` — breathing/stillness/HR analysis — plus `StreakCalculator`
  and `VerdictEngine.swift`, the rule-based spoken verdict), `Onboarding/`
  (`OnboardingModel.swift` — the interview's questions and its arithmetic, pure
  and tested), `Connectivity/`
  (`SessionPayload.swift` — the Codable Watch↔phone transfer contract),
  `Session/` (`SessionStore.swift` — iOS persistence helpers),
  `Theme/AppColor.swift`, `Persistence.swift`, `Assets.xcassets`
- `CoherenceTests/` — iOS unit tests (host app Coherence)
- `Meditations/` — guided-narration working files (54 MB). **Gitignored on
  purpose**; the shipped track lives in `Coherence/Audio/Guided/`.

## Build

```
xcodegen generate
xcodebuild -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme CoherenceWatch -destination 'generic/platform=watchOS Simulator' build
xcodebuild test -scheme Coherence -destination 'platform=iOS Simulator,name=iPhone 17'
```
