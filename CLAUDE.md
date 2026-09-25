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

## SCORE v5.3.0: stillness is cubed, not floored (2026-09-16, Melvin)

A real user's card showed stillness 75%, heart 74 → 79, breathing 6.2/min
and a score of 1. The formula was exact: v3's `spreadStillness` mapped
[0.80, 0.98] onto [0, 1], so 75% earned nothing, a climbing heart earned
about 0.03, and the 6.2/min had no qualifying doorway. Melvin: "scale it so
that if it's higher it matters more, but lower down it doesn't just cut
off." `spreadStillness` is now raw cubed. Measured on the scale: 0.84 → 0.59,
0.90 → 0.73, 0.97 → 0.91 (a 13-point gap of the 40 on offer between a good
sit and a great one, against 29 under the floor and 5 under a straight
line); 0.75 → 0.42, 0.50 → 0.13, 0.22 → 0.01. That user's session goes from
1 to about 18. The card's percentage and the score's stillness now move
together. Migration key `scoreBackfillDone.v8` rescores all history.
`OttoBrief`'s score rules say "cubed". Heart term unchanged: 60% for time
at or below the opening rate, 40% for the size of the drop, which is
already "the longer you stayed under your start, the better."

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
- **THE MODEL DOES NO ARITHMETIC (2026-09-16, Melvin).** On a real sit
  Otto said "still for 0.76 seconds", invented an opening rate of "50 to
  60 bpm" and summed "60% + 40% + 0% = 100%", then got it right on a
  regenerate. A 3B model handed rules and raw numbers will do sums, and do
  them differently each time. Now `SignalEngine.breakdown` (the same code
  path as `score`, so ring and explanation cannot disagree) exposes every
  term, and `OttoBrief.scoreCard` writes the working in POINTS already
  scaled to the sit's cap ("Heart earned 0 of 45", "Stillness 0.76, cubed
  0.44, 13 of 30", "Total 0 + 13 + 0 = 13"), plus the only two
  hypotheticals allowed (at 10 min; with a doorway), the band the score
  sits in (the model called 13 "deep and held" once), and a rule-ranked
  COACHING line by points left. Every table row carries its points and
  band too. Sampling temperature 0.3. **Iterate in the lab, not on a
  phone:** `test_dumpBriefForTheLab` writes the brief for a sit shaped
  like Melvin's (`TEST_RUNNER_OTTO_BRIEF_OUT=/tmp/otto_brief.txt`), and
  `tools/otto_lab.swift` puts questions to the same model on the Mac,
  `RUNS=3` for consistency. Rules learned there: state facts as
  descriptions, never prohibitions (a "never seconds" rule was parroted
  back verbatim); precompute anything the model must compare (bands);
  avoid words with a second meaning ("doorway held 2:30" became "held the
  breath", now "kept up for").
- **Chats persist** (`OttoChatStore`, one JSON per session under
  Application Support/Otto, plus "profile" for the general chat; never
  synced, since a transcript quotes heart rates). Reopening replays the
  last six turns into a fresh `Transcript` under the CURRENT brief, so a
  chat reopened after new sits knows about them. Deleted with the
  session, on sign-out, on account deletion and on credential revocation.
  The ellipsis menu offers "Start a new chat".

## 1.1 IS THE SOCIAL RELEASE, ON BRANCH `social-1.1` (2026-09-18)

Melvin: ship the social update on its own and ASAP, because it is what
users want, and Otto and camera vision would hold it up over privacy work.
So the release branch is **`social-1.1`**, not `mvp`: Friends ON
(`friendsInRelease = true`), Otto OFF, camera vision not on it, version 1.1.

- **Followers and following, with no new data.** The friend edge has always
  been directional (`from` asked, `to` was asked), so following is who a
  person added and followers is who added them; a mutual pair is the
  friendship that already existed. `CommunityStore.follows(of:)` reads both
  for anyone; for MY profile `CommunityModel.follow` does the arithmetic on
  the lists already loaded and queries nothing. `FollowLine` sits under the
  handle on Profile and on a person page, and each half opens its list in
  its OWN sheet (both screens already present sheets; stacking them on one
  view is the only-one-presents trap). The friend-count stat tile came off
  the row, which was five wide and is now four.
- **ONE technique list, in `TechniqueOptions`** (Melvin: "the options need
  to be the same as when you log it for yourself. This is obvious."). Save
  session offered `loggable` and stopped; the results card also offered
  "Something else" with a free-text field. Both now render the same menu
  content and Save session carries the field, so a technique added anywhere
  appears in both. `SessionStore.saveSession` gained `techniqueNote`
  (nil keeps what is stored, so a caller without the field cannot wipe it).
- **Silence and Breath work lead the picker.** `breathworkID` joins
  `silenceID` and `guidedID` as loggable-but-not-a-guide-entry: the guide
  teaches specific patterns inside its methods, and this is the plain
  category people reach for. Silence lost its "/ my own practice" tail,
  which overlapped with "Something else".
- **The code-side release work is done**: the privacy manifest declares
  Photos or Videos, Other User Content and Name, all LINKED (the public
  database is one we CAN read, which is what Apple's "collect" means); the
  privacy policy has a "Friends and posts" section and its short version no
  longer claims we see nothing; the terms have section 6a, user content and
  no tolerance for objectionable content, with report, block and removal
  spelled out for guideline 1.2.
- **NOTHING IS SUBMITTED UNTIL THE CONSOLE WORK AND A REAL ROUND TRIP ARE
  DONE WITH AZIZ** (Melvin's call, same day). Friends has never run against
  real iCloud beyond the username claim, and the public record types need
  their QUERYABLE INDEXES in Production: indexes are never created lazily
  the way fields are, so without them every feed, search and request fails
  on a real install while the simulator's fake works perfectly. That is the
  1.0 failure exactly, on the one feature whose value is the server. The
  rest of the list is RELEASE_CHECKLIST.md "OPEN for 1.1".

## HOME FIXES, MOCKUPS FOR OTTO IN A TREE, AND THE ANIMATION ANSWER (2026-09-20)

- **The sky runs under the status bar.** A `.background` inside a
  `ScrollView` cannot escape the safe area, and padding the scene from
  outside leaves the band above its background. The fix that works: the
  scroll view ignores the top safe area and the scene pads ITSELF by the
  inset (`ottoScene(topInset:)`) before its background. Two wrong attempts
  are in the git history; do not repeat them.
- "0 mornings" is "day streak" again, and **sessions replaces sits** in
  every user-facing noun (Otto's brief, the guide count, Profile's stats,
  the awards, the score sheet, "Nice session"). Verbs stay ("how to sit").
- **Dark mode is gone on purpose** (Aziz, 2026-09-19, "One appearance"):
  the palette is sampled from Otto's cream art and a dark build needs a
  second Otto. `Preferences.theme` stays stored, unread.
- **Home is direction B, built (Melvin: "Go with B for home, build it").**
  `mockups/home-v3.html` drew four placements; B is Duolingo's shape: Otto
  (talking pose, 104pt, bleeding 22pt past the left gutter) sits beside a
  speech bubble under the greeting, on the sky gradient with rounded bottom
  corners, then the streak pill. `ottoScene(topInset:)` in ContentView;
  `OttoBubble` and the `ottoBreathing()` scale pulse (5 s, anchored at the
  feet) in OttoView. **The bubble's lines are rule-written from the streak,
  practiced-today and rest-day state (`ottoLines`), never generated**, and
  tapping Otto cycles them. (The breath-doorway tip that always closed the
  list is gone since 2026-09-22; see "OTTO JIGGLES" below.)
  A, C and D stay in the mockup. `mockups/onboarding-v3.html` (Headspace's
  nine screens, Otto's face, "N of M" counter, breathing head top-left) is
  still AWAITING MELVIN'S SIGN-OFF. Serve `mockups/` with the launch
  config; data: URLs drop the images.
- **Otto moves with Rive (Melvin: "ok lets go with rive").** Researched and
  recorded in BACKLOG.md: state machine driven from Swift, rigs the existing
  PNGs, Duolingo uses it, $9/month to export, official MCP from the desktop
  editor. **Blocked on Melvin's side until the Rive desktop editor is
  installed and signed in on this Mac** (the MCP is served by the editor
  at 127.0.0.1:9791; `claude mcp add --transport http rive
  http://127.0.0.1:9791/mcp`). Until then the `ottoBreathing()` pulse is
  what ships; it is the one place to swap for a `RiveViewModel`.
- **Uploading from this Mac works once the Apple ID is in Xcode.** The
  first "No Accounts" was timing, not a missing certificate;
  `-allowProvisioningUpdates` minted the distribution cert. **Never pipe
  the upload through `head`:** it closes the pipe at N lines and can kill
  xcodebuild mid-upload. Log to a file and grep after.

## OTTO IS RIGGED IN RIVE (2026-09-20): `Coherence/Otto/Otto.riv`

Built through the Rive editor's MCP from this session, on the file Melvin
created (editor.rive.app/file/otto/2597495, cloud only, no path on disk).
The runtime is `RiveRuntime` 6.27 via SPM in project.yml. `OttoRive.swift`
holds `OttoRig` (loads the file, binds the view model, exposes `wave()` and
`talking`), `OttoRiveView` (the rig, or the PNG with the SwiftUI pulse when
the file is missing or fails to load: a bad export costs motion, never a
screen) and `BreathHaptics` (a CoreHaptics swell on the same 5 s period,
off by default, for onboarding's breath screen only; Home never buzzes).

- **Shape of the rig.** Artboard `Otto` 400x470, transparent. Node `Nod`
  at the feet (200, 460) > node `Body` > Solo `Pose` holding the talk and
  wave PNGs, each offset so its bottom edge sits on the node. Timelines:
  `Breathe` (300 frames, loop, Body scale 100 to 103.5 percent from the
  feet), `Wave` (72 frames, one shot: Solo flips to the wave PNG, Body
  rocks -5/3/-2 degrees with a scale bump, flips back at frame 66), `Talk`
  (48 frames, loop: Nod rocks 1.5 degrees and dips 3 pt), `Still` (empty).
  State machine `Otto`, two layers so they mix: `Body` (Entry > Breathe,
  Breathe > Wave on the `wave` trigger, Wave > Breathe at 100 percent exit
  time) and `Head` (Entry > Idle, Idle <> Talk on `talking`). View model
  `Otto`: `wave` trigger, `talking` boolean, bound to the artboard; the
  runtime's `enableAutoBind` hands the instance to Swift.
- **The MCP cannot create bones** (its own words), so the arm does not
  bend: the wave is a pose swap plus body motion, Duolingo's cheaper trick.
  If a bending arm is wanted, draw three bones on him by hand in the editor
  and the MCP can bind and weight the mesh.
- **Things that cost a round each, so they are not re-learned:**
  `createLinearAnimations` takes duration in SECONDS (72 became 4320
  frames); set frames afterwards on property 57. Scale keyframes are in
  percent (100, not 1). Exit time only works as a percentage here: flags
  (152) = 12 (enableExitTime 4 + exitTimeIsPercentage 8) and exitTime (160)
  = 100; in frames or seconds it fired at once. Uploaded images default to
  hosted and excluded from export; set exporttypevalue (358) = 0 and
  includeinexport (801) = true or the .riv ships without pixels. The
  editor is sandboxed: it can neither read the PNGs from the repo nor
  write the export anywhere, so upload as data URIs and export with
  `inline_base64: true` over `curl -N` (without `-N` the body came back
  empty). New artboards carry a grey fill; delete it. The session's
  transport carries no session id; every call works stateless.
- **Verified:** `simulateStateMachine` shows Entry > Breathe, Breathe >
  Wave at the trigger, back at frame +72, Idle <> Talk on the boolean; the
  simulator shows the rig on Home and tapping Otto waves. The first build
  crashed because the runtime's convenience init is `try!`; the rig now
  loads through the throwing inits and logs "Otto rig:" on failure.
- **Redesign pending (Melvin, same day: "too childish, slightly more
  realistic and furry").** `mockups/otto-redesign.md` is the brief and
  prompt. The rig survives the swap: same pose names, same framing,
  replace the two image assets in Rive, export over the file.
- **Onboarding v3 is approved except the breathing screen**, which now
  reads: Otto sits and breathes, nothing rises (the mockup is updated). The
  Swift build of the nine screens waits for the redesigned art, because
  every screen is built around his face.

## ONBOARDING IS HEADSPACE'S SHAPE NOW (2026-09-20, Melvin)

"Redo the onboarding by copying headspace... although the intro screen where
the head comes up and down should instead be a good animation of Otto
breathing." Built to `mockups/onboarding-v3.html`. The flow is now welcome,
three breaths, the paced breathing screen, the interview, what's waiting,
reminders, health consent, sign in, profile, tour.

- **Three screens open it** (`OnboardingV3.swift`): Otto waves through the
  Rive rig; "let's take three breaths together"; then three paced breaths
  with a Continue after the first, because a breathing exercise with no exit
  is a trap. They exist because of where people actually leave: sixteen
  strangers reached the first screen in thirty days and twelve left on the
  second.
- **THE WHOLE PAYOFF BLOCK IS CUT**: calculating, the result, the cost, the
  sample-session pair, the commitment and the wall. Every `Step` case and
  answer field stays and the routing hops past, per the standing rule.
  **The analytics said that block lost nobody**, which is why it survived the
  09-15 cut; it goes because it is not in the shape Melvin asked for, not
  because it was failing. **Watch `onboarding_completed` against the pre-cut
  rate: if finishing drops, this is the first suspect.** Nothing outside
  `Onboarding/` reads `daysPerWeek`, `primaryCost` or `PersonalPlan`, checked
  before cutting.
- **The progress rail is gone; Otto breathes beside a count.** The count is
  honest per person, because the model already skips questions whose premise
  the reader contradicted, so "3 of 8" is three of THEIR eight.
  `InterviewCount` carries it and fifteen question screens take it.
- **`Step` IS `Int`-BACKED, SO NEW CASES GO AT THE END. ALWAYS.** The two new
  screens were first added after `breath`, which renumbered thirty-odd cases
  by two, and a saved resume record would then have reopened somebody on a
  different screen than the one they left. Caught before it shipped. The enum
  now says so at the point of temptation.

### Otto breathes at six a minute, and the rig holds two poses

- **The `Breathe` timeline is ten seconds** (600 frames), not five. It was
  five, which is twelve breaths a minute, while every piece of copy and the
  Watch orb claim six. Home, the onboarding breath screen and the Watch now
  agree, and the claim is true.
- **The rig carries its own art, so `OttoRiveView(pose:)` could not change
  what it drew.** The breathing screen asked for the cross-legged pose and
  got the waving one, because the rig only held the wave. There is now a
  `sitting` boolean on the view model and a `Pose` layer with `PoseWave` and
  `PoseSit`, which cross-fade two images by opacity rather than a Solo. The
  Swift side sets it from the pose (`pose == .meditating`).
- The other poses (awake, head, talk) are in the Rive file as ASSETS only, so
  they show in the editor's Assets panel without joining the export.

## ONBOARDING, ROUND 3 (2026-09-19, Melvin): two questions and the Watch screen go

- **`aloneWithThoughts` and `you` left `InterviewStep`** (the `doingNothing`
  precedent: the `Step` case and the answer field stay, the model never asks,
  the view routes past). The name is asked on Create your profile beside the
  handle, so `you` asked for it twice, and its age was read by nothing.
  `nextAfter` returns `.calculating` for a Step not in `interviewPairs`, so a
  cut step must route to the LAST ASKED step before it (`aloneWithThoughts`
  and `doingNothing` go to `nextAfter(.stress)`), not to `nextAfter(self)`.
- **The tour is the whole tutorial.** Continue on its last note calls
  `finish()`; `watchConnect` ("Put your Watch on") is routed past and
  `OnboardingHandoff.requestSetup()` is no longer called, so Home opens with
  nothing asked and the first session starts at the plus. Melvin: "let them
  explore the app on their own". Resume fallback is `tourHome`.
- **The tour's spotlight on the plus was 18pt low and full width.** The
  `.begin` anchor sat after `.offset(y: -18)` and `.frame(maxWidth:)`, so it
  measured the un-offset slot, and the top of the raised circle fell outside
  the lit window. It now sits on the button itself, before both. Verified on
  the simulator: the whole circle is inside the window.
- **The bar had too much air under it.** `MainTabBar` had 8 over the icons
  and 2 under the labels on top of the home-indicator inset; now 6 and 0.
  The feed's bottom spacer was 72 to "clear the bar", but the bar is a
  safe-area inset and the scroll already clears it; 24 clears the raised half
  of the plus and nothing more.

## OTTO IS DRAWN; FRIENDS AND PROFILE GET THEIR AIR BACK (2026-09-18)

- **SUPERSEDED 2026-09-19. Otto is ART now, not a drawing.** He shipped as
  vector paths parsed at runtime from `mockups/otto-sloth.html` by a small
  `SVGPath`, which was the right call while he was a one-colour line glyph
  that had to take the theme's tint. He became a full-colour character in
  the friendly redesign, and a character is art: `OttoArt.swift`, `SVGPath`
  and `OttoArtTests` are DELETED and the poses ship as image sets. The
  reasoning that put him in code (a raster cannot recolour, an image model
  will not hold a line-art language across three sizes) was sound and stopped
  applying the moment he stopped being line art. See the Rive section below
  for how he is animated, and `mockups/otto-redesign.md` for the art brief.
- **The Friends feed was too dense** (Melvin: "look at strava, much more
  spaced out, and it has padding around the images and the text"). The post
  card bled to both screen edges with the photo running wall to wall and
  8pt between cards, so nothing had air and one sit ran into the next. Now
  an inset rounded card with ONE inset constant for every child
  (`PostCard.inset`, 18), the photo inset and rounded like the text, 16pt
  between cards and between the feed's sections, and bigger avatars and
  touch targets on the person rows. A feed is read while scrolling, so the
  white space is what separates one person's sit from the next.
- **The profile lost two things** (Melvin: "too crowded, i dont think otto
  should be in there. nor the next: half an hour"). Otto's row is gone from
  Profile: its door is the results screen, where the person is looking at
  the sit they want explained and the question has a subject. `OttoView()`
  with no session id still opens on the last ten sessions, so the general
  chat is not lost, it just has no second door. The "Next: <award>"
  progress card is gone too: on a screen already showing the streak, four
  stats, the shelf and every session, one more bar reads as another thing
  undone, and the shelf already shows what is unearned.

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
- **THE SELFIE ROTATION, MEASURED AT LAST (2026-09-18). Do not re-derive
  this from reasoning; four fixes were, and all four were wrong.** What
  Aziz's iPhone 17 Pro Max actually hands back from the front camera:

      pixels 4032x3024 (LANDSCAPE), orientation tag = .down,
      connection videoRotationAngle = 90, isVideoMirrored = false

  So **`videoRotationAngle` does not rotate the delivered pixels**, and the
  tag is `.down`, a HALF turn, which leaves the frame landscape however it
  is applied. Every earlier attempt either applied the tag and kept a
  landscape image, or assumed the tag meant a quarter turn and swapped the
  target size, drawing the shot on its side and squashing it.
  `uprightMirroredSelfie` therefore decides from the PIXELS: apply the tag
  only when doing so yields portrait; if the pixels are already portrait,
  ignore the tag; if both are landscape, turn it clockwise. Then mirror, as
  its own step. The screen is portrait only and front camera only, so a
  landscape result is wrong by definition.
  **The lesson that matters more than the fix:** the simulator has no
  camera and `log collect` on a device needs root, so this was guessed at
  four times across two people. It was solved in one round by
  `SelfieDiagnostics` (DEBUG, `SELFIE_DEBUG=1`), which writes the raw file,
  each intermediate and a facts sheet to Documents/SelfieDebug for
  `devicectl device copy from --domain-type appDataContainer`. **When a bug
  only exists on hardware, ship the instrument before the fix.**
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

## THE RIVE EXPORT ONLY EVER EMITTED THE FIRST ARTBOARD (2026-09-20, FIXED)

**The rig ran on the second attempt and the diagnosis in between was wrong,
so the correction is worth more than the fix.** The previous note said
`Otto.riv` shipped the editor's default names because the rig had been built
on the default artboard. It had not. The editor's file always held an
artboard `Otto` and a state machine `Otto`, exactly as asked for. The EXPORT
is what dropped them.

**What the export actually does here: it emits the FIRST artboard in the
file and nothing else.** The file carried the editor's leftover
`iPhone 16 - 1` from the day it was created, so every export returned that
and the rig never left the editor. Measured, not guessed:

- Renaming the leftover artboard changed the next export immediately, and by
  exactly the difference in name length, so the export is live rather than
  cached.
- An artboard CREATED through the tool never appeared in any export, and one
  DELETED through the tool kept appearing. Seven exports, byte identical
  across property edits.
- `includeinexport` (key 802 on an artboard, 801 on an asset) is not the
  gate. Setting it both ways changed nothing either direction.

**The fix is to leave exactly one artboard in the file.** Delete the
editor's default artboard and any unused image assets, then export. The
result went from 352 KB of the wrong thing to 212 KB containing `Otto`,
`Breathe`, `Wave`, `Talk`, `Still`, the `Body` and `Head` layers and the
`wave` / `talking` view model properties. **A Rive file that is meant for a
runtime should hold one artboard.** If a second is ever needed, expect to
prove it exports rather than assuming it does.

**Verify from the binary, then from the runtime, never from the editor.**
The editor's own `listArtboards` reported the rig correctly the entire time
the export was empty of it, so the editor cannot confirm its own export.
Counting name bytes in the `.riv` takes a second and would have caught this
on day one. The runtime is the second check: the loader NSLogs
`Otto rig: bound` on success, and on failure names the artboards the file
offers beside the two the app needs.

**`print` from an app launched by simctl never reaches `log show`.** That is
why the original failure was invisible for a day. Anything that explains a
silent fallback has to be legible without a debugger attached.

### The wave is a separate arm layer, because bones cannot be weighted here

**Melvin drew a bone chain in Rive and asked for the hand to wave. Bones
are the right tool and they do not work through this MCP.** `bindBones`
succeeds and `autoWeight` runs, and then `querySkin` shows **288 of 289
vertices weighted 1.0 to the root bone** with the forearm and hand bones
influencing nothing. Moving the root 200 units and re-weighting changes
nothing, so it is not a placement mistake. Do not spend another afternoon
on it: if a skinned limb is ever needed, the weights have to be painted in
the editor by hand.

**What ships instead: the arm is its own image, rotating about the elbow.**
`tools/otto_cut_arm.py` splits `otto-wave.png` into `otto-wave-body.png`
and `otto-wave-arm.png`. It cuts by SEVERING, not by a half plane: a half
plane was tried first and takes the head with the arm, because the arm has
body on one side and head on the other. So it erases a thin band along a
line running from the gap between the hand and the cheek, down through the
forearm, into the background below, then keeps the connected island that
holds the hand. **The arm keeps a 26 pixel band past the cut and draws on
top**, which is why the joint does not open when it turns, and why the
swing has to stay under about ten degrees.

The Wave timeline rotates that layer 0, -12, +10, -10, +8, -5, 0 over 72
frames. Verified by capturing the artboard at both extremes before keying
it, and then on the simulator.

**TWO RIVE UNITS THAT COST A ROUND EACH.** An image's `originX` / `originY`
are **PERCENTAGES, not fractions**: 50 is the centre, and passing 0.5 puts
the origin in the top left corner, which moves the art rather than the
pivot. And a traced mesh (`generateMesh` with `trace: true`) renders the
image exploded and enormous; a plain subdivided rectangle (`trace: false`,
`subdivisions: 4`) is correct and is all a deformation needs anyway.

**What Melvin had done, and why none of it could work:** the pose had been
moved into its own artboard and nested back in, so the bones and the image
were in different artboards and bones only bend a mesh in their own. The
old body node had been deleted with the Breathe keyframes pointing at it,
and a second artboard had appeared, which silently breaks the export. All
of that is rebuilt. A `.rev` backup of the state before the rebuild is in
the session scratchpad.

### The rig as it now stands

Artboard `Otto`, 400 by 520, transparent, the only artboard in the file.
Node `Nod` at (200, 510) holds node `Body` holds Solo `Pose`. **An image sits
its feet on its parent node at `y = -height / 2`**, which is the one number
to recompute when the art changes size. State machine `Otto`, layers `Body`
(Entry to Breathe, Breathe to Wave on the `wave` trigger, back at 100 percent
exit time) and `Head` (Idle and Talk on the `talking` boolean), verified with
`simulateStateMachine` and then on the simulator.

**The redesign left one pose, so the Solo swap inside `Wave` is a no-op.**
`OttoTalk` and `OttoWave` are the same image now, and the file embeds one
asset, `otto-v2-wave` at 384 by 505. The swap is kept because it costs
nothing and a second pose would use it. **Swapping the art later means
replacing that embedded asset in Rive and exporting again**; the image sets
in the app are a separate copy and the `.riv` cannot read them.

## OTTO BREATHES FROM THE CHEST, BLINKS, TALKS, AND SITS ON A BRANCH (2026-09-20, second pass)

Melvin, on the first rig: he is not breathing, he is off centre, he is not
talking, he is too small, he is not waving, and "I want him on a branch
somehow. some kind of greenery". Everything below is that list. The rig is
still `Coherence/Otto/Otto.riv`, still ONE artboard, now 425 x 522 with five
state machine layers: Body, Head, Pose, Branch, Blink.

- **The breath is a CHEST PATCH, not a whole-body scale.** The old Breathe
  timeline scaled the entire body 3.5 percent from the feet, which reads as
  the picture zooming, which is why he "wasn't breathing". `tools/otto_chest.py`
  cuts a feathered ellipse of his chest out of each pose, keeping the FULL
  canvas so it lines up with no arithmetic, and the rig draws that patch on
  top of the art and swells it about 6 percent on the standing pose and 9 on
  the sitting one (his sitting belly is smaller, so the same percentage reads
  as less) while the body underneath moves under 2 percent. **The feather is the whole trick**: a
  hard-edged patch shows its rim as a seam, and alpha falling off over 46
  pixels hides the handover. Verified by scaling it to 112 percent and
  capturing: no seam anywhere. Still 600 frames at 60fps, so still six breaths
  a minute.
- **Two poses, two patches.** `ChestWave` lives inside the WavePose group and
  rides its opacity; `ChestSit` is a sibling of `SitPose` and is keyed in the
  `PoseWave` / `PoseSit` timelines by hand, because it has no group to inherit
  from.
- **He blinks.** A `Blink` layer loops a five second timeline: two lid shapes
  (ellipses in the mask brown with a radial gradient, plus a curved lash path)
  scale down over the eyes for about 240ms. **A straight rectangle lash read as
  a glitch; a crescent reads as a closed eye.** The lids live inside WavePose,
  so the meditating art, whose eyes are already closed, never blinks twice.
- **THERE IS NO MOUTH. The art's own face is the face.** Two rounds were spent
  on one: first a mouth that chattered through nine keyframes over a nodding
  head ("looks weird, just show the still with his mouth open"), then a single
  dark shape held open at the smile line, which Melvin read for what it was:
  "theres an oval over his lips, get rid of that". A shape laid over a face
  that was painted with lighting and shading reads as a sticker, whatever it
  is doing. `MouthOpen` and `MouthHole` are DELETED and the `Talk` timeline
  keys nothing. **Do not draw another one.** The `talking` boolean and its
  state stay wired so a future idea has somewhere to land, and what makes his
  lines read as speech is `OttoSpeech`: the words arrive typed, one character
  at a time, out of a bubble whose tail points at him.
- **`OttoSpeech` is what makes it read as speech**, and it is Duolingo's
  bubble now (Melvin, 2026-09-21, with a screenshot of "Hi there! I'm Duo!"):
  **see-through, an outline and nothing else**, text centred, and the tail
  drawn as part of ONE path (`SpeechBubbleShape`) so the line runs unbroken
  into the point. It types at **about 300 characters a second** ("make the
  text appear like 10x quicker"; it was 30), so a two-line line lands in a
  quarter second. **Unarrived characters are laid out in clear ink**, which
  keeps line breaks where the finished line puts them; revealing a growing
  prefix reflowed centred text as it typed. Home's `OttoBubble` is still the
  filled one, because Home is frozen for Melvin's critique.
- **The breathing screen buzzes, and it is the only screen that does.**
  `BreathHaptics` (built earlier, unused until now) plays a swell on the
  inhale and a softer fall on the exhale on the rig's own ten seconds, started
  on appear and stopped on disappear and before the hand-off. The Watch still
  plays nothing, Home still plays nothing, and the simulator plays nothing at
  all, so this can only be judged on a phone.
- **The branch is a `branch` boolean, and Home never sets it.** Otto's feet sit
  at the bottom of the artboard, so a branch needs room that is not there. A
  new `Stand` node between the artboard and `Nod` carries the whole figure, and
  the `BranchOn` timeline shrinks it to 72 percent and lifts it onto the limb
  while the branch group fades in and sways. **Growing the artboard was the
  obvious move and it is wrong**: every screen that draws Otto without a branch
  would have got smaller. Keyframes that referenced `Nod`'s old absolute y had
  to move with it (Talk keyed 512; Nod is now 0 inside Stand).
- **`OttoOnBranch` draws him the full width of the screen**, past the screen
  padding, so the limb runs off both edges instead of ending in mid air. The
  artboard's proportions make that frame 483pt tall on a 393pt phone, most of
  it empty sky, so the view shows only the bottom 360 to 420 of it and clips
  the rest.
- **He was never waving, and the reason is worth keeping.** `enableAutoBind` is
  asynchronous; the welcome screen fires its wave 0.45s after appear, and on a
  cold launch the data-binding instance does not exist yet, so the trigger went
  nowhere. `OttoRig` now holds a pending wave and fires it on bind, and re-sends
  `talking`, `sitting` and `branch` there too, since `onAppear` routinely beats
  the binding.
- **"Off centre" was a square frame.** The view framed itself `size` by `size`
  while the artboard is 425 x 522, so `.contain` letterboxed him and
  `.bottomLeft` pushed him to one side. `OttoRiveView` now takes the artboard's
  aspect by default. **Home passes an explicit `width` to keep its old square
  frame**, because it is the one screen Melvin asked to leave alone.

### Rive things that each cost a round

- **`group_editor` ignores the `x` / `y` it is given** and places the group at
  the artboard origin. Set the position afterwards with `set_property_values`
  (13 and 14), in the parent's local space.
- **`createParametricShapes` honours a `paints` array; `addPaints` on a shape
  that already has a fill does nothing.** A parametric shape is born with a
  grey fill, so recolouring one later means `setPaints` on the existing Fill
  id, which is the shape id plus two for these.
- **A container's child list is front to back, and this cost TWO rounds.** A
  newly added child lands at the END, which is BEHIND everything. The wave
  pose's chest patch was invisible until `bringForward`, the fix was applied
  there and only there, and the SIT pose's patch sat behind the sit art for a
  day: Melvin's "im not seeing him breath at all on the second screen" was
  exactly that, and the small motion left on those screens was the branch
  swaying, not a breath. **When a fix is a draw-order fix, apply it to every
  sibling that was added the same way, and prove each one by exaggerating the
  scale and capturing.** A diff of two screenshots a half-breath apart shows
  the belly's outline lit up when it works.
- **`export_file` still requires `destination` even with `inline_base64`**,
  although nothing is written there when the editor is sandboxed.
- Leaves and limbs are freeform paths (`createShapes`), not ellipses: an
  ellipse reads as a blob, and a lens with two pointed tips reads as a leaf.

## THE SIT IS THE PRODUCT: A VALLEY, NO WATCH, NO ONBOARDING (2026-09-21, Aziz)

Three asks in one line, and they are one change: 808 stops being an
instrument you need hardware for and starts being a meditation app that
measures you when it can.

### The session screen is `mockups/session-v3.html`, built

`Coherence/Session/SessionScene.swift` (the valley) and a rewritten
`SessionActiveView` (the clock, the lines, End). The breathing orb is gone.

- **The sun does what a progress bar would.** One number, `progress`, drives
  the sky gradient, the sun's height and size, the mountains, the meadow, the
  cloud colour, the stars and the light on everything alive. It cannot be read
  precisely, which is the point.
- **It ends at dusk, not at dawn.** A sunrise would be a brighter screen at
  the moment somebody is most settled, and by the middle of a sit the screen
  has to be dark enough to sit with in a room at night.
- **The clock is on the whole time** (Aziz, same day, revising the first
  build). It used to hide after the opening and come back for three seconds
  on a tap, on the argument that a countdown you cannot look away from is the
  opposite of the thing being sold. It is not: a timer you have to go looking
  for is a timer you keep touching the screen for, which is worse. Tabular
  digits, because a countdown redrawing every second must not shuffle
  sideways past 9:59.
- **The ring is a MEDALLION IN THE SKY, not a hoop around him.** At 79% of the
  width centred at 39.5% of the height it ran **88pt into Otto's face on a
  tall phone and 137pt on a short one**, measured. `SitLayout` now hangs it
  off the top of his head with a fixed 12pt clearance on every device, and
  sizes it off BOTH axes (`min(w * 0.40, h * 0.175)`) so a short screen does
  not have to choose between the ring and the headline. The figure scales
  with its ring rather than sitting at a fixed 46pt.
- **`SitLayout` is the one place the geometry lives**, shared by the scene and
  the screen on top of it, because both need to know how big Otto is and
  where his head ends. Its scale is `min(w / 300, h / 620)`: scaling by width
  alone made him eat a short phone, since he is sized by width and placed by
  height, and on a 667pt screen that put the top of his head 130pt higher up
  the frame than the composition intends.
- **The headline is centred in the band between the island and the ring**,
  not pinned to a fraction of the height. A flat 12.5% sat in the Dynamic
  Island's shadow; a second flat fraction low enough to fix that collided
  with the ring on a short phone. Centring it in the space it actually has
  drops it about 45pt on a tall phone and still clears on a short one.
- **An open-ended sit gets the track and NO arc.** The arc is a proportion of
  something and there is nothing for it to be a proportion of. Its clock
  counts up. The sun still moves, over a nominal twenty minutes, as
  atmosphere. Nothing claims otherwise.
- **Composition numbers are ported as fractions, not pixels** (horizon 34%,
  Otto 24%, ring centre 39.5%, ring 79% of the width). The mockup is a 300pt
  panel, so one scale factor ports every size in the file.
- **The meadow is ONE `Canvas`, not 26 view hierarchies**, drawn back to
  front: smaller and paler toward the ridge, bigger and brighter at the
  bottom edge, which is what makes a flat field read as ground going away
  from you. **Never reorder `Meadow.flowers`: the draw order is the depth.**
- **The palette is hex literals and that is correct here.** The house rule
  ("never hardcode a hex") protects themeable tokens from drifting. These are
  keyframes of a painting interpolated every frame, an asset catalog hands
  back a `Color` whose components cannot be read, and dusk is dusk on every
  phone. `DayLight.at(progress)` is the one place they live.
- Not built: the "Instagram is open again" chip. The blocker does not exist
  yet and a screen must not advertise a feature the build does not contain.
- `PREVIEW_BREATHING=<seconds elapsed>` opens the sit at any moment of its
  arc, so the whole day can be reviewed without waiting ten minutes.

### Begin never asks about a Watch

**A meditation app that refuses to time a meditation because of missing
hardware has stopped being a meditation app.** The first pass made the Watch
optional, checking for one and falling back. Aziz cut the check too: "dont
even ask if a watch is there."

**So `begin` runs the sit on the phone, unconditionally, in the same runloop
turn.** Gone from it: the WatchConnectivity pairing probe, `startWatchApp`,
the workout authorization, and the 45-second watchdog that waited for a wrist
to confirm it began (`armStartWatchdog` and `convertToPhoneSession` are
deleted with it).

**What that costs, so nobody rediscovers it: a phone-started sit is not
measured, even for somebody wearing a Watch.** Heart, stillness and breath all
come off the wrist and the wrist is not being launched. A Watch owner who
wants readings starts from the Watch, which still composes its own params,
runs the full pipeline and ships its payload here; `persist` writes it exactly
as before. Two paths now, nothing in between: **phone starts a timer, wrist
starts a measured session.** The asymmetry is deliberate. The phone's Begin
belongs to the person sitting down, and it was spending up to forty-five
seconds, a permissions screen and a whole failure vocabulary on hardware most
people do not own.

- `SessionCoordinator.ActiveSession.engine` is `.watch` or `.phone`;
  `beginOnPhone` runs the sit here (clock, sound, write). `.watch` is now
  reached only by `adoptRunningSession`, when the wrist announces its own.
- `Session.source` (`"watch"` / `"phone"`, defaulted, CloudKit-safe) exists
  because **a phone sit and a session synced from another device look
  identical in storage and need opposite sentences.**
- **`SessionStore.persistPhoneSession` writes a Session and NO
  `MeditationStats`.** An empty stats row claims we looked and found nothing,
  and nothing was looking. Everything derived (streak, awards, calendar,
  counts) reads Sessions, so a phone sit counts everywhere and simply has no
  score.
- **`SessionStore.persist` now bails on an existing SESSION too**, not only
  existing stats. The watchdog handover can leave a Session with no stats, and
  a payload landing afterwards would insert a second row under the same id;
  SwiftData enforces no uniqueness, by design, so nothing would have
  complained. Same reason `sessionFailedToStart` ignores a Watch refusal while
  `active?.engine == .phone`.
- **The first-session paywall is skipped for a phone sit**, which is now
  every sit started here. The offer is "you
  have just seen your evidence, here is how to keep seeing it", and that sit
  produced none.
- Copy swept of hardware it no longer needs: the Begin screen, Otto's first
  Home line, the "First meditation" award, the results card ("You sat, and it
  counts"), Save session (Time becomes the hero when there is no score).
- **`EvidenceRow` prints no stat columns for a phone sit and no empty score
  capsule.** Three em dashes under Heart, Still and Breath is the card telling
  somebody what they are missing, which is the one thing this product's copy
  never does.
- **Still Watch-gated, and Aziz should know:** posting to Friends carries a
  score, so a phone sit cannot be posted (Friends is off in Release anyway),
  and the share card is built from measurements. Both need their own pass.
- `PhoneSessionTests` locks the write path, the streak, the floor, the
  idempotency and the late-payload case.

### Onboarding is gone (REVERSED 2026-09-22, see "ONBOARDING IS BACK")

This pass also removed onboarding; Melvin restored it the next day. The
record, and what changed when it came back, is "ONBOARDING IS BACK" below.

## PROFILE IS THE VALLEY TOO, AND IT COUNTS MINUTES (2026-09-21, Aziz)

Built from `mockups/profile-valley.html` after four passes. The page is the
grass Home stands on, with a 20 percent band of the valley at the top and
nobody in it, and your practice on cards below. `ProfileTab` in
`SessionHistoryView.swift`.

- **Otto's head IS the portrait.** Aziz: "no more pfp and make the sloth in
  the circle." He sits in a sky circle with a white ring, straddling the
  identity card's top edge. The photo pipeline (`setAvatar`, the photo step
  in Create your profile, `CameraPicker`) is still wired and is now unused
  on this screen; removing it is its own job.
  **The cost, stated:** everybody's avatar is the same sloth, so a Friends
  feed of six people is six identical faces. The fix already exists and is
  not built: draw each person at THEIR aura stage.
- **"Your scores" is "Your minutes"** (Aziz: "we dont wanna worry about any
  of the watch stuff"). A phone sit measures nothing, so a score chart would
  be an empty frame on almost every page. Length is what a phone can report
  honestly, and the research this app is built on says consistency predicts
  improvement while session length does not, so a chart of minutes is a
  record and not a target. **Amber stays**: it has always meant the measured
  quantity of a session, which with a Watch is its score and without one is
  its length.
- **An UNEARNED score award is hidden, not deleted.** The three `.depth`
  awards are unreachable from a phone, and three permanently grey trophies
  is the shelf telling somebody what they are missing. A wrist session still
  earns them, and an earned one appears on the shelf as normal.
- **Pills are controls, content is bare.** The first pass drew four floating
  boxes and Aziz said "something seems off". The repo's own 14-app research
  answers it: no boxes, bare text on a hairline. The rule that came out of
  that pass, and it resolves the question every new screen asks: **a cream
  capsule is something you press; a number you read sits on the card.**
- **Sampled from Melvin's Home, not invented.** A cream-on-cream pass was
  rejected ("more on theme with what we have not this pastelish color"); the
  page now uses the grass, the white cards and the amber bars that Home
  already uses, so the two tabs are one place.
- **"practiced", not "practised"** (Aziz). American spelling everywhere.

### The transitions, and the two things that went wrong in them

Aziz: "remember to do good trnasitions so everything is smooth." The valley
never moves; the five cards rise 16pt and fade, 55ms apart, on the app's
spring, and the chart's bars grow from the floor on the same curve.

- **Flip the flag on the NEXT runloop turn, never inside `onAppear`.** An
  `.animation(value:)` animates EVERY animatable change in its subtree at
  the instant the value flips, and flipping it during the first layout pass
  caught the cards' own width settling under the `GeometryReader`. The text
  re-wrapped as they widened: "Only you" arrived as "Onlyyou" and the
  chart's axis label crossed its header. Letting layout finish first leaves
  the animation nothing to carry but the opacity and the offset.
- **A child must not carry its own animation inside an animating parent.**
  The chart had a slightly slower spring for its bars, so it also re-drove
  the position its card was already moving it to, and slid up a beat behind
  its own card. One object, one curve.
- **The chart's y-domain is PINNED while the bars grow**, or the axis grows
  with them and the arrival reads as the numbers changing.
- Verified the way this project verifies motion: a screen recording at 20fps,
  frame differences to find the moving window, then the frames themselves.
  Two screenshots half a breath apart cannot resolve a half-second stagger.
- **The gear rides the scene, not the screen.** Pinned to the top right of
  the window it sat on top of whatever card scrolled under it and collided
  with the stats row's last number.

### The log is a WEEK, and a session is its length (2026-09-22, Aziz)

Two notes, one problem: "the all sessions screen the way they are just all
laid out isnt the best way to do it" and "i dont like the sloths on all the
meditations". Every session was a full-width card with a 98pt picture panel,
and with no selfie that panel drew Otto, so nineteen sessions was nineteen
identical sloths. **Nothing was scannable because every row weighed exactly
what every other row weighed.** Mockups: `sessions-list.html` (three
directions) then `sessions-week.html` (the chosen one, scoped to a week).

- **The card IS the week**, Monday or Sunday by the device's own
  `firstWeekday`, and the current one is called "This week". Arrows step,
  the card swipes, and the label opens a picker. The header carries the only
  two numbers a week is worth, how many times you sat and how long in total,
  which is the line the minutes chart is made of. The forward arrow is
  dimmed on the current week.
- **A week, not a month, and not everything.** A week is the unit the
  product already thinks in (one rest day per seven, Home's seven-day
  strip), it fits on one screen without scrolling, and its two numbers are
  small enough to mean something.
- **A session is its length first** (Aziz picked direction C): an amber puck
  where the repeated Otto used to be, then the day, then the sound and the
  score if there is one. **The puck is the soft amber, never the accent.**
  Seven saturated gold pucks down a page would spend the one-gold-per-section
  rule seven times and leave nothing on the screen emphasised; a tint is a
  material, the accent is a decision.
- **A phone sit is short a clause, never told it lacks a score.** The
  subtitle is "Silence" or "Silence · scored 66", and nothing says "no
  score".
- **Only SHARED sessions carry a chip.** Every row said "Only you" in the
  first build, which is nine identical capsules down one card: the same
  repetition that got Otto taken off these rows. A chip earns its space when
  it marks the exception, and posting is the exception. The Friends banner
  lost "Everything marked Only you stays here" for "Everything else stays
  here", because the copy may not promise a marker the rows no longer draw.
- **An empty week gets four words and no advice**, and no summary line: "0
  sessions, 0 min" is a scoreboard of nothing. Past weeks print full dates
  on their rows, since "Friday" is ambiguous once you are not in this week.
- **Tapping a day on Home opens that day's WEEK** instead of filtering the
  log to the day, which is what it used to do. A one-day filter inside a
  week view is a second, invisible scope on top of the visible one.

### The week picker, and the month-view rule it does not break

`WeekPicker` is a month grid whose ROWS are the targets: the whole row
lights, tapping anywhere in it selects that week, and a dot marks a day
practised so the sheet answers "which week was that" before anything is
chosen. `SessionCalendar.monthGrid` already returned rows aligned to
`firstWeekday`, and `test_monthGridRowsAreWeeks` pins a row to the week the
log then shows, so tapping a row can never land on a different seven days
than the one touched.

**This does not reopen "808 has no month view anywhere".** That rule is
about a grid as a STATUS display, which answers "did I show up" at a
resolution nobody needs and draws days that have not happened. This one
exists only while you are choosing, selects weeks, and is gone on the tap.

### Four things the animation cost, all worth keeping

- **`.animation(_:value:)` governs its whole subtree, and an outer one wins.**
  The week slide did not animate AT ALL, and the proof is that three
  screenshots across a deliberately three-second spring came back
  byte-identical. The card sits inside `rising(settled:)`, whose
  `.animation(_:value: settled)` had already claimed the subtree. Naming the
  animation again on the inner container, keyed to `weekStart`, wins it back.
  Same family as the arrival bug earlier in the week: that modifier is
  greedier than it looks, in both directions.
- **A cross-fade between two pieces of TEXT is two legible weeks stacked on
  each other.** The header label was left behind while the rows slid, and
  mid-flight it read as a rendering fault. The label and its summary now
  carry the same identity and transition as the list, inside a fixed 38pt
  frame so the arrows do not bob when the summary line comes and goes.
- **Not a paging `TabView`.** Paging forces one height on every page and a
  week of one session is a fifth the height of a week of six. One view whose
  contents change, a transition for the slide, and a drag gesture that
  commits past 60pt.
- **A DateFormatter takes the device's zone, not the calendar's.** A week
  start is a midnight in the calendar it was computed in, so "Sep 6 to 12"
  printed as "Sep 5 to 11" four hours west of UTC. Set `f.timeZone` and
  ONLY that: handing the formatter the calendar too renders months as "M09"
  whenever that calendar carries no locale, which is what a hand-built one
  in a test is.

### How to see a slow animation when the recorder is wedged

`simctl io recordVideo` can leave the host recording locked with no process
to kill, and then every later recording fails with "Host recording is
already in progress". Slow Animations in Simulator's Debug menu did not take
either. **What worked: build once with the animation set to
`.linear(duration: 12)`, take single screenshots, then put the real spring
back.** A screenshot lands somewhere between one and four seconds after the
tap that triggered it, so nothing shorter than about eight seconds can be
caught this way.

### Coming, so nothing is designed against it

**The sloth will be customizable, and points come from habitual practice**
(Aziz, 2026-09-21). Recorded at the top of `BACKLOG.md`. It means the
portrait circle on this page is a fitting room later, and it means points
have to be earned by consistency rather than by score, since a phone sit has
no score.

## THE WEBSITE CARRIES A GOOGLE "PREFERRED SOURCE" BADGE (2026-09-21, Melvin)

In the footer, its own row above the copyright: the Google G and "Add us as a
preferred source on Google", linking to
`https://www.google.com/preferences/source?q=meditate808.com`, the deeplink
Google documents for sites that do not load its script
(developers.google.com/search/docs/appearance/preferred-sources). **Deliberately
the link and not Google's `publisher.js` button**, so the site still loads
nothing from a third party. What it does is modest: a reader who adds 808 sees
it favoured in Top Stories and AI Overviews, which an app landing page rarely
appears in. Whether meditate808.com is even listed in Google's source tool
needs a signed-in Google account to check, so that is Melvin's to click.
**Live only after the manual Cloudflare Pages redeploy.** The footer still
says "Meditation, measured on your Apple Watch" under the retired flower mark,
both left alone as out of scope.

## THE QUESTIONS ARE DUOLINGO'S SCREEN, AND 808 IS NOT A WATCH APP ANY MORE (2026-09-21, Melvin)

Melvin, with Duolingo's "What would you like to learn?" and "Just 7 quick
questions" screenshots, after raising the corner-Otto layout twice: "LOOKS
UGLY ... can you lock in". The standard this sets: **when he sends a
reference screen, build that screen.** Not a reading of it.

- **The pivot, to hold everywhere:** 808 is becoming a meditation app with
  many features, social first, with a camera session coming. Stop writing as
  if the Watch is the product. The welcome line is now "Hi there! I'm Otto.
  Let's meditate together." and What's waiting leads with "Meditate your
  way." Any new copy that is only true for Watch owners needs a reason.
- **Question screens** (`OnboardingScreen` whenever it has a `counter`): the
  back arrow and Duolingo's thick progress bar share the top row; Otto with
  the clipboard stands under the arrow, still (no pulse); the QUESTION is
  his line, typed into a bubble whose tail points left at his face; the
  answers sit close under him. **No "N of M" and no subtitle** on these
  screens. `OnboardingCounter` is deleted. The bar opens at the answered
  fraction and grows into this question as the screen arrives, and it fills
  at THIS reader's last question because the fraction is of their own list.
- **Answers look like Create your profile's fields**: a white plate, radius
  12, no outline; chosen is a 2pt gold outline over a faint gold wash.
  Single-select rows draw no radio circle (the whole row lights); multi-select
  keeps its square, the one cue that a second tap adds.
- **Every onboarding CTA is the profile screen's lifted gold button**
  (`OnboardingPrimaryButtonStyle` = `PrimaryButtonStyle` + the two-pulse
  haptic, which now lives in `PressHaptic`). The flat gradient is gone.
- **The question-count screen is only the bubble and Otto**: "Just **8 quick
  questions** before your first session!" The number is still the derived
  ceiling (a newcomer answers 7), and the bold runs come from markdown in
  `OttoSpeech`.
- **Bubbles hug their words** and read left-aligned, like Duo's.
- **The drifting wave behind onboarding is deleted** ("not on theme"), and
  with it the `ambient` switch on the ground and the scaffold.
- **`OttoOnBranch` derives its window from its width** (`aspect / 0.86`)
  instead of a height per screen. A hand-picked 360 cut his head off on the
  count screen and 400 shaved his tuft on the welcome screen.
- **No delay before Otto speaks.** The welcome line waited 1.4 s for the
  wave; Melvin read it as the screen lagging.
- **THE BREATH, FOURTH PASS: the sitting pose is a MESH** (Melvin, same day:
  "still not breathing ... it doesnt progress past the first breathe in").
  Two separate failures. (1) The chest patch was real but too faint to see
  on a phone. The sitting image now carries a 9 x 9 mesh (`generateMesh`,
  `trace: false`, `subdivisions: 3`, 81 vertices in the image's centred local
  space) and `Breathe` keys 285 vertex positions: the lap and hands never
  move, the chest widens about 15 percent, the shoulders and head rise about
  6 units. It warps the one image, so there is no seam to hide, and
  `ChestSit` is DELETED. The displacement lives in one function (rows by
  height, widening capped at the torso's edge) and was previewed at the peak
  before any keying. **Vertices are keyable through `modifyKeyFrames` on
  property keys 24 (x) and 25 (y); re-adding a key at an existing frame
  replaces it.** The standing pose keeps its chest patch, because its arm and
  eyelids are separate layers a mesh would slide out from under.
  (2) **The screen never advanced because its breaths ran on a
  `Timer.publish` built inside `body`.** A publisher made there is made again
  on every redraw, the resubscription restarts its countdown, and the screen
  redraws whenever onboarding's parent does, so the five-second tick could be
  pushed back indefinitely. The breaths now run from one `.task` (cancelled
  with the screen), and `OttoSpeech` types from a `.task` too. **Never drive
  a sequence from a Timer made in `body`.**
- **The invitation and the breaths are ONE screen** (`BreathExerciseScreen`),
  after Melvin rejected both a slide and a fade: "IT SHOULD JUST START
  BREATHING, NO TRANSITION". `.breath` and `.breathing` stay separate `Step`
  cases (resume, analytics) but share one view identity (`screenIdentity`),
  and a step change inside one identity is applied with no animation at all.
  Verified at 0.1 s per frame: invite to "Breathe in 1 of 3" in one frame.
- **Continue appears only after the THIRD breath.** It used to appear after
  the first ("a breathing exercise with no exit is a trap"), and Melvin read
  that as the exercise stopping after one breath. Thirty seconds is not a
  trap. Verified: Continue at 30.2 s after I'm ready, with in / out 1, 2, 3
  of 3 in between.
- **A breathing circle does the pacing, not his chest** (Melvin: "he still
  barely looks like hes breathing"). `BreathCircle` is the old breath screen's
  sage orb, above his head, 90 to 180 pt. Its size is computed every frame
  from `breathStart` (set at release, minus his phase), never animated, so it
  cannot drift from the words; it rests on the invitation and after the third
  breath. Otto sits about 28 pt lower to make room. Verified by recording:
  peaks every 10 s, three times, with the word swap on each peak.
- **Otto waits on the invitation and the words follow his chest.**
  `OttoRig` counts Rive's own advance (`OttoRiveViewModel` overrides
  `player(didAdvanceby:)`), pauses the rig 0.45 s after bind when
  `holdWhenSettled`, and `release()` resumes it and returns where in the
  ten-second breath he is, so "Breathe in" starts on his inhale rather than
  on a clock that has drifted from him.
- **Back slides the other way.** A change of direction has to re-render the
  outgoing screen with its new transition BEFORE it is removed (SwiftUI
  takes a removal transition from the view as last drawn), so `show` sets
  `motion` and moves on the next turn of the run loop. Verified from a
  screen recording, frame by frame: the question exits right and the count
  screen enters from the left.
- **Back from What's waiting did nothing**, found while testing Back: the
  last question routes through the cut `.calculating`, which went into the
  history, so Back landed there and it sent the reader straight forward
  again. Pass-through screens (`Step.onlyPassesThrough`) never enter the
  history now.
- **What's waiting is centred**, bigger rows, and says "Meditate your way",
  "See how it went", "Do it with friends".
- **THE BREATH, THIRD PASS: only the chest moves.** Melvin: "it just looks
  like his whole body is floating up and down". Three causes, all removed:
  the Body scaled 1.8 percent taller and leaned on every breath; the branch
  state bobbed the whole figure 3 units; and on the breathing screen the
  bottom inset swapped a 54 pt "Follow along" for the taller lifted button
  after the first breath, which shifted EVERY view above it in one jump. The
  button is now always laid out and only fades in. The chest patches scale
  from low in the belly (origin moved down, positions rebased so rest is
  pixel-identical), so an inhale lifts the chest toward the chin and widens
  it while the lap stays put: 110 x 114 percent sitting, 107 x 111 standing.
  **Verified the way it should always be verified: a difference map of two
  screenshots half a breath apart shows the chest lit and Otto's outline
  black.** Before the fix the same map outlined his whole body.

## OTTO'S AURA: HE GLOWS WITH PRACTICE AND SLUMPS WITHOUT IT (2026-09-21, Melvin)

Decided from `mockups/otto-aura.html`: he gets sad, and he lives on Home.

- **The rule is `OttoAura` (`Shared/Engine/`), derived from session dates
  like the streak, never stored.** Start 40, +10 per day meditated, -20 per
  missed day, with one rest day a week free through
  `StreakCalculator.restAvailable`, so the two rules cannot disagree. An
  unfinished today costs nothing. Consistency only, never the score. Stages:
  Low 0-9, Frustrated 10-29, Curious 30-49 (a new person), Progressing 50-69,
  In flow 70-89, Enlightened 90-100. `OttoAuraTests` pins the mockup's
  promises: first session lifts him to Progressing, five days in a row reach
  Enlightened, a week away from Enlightened brings him to Low.
- **"Not now" windows cost in proportion (Melvin's formula, 2026-09-22):** a
  window Otto was told "Not now" in, that closes with no session started
  inside it, costs `20 × hours / 24` (`OttoAura.skipCost`), so a skipped
  Mindful day costs a missed day's 20. It belongs to the day it opened and
  counts once closed. **No day costs more than 20** (a day's windows are
  capped, and a missed day already costs 20), **a rest day forgives the
  missed day, never the window**, and a skipped window before the first
  session starts the history. The level is a Double inside and rounds on the
  way out. `level(from:notNow:)` defaults to no windows, so Home is
  unchanged until Block supplies them.
- **`OttoAuraFigure` draws him on Home.** Low, Frustrated and Curious are
  still drawings (`OttoLow`, `OttoFrustrated`, `OttoCurious`, from
  `mockups/otto-v3/`), deliberately motionless. From Progressing up he is the
  Rive rig sitting, breathing through the mesh; In flow adds a glow and one
  orbit, Enlightened a second orbit, sparks, ground ripples and a slow lift.
  **The aura is drawn in SwiftUI, not baked into art**: painted glow cannot
  move, and glow cut off a dark background turned to mud on the cream when
  tried for the mockup. Its colours are `AppColor.auraGlow` / `auraRing`,
  kept apart from the score's gold, and it is never a closed ring with a
  number in it.
- **He no longer waves on a tap on Home**: the wave belongs to the standing
  pose and every stage sits. (He jiggles instead, since 2026-09-22.) A tap still cycles his lines, and his mood leads
  them at Low, Frustrated (only if today is not yet practised), In flow and
  Enlightened.
- **There is no lying-down Otto** (Melvin, twice now). At his lowest he sits
  slumped with his head drooping.
- The new drawings carry a smaller head than the rig's sitting Otto, so
  matched by height they read a size smaller; Curious stands at 1.04 of the
  frame and overflows upward into the sky.
- `OTTO_AURA=<0...100>` (DEBUG) shows any stage on a simulator with no
  history. Not built yet: the onboarding "See for yourself" slider screen from
  the mockup.

## THE RIG DID NOT CONTAIN THE BREATH FIXES THE NOTES CLAIM (2026-09-21, fixed)

**Read this before trusting any Rive paragraph above.** Two of them describe
work that is not in `Otto.riv` and was not in it when the app shipped today.

Measured from the editor, not inferred. `queryKeyFrames` on `Breathe` returns
keys for exactly three objects: `ChestWave`, `ChestSit` and **`Body`**. So:

- **There is no mesh.** `SitPose` is a plain `Image` with no children and no
  vertex keys anywhere. The "THE BREATH, FOURTH PASS: the sitting pose is a
  MESH" paragraph describes 285 vertex keyframes that do not exist.
- **`ChestSit` is not deleted.** The same paragraph says it is. It is alive at
  `0-2874` and it is the only thing moving the sitting chest.
- **The third pass is not in either.** "only the chest moves" says the Body's
  scale and lean were removed. `Body` was still keyed `sy 101.8` (literally
  the "1.8 percent taller" the note says it removed) and `r` swinging plus and
  minus 0.55 degrees.

So the app was shipping the breath Melvin rejected twice, while the file said
it had been fixed. **A difference map of the running app is what caught it:
his whole outline lit up.** It had been read once as edge antialiasing, which
is how a whole-body scale disguises itself at 1.8 percent.

**The fix is the third pass, applied for real:** the eleven `Body` keyframes
(sx, sy, r) are DELETED from `Breathe`, so the body is perfectly still, and
the two chest patches carry the whole breath at the documented amplitudes,
sitting 110 x 114 and standing 107 x 111. Verified the prescribed way: the
difference map now lights the belly ellipse alone, with his head, arms, hands
and outline black.

**The lesson, which is the reason this section exists.** A note saying a fix
shipped is not evidence that it shipped. The Rive file is cloud-only and
mutable by anyone with the link, the export is a separate act from the edit,
and the repo's `.riv` is a third copy. **Before building on any rig
behaviour, query the keyframes and read the binary.** The editor cannot
confirm its own export, and CLAUDE.md cannot confirm the editor.

## OTTO GREETS YOU SEATED, AND THE ART WAS ALREADY ON THE SHEET (2026-09-21)

Aziz asked for the pre-sit screen to show him "seated, daytime, smiling and
waving". I had told him that needed a new generation. **It did not: the fifth
figure on `mockups/otto-v3/sheet.png` is exactly that pose and had never been
sliced out.** Check the sheet before asking for art.

- `mockups/otto-v3/otto-sit-wave.png`, 418 x 434, cut from the sheet's
  bottom-right figure by alpha bbox. Its flourish marks were BLUE, which is
  invisible against the valley's blue sky, so they are recoloured to the amber
  the standing wave uses, mapping each pixel's luminance onto the amber rather
  than flooding it flat, which keeps the shading and the antialiasing.
- **`greeting` is its own boolean, not a third value of `sitting`.** The two
  answer different questions: `sitting` is posture, `greeting` is what he is
  doing. The Pose layer reads both, so leaving the greeting routes to Sitting
  or to Waving depending on `sitting`, and tapping Begin settles him into the
  meditation posture instead of cutting to it. Verified with
  `simulateStateMachine`: Entry to Waving, Waving to Greeting on the flag,
  Greeting to Sitting when the sit starts.
- Rig: asset `otto-sit-wave`, image node `GreetPose` in `Body` at
  `y = -height / 2`, timeline `PoseGreet`, state `Greeting`, four transitions.
  **Both traps in the notes bit again and were caught by them:** an uploaded
  asset defaults to hosted and excluded (set 358 = 0 and 801 = true or the
  .riv ships with no pixels), and a new child lands at the END of the list,
  which is BEHIND everything, so `GreetPose` needed `sendToFront`.
- Swift: `OttoPose.greeting`, `OttoRig.greeting` re-sent on bind like the
  others, `ValleyScene(progress:pose:)`, and `OttoGreet` as the still fallback.
- **Open: he does not breathe on the Ready screen.** `Breathe` keys only
  `ChestWave` and `ChestSit`, and the greet pose has no chest patch yet.
  `tools/otto_chest.py` cuts one; it is a feathered ellipse, an image node and
  three keyframes.

## THE SEATED WAVE ACTUALLY WAVES (2026-09-21, Aziz)

"the sloth isnt waving at all", "i dont like him with the little yellow
lines", "theres a white space between his moving arm and his head". All
three were real and all three are fixed.

- **The white space was baked into the art.** Not a rendering bug: an opaque
  white wedge of 204 pixels sat in the crevice between his raised arm and his
  cheek, and a second sliver above it. Found by connected-component labelling
  the pale pixels, because the eye whites and the teeth match any plain
  threshold. Filled with the median of the fur ringing it, darkened 10
  percent so it reads as the shadow that belongs there, then blurred only
  over that patch. **Verified by re-measuring to zero, not by looking**: the
  first two attempts each looked plausible in a zoom and had done nothing.
- **The flourish is gone**, marks and all. It was blue in the source, which
  is why it was recoloured amber an hour earlier; Aziz did not want it in
  either colour. Removed by fading alpha with blueness so no fringe is left.
- **The arm waves**, because it is now its own layer rotating about the
  elbow. `tools/otto_cut_arm.py` grew two things for it:
  - **A POLYLINE cut.** The standing pose could be severed with one straight
    line because its arm is held away from the body. The seated arm is
    against the torso and enclosed by it, so no straight line both follows
    the arm's contour and reaches background. The cut is four points now,
    down the arm and out at the bottom left.
  - **A FEATHERED overlap.** The hard-edged band is invisible at rest and
    then swings out from behind the head as a straight diagonal lip the
    moment the arm turns, which is exactly what it did at 12 degrees. Fading
    the outer 70 percent of the band hands those pixels to the body beneath,
    which is the same fur, so the join reads as shading. Checked at five
    angles: clean through about plus or minus 8.
  - The wave is 7 keys over 80 frames, minus 8 to plus 7 degrees, inside a
    240-frame looping `PoseGreet`, so he waves and then rests before waving
    again.
- **The arm's placement cost one wrong capture, and the lesson generalises.**
  An image's origin is where the node's position lands ON the image, so
  moving the origin to the pivot means recomputing the position in the
  PARENT's frame: top-left must stay at `(-w/2, -h)`, giving
  `x = -w/2 + pivotX`, `y = -h + pivotY`. Computing it against the pose's own
  frame instead dropped the arm on the floor.
- **Delete the superseded asset before exporting.** The single-image
  `otto-sit-wave` stayed embedded after its node was deleted, 185 KB of a
  679 KB file, for art nothing draws.

## THE READY SCREEN'S HEADLINE IS OTTO SAYING IT (2026-09-21, Aziz)

"make the readypage like a bubble text box of the brain guy saying it". The
headline and subtitle are gone; `OttoSpeech` carries the line instead, with
the tail pointing down at him, so the screen has one voice rather than a
caption above a character.

- **`OttoSpeech` gained `ink`, `stroke` and `fill`, all defaulted to what it
  did before**, so onboarding is untouched. Two reasons the session screen
  needs them. Its warm brown ink is a different palette on a blue sky, so the
  bubble takes the valley's own ink. And **an outline-only bubble is
  unreadable over a painted scene**: the morning sun rose straight through
  the glass and sat behind the word YouTube. Duolingo's see-through bubble is
  right over onboarding's flat ground and wrong over a landscape.
- **The bubble is pinned by its BOTTOM to just above his head**
  (`SitLayout.ottoTop - 8`), not centred at a fraction of the screen.
  Anchoring the centre leaves the tail short of him on a small phone and
  buried in his tuft on a large one.
- **The copy lost its second half and that is deliberate.** It said "808
  stays open the whole time"; the sit screen's own arrival frame already says
  "Keep 808 open to ensure you are meditating", which is where that matters.
  Each screen carries the line that is actionable on it, and the bubble stays
  two lines instead of four.

## THE GREETING POSE BREATHES TOO (2026-09-21)

`tools/otto_chest.py` gained the seated greeting, cut from
`otto-sit-wave-body.png` rather than the whole pose: the arm is its own
image that rotates, and a patch carrying part of it would swell the arm on
every breath.

`ChestGreet` is placed the way `ChestSit` is, and the arithmetic is worth
keeping because it is not obvious. The tool prints the ellipse centre as a
percentage, which goes straight into `originx`/`originy`; the position is
then `(-w/2 + centreX, -h + centreY)`, which puts the patch's pixels exactly
on top of the pose's. Same amplitude as the sitting pose, 110 by 114 with a
3 unit lift, so the two never drift apart.

**Verified with the difference map, and the first run measured a peak of 2
because the tap had opened the setup sheet rather than the screen.** Always
confirm which screen is actually up before reading a diff: a static sheet
and a broken animation look identical in the numbers.

## THE GREETING BLINKS; THE EDITOR'S COPY HAD LOST A DAY (2026-09-22, Aziz)

"make sure on the begin meditation page otto is blinking". The standing
wave's lids (`BlinkL` / `BlinkR`) live inside `WavePose`, so they faded out
with it and the seated greeting never blinked. Two new lids, `GreetBlinkL` /
`GreetBlinkR`, are duplicates of those, reparented into `Body` behind
`GreetArm` and in front of the greet art, placed at Body-space (-65.4, -315.6)
and (52.4, -349.1), r = -15, over the greet eye centres (144.5, 146) and
(275, 113.5) of the 418 x 434 art. `Blink` keys their sy exactly like the
originals (closed at 234 to 237 of 300 frames); `PoseGreet` keys their opacity
100, `PoseWave` and `PoseSit` key it 0. Verified by recording: the eyes shut
twice, five seconds apart, clean, and the sit after Begin shows no lids.

**The editor's cloud copy of Otto was older than the repo's `.riv`.** The
2026-09-21 greeting work (the `greeting` view model property, the Greeting
state and its transitions, the pose keys) was in `Otto.riv` and not in the
editor; restoring version history twice brought back the same older copy.
It was rebuilt in the editor before the lids went on, and the export now
contains both. **Before editing Otto in Rive, export the editor's copy and
compare it to `Coherence/Otto/Otto.riv` (size and names); never assume the
editor holds what shipped.**

**Reparenting while a timeline is open writes keyframes into it.** Moving the
lids with the editor sitting in `BranchOff` added position keys there, which
would have pinned the lids in every branch state. Plain property writes did
not. Re-query every timeline after a reparent. `simulateStateMachine` also
refuses to run in animation mode, so verify on the simulator instead.

## END WORKS ON THE FIRST TAP: THE BOTTOM EDGE BELONGS TO iOS (2026-09-22)

End on the sit screen refused five taps in a row. The device log said why:
each finger-down reached the app and each finger-up went to the system
(`systemGestureStateChange: 1`). The screen hides the home indicator
(`persistentSystemOverlays(.hidden)`) and End sat 42pt from the bottom edge,
where iOS reads a touch as the start of a swipe home. A Button fires on
finger-up, so it never fired.

Fixed three ways, all needed: `.defersSystemGestures(on: .bottom)` on the
screen, End lifted to 44pt above the bottom inset, and a bigger hit target
(32 by 14 padding, `contentShape(Rectangle())`). **Any control near the bottom
edge of a screen that hides the home indicator needs the same.** A tap that
works "sometimes" down there is this, not flakiness.

## HOME IS THE VALLEY, WITH OTTO IN THE MIDDLE (2026-09-21, Melvin)

"keep it on the same theme" as Aziz's sit and Ready screens, with Brainrot's
home as the reference, and "make him in the center of the home screen, not
off in the corner". This supersedes Direction B (Otto leaning in from the
left beside a bubble).

- **Home draws Aziz's `ValleyScene` itself**, at `progress: 0`, through a new
  `aura:` parameter that seats `OttoAuraFigure` on the cushion instead of the
  sit's rig. Home, Ready and the sit are one place, and Otto never changes
  picture between them. The scene is 74 percent of the height under the bar
  plus the top inset.
- On the sky: the greeting centred where Brainrot writes its name, the streak
  as a flame and a number in a frosted circle in the corner (the tour's
  `.streak` anchor moved onto it), and Otto's line in an `OttoSpeech` bubble
  pinned by its bottom above his head, exactly as the Ready screen pins
  its line. A tap on him still cycles the line.
- **The cards rise onto the near meadow** (`-17%` of the scene) rather than
  waiting under a field of empty grass. First the aura card: "Otto's glow",
  its percentage and a bar. (It was "Otto is curious" with no number until
  2026-09-22, so it could not be read as the score; see "OTTO JIGGLES".) Then Brainrot's three tiles in 808's
  facts (best streak, sessions, time meditated), This week, and Recent, now
  one card so its header is not text on a painting.
- **The page is grass**: the background is the meadow's near colour, and the
  sky that shows when the top is pulled down scrolls WITH the scene. A
  background pinned half sky and half grass showed a band of sky behind the
  tiles the moment the page moved.
- The still aura drawings are matched to the rig by HEAD width in the valley
  (Curious at 0.95 of the frame), after Aziz's rig update drew the sitting
  Otto smaller than the 1.04 tuned on the old Home.
- **The tab bar sits 16pt down into the home indicator's inset**
  (`MainTabBar.intoInset`). The air Melvin kept pointing at was never above
  the icons; it was the inset under the labels. Labels now sit about 39pt
  off the bottom edge, where Brainrot's do.
- Not changed, and next if wanted: Guide, Friends and Profile are still the
  cream pages, and `OttoBubble` / `ottoScene` from the old Home are gone.

## ONBOARDING IS BACK, WITHOUT THE WATCH (2026-09-22, Melvin)

Aziz cut onboarding in `d4ddbfc` (2026-09-21); Melvin, who had rebuilt it
that week and did not know, reversed it the next day ("Aziz definitely did
that by mistake"). `RootView` gates on `onboardingComplete` again, the DEBUG
`SKIP_ONBOARDING` hook is back, and `coordinator.setOnboarded(done)` mirrors
it to the Watch again.

- **The Watch question is gone** (`InterviewStep.watchGate` removed; the
  `watchGate`, `watchSetup` and `waitlist` Step cases pass through to What's
  waiting). A session runs on the phone with or without a Watch, so the gate
  sorted people for a difference the app no longer makes.
- **The phone detects the Watch instead of asking** (`watchPaired`, from
  `WCSession.isPaired`): health consent and the Health prompt behind it
  appear only when a Watch is paired, and are skipped (never entering Back
  history) otherwise.
- The tour's notes were rewritten (no calendar, no Watch, the guide is the
  circle under the streak on Home, where its `.guide` anchor now lives).
  What's waiting's second card is "Keep Otto glowing" (a score after every
  session stopped being true without a Watch), and the reminder preview on
  the permission screen now shows the real reminder's words.
- **When merging Aziz's branch, name any cuts to Melvin before building on
  them.** This one arrived in a merge and was repeated back as settled.

## 808 IS A CONSISTENCY APP; BLOCK REPLACES THE GUIDE TAB (2026-09-21, Melvin)

**Read `CONSISTENCY.md` before writing anything a user will see.** The
hardest part of meditation is doing it again tomorrow, so that is what 808
sells now. Otto is someone you look after (his aura), and Block holds the
apps you chose until you have meditated in the window you chose. Measurement
stays, as a feature, not the headline.

- **The guide is a circle under the streak on Home** (`guideBadge`,
  `HomeSheet.guide`), built and verified. The Guide TAB stays until Block
  replaces it in Swift.
- **`mockups/block-v1.html` is APPROVED (2026-09-22)**, with five decisions
  recorded in `CONSISTENCY.md` > Decided: a finished session releases the
  apps for the rest of THAT WINDOW, not the day; "Not now" costs glow only
  when the window then passes with no session, in proportion to its length
  (see the aura section); Strict ships in v1; Block is paid; **the default
  blocker is Mindful day**, the picked apps held all day until you meditate,
  one switch off. Apple lets only the person pick apps (tokens are opaque),
  so "on by default" means set up and waiting; a free person switching it on
  meets the free-week offer.
- **The loop Apple allows:** shield ("Otto's holding Instagram", "Ask Otto")
  → a Time Sensitive notification, because a shield cannot open an app → 808
  opens on one of twenty interventions → "Okay, let's meditate" or "Not now"
  (5 to 60 minutes). The shield is only an icon, a title, a line and two
  buttons; everything else lives in the app.
- **Family Controls (Distribution) is APPROVED (2026-09-22), all four App
  IDs, within minutes of the request.** It is per App ID, requested by the
  Account Holder (Melvin) in Certificates, Identifiers & Profiles >
  Identifiers > the App ID > Capability Requests, for the app AND each
  extension: `com.lockout.meditate808.monitor`, `.shield`, `.shieldaction`.
  Those three bundle IDs are fixed; build the targets with exactly them.
  Block is built on its own `block` branch because it is large and `mvp` /
  `social-1.1` are release branches. **The simulator cannot show shields.**
  A DeviceActivity interval must span 15 minutes, so a 5-minute pass starts
  in the past; verify on a device.
- **NEVER SEND SCREEN TIME DATA OFF THE PHONE.** Apple's Family Controls
  terms, accepted with the request, allow it only for the person's own
  device management and forbid sharing it beyond the person and their
  device. So nothing Block learns (apps, shield taps, passes, skipped
  windows) goes to PostHog, Friends or any server, the same stance as
  "never track a biometric". Anything shown to friends, such as an
  accountability glow, is computed from sessions alone.
- **The app's primary purpose must be Apple's purpose 2** (individuals
  managing their own device use for focus). The request text, recorded in
  `CONSISTENCY.md`, leads with Block, and the App Store listing of the
  release that ships Block must too.
- Aziz's areas are not touched by this: the plus's session screens and
  Profile.

## BLOCK IS BUILT, ON BRANCH `block` (2026-09-22, overnight)

The whole feature, behind `FeatureFlags.block` (ON in DEBUG, OFF in Release
until `blockInRelease` flips; tripwire in `FeatureFlagTests`). Off means the
Guide tab and no Block screen in onboarding. Status and the phone test list
are in `CONSISTENCY.md` > Build status and RELEASE_CHECKLIST.md.

- **Where it lives.** `Shared/Block/BlockModel.swift` is the rules, pure and
  tested (`BlockRulesTests`, `InterventionPickerTests`); the extensions list
  that one file. `BlockKit/` is the Screen Time half (App Group store,
  shields, DeviceActivity schedules), compiled into the app and the
  extensions. `BlockExtensions/{Monitor,Shield,ShieldAction}` are the three
  app-extension targets in project.yml. `Coherence/Block/` is the app side:
  `BlockController`, `BlockTab`, `BlockerEditor`, `InterventionView` (the
  twenty screens, Firm's breath, the how-long screen), `BlockHooks`,
  `BlockIntroScreen`.
- **Each process writes only its own App Group keys**: the app the state,
  the shield action the asks, the monitor the daily-limit hits. A shared
  read-modify-write would lose a tap on the shield to the app saving a
  moment later.
- **Every change goes through `BlockController.commit`**: save, re-register
  the schedules when the blockers changed, reconcile the shields. The
  monitor reconciles on every wake, judging a second ahead so a window
  Screen Time opens a hair early is not judged closed.
- **One DeviceActivity schedule per blocker, daily**; the weekday rule lives
  in `BlockRules`, which every wake asks. A pass end is its own activity,
  started in the past when shorter than Screen Time's fifteen-minute floor.
  **That trick is unverified: test it on a phone first.**
- **"Not now" opens every holding blocker with a pass left**; Strict and
  spent ones stay held. A session opens the rest of the window it started or
  ended in, if it meets the blocker's shortest session, idempotently, on
  every new session and every return to the foreground.
- **"Okay, let's meditate" starts the session straight away** (Melvin),
  after Otto's cover is fully down (`startAfterOtto` in `onDismiss`), with
  the Ready screen's last sound; the guided track only if paid.
- **The shield cannot open the app**, so Ask Otto posts a Time Sensitive
  notification; the delegate (`BlockNotifications`, the first notification
  delegate 808 has had) routes the tap. Opening 808 by hand within three
  minutes of an unanswered ask shows Otto too, in case the notification never
  arrived. A presentation is claimed once per fifteen seconds, because the
  tap and the foreground both ask.
- **Paid**: `Entitlements.block`; `BlockAccess` allows everyone in DEBUG
  (the beta loads no products), and `BLOCK_PAYWALL=1` puts the paywall back.
- **DEBUG hooks:** `PREVIEW_BLOCK=1` (Mindful day set up and holding,
  Screen Time treated as allowed, no Screen Time calls), `PREVIEW_BLOCK=empty`,
  `PREVIEW_TAB=block`, `PREVIEW_INTERVENTION=<kind>` (e.g. `faceTime`).
- **`ValleyScene(showsOtto: false)`** draws the valley alone, for the screens
  that stand their own pose in it. Default true, so Aziz's screens are
  unchanged.
- **Font names are PostScript**: `MarkerFelt-Wide`, not "Marker Felt", which
  silently fell back to the rounded system face.
- **Signing, learned from the first phone build (2026-09-22):** automatic
  signing (`-allowProvisioningUpdates`) registered the beta's `.dev` App
  IDs and gave them Family Controls, but **it cannot create an App Group**:
  every profile came back with `application-groups: []` and the build
  failed until the group exists in the developer portal (Identifiers > App
  Groups, the Account Holder's step). Production needs
  `group.com.lockout.meditate808`, the beta `group.com.lockout.meditate808.dev`.
  And **Time Sensitive Notifications is refused on an app extension**
  ("not a valid entitlement"); it lives on the app only.
- The camera usage string now also names Otto's FaceTime screen (live
  preview, nothing recorded), and the reminder screen stopped promising
  "nothing else, ever" on Block builds.

## OTTO JIGGLES, HAS TWENTY-FIVE MORE THINGS TO SAY, AND HIS GLOW IS A PERCENTAGE (2026-09-22, Melvin)

- **A tap jiggles him** (`OttoJiggle`, in `OttoAuraFigure.swift`): a squash
  from his feet and a wobble that dies away, about 0.55 s, as SwiftUI
  keyframes on the FIGURE, so the rig and the still drawings react the same
  and his glow and orbits hold still. Anchored at the bottom so his feet stay
  planted; skipped under Reduce Motion. Home and the Block tab. The sit and
  the Ready screen never jiggle: `ValleyScene.jiggle` defaults to 0 and only
  Home bumps it. Verified from a screen recording, frame by frame, with
  `tools/motion_strip.swift` (there is no ffmpeg on this Mac).
- **`OttoSayings`** (`Shared/Engine/OttoAura.swift`, next to the aura, the
  way `VerdictEngine` keeps its phrase bank): 25 lines after today's state
  line, twelve famous meditators and thirteen of his own, alternating, started
  at a different line each day. `OttoAuraTests` pins the rules: nothing about
  a score, a doorway or a Watch; no em dashes; **74 characters at most**,
  because that is two lines in his bubble on a 375pt phone and a third line
  on Home runs into the Guide circle.
- **The doorway line is deleted, and so is "breathe slow for a minute"**
  (Melvin: there are endless ways to meditate, so forcing one technique on
  people was wrong). Where he gives advice he offers several ways in.
- **Every famous line was checked against its source first**, and several
  famous ones are fake. Refused, so nobody adds them back: "It does not
  matter how slowly you go as long as you do not stop" (in no edition of the
  Analects; the real Book IX passage is the mound raised one basket of earth
  at a time, which he says instead); "Sleep is the best meditation" (credited
  to the Dalai Lama everywhere, sourced nowhere); sloths holding their breath
  for forty minutes (about fifteen, per the Sloth Conservation Foundation);
  sloths sleeping twenty hours (captive animals; wild ones sleep eight to
  ten, which he says). Sources for the twelve that stayed are in the doc
  comment on `OttoSayings`.
- **The aura card says "Otto's glow" and a percentage.** Melvin: "Otto is
  curious" did not say anything. It carried no number only so it could not
  be read as a session's score, and the score is on its way out. The stage
  names still drive his mood lines and his VoiceOver label. The nudge under
  the bar lost "Nothing measured today", since a phone session measures
  nothing and the line told people what they lacked.
- **The Block tab's Otto matches Home by head width**, about 125pt on an
  iPhone 17 Pro (the clipboard pose was 91pt), so the scene grew from 46 to
  56 percent of the height to keep his line above him.

## NOTHING OPENS AFTER A SESSION EXCEPT OTTO'S GLOW (2026-09-22, Melvin)

"Remove the save session screen, it looks ugly and is off theme and is a lot
of friction. Instead, the first thing the user sees after meditating is Otto
gaining aura." So a finished sit now goes straight to Home and plays the glow
it earned. **The Save session screen and the results screen no longer open
after a session**; both still exist and are still reachable from a session's
own row, and Save session is still Aziz's screen, cut from this path only.

- **`SessionLandedHooks`** (ContentView) replaces the Save-session half of
  `FriendsHooks`: same gate (wait for the live-session cover and any award
  unlock, then 700ms), new destination. It runs with Friends off, because the
  glow is not a Friends feature.
- **`celebrate(_:)`** switches to Home, works out the level before and after
  the landed session from the session dates (the aura is derived, so "before"
  is simply the level without that date), sets `auraGain`, jiggles him, and
  counts the card up to the new level. `AuraGainBurst` (in
  `OttoAuraFigure.swift`) draws the light, the sparks and the "+N%".
- **A derived curve cannot be animated with `withAnimation`.** The burst was
  first written as `.opacity(f(phase))` with one animated `phase`, and it
  never appeared: SwiftUI interpolates each modifier between its start and end
  value, and this curve rises and falls, so opacity went 0 to 0. Only
  `keyframeAnimator` (or `TimelineView`) re-evaluates the function every
  frame. The jiggle works for the same reason. **Animate a value, and only
  monotonic functions of it survive.**
- The burst is drawn UNDER his speech bubble so sparks pass behind the words,
  and the "+N%" rises beside his head, not above it, where the bubble is.
- **`RootHooks` wraps Friends and the landing in ONE modifier.** Adding a
  second `.modifier(...)` to ContentView tipped the type checker over again.
- `PREVIEW_AURA=<from>:<to>` (DEBUG) replays the whole thing on Home without
  waiting a day to earn it.

### The prompt and the session page, built (same day, Melvin's picks)

From `mockups/after-session.html`: **option B, the toast above the tab bar**,
and **screen 1**, with four changes.

- **The toast never fades.** "Make it never fade, just always there unless
  they like click on an X in the top left corner." So it is state, not a
  timer: `SessionDetails` in UserDefaults, raised when the glow finishes,
  cleared by the X or by saving the session, and read back on every launch.
  A toast that disappears is one most people would never once use, which is
  the whole reason a fading one was rejected.
- **`SaveSessionView` is rewritten as the session's page**: the valley's sky
  band with the length as the one big number, the title, and Otto's head on
  its edge; then how it felt, what you did, what friends read (Friends only),
  private notes, photo or video, who can see it. The band is PINNED, because
  scrolling it ran the length and the X through the status bar.
- **How it felt is a slider out of ten** (Melvin: "should be a scroll bar,
  not emojis, make it out of 10 still"). It shows "Not rated" and a grey
  track until it is touched, because a slider parked at five would file every
  unrated session as middling.
- **What did you do lists every sound 808 offers**, not just the practices
  (Melvin: "thats something ive been meaning to tell you for awhile").
  `MeditationMethod.loggable` is now `techniques + sounds`, the sounds coming
  from `SoundMenu`, which is already the one list of them, so a sound added
  there appears in the picker, on the results card and in the labels at once.
  The session's own sound is preselected: it is known, and it is the likeliest
  answer.
- **Any photo and any video, for friends and for yourself.** The BeReal rule
  (front camera only, no library, no selfie no post) is gone, on Melvin's
  call. `SessionPhoto` gains a `video`, exported to 540p and half a minute
  before it is stored, with its first frame kept in `jpeg` so the calendar,
  the rows and the results screen draw it without knowing there is film
  behind it. **The feed still posts the still**: a video in a post is its own
  piece of work.
  - **The UI dropped the requirement here, but `CommunityStore.post` still
    threw `.selfieRequired` for a photo-less Friends post until 2026-09-23.**
    Save session never forced a camera, so a Friends post with no photo would
    silently fail at the store layer with "Take your selfie to post."
    `CommunityStore.post` no longer guards on a photo at all; a post with
    none simply carries none, same as an optional score. `CommunityError
    .selfieRequired` is deleted. The reaction pill on a post card was
    restyled the same day, see "FRIENDS IS IN THE VALLEY" below.
- **Otto reflects, he does not thank.** "It's not like youre doing him a
  favor by taking care of him. It should be assumed." His line after a
  session is "That's today done. I'm brighter for it."
- **The sloth is off the session rows** (Melvin: "the sloth looks weird as
  fuck if hes there on every meditation"). `EvidenceRow` draws its picture
  panel only when there IS a picture; the score moved up beside the rating.
  Same note that took him off Aziz's log a day earlier.
- **A session row opens its page**, and the measurements are one tap further
  in ("See the measurements", only when something measured them).
- **The results screen is the measurements and nothing else** (Melvin, same
  day: "yes strip it"). Gone from it: the rating card with its slider,
  technique picker and note, the photo card, and the "Only you / Edit" chip.
  What is left is the ring, the verdict, Otto, the tiles, the curves, the
  unlock and Share. The session's page owns everything a person SAYS; this
  screen owns what was measured, and it is reached from that page.
  **The first-session paywall moved with it**: the offer rode the reflection
  card's own `onDisappear`, and it belongs to the screen.
- **Still open:** a Friends post carries a score, so a phone session cannot be
  posted yet.

### Friends can be tested without iCloud, and a post's score is optional (same day)

- **`CommunityModel.testMode`** (DEBUG): Friends against
  `MemoryCommunityDatabase`, seeded, so the tab works on a simulator with no
  iCloud account (Melvin: "the friends tab has been like closed off this
  whole time due to icloud, can you fix this so i can test it"). On by
  default in the simulator, off on a phone; the unavailable card offers to
  turn it on and a banner across the feed says it is on. Everything works
  except leaving the device, and nothing survives a relaunch.
- **A post's score is optional** (Melvin: "have the score on the friends
  post be optional, again like we are making the watch optional"). `Post`
  and `Draft` carry `Int?`; the card drops the capsule and the Score column
  rather than printing a zero, and the profile's average counts only the
  sits that have one. The session page no longer refuses to share a phone
  sit. **Whether it is also a CHOICE is undecided**: `mockups/post-score.html`
  draws the card both ways and three homes for a switch (none, per post, or
  once in the profile). My recommendation is on the page: none now, a profile
  preference later, and never a per-post switch, because the posts somebody
  leaves the score ON for say what the hidden ones were.
- **The profile photo is any picture again, with Otto as the default**
  (Melvin: "either a selfie or from your library, and then can have otto be a
  default if you dont want to pick anything"). This reverses Aziz's call of
  2026-09-21 ("no more pfp and make the sloth in the circle"), which had
  made Otto everybody's portrait. `ProfilePortrait` is the one view that
  draws a face, so Profile, the feed and a person's page cannot disagree;
  the picker in Create your profile already offered camera or library.
  **Initials are gone**, which was the old fallback.

### Block can be tested without Screen Time (same day)

Melvin: "make it so i can test the block thing, screentime is password
protected and i dont know the password". The simulator asks for a passcode
nobody has, and it cannot draw a shield either.

- **`BlockController.testMode`** (DEBUG): Screen Time is treated as allowed
  and never called, switching a blocker on counts as having apps (the
  simulator's picker has none to offer), and a card on the Block tab holds the
  switch, a "Hold again" that forgets today's releases, and "Open a held app".
  On by default in the simulator, off on a phone, and `PREVIEW_BLOCK` still
  turns it on with Mindful day already holding.
- **The stand-in shield uses the real shield's words and the real
  notification**: `BlockShieldWords` and `BlockAsk` moved into BlockKit, which
  both the extension and the app compile, so a rehearsal on the simulator
  sends exactly what a phone will. Verified end to end on the simulator:
  switch on, open a held app, Ask Otto, the Time Sensitive banner, one of
  Otto's twenty screens, meditate, apps open.
- **A foreground banner only lasts about five seconds.** Tapping it after that
  lands on the screen behind it and looks like the notification did nothing.
  The fallback is the real one: opening 808 within three minutes of an
  unanswered ask shows Otto anyway.

### Two sizing fixes

- **Otto on Home was drawn a thumb's width left of his own cushion** at
  Progressing and above, where he is the Rive rig. `OttoAuraFigure` passed an
  explicit square width, and a square frame letterboxes the 425 x 522 artboard
  and hangs it bottom LEFT. It takes the artboard's aspect now. The note under
  the Rive section about Home keeping its old square frame is what caused it.
- **The Block tab's Otto** is between where he was and Home's size: about
  104pt of face against Home's 125 and his old 91 (Melvin asked for bigger,
  then "a bit smaller").

## SHOW THEM, DO NOT TELL THEM; AND THE LADDER IS TWO RUNGS (2026-09-22, Melvin)

- **Two onboarding screens are cut**: "Here's what's waiting" (three feature
  rows) and the Block explainer. Melvin: "they look AI generated you know,
  maybe just get rid of them." Both were the app describing itself.
- **`AuraDemoScreen` replaces them**: "I get brighter every day you meditate
  / See for yourself. Drag the bar." A drag bar moves Otto through his
  states live, and a caption names what each position costs in days, which
  is the real rule in `OttoAura`. It moves itself once on appear, so the
  affordance is discovered rather than captioned.
- **The rule this sets, and it applies to every screen that sells
  something: hand them the thing, do not describe it.** The remaining places
  telling rather than showing, worth the same treatment: the guide's method
  list (let them try a breath instead of reading about it) and the sound
  library (a tap should play three seconds of it).
- **The downsell ladder is two rungs**: the free week, then **half off the
  first year**, then the free tier. Melvin: "there are too many, and they
  arent convincing ... unless it includes a discount, which i actually do
  want to do." The hardware anchor left the ladder, and the year's price
  restated in smaller words is gone, because restating a price concedes
  nothing.
- **The discount is its own product**, `com.lockout.meditate808.yearly50`:
  the full yearly price with a first-year introductory offer at $14.99. A
  product carries exactly one introductory offer, which is why this cannot
  be the yearly product, and is the same rule that killed the half-off-month
  rung in August. On the paywall it REPLACES the yearly card rather than
  sitting beside it, and its cadence line carries the renewal price
  everywhere the number appears. `PaywallLadderTests` pins all of it,
  including that the ladder never grows past two rungs.

## OTTO HAS SEVEN STATES, DRAWN AS ONE SHEET (2026-09-22, Melvin: "Yessir this is fire")

`mockups/otto-v4/sheet.png`, generated in ONE ChatGPT run from
`mockups/otto-v4/PROMPTS.md`. One state per chat drifted (the stage 3 run
arrived with dust around him that no other stage had, and patchier fur than
stage 2), so the rule is: **a progression is generated as one image, never
state by state.**

- **`OttoAura.Stage` is seven cases whose raw values are the DRAWING NUMBER,
  1 to 7, not a level**: withered, faded, stirring, steady, bright, radiant,
  nirvana, in bands of fifteen (0-14 ... 90-100). Everyone starts at 40, in
  Stirring (half gray), so the first session is the one that brings his
  colour back (Steady). `floats` is true from Radiant up. `OttoAuraTests`
  pins the bands and the three promises.
- **`tools/otto_aura_cut.swift` cuts the sheet**, and it is Swift because
  this Mac has no numpy or PIL. The figure is found by DARKNESS (every
  channel under 178), closed by 3 px so the cream claws join the fur, then
  hole-filled so the face and belly come in. Everything else is
  **un-composited off the white** (colour to alpha), which turns the drawn
  haze, motes and halo into real translucent light that glows over the sky
  instead of a pale blob. The printed numbers are found and erased first;
  rows split at the gap between bodies so a mote is never handed to the row
  above. `--normalize 490` scales every state to the same BODY WIDTH (the
  model drew the second row 12% bigger) and seats them on one baseline in
  one 664 x 744 canvas (`mockups/otto-v4/canvas.json`).
- **`OttoAuraFigure` draws the seven stills** (`OttoAura1` to `OttoAura7`),
  with the light baked in, so the SwiftUI glow, orbits, sparks and ripples
  are deleted. Canvas constants: baseline 0.872, Steady's body 0.82 of the
  height; anything placing an aura still (the Block interventions do) must
  scale by `bodyShare` and hang it on `baseline`. Radiant and Nirvana float
  and bob. `OttoLow`, `OttoFrustrated` and `OttoCurious` are deleted.
- **Next, and asked for: the Rive rig** (Melvin: "the bugs should come and
  go periodically. The aura should swirl around. He should be floating up
  and down"). It needs a CLEAN sheet (no bugs, no light) and a sheet of the
  bits (moth open and folded, beetle, fly, the mandala alone), asked for in
  the same ChatGPT chat, and its own Rive file `OttoAura` so the session rig
  (one artboard, see the export note) stays untouched. The stills stay as the
  fallback when the rig cannot load.

## OTTO'S AURA RIG IN RIVE: `Coherence/Otto/OttoAura.riv` (2026-09-23)

Melvin: "the bugs should come and go periodically. The aura should swirl
around. He should be floating up and down a little bit when hes floating.
Use rive obviously." Built through the editor MCP over HTTP (curl, no
session id needed after `initialize`), in its OWN Rive file (the editor's
"Untitled" tab, file 2603863; rename it OttoAura in Rive), never in the Otto
file, because that export only ever carried its first artboard.

- **One artboard, `OttoAura`, 664 x 744: the stills' canvas exactly**, so
  `OttoAuraFigure` frames the rig and the fallback stills identically. His
  body's bottom centre is (332, 649). Node tree: Figure (at the baseline) >
  Shadow + Lift (per-stage height) > Bob (the float) > Back (glow, mandala,
  the rings' back arcs, leaves) / Stages (S1..S7, each a clean body plus a
  feathered chest patch) / Bugs (moth, beetle, fly) / Front (the rings'
  front arcs, three groups of motes).
- **One view model property, `stage` (1 to 7)**, and it defaults to 0 so
  the Stage layer waits in Entry until the app speaks; Entry to S_k is
  instant, S_j to S_k crossfades in 500 ms (42 transitions, one condition
  each). Layers run together: Stage, Float (from 6 up: lifted and bobbing,
  a shadow shrinking under him), Breath (chest patches on a 10 s breath),
  Aura (9.6 s loop: glow pulse, comets round two tilted rings via trim
  paths, twinkling motes, leaves spiralling up BEHIND him since one crossed
  his face in front), Bugs (11 s loop: the moth rests, flies off at 5 s,
  comes back; the fly circles and lands; the beetle crawls his forearm) and
  Halo (the mandala turns a quarter every 38.4 s, which is seamless because
  it is four-fold).
- **The art:** bodies from a CLEAN sheet (same chat, "remove the bugs and
  the light"), cut with `tools/otto_aura_cut.swift --normalize 490 --canvas
  664,744,649` so they land on the first sheet's grid; bugs, mandala, birds
  and grasshopper cut with `tools/sprite_cut.swift` (flood the paper for
  creatures, colour-to-alpha for light, frames aligned on the beak).
  `tools/otto_aura_rig_build.py` is the recorded first-pass build.

**Rive MCP lessons from this build, each of which cost a round:**
- **Insertion order depends on the tool.** New groups and shapes land IN
  FRONT of their siblings; new images land BEHIND them. The old note that
  "a new child lands at the END, behind everything" is only true for images.
- **group_editor ignores x/y, and a group made under a moved parent is
  offset to cancel the move** (Lift came out at -332, -649). Write positions
  after creating, and zero the children.
- **Deleting a view model broke that file's data panel**: every view model
  made afterwards was unlisted and silently left out of the export. The fix
  was a truly blank file. Make the view model FIRST in a new file, check
  `listViewModels` shows it, and check the exported bytes contain `stage`.
- `upload_rev` with target `current_project` can create a file, but nothing
  can open it for you; the person has to.

## OTTO GETS THIRTEEN LOOKS, CLEAN EDGES, AND LEAVES OF HIS OWN (2026-09-23, Melvin)

### The white paper is out of every cut: `tools/otto_defringe.swift`

"You can see a little white space between his arm and his head, so its
obvious its cropped out ... slightly around his legs, arms, top of his head in
the tufts of his hair." Every Otto was drawn on white and cut out, and two
things of the paper survived:

- **Paper trapped inside him.** Cutters fill enclosed regions so his face and
  belly come in, which also fills the gap between a raised arm and his head,
  between tufts and between his legs with opaque white. The rule, MEASURED on
  every cut: a region paper-pale (darkest channel >= 224) is a hole unless it
  touches TRUE black (below 50: a pupil, so eye whites and catch-lights stay)
  or is ringed by at least 40% cream (his muzzle highlight at stages 6 and 7
  is as pale as paper). **His dark eye patch is not true black**: a looser
  "near-black" test kept the walkthrough's arm-to-head wedge because it
  touched the patch.
- **A rim of paper round him.** Edge pixels half fur, half paper were kept
  opaque. Each is un-mixed against the fur just inside it; the white share
  becomes transparency. Only pixels that really are fur plus white: the
  orange rim LIGHT on stages 6 and 7 is not on that line and is left alone.
  Semi-transparent edge pixels too (scaling up the art blended the rim into
  them). `--no-holes` for lit art (the lit Nirvana's pale wheel read as a
  hole and was eaten on the first run), `--floor 12` clears invisible specks
  round clean bodies.
- **Applied to:** the pose sources in `mockups/otto-v3` and every image set
  resampled from them (they are straight resamples, checked), the seven aura
  stills, the seven aura bodies and chests in `OttoAura.riv` (swapped on the
  same crop boxes, old images deleted). **NOT yet `Otto.riv`** (the session
  Otto: welcome wave, Ready greeting, the sit): the Rive MCP cannot switch
  files, so it waits for someone to click the Otto tab in the editor.
- A chest patch is rebuilt from its old feather, not guessed: mask = old
  chest alpha / old body alpha, laid on the new body (reproduces the old
  patch at 0.01 mean difference).

### Thirteen looks, seven stages

`OttoAura.look(level:)` picks one of THIRTEEN drawings: the seven stages at
the odd numbers (`Stage.look`), a body halfway between each pair at the even
ones (`mockups/otto-v4/sheet-between.png`, Melvin's A to F). **`Stage` is
unchanged** and still decides moods, stills and every promise; the look only
decides the picture. The level moves in tens, so 0, 10 ... 100 are where it
sits, and each of those eleven gets its own drawing: 40 is Stirring, 50 is
Steady, 90 the one just short of Nirvana (the faint wheel), 100 Nirvana. C
(45-49) and E (75-79) show only after a skipped "Not now" costs part of a
day. `OttoAuraTests` pins the grid, the promises, reachability and that the
look is never more than half a step from the stage.

In the rig: groups M1..M6 beside S1..S7, `stage` 1..13 (S_k = 2k-1,
M_m = 2m), all 169 transitions, Float from 9. Every effect steps between its
neighbours. A has no chest patch: his head hangs into where it would swell
(stage 1 has none for the same reason). **The new sheet came out about 12%
more saturated**, which made Steady look paler than C and D; each in-between
was scaled to its neighbours' mean saturation (hue and brightness kept).
**The fly now sits in a wrapper** the stages switch: the bug loop keys the
fly's own opacity, and a later layer overrides an earlier one, so it showed
on Faded and B.

### Leaves: their own orbits, counted per stage

"Following too much of a straight path ... some being higher vs lower." All
six once rose on one helix. Now each circles at its own height band, radius,
tilt, speed and spin, rising and falling through its band, on their own
19.2 s loop and layer ("Leaves"). Each leaf and its front twin has a wrapper,
so a stage shows a count: E 1, Radiant 3, F 4, Nirvana 6. Behind him on the
far half, in front on the near half, handed over out at his sides.

### Rive MCP traps that cost a round each

- **An upload can come back with an id that never registers** (chest-1 in
  the first build, chest-2 here). Look assets up by name after uploading and
  make the script resumable; do not trust the returned id.
- The MCP cannot switch the editor's active file. `duplicate_objects`
  returns no ids (the copies are named "X 2"); `rename_objects` takes
  `renames: [{id, name}]`; keys are deleted with `modifyKeyFrames`'s
  `delete`. Export a `.rev` backup before a build that deletes transitions.
- This Mac's shell is zsh: arrays start at 1 and `set -- $x` does not split.
  Put loops that rely on either in a `bash` script.

### Also today

- Otto's FaceTime screen shows your live front camera while it rings, and
  once answered puts you top right, FaceTime's self view, with Otto in the
  valley speaking in bubbles (`FaceTimeCamera.swift`; the session runs off the
  main thread). The simulator has no camera, so only the fallback is checked.
- Every one of Otto's screens puts its second choice ("Not now", "Hang up")
  in a cream pill; as bare text it could not be read over the flowers.
- Settings > "Otto's unblock screens" rehearses all twenty screens and the
  how-long screen with nothing real happening. `PREVIEW_UNBLOCK_KIND`,
  `PREVIEW_UNBLOCK_GALLERY`, `PREVIEW_INTERVENTION_HOWLONG`,
  `PREVIEW_FACETIME_ANSWERED` and `PREVIEW_SETUP` open them on a simulator.

## 1.1 IS PREMIUM ONLY; MISSED DAYS ESCALATE (2026-09-23, Melvin and Aziz, after a call)

- **Premium only, one switch: `Monetization.premiumOnly`** (`Coherence/Store/
  Monetization.swift`). Onboarding ends on the paywall again
  (`paywallInsideOnboarding` follows the switch), declining both ladder
  rungs returns to the plans, and `RootView` shows the paywall at launch to
  anyone without a subscription, opening the app by itself on purchase or
  restore. The 2026-08-24 free tier is still in the code, unreachable.
  **Only a store that has its plans locks anything** (`Store.State.ready`):
  offline, before products exist, and on the .dev beta (whose bundle owns no
  products) the app stays open, so nobody, App Review included, is stuck on
  a paywall that cannot sell. `HARD_PAYWALL=1` reviews the lock in DEBUG.
- **The trial's length is App Store Connect's**, read off the monthly
  product's introductory offer (`Store.trialDays`) and said through
  `TrialCopy` everywhere ("Start 3 days free", "Three days free."). The
  founders said "likely 3 days"; Connect still says 7, and the simulator,
  which reaches the real sandbox products, shows seven. Fallback 3.
  **Never hardcode a trial length in copy again.**
- **Missed days escalate: 10, 15, 20, 25 ...** (`OttoAura.missCost(run:)`).
  The weekly rest day is free but counts as a day of the run; a meditated
  day ends it; a missed day and its skipped "Not now" windows cost the
  larger of the two, never the sum. Gains stay a flat 10 ("maybe scales
  similarly" is written down in BACKLOG.md, not built).
- Open, in BACKLOG.md: the trial length, gains that grow, what 1.0 users
  who installed free get on updating (today: the paywall), and the store
  listing and review notes for a subscription app.

## 1.1 RELEASE PREP, AND OTTO'S LAST FIXES OF THE DAY (2026-09-23, Melvin)

"I really dont want to be rejected for any reason." Two agents and a
review pass; the ordered list of what is still owed by a human is the new
top section of `RELEASE_CHECKLIST.md` ("NEXT RELEASE: 1.1").

- **Delete account now deletes the person's public Friends data**
  (5.1.1(v)): profile, @username reservation, posts with their media,
  reactions given, friend edges and blocks they wrote
  (`CommunityStore.deleteEverythingOfMine`). **Reports are kept** as
  moderation records; edges other people wrote stay theirs (the public DB
  only lets a creator modify a record). Best effort and resumable: a
  failure, or no store because iCloud is unreachable, sets
  `community.pendingAccountDeletion.v1` and a launch task retries;
  claiming a new username clears it, so a retry can never delete a profile
  made after coming back. **Needs a new QUERYABLE index, `Reaction.author`
  (eight in all, `CLOUDKIT_SETUP.md`).**
- **Every Block extension has its own privacy manifest** (App Group
  `UserDefaults`, reason `1C8F.1`; the app declares it beside `CA92.1`).
  Missing ones are refused at upload (ITMS-91053), and the extensions are in
  every archive whatever `blockInRelease` says.
- **The camera permission names "Otto's video call screen"**, not FaceTime
  (5.2.5). **PostHog crash capture is off in code**: it only installs when
  the app switches it on, so the App Privacy label needs no Diagnostics row.
- Policy, terms (new 6b, Block), `APP_STORE.md` (review notes that need no
  Watch, age rating worked answers: UGC and Social yes, 13+) all updated.
  **Open, the founders' call:** a Friends post carries the score, which is
  derived from heart rate, into the public iCloud database; 5.1.3(ii) says
  health information may not be stored in iCloud and has no consent
  exception. Recommended: keep the score on the private session page and
  drop it from posts, the zero-risk option. Not changed without a yes.

### Otto, the same day

- **The editor's copy of `Otto.riv` lost the greeting's eyelid keys a
  SECOND time**, and the sitting pose had had no chest patch since the
  2026-09-22 rebuild, so he did not breathe during a sit. Both restored
  (ChestSit pivots low in the belly, 110 x 114), the eight pose images
  swapped for the defringed sources (verified pixel for pixel against what
  the rig held), blink and breath verified from recordings. **Always export
  the editor's copy and diff it against the repo before editing Otto.**
- **The aura rig (`OttoAura.riv`):** the moth flies out past the left edge
  of the screen and back in from beyond it; the thirteen bodies (562 to 610
  canvas units) all stand 600, by scaling `Bob` about his base in each
  look's timeline so his light and bugs scale with him; and a `snap`
  boolean gives every look-to-look fade an instant twin, used by the
  stress bar (`auraSnap`), while Home keeps its 500 ms crossfade.
  **The artboard never clipped: the moth was cut by the edge of the app's
  Rive view.** `OttoAuraFigure` draws the rig 2.6 times wider than its
  canvas (`flightSpan`, hit testing off) so anything in the rig can leave
  the screen.
- **The grasshopper crosses, it never fades**: one per 45 s window, in
  from beyond the left edge, a rest after every hop, out past the right,
  on one feet line in the flowered grass (71 to 82% of the scene; the old
  band began on the ridge, which was the "floating"). It passes behind Otto
  when it crosses farther back than his cushion (`ValleyLife.meadowBehind`,
  drawn inside the ground scene) and in front when nearer, slightly larger
  the nearer it is.
- **Birds never turn over**: the loop-the-loop pattern is a gentle lift.
- **The tour switches tabs the way a tap does**: its tab is its own state,
  changed with animations off; the spotlight still eases.
- The Friends post card lost its rule above the numbers.
- **The Rive MCP cannot switch the editor's file.** Ask the person to click
  the tab, then confirm with `session_info` before any write.

## ONBOARDING SETS UP BLOCK, AND WHY AZIZ PULLED AND SAW NONE OF IT (2026-09-23)

- **Onboarding picks the apps and the schedule** (Melvin, after the call:
  "user should set up what they want to block in the onboarding ... should
  set up schedule in onboarding ... least friction possible"). Two screens
  after the wall and before the paywall, Block builds only:
  `BlockAppsScreen` (Screen Time permission, then the picker; "Not now"
  moves on) and `BlockScheduleScreen` (`OnboardingBlockSetup.swift`). Both
  write the Mindful day blocker `BlockController` already seeds, through
  `BlockController.save`, so the Block tab shows exactly what onboarding
  set. `Step.blockApps` 45 and `.blockSchedule` 46, last in the enum;
  analytics "31c" and "31d". Off Block builds they route past and never
  enter the Back history.
- **Aziz pulled and was a day behind because the work was on another
  branch.** Everything Melvin's sessions built from 2026-09-22 23:38 went to
  `block`, while `mvp` and `main` stayed on Aziz's own last push (116ee38).
  He fast-forwarded both to `block` (27eac0f) on 2026-09-23 at 20:04 EDT.
  **A pull that brings new Swift files or a new `.riv` also needs
  `xcodegen generate`, with Xcode closed, before building**: 66 files had
  been added since his last sync, and a project that has not been
  regenerated cannot see any of them.

## FRIENDS POSTS CARRY NO SCORE, AND YOUR OWN POST CAN BE EDITED (2026-09-23, Melvin)

- **The score is off posts entirely** (Melvin: "Yea get rid of the
  score"), which closes the 5.1.3(ii) question in the section above: it is
  derived from heart rate and the public database has no consent gate.
  Nothing writes or reads `score` on a post; the card lost its Score column
  and a person's page its average. The CloudKit field stays in the record
  type (fields cannot be removed) and is simply unused.
  `test_postNeverCarriesAScore` checks the record itself.
- **Edit post sits above Delete post** in the ⋯ menu of your own posts, when
  this device still has the session behind it
  (`CommunityStore.sessionID(forPost:)`), and opens that session's page in
  edit mode. Saving updates the same record and keeps its date.
- **A saved post takes its place by date, not the top of the feed**
  (`CommunityModel.placing`). Inserting at the top sent an edited post above
  posts practiced after it until the next refresh; found on the simulator.

## OTTO'S SCREENS: THREE PHONE BUGS AND THE HOW-LONG SCREEN (2026-09-23, Melvin)

- **"Not now" offers 10, 20 or 30 minutes, one row**, sitting just above the
  buttons it sets. The valley is drawn taller on that screen only, so its
  grass rises to Otto's lap (it began at 66% of the frame, below his feet,
  and he floated in front of the mountains).
- **Tapping "Otto wants a word" could open 808 on nothing.** Every Otto
  claimed a fifteen-second window, meant to swallow the second of the two
  asks one tap makes (the delivery and the foreground), and it swallowed the
  next real tap as well. The window is two seconds now, and
  `BlockHooks.ottoShowing` stops an ask while one of his screens is up or
  queued.
- **The video call went blank for seconds after Accept, and repeated calls
  froze the phone.** Accept threw away the full-screen camera preview and
  attached a second, smaller one to the running session, which rebuilt its
  video path while the interface waited. Every call also built its own
  session and configured it on the main thread. Now all calls share one
  session (`FrontCameraEngine`), touched only on its own serial queue,
  counted in and out so the last one out stops it, and the screen keeps ONE
  preview that Accept moves and shrinks into the corner. The simulator has
  no camera, so this was verified on the phone or not at all; the engine
  logs how long configuring, starting and stopping take (category
  `FrontCamera`), readable through `devicectl ... --console`.
- **Nothing was left on the phone to explain the freeze**: no crash or hang
  report for 808 in its logs. The fixes target the two things in the code
  that could hold the main thread; if it recurs, stream the console.

## ONBOARDING STANDS IN THE VALLEY; THE STRESS QUESTION IS ANSWERED ON OTTO (2026-09-22, Melvin)

"More on theme, like in a green forest area like the home menu but its in
the background."

- **The valley is drawn ONCE, by `OnboardingView`**, behind the screen
  ZStack, and `.environment(\.onboardingSharedGround, true)` turns every
  screen's `onboardingGround` transparent. So screens slide across a world
  that stays put rather than each carrying a copy of the sky. Outside
  onboarding (the paywall from Home) `onboardingGround` still draws the paper.
- **Type on the meadow is white with a shadow** (`onMeadow()`; `FootnoteInk`
  picks it under the shared ground): the hint, "Not now", footnotes. Grey
  captions over the ridge could not be read, so the permission screen's
  caption moved onto its card and sign-in's words moved up onto the sky.
  Answer plates are opaque white with a soft shadow; the chosen one's gold
  wash sits ON the plate, since a 10% wash over the valley showed the ridge
  through it.
- **"How stressed have you been lately?" is answered on Otto** ("should show
  the sloth slider, combine it with that screen"). He sits on his cushion in
  the shared valley (`OnboardingValley` shows him only on this step) and asks
  it in his bubble; dragging the bar changes his state, Fine his brightest
  and Burnt out withered (`StressScreen.stage(for:)`). It sweeps once on a
  fresh screen, never over an answer already given. The aura demo screen is
  cut the day it was built and routes past like the others.

## THE BETA CRASHED ON LAUNCH A THIRD TIME, AND THE PROFILE WAS THE LIAR (2026-09-22)

Same crash family as 2026-09-12 and 2026-09-15: **`CKContainer` traps on a
container the process does not hold.** Both earlier fixes stand. The new road:

Assigning the App Groups to the `.dev` App IDs regenerated their provisioning
profiles, and the fresh profile lists
`icloud-container-identifiers: [iCloud.com.lockout.meditate808]`, because the
App ID is allowed to hold it. The beta strips iCloud from the BINARY on
purpose. `CloudEntitlement` reads the profile, so it reported a container the
binary does not carry, and the first `CKContainer(identifier:)` after launch
killed the app (signal 5, about a second in, nothing in the console but the
line before it).

**The build now says so itself.** `tools/beta_install.sh` adds
`CloudKitDisabled = true` to Info.plist in the same branch that deletes the
iCloud entitlement keys, and `CloudEntitlement` checks that flag before
anything else. Nothing at runtime can read its own signed entitlements
without private API, so the build that removes them leaves the note behind.

**The lesson, which is the reason this is its own section: a provisioning
profile states what the App ID MAY hold, never what this binary DOES hold.**
Any build that edits its own entitlements has to tell the runtime.

Diagnosis, for next time: `xcrun devicectl device process launch --console
--terminate-existing <bundle>` prints the app's stdout and names the signal,
and reading the profile's own entitlements is one command:
`security cms -D -i <profile> | plutil -extract Entitlements json -o - -`.

## THE BLOCKER EDITOR IS BRAINROT'S, IN THE VALLEY (2026-09-22, Aziz)

Aziz, with three Brainrot screenshots: "make it more like this and also just
use current theme i dont like the current pastel brown in here". Built to
`mockups/blocker-editor-v2.html`. `BlockerEditor.swift` is rewritten; how
Block behaves is untouched (same windows, limits, passes, strictness).

- **Brainrot's order:** a symbol in a circle with a pencil, the name, **All
  Day / Schedule / Daily Limit** as one control, Blocked apps, the timeframe
  or the limit (15m, 30m, 1h, 2h, Custom on a wheel), Active days as
  Weekdays / Weekends / All over seven circles, Save, Delete.
- ~~808's three extras were one card, "When Otto lets you in"~~: REMOVED the
  same day. See "BLOCK HAS NO STRICTNESS AND NO PASS LIMIT" above.
- **The mode is DERIVED, not stored**: a daily limit set means Daily Limit,
  else `.allDay` means All Day, else Schedule. So a blocker saved by the old
  editor opens on the right segment. A daily limit forces the window to all
  day, because it counts the whole day and its screen shows no hours.
- **The editor has no on/off switch** (Brainrot's has none); the list keeps
  it. A NEW blocker therefore saves switched ON, and `BlockTab.save` still
  routes a free person to the paywall.
- **`Blocker.symbol`** (optional SF Symbol, nil draws `kind.defaultSymbol`)
  is the one new field. It decodes absent for every blocker saved before it;
  `test_symbolDefaultsToTheKindsAndSurvivesASave` pins that. The list row
  draws it too, or the pencil would change nothing anyone sees. SF Symbols
  only, never emoji.
- **Colour: blue for choosing, gold for doing.** Every choice lights in
  `AppColor.skyDeep`, the valley's midday sky deepened for white text; the
  one gold object is Save. Unchosen labels are `meadowInk`, and tracks and
  dividers use `BlockerEditor.quiet` (meadowInk at 11%). **Do not use the
  app's `hairline` on these white fields**: it is cream, and the first build
  that did read as the pastel brown this screen was rebuilt to lose.
- The page is the valley: `ValleyScene(progress: 0, showsFigure: false)` as a
  132pt band, the symbol's circle on the seam the way Profile seats its
  portrait, grass below, white fields.

## THE READY SCREEN HAS A TIMER AGAIN: A TAPE, AND TAP TO TYPE (2026-09-22, Aziz)

"on the meditate screen i want it so theres a timer on there and we can do a
cool scroll animation", then "also do it where you can tap and you can just
say the specific amount of time". Built to `mockups/ready-timer.html`
(direction 1, the tape; the drum and the ring stay in the mockup).

- **A big clock in the sky and a ruler under it** (`SessionLengthPicker` and
  `LengthTape`, `Coherence/Session/LengthTape.swift`). The ruler slides under a
  fixed amber needle: a tick a minute, a number every five, ∞ (Open) at the
  left end. Ticks swell toward the needle, the clock rolls to the new number,
  and a selection haptic marks every minute. **Tapping the clock turns it into
  a number field** (empty, the current length as placeholder) with a Done
  pill; 0 means Open, 1 to 4 means 5, the ceiling is 600.
- **Five minutes is the shortest timed session** (Aziz, same day: "minimum is
  five and if you go beyond 5 its infinite"). The tape runs ∞, 5, 6, 7..., so
  sliding left past 5 lands on Open, and typing 1 to 4 gives 5. Five is also
  what opens Block's apps, so a timed sit always counts
  (`test_theShortestTimedSessionOpensBlock` ties the two). A 2 minute default
  saved earlier opens on 5; Settings' lengths are now Open, 5, 10, 15, 20, 30.
- **`SessionLength` (Shared, tested) holds the rules**: Open, then every
  minute from 5 to 120, evenly. It first jumped 60, 75, 90, 120 on
  consecutive ticks and the four labels piled into one smear (Aziz: "this
  looks weird"); **every labelled tick must be the same distance apart.** A
  typed 300 is kept as 300 while the tape rests on its nearest tick (120) and
  only moving the tape off that tick writes back.
- **The length is remembered** in `Preferences.defaultDurationSec`, which the
  Settings "Default length" picker also edits (it now lists a custom value
  rather than showing blank). Begin passes it as `plannedDurationSec`, and the
  phone path already ends a timed sit by itself.
- **Reading the tape cost two wrong attempts, both worth knowing.**
  `scrollPosition(id:anchor: .center)` reported the tick BEFORE the one the
  ruler settled on (clock 9:00 over a needle on 10). A GeometryReader in the
  scroll content fired once at rest and never while scrolling. What works:
  `onScrollGeometryChange` (iOS 18), `contentOffset.x + contentInsets.leading`
  divided by the tick spacing. iOS 17 falls back to the scroll position id.
- **Programmatic moves never animate** (`scrollTo` bare): a slide would pass
  every tick on the way and write each one back. Offsets before the first
  placement are ignored for the same reason (they would write Open over the
  remembered length).
- Scale the tick's line and its number SEPARATELY: scaling the whole stack
  pushed the number out of the ruler's frame and clipped it under the needle.

## ONBOARDING'S BREATH IS ONE BREATH, IN BLUE WATER (2026-09-23, Aziz)

From a reference screen (a character breathing while blue water rises and
falls): `BreathExerciseScreen` is now **one breath, in 4, hold 2, out 4**, on
a **white** screen. `mockups/breath-one.html` drew it; Aziz then changed four
things on the build, all in:

- **No "I'm ready"**: the breath starts on its own 0.6 s after the screen
  lands, and calls `onReady` itself so the flow still moves to `.breathing`
  (resume and analytics count that step). **Continue appears only after the
  breath.** The invitation bubble is gone.
- **Otto sits in the middle of the screen**, the words ("Breathe in." over a
  sky-blue "3 seconds") under him, with a matching clear block above so it is
  his centre on the screen's.
- **The water rises all the way to the top** on the hold (`high` 1.08) and
  falls away on the exhale: `BreathWater`, three pale layers of `skyDeep`
  (0.12 / 0.18 / 0.30) each with its own slow wave. At 0.55 the front layer
  swallowed the blue countdown.
- **A standing Otto raising his arms was tried and DROPPED the same day**
  (Aziz: "that looks terrible"). Three pieces cut from a ChatGPT sheet (body,
  arms), each arm rotated about the shoulder, two arm sets (curled paws, then
  open paws). **Rotating a flat piece of a painted 3D-style character never
  looks natural**: the fur shading is drawn for an arm hanging down, so the
  same picture turned overhead has the wrong light, joint and paw for its new
  angle. If arms-up breathing returns, the ways that work are an
  image-to-video clip of the art (keyed, synced to the clock) or a proper
  bone rig by a Rive animator, not rotated cut-outs. The art stays in
  `mockups/otto-v3/otto-stand-*.png` and `mockups/otto-breathe-brief.md`;
  the image sets and `OttoArmsBreathing` are gone. **The sitting Otto with the
  swell below is what ships.**
  - ChatGPT's "transparent" PNGs came back as a PAINTED checkerboard (RGB, no
    alpha). Check for a real alpha channel before cutting generated art.
- One clock (`breathStart`) drives the water, the swell and the words.
  `BreathHaptics.playOnce(inhale:hold:exhale:)` plays the 4, 2, 4 once.
  `BreathCircle` is no longer used here.

## AFTER A SESSION, EVERYTHING IS IN THE VALLEY (2026-09-22, Aziz)

"revamp the screen after you meditate". Built to `mockups/after-valley.html`.
The flow itself was already right (End, Home, the glow rising, the "Add how
that felt" toast); three screens around it were still cream. No field, rule
or step changed.

- **The session's page** (`SaveSessionView`): the valley band with the length
  as the one big number, the title and "Today, 10:55 PM · Silence" in the sky,
  Otto's head on the grass at the right. Each question is its own white card
  (`whiteCard`), every choice is sky (the slider, the picker chevron, the media
  pills, a segmented Only you / Friends), and Save is the one gold thing, over
  grass that fades up under it.
  **The scene is drawn TALLER than the band and cut at its bottom**
  (`(top + 150) / 0.53`, 0.53 being where the scene's meadow begins): at the
  band's own height the horizon fell across the title.
- **Too short** (`SessionTooShortView`): Otto, Curious, on his cushion in the
  valley, saying it in his bubble ("**That was 13 seconds.** Sessions count
  from 30 seconds. Want to go again?"); Start a session gold, Done a cream pill.
  The Watch-unreadable case gets its own line in the same bubble.
- **An award** (`AwardUnlockView`): the badge hangs in the sky with an aura
  glow while Otto waves up at it from the cushion; the award's own words above.
  **Full-screen views that ignore the safe area read its insets as zero**:
  place text from `SitLayout.skyTop`, as the sit screen does, not from
  `safeAreaInsets.top`.
- `PREVIEW_AWARD=<award id>` (DEBUG, e.g. `streak3`) announces an award on
  launch; `PREVIEW_TOO_SHORT=<seconds>` and `PREVIEW_SAVE=1` already existed.

## FRIENDS IS IN THE VALLEY (2026-09-22, Aziz)

"revamp the friends screen make it the same vibe as the rest". Built to
`mockups/friends-valley.html`. It was the last tab on plain cream with brown
ink. **No wording, action or rule changed**; one small addition (Withdraw on
a sent request, the same `model.remove` a person's page already used).

- **The feed**: a band of valley (`FriendsSky`, the scene with nobody in it)
  carrying "Friends", your @ and the requests pill (gold only when someone is
  waiting, the one gold thing in the sky), and **your friends standing on the
  meadow** (`FriendsOnTheMeadow`): tap a face for their page, the last face is
  Invite. **Anyone who posted a session today glows** in Otto's aura light.
  It reads only `model.friends` and the feed, the only evidence 808 has that a
  friend sat; nothing from Block or Screen Time reaches it. Below: a cream
  search capsule, then posts as white cards on the grass.
- **Post cards** are white (`whiteCard`), numbers in the sky's ink,
  hairlines `ValleyGround.quiet`, and "Nice session" is a sky pill that turns
  gold once given. **Restyled 2026-09-23 (Melvin): the pill is the emoji
  alone, on the left, with who gave one reading to its right** (where the
  pill used to sit) — "Nice session" survives only as the button's
  accessibility label, since the card no longer prints it.
- **Requests**: a short band, the title in the toolbar's PRINCIPAL slot (a
  leading toolbar item is wrapped in an iOS 26 glass capsule and reads as a
  button), one white card per group of people, Accept gold.
- **A person's page** is your own Profile's shape: portrait on the seam, one
  white identity card with the follow line and the one relationship button,
  one stats card, then their posts.
- **Shared pieces now in `DesignKit`**: `ValleyGround` (meadow, ink,
  inkSoft, quiet), `GrassHeading`, `.whiteCard(radius:)`. `NoTopEdgeHaze` is
  internal (was private to the guide).
- **A page with NO navigation bar has no top edge for iOS to fade**, so
  scrolled content ran under the clock with nothing behind it.
  `scrollEdgeEffectHidden(false)` did nothing there. `StatusBarScrim` fades a
  band of meadow in behind the status bar once the band has scrolled away
  (`onScrollGeometryChange`, iOS 18+).

## A TIMED SESSION ENDS WITH A NOTIFICATION; "GET COMFORTABLE" IS IN THE VALLEY (2026-09-22, Aziz)

- **`SessionEndNotice`** (`Coherence/Session/`): a timed phone sit schedules a
  local notification for its planned end ("That's 10 minutes" / "Your session
  is done. Take a breath before you get up."), **Time Sensitive** because it
  is a timer the person set and the Ready screen's own Silence switch turns on
  Do Not Disturb. With 808 on screen it plays only its sound
  (`BlockNotifications.willPresent`), since the sit screen already says it is
  over. `BlockNotifications` is now installed on EVERY build, not only
  Block's, or the foreground chime would never play in Release.
- **Taken back only on an EARLY end** (`finishPhoneSession(early:)`): on time,
  the notification is firing at that same moment and IS the chime.
- **Permission is asked on Begin of a timed sit, before the countdown**, only
  if never asked. Never on appear.
- **A late finish is capped at the planned length.** A silent timed sit lets
  iOS suspend 808, so the finish can run when the phone is next picked up;
  the session is the length that was set, not the length of the wait.
- **The countdown is direction A of `mockups/ready-countdown.html`**: nothing
  new appears, things leave. The pills slide into the meadow, the tape goes,
  the clock counts 5 to 1 in its own place and face, Otto says "Get
  comfortable.", one Cancel pill sits where Begin was (the corner Cancel hides
  so there are never two), and at zero he settles from waving into sitting for
  0.7 s before the sit takes over. The old cream wash with a brown number is
  deleted.

## BLOCK HAS NO STRICTNESS AND NO PASS LIMIT; FIVE MINUTES OPENS THE APPS (2026-09-22, Aziz)

"get rid of the passes and the intensity and the when otto lets you in
thing. also the minimum length for a session that open your apps is 5
minutes". The editor's "When Otto lets you in" card is gone, and with it
three per-blocker settings: strictness (Chill / Firm / Strict), passes a
day, and the shortest session that counts.

- **"Not now" always works.** No strict mode, no daily cap, no Firm
  ten-second breath (`FirmBreath` deleted), no "N passes left today". Its
  only price is the glow rule: a window that closes with no session after a
  "Not now" costs glow, unchanged.
- **`Blocker.sessionMinutes = 5`** for every blocker, checked once in
  `BlockRules.recordSession`. Otto's screens that said "two minutes" now say
  five, since two would open nothing.
- `BlockStrictness`, `passesPerDay`, `minimumMinutes`, `passesLeft`,
  `canTakePass`, `passesLeftNow` and `strictnessNow` are deleted. **Blockers
  saved with the old keys still load** (the decoder ignores unknown keys);
  `test_blockersSavedWithStrictnessStillLoadAndTakeNotNow` pins it.
- `InterventionDoors.canPass` survives for one screen only: the countdown
  hides "Not now" until it reaches zero.

## THE GUIDE IS IN THE VALLEY (2026-09-22, Aziz)

"revamp all the how to meditate guides in there so it fits our current
theme". Built to `mockups/guide-valley.html`. The guide was the last pair of
screens on the cream page with brown ink. **No copy changed.**

- **The list:** the valley band with Otto (asking pose) saying the title in
  a white bubble, "How to meditate" over "8 ways in. Any order you like.";
  grass below; level headings in white; each method a white card with its
  symbol in a sky circle, the blocker list's object. The session count is
  SKY and still absent at zero: it is a record, and gold is kept for Begin.
- **A method:** its symbol on the seam of the band, a white head card
  (level, title, line), steps as one card with sky number dots, variants
  and "What it is for" as cards, the origin under a divider (the SCIENCE.md
  two-tier rule), and **Begin pinned, gold**.
- **Symbols live in `MeditationMethod.swift`** (`symbol`, a switch on id
  with a leaf fallback), so a new method still needs no view change.
- **iOS 26 hazes scrolling content under the navigation bar toward the
  page's background.** The page is the meadow, so the sky came out green
  under the back button. `NoTopEdgeHaze` turns the top edge effect off.
- **A parent's `safeAreaInset` does NOT reach a page pushed onto a
  NavigationStack inside it.** Measured, not guessed: the method page's
  bottom inset read 34 (the home indicator alone) while the tab bar sat on
  top of its pinned Begin. ContentView now measures the bar and hands its
  height to the tabs as `tabBarClearance` (environment, set on the tabs
  only, so sheets get 0); a pushed page that pins something to its bottom
  adds it. **Any future pushed page with bottom-pinned content needs the
  same.** The first fix, moving Begin from a ZStack into its own
  `safeAreaInset`, was right in general and changed nothing here.

## THE SOUND PICKER IS A STATE OF THE READY SCREEN, NOT A SHEET (2026-09-21, Aziz)

"the sound screen button looks terrible", then on the first redesign: "no
that looks terrible, i want it to be based on the current vibe we got going
on in this screen and the next one, i basically wanna turn the vibe of the
app into this". Mockups `sound-v1.html` (rejected) and `sound-v2.html`
(approved).

**v1 was rejected for the right reason and it is worth keeping the reason.**
It was a tidy grid of white tiles on a cream sheet: defensible on its own,
and a different app wearing this one's colours. The valley is not decoration
on the session screens, it IS the screen, and a modal that slides a second
surface over it makes two screens out of one.

- **`showOptions` and its `.sheet` are gone.** `choosingSound` is a State of
  `SessionSetupView`, and the two states share ONE `ValleyScene`. Tapping
  Sound swaps the pills and moves Otto; Done swaps them back. Nothing else
  moves, which is the whole effect.
- **Otto is a PLACEMENT on one view, not a second Otto**
  (`ValleyScene.ottoInCorner`). Cross-fading a small figure in would tear
  down the Rive rig and build another, costing a blank frame and restarting
  his wave; moving and resizing the same view is a spring the rig plays
  straight through. His cushion fades with him.
- **`SoundChoiceList` has no chrome of its own**: pills of exactly the
  material Sound and Silence notifications use, one gold outline for chosen,
  and a mask that fades the scroll at BOTH ends so it sits in the scene
  rather than on a panel over it.
- **Symbols, never emoji.** The first build used ☔🌊🌲🔥 and they arrive in
  full colour from a palette that is not ours and cannot take the sage and
  amber. SF Symbols tint.
- **Section labels wear the pills' cream.** Bare ink on the scene reads on
  the sky and vanishes into the meadow's flowers as the list scrolls, and a
  label that is legible in one part of a scroll and not another is not a
  label.
- **The first pill was arriving half dissolved** inside the mask's top fade.
  Content under a gradient mask needs padding past it.
- Silence no longer says "Just the measurement": a phone sit measures
  nothing, so that sentence was false for every session started here.

**The rule this sets, which Aziz wants everywhere:** one scene per job and it
does not move; every control is a cream pill floating on it; Otto says the
sentence that would otherwise be a title; exactly one gold object per
decision. Home is explicitly frozen for Melvin's critique, so it is NOT to be
converted until he has looked.

## THE READY SCREEN'S PILLS ARE HOME'S SIZE, AND OTTO IS LIFTED PER SCREEN (2026-09-23, Melvin)

"make the buttons 'sound and silence notifications' a bit bigger, like
closer to the size of the banners in the home screen, gonna have to raise
Otto a little bit for this."

- **`SitPill` is Home's card size** (a 42pt roundel, a title and a line under
  it) with a `compact` one-line size for short phones (`height < 700`, the SE).
- **Otto is lifted by exactly what each screen needs** (`ottoLift`): enough
  to clear his cushion by 6pt above the pills, capped so the gap between the
  timer tape and his bubble never closes under 10pt. The bubble rises with
  him and the tape half as far, since it stays centred in the band above the
  bubble. A 17 Pro gets about 63pt and the whole cushion shows; an SE has no
  sky to give, so there the compact pills still sit over his lap, as they
  always had. **A flat lift was wrong on every phone**: the first build's 6pt
  left the pills over his legs on a 17 Pro and up to his chest on an SE.
- **Only the sitter moves** (`ValleyScene.ottoLift`, which moves Otto and his
  cushion and nothing else). Offsetting the whole painting moved the horizon
  and sun with him, and would have slid the entire valley down at the
  hand-off. The lift is 0 while counting in, so he settles to exactly where
  the sit draws him while the pills leave.
- **The heights are measured** (`onGeometryChange` on the controls block and
  the tape, heights only, never positions, because the slide transitions move
  them), seeded with the 17 Pro's values so the first frame is already right.
- **"Choosing a sound sends you home" was `@Environment(\.dismiss)`** inside
  `SoundChoiceList`, which has no presentation of its own, so Done dismissed
  the fullScreenCover the Ready screen lives in. It takes an `onDone` now.
  **A child view with no sheet of its own must never call `dismiss`.**
- **"Shortcut not found" was 808 marking the Do Not Disturb shortcuts
  installed when the install links were still nil**, so it ran `808 Silence`
  on a phone that had never been given it. `FocusShortcut.installed` is set
  only by a step that earns it, under a new key (`.v2`) so the stale `true`
  is gone. The setup sheet opens ONE link per tap (808 is in the background
  while Shortcuts shows its Add screen, so a second open straight after the
  first is refused), and while the links do not exist (DEBUG only; Release
  hides the switch) it walks through making the two by hand. The links are
  Melvin's to publish (BACKLOG.md).
- **The switch shows what 808 DID, not what iOS's Focus status says**
  (Melvin, same day: "the button does not toggle ... DND gets turned on").
  `isFocused` reads off for a moment after a change and ALWAYS reads off
  when Share Focus Status is turned off for Do Not Disturb. Believing it
  flipped the switch back AND dropped the note that 808 had silenced the
  phone, so nothing turned Do Not Disturb off when the sit ended. Now the
  status only ever adds to what 808 knows: an "off" is believed only after
  it has said "on" since 808 silenced the phone, and for 4 s after any
  switch 808's own action outranks it in both directions (`settle`).
- **The silence is stored** (`focus.silencedAt.v1`), because only the
  foreground can open Shortcuts: a timed sit that ends with the phone locked,
  or iOS closing 808 mid-sit, would otherwise leave the phone silent with
  nothing that remembered why. The restore is owed and paid on the next
  foreground (`becameActive`, called from `CoherenceApp` at launch and on
  every return), within 12 hours, after which it is forgotten rather than
  risk switching off a Focus that is no longer 808's. The end of a sit only
  ever restores 808's own silence (`restoreIfOurs`); tapping the switch off
  is an explicit ask and runs Restore whoever turned it on (`turnOff`).
- `PREVIEW_SETUP=1` (DEBUG) opens the Ready screen on launch. On a fresh
  simulator Friends test mode earns "Brought a friend" and its award covers
  everything; `simctl spawn <sim> defaults write com.lockout.meditate808
  community.testMode.v1 -bool NO` before launching avoids it.

## ONE ROUNDED FONT EVERYWHERE; DIN NEXT ROUNDED NEEDS A LICENCE (2026-09-21, Melvin)

"use their font everywhere, i think its DIN Next Rounded". Duolingo's body
face is DIN Next Rounded (their headlines are their own Feather). **It is a
Monotype font, and embedding a font in an app needs an app licence bought for
that app**: a desktop licence or an Adobe Fonts activation does not cover it,
and an unlicensed copy does not go in a shipped binary. It is not on this Mac
either.

**What ships is SF Pro Rounded, everywhere, as the stand-in.** Closest shape
available without a licence (rounded terminals on a plain grotesque), built
into every iPhone, every weight and language, Dynamic Type for free.
`DisplayFont.display` returns it, `AppFont` already did for body sizes, and
**`CoherenceApp` sets `.fontDesign(.rounded)` on the root**, which reaches
every `.system(size:)` with no design and every text style (verified on the
simulator: onboarding's non-rounded subtitles and options came out rounded).
Two `.monospaced` call sites in `OnboardingInterview` keep their digits. The
Watch keeps the system face.

**Baloo 2 is superseded** (Aziz's pick, 2026-09-19). Its TTFs, OFL and
`UIAppFonts` entries are left in place, unread, so going back is one line.

**If the DIN Next Rounded app licence is bought:** files into
`Coherence/Fonts/`, names under `UIAppFonts`, `Font.custom` in `DisplayFont`
and `AppFont`. The root `fontDesign` cannot carry a custom family, so the
~200 raw `.system(...)` call sites move to `AppFont` in the same pass.

## THE UI REVAMP IS PARKED, AND HOME STAYS AS IT IS (2026-09-20, Melvin)

"The home tab i dont even know what to do with. Keep it as it was before and
ill critique it. Slow down with this UI revamp. Keep it to 5 tabs."

So `mockups/ui-v4.html` is a drawing and nothing more: **the four-tab layout is
not happening**, Guide keeps its tab, and Home is exactly the Direction B scene
from earlier that day. The three decisions the mockup asks for are parked until
Melvin has critiqued the Home he already has. Nothing in that mockup is to be
built without him saying so.

## THE FRIENDLY REDESIGN (2026-09-19/20): what changed, in one screen

Aziz: "the app is just hard to look at, think duolingo esque, just real
friendly looking." Every screen was rebuilt over two days and it is all on
`mvp`. The reasoning for each decision is in the commit messages; this is the
map.

- **Every colour is sampled out of Otto's artwork** (`AppColor`): paper is his
  cream, ink is his nose, blush is his cheeks. The three meanings are
  unchanged and finally separable: **amber is a measured score, sage is
  anything measured off the body, blush is the streak.** Gold used to mean
  both "you scored this" and "you showed up", which is why one-gold-per-
  section could never hold.
- **One appearance. Dark mode is deleted**, `RootView` pins light, and every
  colorset carries the same value in both so they cannot drift.
  `Preferences.theme` stays in the schema (dropping a synced property is a
  migration hazard) and is simply never read.
- **Baloo 2 for display text, SF Rounded under about 15pt** (`DisplayFont`).
  The split is deliberate: SF is hinted small, carries every language, and
  scales with Dynamic Type. `Font.custom` wants the POSTSCRIPT name.
- **The 808 flower is gone from the product.** `LogoMark.swift` and
  `tools/logo_lab.swift` are deleted; Otto's head is the mark and the icon.
- **Home** is a scene (Otto under a sky, on a horizon), a streak capsule on
  the seam, a rolling **seven days ending today** (never the calendar week: a
  Sunday-to-Saturday strip draws days that have not happened as failures),
  and Strava-style session cards.
- **808 has no month view anywhere.** `MonthCalendar` is deleted. The week
  answers "did I show up" for the days still winnable and Profile's score
  chart answers the long question better than a dot grid.
- **Profile** is a portrait under the same sky, one stats card, **Your
  scores** (one bar per sit, average as the only line, because there is no
  value between two sits), and awards as filled squircles: earned is raised,
  unearned is a hollow.
- **The share card is the app now**: Home's sky, sage curves, Otto's head,
  sentence case throughout. It is the only organic advertising 808 has, and a
  dark card sells a dark app.

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
   `com.lockout.meditate808.{monthly,yearly,lifetime,yearly50}`, monthly + yearly as
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
- StoreKit products: `com.lockout.meditate808.{monthly,yearly,lifetime,yearly50}`

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

## ONBOARDING POLISH AND MEADOW DEPTH (2026-09-23, Aziz)

- **Welcome:** the grasshopper crosses IN FRONT of Otto (`OnboardingFrontLife`
  drawn over the screen; the valley's own meadow life is off on that step via
  `meadowLife`), no ground shadow under him (`OttoInMeadow(shadow: false)`),
  and his line is a solid white, rounder bubble (`OttoSpeech(friendly: true)`)
  sitting directly above his head rather than under the title.
- **The waving/talking art is nudged left by 6% of its height** in
  `OttoInMeadow`: his raised arm sits on the left of the frame, so his body
  read right of centre on the welcome and question-count screens.
- **Breathing screen glitch:** the words slot is always laid out (an empty
  slot took no height, so Otto jumped ~35pt when "Breathe in" arrived), and
  the time is clamped at 0 (a negative first frame flashed "5 seconds").
  Verified from a 10fps recording: flat, then a smooth inhale rise.
- **The meadow has depth now, in every valley scene.** A hopping grasshopper
  exposed a flat field. Three cues, all in `SessionScene.swift`: haze where
  the grass meets the ridge, the ground darkening toward the viewer, and 46
  fixed grass tufts (`Meadow.tufts`, seeded, drawn far to near, smaller and
  paler toward the ridge). The grasshopper also casts a shadow on the grass
  (`HopperPose.groundY` / `lift`) that shrinks and fades as it jumps.

## RULE: ANYTHING STANDING IN THE MEADOW USES `standsInMeadow` (2026-09-23, Aziz)

**The meadow is one canvas painted before everything on it, so anything
placed afterwards covers every flower, near or far.** It went wrong three
times in one evening (a grasshopper "landing on the petals" of a nearer
flower; Otto's cushion covering the flowers in front of it on the welcome;
the same on every seated screen, Home included, unnoticed until then), and
Aziz asked that it never happen again. `View.standsInMeadow(feetY:scale:
sceneSize:)` (SessionScene.swift) repaints the grass and flowers whose foot
is nearer than `feetY` over the view, masked to the view's own outline.
- **Every new thing that sits, stands, lands or walks in the meadow goes
  through it** (the cushion, grasshoppers, and whatever comes next), laid
  out in scene coordinates with `.position`.
- **Before calling any meadow change done, look at a screenshot for flowers
  that should be in front of the new thing.** Depth mistakes are invisible in
  the code and obvious on the screen.
- It cannot mask a video (`AVPlayerLayer`), so a clip of Otto stands on a
  cushion or ground that goes through it; that is why the welcome's Otto
  stands on his cushion.

**Meet Otto is three pages of one screen** (`MeetOttoScreen.Page`): "Meet
your meditating partner: Otto" with Otto saying "I'm doing alright." →
"The more you meditate, the more enlightened he becomes." → **"See for
yourself!"** (`Step.seeForYourself`, Brainrot's screen): a BLUE bar
(`GlowScrubber`, `AppColor.skyDeep`) with his face as the handle, starting in
the MIDDLE (level 50, Steady, so nothing jumps from the pages before), which
drives the valley's Otto through all thirteen looks (`OnboardingView.
glowDemo`), a selection tick at each change. Otto never moves between the
three pages; only the words and the bar change.

**Then the clutter screen** (`ClutterScreen`, `Step.clutter`, after See for
yourself, Aziz's copy, from Brainrot's "You're not addicted"): "Clarity and
peace are within reach." arrives with the slide and "Your mind is just
cluttered." types itself out (a tick a letter), then
nine ordinary thoughts pop up over Otto as white capsules with a coloured
dot, SLOW THEN FASTER (gaps 0.9 s down to 0.12 s), each with a rigid tap
that gets firmer, and the valley's Otto dims a step with each (`clutterLevel`
50 down to 22). Then, on a white card over the meadow: "Meditation is how
you clear it. Doing it every day is how it stays clear. That's what 808 is
for." (typed, a tick a letter, the button rising only once it is
done). **"Let's clear it" does what it says**: the thoughts lift off, his
colour comes back, and only then does the flow move on. Copy rule it keeps:
the thoughts are recognition, not alarm; the claim is only that a daily
practice keeps it clear, no number.

**One Otto from Meet Otto to the questions.** The question count ("Just N
quick questions") now uses the valley's seated Steady Otto too, its bubble
pinned above his head, instead of standing its own waving Otto: arriving
from the clutter screen, the seated one faded out while a standing one slid
in, two see-through Ottos at once (Aziz: "the transition is weird"). The
clutter screen's heading now arrives WITH the slide instead of fading in a
beat later, which left a moment of empty sky. **When consecutive screens
share Otto, let the valley draw him and change only the words.**

**"Let's personalize 808 for you."** (Brainrot's screen, Aziz) REPLACES
"Just N quick questions" on `Step.questionCount`: an `IntroScreen` with the
valley's seated Otto, who says "Your answers show me what gets in the way,
so I can help you keep going." (Aziz's line, Brainrot's direct reason for
asking) in his typed bubble, and "Let's do it!". The answers are not yet
used after onboarding beyond the reminder time (Aziz: leave it).
- **Otto WRITES in a notepad here**, a Runway clip (`otto-writing.mov`,
  `SeatedClip.writing`). It had a hard cut on its first frame (Runway's
  still, framed differently), which is dropped; no two moments of the
  writing match (the fur shimmers), so it is a BOOMERANG of the writing,
  frames 2 to 84 at 20 fps, through a small head tilt and before he looks up.
  Keyed with new options in `otto_video_key.swift`, all needed and all
  measured: `--white-floor 160 --warm 6` (Runway drew a NEUTRAL grey shadow
  under him while the page is a WARM white: warmth, not brightness, tells
  paper from ground), `--keep-pockets` (pocket removal punched holes in the
  page), `--largest` (noise specks stretched the crop to the whole frame),
  `--erode 2 --band 3` (a softer edge than the wave, which left a pale rim)
  and `--cool` (the shadow's core is blue-grey; Otto's colours always have
  red above blue, so it cannot eat him).
- **The clip sits in the VALLEY'S layer (`SeatedClipLayer`, drawn by
  `OnboardingView`), not in the screen.** Inside the screen it slid in beside
  the valley's Otto while he faded: two Ottos side by side. Now the valley
  keeps his cushion and fades its Otto (`ValleyScene.figureHidden`) while the
  clip fades in on the same spot, sized so its body matches (186 x 1.17 scene
  units, body 95%, on the line 24% up). Verified: one Otto cross-fading in
  place, and 18 s of loop with no flash. **A clip of Otto on a screen that
  slides must live in the fixed layer, never in the screen.**

**The goal question comes first** (`MotivationScreen`, Brainrot's goal
screen, Aziz): "What's your goal with meditation?", AS MANY AS ARE TRUE
and a Continue button, greyed until one is picked (Aziz: not tap to
advance): Feel less stressed, Sharpen my focus, Sleep better, Be more present,
Overthink less, Just curious (`Motivation.offered`; three new cases added
LAST). "Make it a daily habit" was left out on purpose: that is the whole
app. `InterviewStep.motivation` now precedes `referral`. The writing Otto
GLIDES from his cushion into the top-right corner as the question slides in
(`SeatedClipLayer(inCorner:)`, a scale and offset on the same player, so it
animates and never restarts); the cushion fades. **The rest of the old
interview is being redone by Aziz; do not polish it.**

**The first three questions are Brainrot's layout** (`CornerQuestionScreen`:
title in the sky, white answer plates, Continue greyed until an answer, the
writing Otto in the corner across all three):
1. "What's your goal with meditation?" (`Motivation.offered`, pick any).
2. "What usually gets in the way of meditating?" (`Obstacle`: I forget, I
   don't have time, My mind won't settle, I'm not sure I'm doing it right, I
   lose motivation after a few days, My phone pulls me away; pick any). It
   keeps Otto's promise on "Let's personalize" ("Your answers show me what
   gets in the way"). A fresh enum, not `DropoutCause`, which is past tense,
   written for people who quit, and locked by its own tests.
3. "Which one sounds most like you?" (`Role`, Brainrot's "Which best
   describes you?" reworded; ONE pick, still Continue): Creative, Employee,
   Founder, Athlete, Student, Just trying to live well (Aziz: no "/ ..."
   halves, and "Employee", not "Desk job").
4. "When could you fit in a few quiet minutes?" (`QuietTime`, one pick:
   First thing in the morning 8:00, On a break during the day 12:30, In the
   afternoon 3:30, In the evening 7:00, Right before bed 10:00). **The answer
   sets `answers.reminderTime`**, which the reminder screen then opens on:
   the job the cut anchor question used to do.
5. "Have you tried to make meditation a habit before?" (`HabitHistory`, one
   pick: Yes, but it didn't stick / Yes, it worked for a while / No, this is
   my first try). Not yet read by anything; the old `baseline` question and
   the persona it feeds are part of the interview Aziz is redoing.
`OnboardingAnswers.obstacles`, `.role`, `.quietTime` and `.habitHistory` are OPTIONAL on purpose:
synthesized Codable requires every non-optional key, so a plain property
would have failed every saved resume record from before it. **New answer
fields must be optional for the same reason.**

**"Did you know?"** (`DidYouKnowScreen`, `Step.didYouKnow`, after the habit
question, Brainrot's screen): four white fact cards popping in with a tick
above the seated Steady Otto. **Every fact is from a study 808 already
cites** (Mrazek 2013, Killingsworth & Gilbert 2010, Goyal 2014, Cearns &
Clark 2023; details in the doc comment), each about Brainrot's length.
Aziz asked for "risks of not meditating"; it was written as what practice
does instead, because no study measures harm from not meditating (an
invented risk is the health claim App Review rejects) and the copy never
tells the reader what they lack. Goyal is quoted for ANXIETY, not stress
(the stress evidence is weaker). Cards sit ABOVE Otto, compact under 760pt.

**His halo was cut off flat along the top** at the bright looks (Aziz). A
Rive view draws only inside itself, and `.contain` fills the view's
LIMITING side with the artboard, so only one side can be given spare room
without scaling him up. `OttoAuraFigure` now shapes the view by look: wide
(`flightSpan` 2.6) for the low looks, where the moth flies off-screen, and
TALL (`headroom` 1.6, from look 9) for the bright ones, where he floats and
the halo rises over his head. Bottom-aligned both ways, so he is the same
size and place. Verified on See for yourself and on Home at 97.

**Every typed line in the intro screens is Otto speaking** (Aziz): the
line under the title moved into `OttoSaysBubble`, white and round, hanging
just above his head with its tail at him, still typed a letter at a time
with a haptic tick each. The screen types it, not the bubble, so each letter
can tick. `TypedLine` is deleted.

## ONBOARDING'S OPENING IS BACK IN THE VALLEY; OTTO'S CLIPS NO LONGER FLASH (2026-09-23, late, Aziz)

Supersedes the white-page parts of the section below. **Screens 1, 3 and 4
(welcome, Meet Otto, "The more you meditate") stand in the valley**; only the
breath (screen 2) is still a white page (`Step.isWhitePage`).
- `IntroScreen` puts the words in the SKY (ink on the light blue, clear of
  his head) and Otto on the meadow. Meet Otto's two pages pass `standing:
  false` and the valley draws the seated Steady Otto on his cushion
  (`OnboardingValley` stage `.steady`), exactly where the stress screen and
  Home seat him. The welcome's standing clip is placed in SCENE coordinates,
  feet on `SitLayout.cushionBottom` minus 6, height `222 * SitLayout.scale`,
  standing on HIS OWN CUSHION (Aziz: "the same mat hes sitting on ... i want
  it to be consistent"), the scene's `Cushion` at exactly the size and
  place the valley draws it for the seated screens, feet on its top. A
  separate flatter mat and a row of grass blades were both tried and
  dropped the same evening. `WelcomeGround` is deleted.
- **Grasshoppers no longer land on petals** (Aziz: "the 2dness of the
  flowers"). The meadow is drawn once, all of it, before any grasshopper, so
  a NEARER flower whose head reached up to its feet looked like a landing
  pad. Each grasshopper now redraws the grass and flowers nearer than its
  feet line over itself, masked to its own outline (`Meadow(nearerThan:)`
  in `ValleyLife.hoppers`): nearer stems and petals cover its legs and body,
  and nothing outside its outline is drawn twice, so no stem darkens.
- **Melvin's birds and grasshopper are on all three** (Aziz). On the welcome
  the scene runs with `standingFigure: true`: it splits grasshoppers at the
  cushion line as if he were its own and draws only the farther ones;
  `ValleyFrontLife`, drawn above the screen with the SAME seed
  (`OnboardingView.lifeSeed`, passed as `ValleyScene(seed:)`), draws the
  nearer ones over him. `OnboardingFrontLife` and the `meadowLife` switch
  that hid the grasshopper there are gone.
- **THE "GLITCH" WAS `AVPlayerLooper`.** At every loop it showed ONE EMPTY
  FRAME: Otto vanished for a sixtieth of a second every seven seconds. Found
  from a 60 fps recording (a pair of frame differences of 38 grey levels,
  the bare meadow between them), and it had been there since the first
  clip. `OttoClip` now loops one `AVPlayer` on one item, `actionAtItemEnd =
  .none`, seeking to zero on `didPlayToEndTime`, which keeps the last frame
  up through the seek. Verified: 22 s, three loops, largest change 2.8 (his
  arm mid-wave). **Never use `AVPlayerLooper` for an alpha clip.**
- **The "phasing" was the loop crossfade** ghosting his arm: his pose differs
  at every pause (5.5 against a still-to-still noise of 0.2), so no two loop
  ends match. The welcome loop is now a **boomerang**: frames 38 to 107
  forward, then back, turning and wrapping while he holds still, so nothing
  is ever blended. Plus `--steady` in `otto_video_key.swift`: a median of
  three on the alpha across neighbouring frames, because each frame is keyed
  alone and the soft edge wandered a pixel frame to frame.

## THE WELCOME SCREEN IS BRAINROT'S, AND OTTO WAVES FROM A VIDEO (2026-09-23, Aziz)

**Onboarding now opens:** welcome (Otto waving) → one breath (Otto raising
his arms) → **Meet your meditating partner: Otto** ("He's doing alright.",
`MeetOttoScreen`, `Step.meetOtto`, Brainrot's "Meet your brain", Otto as the
Steady aura figure Home draws) → its second page, **"The more you meditate,
the more enlightened he becomes."** (`Step.ottoGrows`, not typed, the same
Otto: both steps share one screen identity, so only the words cross-fade)
→ the question count. Welcome and Meet Otto are one `IntroScreen`.

**Screen changes in onboarding, three fixes (Aziz: "showing the garden area
in between screens"):**
- **The outgoing screen was sliding away BEHIND the valley.** A view
  animating out of a ZStack is drawn behind its siblings unless it has a
  zIndex, so every screen vanished in one frame and the bare garden showed
  until the next arrived. `.zIndex(1)` on `content`. This was true of the
  whole flow, not only the new screens. **Any ZStack that transitions its
  children over a background needs the same.**
- **A white page (`whiteCover`) sits over the valley behind the white
  opening screens** (`Step.isWhitePage`), and when the flow leaves them it
  holds for the slide, then fades, so the valley arrives behind a screen
  that is already in place.
- **Otto's Rive files are parsed once and cached** (`OttoRig.preload`,
  `OttoAuraRig.preload`, called as onboarding appears). Every screen with
  Otto used to parse `Otto.riv` on the main thread as it appeared, which
  stalled the slide onto it for a few frames.

From a Brainrot screenshot: a white page, a soft ground rise (`WelcomeGround`,
warmed toward Otto's cream), a dot of progress bar, Otto standing, "Welcome to
808!" over "It's time to regain control of your mind.", and "Let's go!". This
replaces the valley welcome and its bubble; the grasshopper overlay
(`OnboardingFrontLife`) is deleted because it crossed a white page.

- **The sequence:** Otto fades in and waves, the title arriving with him (a
  pop from his feet and a typed title were both built and cut the same day:
  Aziz, no pop, title not typed); the line under it types with a light
  haptic tick per letter (28 ms, spaces silent); "Let's go!" springs up with a
  thump. `WelcomeHaptics` keeps its generators prepared. `TypedLine` lays
  unarrived letters in clear ink so centred text never reflows. Reduce Motion
  gets the finished screen, a still Otto and no ticks. The simulator plays no
  haptics: judge on a phone.
- **Onboarding's buttons and progress bar are GREEN** (`OnboardingGreen`),
  Duolingo's "go" colour warmed toward the meadow. `PrimaryButtonStyle`
  gained `fill` / `shade` / `ink` (gold by default, so the rest of the app is
  unchanged); the paywall ladder's buttons stay gold.
- **The wave is a generated VIDEO, not the rig.** The rig's arm turns only
  about ten degrees before the cut behind it shows, which on a phone read as
  no wave at all (a whole-body wiggle to compensate was built and dropped).
  Runway (Gen-4 image to video, 1:1, from the clean waving art on white, the
  yellow flourish marks removed) made a 7 s clip. `OttoClip`
  (`Coherence/Otto/OttoClip.swift`) plays `otto-welcome-wave.mov` through an
  `AVPlayerLayer` (BGRA pixel buffers keep the alpha), looping seamlessly with
  `AVPlayerLooper` so he waves for as long as the screen is up (Aziz:
  "constantly waving"); a missing file falls back to the still pose.
- **`tools/otto_video_key.swift` turns a white-background clip into HEVC with
  alpha.** Floods the white in from the border; removes enclosed white
  pockets unless near-black lies within 6 px (keeps the eye whites, whose
  antialiased ring means they never touch the pupil); un-mixes the two-pixel
  edge band from white. `--from/--to` trim, `--crossfade K` blends the loop's
  end into its start, `--center-feet` centres the crop on his FEET (the box
  around him includes the raised arm, which put his body 54 px right of
  centre).
- **FRAME RATE, the "glitching" (Aziz, twice).** Runway exports 24 fps, and
  24 does not divide a 60 Hz refresh, so frames are held unevenly and the
  wave judders. **Interpolating to 60 fps was tried and REJECTED:** ffmpeg's
  `minterpolate` placed its made-up frames unevenly (arm steps of 0.28, 0.71,
  0.43 ...), still a shimmer. What ships: the ORIGINAL frames retimed to
  **20 fps** (`setpts=1.2*PTS -r 20`, every frame kept, the wave 20% lazier),
  which divides 60 and 120, so every frame is held three refreshes. The loop
  wraps while he is HOLDING STILL between waves (frames 38 to 107), crossfaded
  over 9 frames because his arm rests in a slightly different spot after each
  wave. Measured in the app from a 60 fps recording: a steady three-refresh
  cadence and no spike at the wrap.
- **The recipe for every future Otto move the rig cannot make:** clean art on
  white with room for the motion, Runway describing motion only with a
  locked camera, then retime to 20 fps, loop at a still moment, crossfade,
  key.
- **The breathing screen's Otto is a clip too** (`otto-breath.mov`). Since
  2026-09-25 (Aziz) he breathes IN through his nose, holds, and breathes OUT
  through his mouth with light-blue breath lines rising (light blue so they
  survive the white-background key; `--steady` and `--largest` must NOT be
  used on it, they erase moving thin lines and lines detached from him).
  Retimed from the 24 fps source by phase: in 20-99 one-to-one (80 frames),
  hold 100-155 sampled to 40, out 156-239 sampled to 80; no built-in stutter
  this time. Crop 510 x 674, drawn 320 tall. It replaced the first version,
  where he raised his arms palms up, held them overhead and lowered them palms
  down. It replaces the rig and the whole-figure swell, starts on the same
  clock as the water, words and haptics, and holds its last frame. Cut to
  EXACTLY 80 frames rising, 40 held, 80 lowering at 20 fps, which is the
  screen's 4, 2, 4 (the extra frames came out of the slow starts and ends,
  every other one, and out of the still hold). Verified on the simulator:
  arms at the top as "Hold." appears, back on his knees for "Nicely done".
- **CHECK EVERY RUNWAY CLIP FOR A BUILT-IN STUTTER.** The breathing clip
  (10 s) had one and the wave (7 s) did not: in every block of four frames
  one was a REPEAT of the frame before and the next one jumped two steps
  (frame-to-frame motion 0, 1, 1, 2). Found with the same frame-difference
  measure. Fix: drop the repeats, give each remaining frame its true time
  (frames 4k+2 and 4k+3 sit one slot early), feed that as variable frame
  rate through the concat demuxer, and let `minterpolate` fill only the one
  missing slot per block. Motion then ramps smoothly. Do it before cutting.
