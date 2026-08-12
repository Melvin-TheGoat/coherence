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
    - `OnboardingKit.swift` — the **colour arc as a modifier**. Screens declare a
      SECTION, never a colour: amber (relief) → teal (the body enters) → red
      (cost) → gold (the win). No screen hand-rolls a background.
    - Interview is now **12 questions**: baseline · why · stress · alone-with-
      thoughts · doing-nothing · restarts · how-long · causes · watch gate ·
      anchor · you · attribution.
    - **Departures from the spec, deliberate:** commitment moved BEFORE the
      projection (the projection is arithmetic *from* the committed days/week);
      the progress rail shows during the interview only; paywall position is one
      constant, `paywallInsideOnboarding`.
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
  - Business: **Delaware C-corp** question from the lawyer (he advised a DE
    corporation over the MI LLC for hiring/investors/exit — this would ADD an
    entity, not fix a mistake; the LLC, EIN and in-flight D-U-N-S all stay valid).
    **D-U-N-S case 10747633** with D&B — documents sent, awaiting the number.
    Lawyer redlines pending on the four docs in `~/Desktop/808-legal-review/`.
    Meta app ID still needed for zero-tap Instagram Stories.

## TestFlight (first build shipped 2026-08-11, build 202608112356)

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
  Organizer.
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
- **Watch `NSMotionUsageDescription` rewritten** — still described belly
  breathing (cut). Same class as the removed camera string: a permission
  prompt describing a feature that doesn't exist. Committed via the index
  (file is skip-worktree).

Still owed at App Store submission (not TestFlight): App Privacy labels
matching the policy; the new age-rating questionnaire; EULA placement in App
Store Connect metadata (attorney question); StoreKit must be live or the
paywall absent — "Free while we're testing" copy must never reach an App
Store build (it flips itself once products exist, but verify).

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
