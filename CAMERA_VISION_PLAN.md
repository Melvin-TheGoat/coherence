# Camera vision: the no-Watch session

Status, 2026-09-14. Resumed by Melvin. The engine side is built and measured
(`Shared/Engine/CameraSignal.swift`, `tools/camera_harness.swift`); the
session flow below is designed, not built. Branch `camera-vision`, merged up
to `mvp`. Nothing here ships until the ground-truth plan in section 5 has run.

The promise is the same one the Watch keeps: prop the phone, meditate, and
afterwards see what your body did. The camera reads two of the three signals
(stillness and breathing). It cannot read heart rate, and the score says so.

## 1. The session flow (phone only)

**Setup screen.** Reached from the plus tab when no Watch is paired, or as a
choice beside "On your Watch" when one is. Copy states the positive: "Prop
your phone so it can see you from your lap to your head, about an arm's
length away, and sit or lie however you like." Three lines of guidance, each a
measurement from the captures: the torso must be in frame (the ROI is what
made breathing readable; whole-frame read harmonics); the phone must rest on
something, not be held (a moving camera injects its own shift signal); the
room needs enough light to see you (the luma channel and the person detector
both go blind in the dark). The sound picker is the existing one. The
Do Not Disturb tip stays.

**Placement check.** The live preview, big on the Begin sheet before the
session starts (3:4, the front camera's own frame, the width the sheet has
left after the title and the tip), with a thin WHITE outline of a seated
figure (`SeatedFigureOutline`, a Shape drawn from paths, no image) laid over
it to sit into. When Vision has found a person in three of the last four
detections (one a second) the outline turns TEAL and the caption under the
preview reads "You're in frame" instead of "Sit so your head and lap fit the
outline". Nothing else changes colour: a found torso is guidance, not an
achievement, and Begin stays the only gold thing (Melvin, 2026-09-16; this
replaces the earlier teal-to-gold idea). Built on this branch for the DEBUG
collector, behind the same Settings toggle: `CameraFramingView`, with one
recorder instance owned by `SessionCoordinator` that the sheet starts, Begin
claims, the Watch's started-ack arms, and a dismissed sheet releases. Whether
the shipped flow gates Begin on being framed is still open. The outline is the
only feedback; there is no "score" here (the gold ring means a measured score,
nowhere else). Permission denied leads to a screen that says what the camera
is for and offers the Watch path; it never dead-ends.

**Settling countdown.** After Begin, ten seconds before t = 0, screen dimmed,
a single line "Settling in". The Watch path trims the first and last five
seconds because putting the arm down and lifting it are large transients.
On the camera path the transient is bigger: you have just tapped the phone
and are sitting back. IMG_7635 shows a settle running x11 to x53 the session's
motion floor and the engine reads a "6/min" through it. The countdown keeps
that out of the session, and the engine's motion gate (x4 the median) catches
what the countdown does not.

**The session.** Screen dimmed to near black, the elapsed time in the same
quiet type as the Watch's live screen, one End button, NO live biometrics.
This is the product stance and the engine's design both: the read is decided
over the whole session by a tracker, so a live number would be one the
finished result may contradict. The camera keeps running with the screen dim
(idle timer off, exposure locked after three seconds, ROI fixed by the median
of the first 30 seconds' detections). No frame is ever stored; each frame is
reduced to nine numbers and released. Leaving the app ends the session, and
the copy says so on the setup screen, because the front camera cannot run in
the background. Bring-your-own audio therefore means audio from this phone or
another device, not another app on this phone.

**Results.** The existing `SessionResultsView`. `SessionEvidence` already
draws no heart panel for an empty heart series, so the screen shows the
stillness curve, the breathing curve with the doorway band, the score ring,
and the verdict. Two additions: a "Camera session" chip beside the date, and
the verdict must be checked against a heart-less input (it must never say the
heart did anything; its phrase bank keys on presence, which is the same rule
that keeps breath out of non-breath sessions). The share card reads the same
row and draws what is present.

**Storage.** One new optional field, `Session.source: String?` ("camera";
nil means Watch), lightweight migration, CloudKit-safe. `MeditationStats`
unchanged: heart fields empty, `stillnessMethod` "camera",
`algorithmVersion` "camera-1.0.0". The phone stays the only writer. The
`ScoreMigration` guard is already in: rows whose version starts with
"camera-" are never rescored by the Watch formula (test locks it).

## 2. What is reused from `SignalEngine`

The camera module produces a `SignalResult` on the same grid (30 s windows,
5 s hop, `floor((total - 30) / 5) + 1` windows, point i centred at
15 + 5i), so every consumer downstream is untouched: `SessionEvidence`,
`VerdictEngine`, `ShareCard`, `SessionStore.persist`, the results screen.

Reused as functions, not copied: `SignalEngine.breathDoorway` (the doorway is
the one definition of "slowed the breath at the start" for both instruments;
the camera passes `clarityFloor: 0.30`, its own read bar, and
`lateClarity: .infinity`, see section 3), `SignalEngine.spreadStillness` (the
camera's stillness is calibrated onto the wrist's scale so the same rescale
applies), and `SignalEngine.durationFactor` (one time ceiling for both).

Not reused: `SignalEngine.analyze`. It takes wrist attitude in radians with
millirad amplitude floors and an accelerometer gate; none of that has a
camera meaning. The camera's breathing path is the probe's, ported:
six shift channels high-passed at 15 s, per-window detrend and DFT scan over
3.5 to 26/min with independent-bin clarity and edge zeroing, candidates pooled
across channels, Viterbi continuity at 0.45 per breath/min of jump. Its
stillness is the ROI frame difference against the session's own floor (10th
percentile of 5 s means), mapped by 1 / (1 + 0.36 (ratio - 1)).

## 3. The score with no heart term

The Watch scores breath .20 / heart .50 / stillness .30, and .60 / .40 when
breath is absent. The camera has no heart. Handing its row to the Watch's
`depth` would renormalise to breath .40 / stillness .60. That is refused.

**Camera: breath .20 / stillness .80 with a doorway; stillness alone
without one.** Then times the shared time factor, clamped at 1.

Why .20 and not .40: the wrist accepted that 62% of pure-drift sits forge an
early doorway BECAUSE breath is .20, at which a forgery moves a session about
three points. On the camera a forged doorway is worth .20 (1 - stillness):
four points on a settled sit, ten on a restless one. At .40 it would be
twenty on the restless one, the trade the wrist refused at .45. Every other
number would be a guess; .20 is the weight at which the risk was measured
and accepted. `test_forgedDoorway_isWorthAtMostBreathWeight` locks it.

Why stillness may carry .80 here when the Watch demoted it to .20: on the
wrist it saturated (0.84 to 0.97 on every genuine sit) and said "you sat".
The camera's does not saturate the same way: the settle is unmistakable (x18
to x64 the floor), the ROI resolves Melvin's 2.5-minute settle where the
whole frame saw one minute, and getting up reads as getting up. What it
cannot resolve at 2 m is a wrist fidget (x1.1 to x1.5 against a settled
x1.31). So the camera score answers "did you settle and stay settled" well
and "how deep" poorly. That is what a camera at two metres can honestly say,
and the rows are versioned "camera-" so the history never draws the two
formulas as one line.

The cost, on the captures: Aziz's 28-minute sit scores 84 (stillness spread
0.75, doorway 5.5/min at 5 s, factor 1.05). Melvin's 10-minute sit scores 20:
his stillness mean is 0.800 (the wrist's own, digitized from the same sit,
is 0.82), which `spreadStillness` maps to 0, and only the doorway's .20 is
left. On the Watch that session was carried by its heart term. A slow
settler pays for it on the camera, and there is no honest way around that
without a third signal.

One deliberate difference inside the doorway: the Watch admits a start after
90 s when the stretch's clarity clears 0.85, a bar wrist sway never reached
across 227 drift sessions. Camera sway does reach it: IMG_9543 minute 19
reads a rock-steady 4.5/min at clarity 0.93 with the wrist beside it at 19.
So on the camera a doorway must begin within the trusted 90 s, full stop
(`lateClarity: .infinity`, `test_lateDoorway_isRefusedOnTheCameraHoweverClear`).

## 4. Where the engine stands (measured, `tools/camera_harness.swift`)

Against the wrist's own curve, same rule as `camera_compare.py`:

- IMG_7635 (Melvin, 10 min, 2 m, bright): median |error| 1.22/min, 55%
  within ±1.5, n = 69. The probe read 1.29 / 56%. Doorway 5.6/min at 90 s.
- IMG_9543 (Aziz, 28 min, 0.5 m, bright): 2.23/min, 35%, n = 243. The probe
  read 1.68 / 45%. The whole gap is minutes 6 to 9, where the tracker takes
  the fast line (12 to 20) and the probe held 5; the wrist says 16.5 then
  6.7, 6.3, 8.9. This is the "short high-rate episode" the branch notes mark
  unresolved between three instruments. Not tuned toward either. Minutes
  10 to 18 agree within 2 (camera 18.1 to 21.3, wrist 18.1 to 20.4).
  Doorway 5.5/min at 5 s: the confirmed paced opening.
- The port reproduces the probe's per-window numbers to 0.10/min median when
  handed the probe's uniform-time assumption; the shipped module windows by
  true time because the in-app collector drops frames.
- Two constants changed from what was carried over, both by measurement:
  the motion gate is x4 the median, not the wrist's x1.5 (which threw away
  fifteen correct reads on IMG_7635 and blocked both doorways); the doorway
  floor is the camera's 0.30 read bar (0.15 admits settle junk as a doorway,
  nothing in between recovers a longer one for Aziz).
- Runtime: 0.3 s for 28 minutes at 6 fps, in -O. Fine at session end.

## 4b. In-app sits so far (the DEBUG collector, 640x480 front camera)

- 14EDEB30 (Melvin, 2026-09-15, natural breathing, first run): 74% of
  windows read, median 5.7/min, doorway 5.7 at 90 s; median error against
  the wrist 1.0/min. Stillness low from real movement.
- 07707B98 (Melvin, 2026-09-16, **paced 12/min**, ~5.5 min): torso ROI
  read 57 of 64 windows, median 11.4/min, per minute 10.8 / 10.6 / 10.5 /
  12.0 / 12.1 / 11.6; the wrist read 10.8 / 10.8 / 10.2 / 12.1 / 12.1.
  Camera vs wrist median |error| 0.17/min, 100% within ±1.5 (n = 40). No
  doorway, correctly: 12/min is above the 9/min ceiling. Both instruments
  sit about 1/min under the pace in the first three minutes and on it in
  the last two, so either the pacing settled late or both undershoot the
  same way; a metronome-timed recording would tell. First of the six paced
  sits in section 5, item 1: **the camera reads a paced 12 as well as the
  wrist does, and refuses the doorway at that rate.**

## 4b. FIRST PAIRED SIT, and a tool bug that flattered everything before it

Aziz, 2026-09-17, sit 1 of the twenty: 6/min paced for three minutes, then
five natural, phone at about a metre, Watch on. `7B2DB2FC`.

**`camera_compare.py` was fitting the alignment it was supposed to measure.**
It swept offsets 0 to 180 s and kept whichever minimised the median error. On
this sit it chose 115 s and reported 1.43/min; the capture header says the true
offset is 8.9 s, which gives **2.52/min**. It also searched positive offsets
only, so it could never find the real one: the recorder always starts a few
seconds AFTER the session. Fixed to read `recorder_started_at -
session_started_at` from the capture header, with the search kept only as a
labelled fallback for a headerless file. **Every camera-vs-wrist number
produced before 2026-09-17 was fitted this way and is optimistic; re-run
anything quoted in this file before relying on it**, including the 12/min
in-app sit in commit `0ec6c1c`.

**What the sit actually says.** Minute by minute, camera minus wrist:

    paced    min 0  +0.3    min 1  +0.2    min 2  +0.1
    natural  min 3  -1.3    min 4  -4.2    min 5  -2.0
             min 6  -8.7    min 7  -7.4

So on the thing the product claims, deliberate slow breathing at the start,
the camera is **within 0.3/min of the wrist, every window** (n=17, 100% within
±1.5), comfortably inside the ±0.5 target in section 5. On natural breathing
it is not close: median 4.7/min out, 11% within ±1.5, and the error grows as
the real rate climbs.

**The shape matters more than the size.** The camera does not scatter; it sits
at 4 to 6/min while the wrist climbs past 13. It reads roughly the rate it
locked onto during the paced opening and does not track upward. A tracker that
behaves this way looks perfect on every paced sit and is wrong on every natural
one, which is exactly the pattern that would survive a ground-truth programme
made only of paced sits. Whether this is the tracker holding its path, or the
ROI reading postural sway rather than the torso, is the open question; both
show up as a slow steady rate.

**Consequence for the doorway.** It may not matter much. The doorway is
defined over the first five minutes and is all-or-nothing, so a camera that
reads slow breathing well and natural breathing badly can still score the
doorway correctly. The risk is the reverse: a camera that always reads 4 to
6/min will invent doorways in sits that had none, which is precisely what
section 5's group 4 controls measure. **Those controls are now the most
important four sits in the programme**, ahead of the counted ones.

## 5. Ground truth before anything ships

The DEBUG collector (`CameraSignalRecorder`, Settings > Camera capture) is
the instrument: every test sit is a labelled pair, camera frames beside the
wrist's own result, t = 0 shared, no offset to solve. Pull with
`tools/camera_pull.sh`, score with `tools/camera_harness.swift`.

What to record, in this order, because each answers one open question:

1. **Paced breathing at known rates, six sits.** A metronome or paced-breath
   app at 6, 8 and 12 breaths/min for three minutes each, then five minutes
   natural, two people. Answers: doorway recall (target: every 6 and 8
   session opens one within 90 s, zero at 12), and rate accuracy on the one
   thing the product claims (target: ±0.5/min on paced, the wrist reads ±0.3).
2. **Counted natural breathing, four sits.** A second person counts breaths
   per minute out loud from a chest strap or by watching, ten minutes. This
   is the data that decides minutes 6 to 9 of IMG_9543. Target: median
   ±1.5/min; if a fast episode is confirmed and the tracker misses it, that
   is a tracker finding, not a tuning target.
3. **Placement sweep, six sits.** The in-app preset (640x480, 10 fps, front
   camera) at 0.5, 1 and 2 m; lap, desk, bed; one dim-lamp sit. Answers: the
   clarity distribution at the real preset (IMG_9543 at 0.5 m sat at the
   0.30 bar, IMG_7635 at 2 m read 0.6 to 1.0) and whether the ROI is found
   (target: fixed within 30 s on every sit; a whole-frame fallback must
   still read the paced sessions).
4. **No-breathing controls, four sits.** Sit still and breathe naturally with
   no pacing, and one sit of deliberate slow postural sway. Answers: the
   false-doorway rate on the camera (the wrist's synthetic figure is 62%;
   a measured real figure above that means the .20 weight must come down).
5. **Stillness against the wrist, all of the above.** Spearman per session
   and the two session means side by side, to confirm the 0.36 gain holds
   at the real preset (today's evidence is one pair: 0.800 vs 0.82).

Twenty sits, two or three people, two evenings. Scoring is the harness's
existing lines; add nothing to the engine until the twenty are in.

## 6. App Store and privacy consequences

- **`NSCameraUsageDescription`** must describe the shipped feature, not the
  DEBUG collector: "808 uses the front camera to measure how still you were
  and how you breathed while you meditate. No photo or video is taken or
  saved." The Watch string precedent applies: a purpose string that describes
  a feature that does not exist is a false statement, so this ships with the
  feature, in the same build.
- **No frame leaves the phone, and none is stored.** Each frame becomes nine
  numbers on the capture queue and is released. The DEBUG CSV is compiled
  out of Release (`#if DEBUG`, proven by `strings(1)` on the binary as the
  other DEBUG hooks were). The results are `MeditationStats`, device-local
  by the 5.1.3 split, exactly as Watch results are.
- **`PrivacyInfo.xcprivacy` does not change.** Apple's "collected" means
  transmitted off device where we can read it. Nothing from the camera is.
  The App Privacy labels stay as they are (Product Interaction, User ID,
  Purchases, Email; no Health, no Photos or Videos). Do not add a camera
  data type: declaring collection that does not happen is as wrong as
  omitting collection that does.
- **The privacy policy needs one paragraph**, both copies: today it says "we
  do not collect camera data", which stays true, and must add that the
  camera session processes the image on the device, stores no image, and
  records only the stillness and breathing series it derives. Manual
  Cloudflare redeploy, as always.
- **Review notes stay true**: no server, no AI service, no account needed.
  Add one line telling a reviewer without a Watch to use the camera session,
  so the Watch-less route no longer needs the "Check again three times"
  escape. Health & Fitness data type remains not collected.
- **Analytics**: `camera_session_started`, `camera_session_completed`,
  `camera_placement_failed`, `camera_permission_denied`. Names only. Never a
  rate, a stillness value or a score.
- **5.1.1**: the permission is asked at the placement check, not at launch,
  and refusing it leaves every other feature working.
- **Equity**: the read is motion-based, not optical absorption, so the
  skin-tone question that blocked the fingertip PPG path does not carry over.
  Low light does: the person detector and the luma channel fail first in a
  dark room, and the placement sweep in section 5 includes a dim sit so the
  setup copy can say how much light is enough.

## 7. Known limits, stated once

Fast breathing episodes are unresolved (section 4). The doorway at 0.5 m is
fragile at the 0.30 bar. A slow settler scores low with no heart to carry
them. Stillness is normalised per session, so someone who never stops moving
normalises to their own motion; an absolute floor at the fixed preset is
worth measuring once the placement sweep exists. The camera cannot run in the
background, so a camera session is a screen-on session. None of these are
stated to the user as failure modes; the copy says what the camera reads
best, which is a still body and a slow breath.
