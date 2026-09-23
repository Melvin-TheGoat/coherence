import SwiftUI
import SwiftData

/// Begin a session. Deliberately almost empty.
///
/// One promise: sit down and 808 sits with you. No practice type, no
/// guidance, no pre-session reading. **The length came back on 2026-09-22**
/// (Aziz, `mockups/ready-timer.html`): a clock in the sky with a tape under
/// it, and a tap on the clock to type an exact number. Open (∞) is still at
/// the end of the tape and silence is still the default sound, so nobody has
/// to decide anything.
///
/// **Begin does not mention a Watch because Begin does not involve one.** The
/// sit runs here, is timed here and is written here. The subtitle used to
/// promise hardware half the people who install 808 do not own, and then
/// promised it as an optional extra, which was still a sentence about a
/// wristwatch on the screen somebody reads with their eyes closing.
///
/// Everything this screen used to ask (belly breathing, the pulse read, the
/// method guide, a length picker) was cut in the MVP focus pass. The tag
/// `v1-full-feature-set` has it if any of it comes back.
struct SessionSetupView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [Preferences]

    /// Empty = silence.
    @AppStorage("sessionSoundID") private var soundID: String = ""

    /// The length on the clock, nil for Open. Starts at the last one used
    /// (`Preferences.defaultDurationSec`, which Settings edits too), so a
    /// daily ten-minute sitter never touches the tape.
    @State private var lengthMinutes: Int?
    @State private var lengthLoaded = false

    /// Seconds left before the session starts, or nil when not counting.
    /// Phone-initiated sessions only: starting from the wrist means you are
    /// already sitting, so the Watch's own Begin stays immediate (Melvin,
    /// 2026-09-01).
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    /// The count reached zero: Otto settles from waving into sitting just
    /// before the sit screen takes over, so the hand-off is his, not a cut.
    @State private var settling = false

    @ObservedObject private var focus = FocusShortcut.shared
    @State private var showFocusSetup = false
    @Environment(\.scenePhase) private var scenePhase

    /// Choosing a sound is a STATE of this screen, not a sheet over it.
    ///
    /// The whole point of the valley is that it does not move: tapping Sound
    /// swaps what is in the list and moves Otto up to the corner to ask, and
    /// Done swaps it back. A sheet would slide a second surface over the
    /// scene and make it two screens, which is exactly the settings-panel
    /// feeling Aziz rejected.
    @State private var choosingSound = false

    /// The two heights `ottoLift` is worked out from, measured as laid out.
    /// Seeded with what an iPhone 17 Pro measures, so the first frame is
    /// already right there and nothing visibly settles on the others.
    @State private var controlsHeight: CGFloat = 221
    @State private var pickerHeight: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let day = DayLight.at(0)
            let lift = ottoLift(in: geo.size)
            ZStack {
                // ONE scene, for both states. Never rebuilt, never replaced:
                // it owns the Rive rig, and swapping it would restart him.
                ValleyScene(progress: 0, pose: settling ? .meditating : .greeting,
                            ottoInCorner: choosingSound, ottoLift: lift)

                if choosingSound {
                    asking(day: day, in: geo.size)
                    SoundChoiceList(soundID: $soundID, top: Self.listTop) {
                        choosingSound = false
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    greeting(day: day, in: geo.size, lift: lift)
                    if let countdown {
                        countingIn(countdown, day: day)
                            .position(x: geo.size.width / 2, y: Self.lengthY(in: geo.size, lift: lift))
                            .transition(.opacity)
                        countdownCancel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        SessionLengthPicker(minutes: $lengthMinutes, ink: day.ink, inkSoft: day.inkSoft)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pickerHeight = $0 }
                            .position(x: geo.size.width / 2, y: Self.lengthY(in: geo.size, lift: lift))
                            .transition(.opacity)
                        readyControls(day: day, compact: Self.compact(in: geo.size))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: choosingSound)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: countdown == nil)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            // Counting in, the one way out is the Cancel pill where Begin
            // was; two Cancels on one screen is one too many.
            if countdown == nil {
                Button(choosingSound ? "Back" : "Cancel") {
                    if choosingSound { choosingSound = false } else { cancel() }
                }
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(DayLight.at(0).ink.opacity(0.55))
                .padding(.horizontal, 20).padding(.top, 14)
            }
        }
        .sheet(isPresented: $showFocusSetup) { FocusSetupSheet() }
        // NOT a permission prompt on appear. Somebody who opened this screen
        // is about to close their eyes, and a system dialog is the single
        // worst thing to put in front of them. The prompt comes when they
        // reach for the switch, which is the moment it is about anything.
        .onAppear {
            focus.refreshStatus()
            if !lengthLoaded {
                lengthLoaded = true
                lengthMinutes = SessionLength.clamped(preferences.first?.defaultDurationSec.map { $0 / 60 })
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { focus.refreshStatus() }
        }
    }

    /// The timer's centre: the middle of the sky between the island and
    /// Otto's line, which is pinned to the top of his head and runs about 84pt
    /// tall. The same band the sit screen centres its headline in. When he is
    /// lifted the band is shorter, so the timer rises half as far as he does.
    private static func lengthY(in size: CGSize, lift: CGFloat) -> CGFloat {
        let bubbleTop = SitLayout.ottoTop(in: size) - 8 - 84 - lift
        return (SitLayout.skyTop(in: size) + 14 + bubbleTop) / 2
    }

    /// Where the sound list starts. Below Otto's corner perch, so his face is
    /// never behind a pill.
    private static let listTop: CGFloat = 196

    /// The Ready controls' distance from the bottom edge.
    private static let controlsBottom: CGFloat = 22

    /// How far Otto is lifted so his cushion clears the Sound and Silence
    /// pills (Melvin, 2026-09-23: "gonna have to raise Otto a little bit for
    /// this, which is ok. Make sure it doesnt clash with the scroll bar at
    /// the top").
    ///
    /// **Worked out per screen, because the overlap is different on every
    /// phone**: the pills are a fixed height and Otto is sized to the screen.
    /// A flat 6pt (the first build) left the pills over his legs and cushion
    /// on a 17 Pro and up to his chest on an SE. Now: enough to clear the
    /// cushion with 6pt to spare, capped by the sky above him. His bubble
    /// rises with him and the timer half as far (it stays centred in the band
    /// over the bubble), so the cap is where the gap between the tape and the
    /// bubble would close under 10pt. A 17 Pro gets the whole lift (about
    /// 63pt). An SE has almost no sky to give, so its pills are also the
    /// compact ones (`compact`); some overlap stays there, as it always had.
    ///
    /// 0 while counting in: the pills leave and he settles back to exactly
    /// where the sit draws him, so the hand-off has no jump.
    private func ottoLift(in size: CGSize) -> CGFloat {
        guard countdown == nil else { return 0 }
        let pillsTop = size.height - Self.controlsBottom - controlsHeight
        let need = SitLayout.cushionBottom(in: size) + 6 - pillsTop
        let bubbleTop = SitLayout.ottoTop(in: size) - 8 - 84
        let tapeBottom = Self.lengthY(in: size, lift: 0) + pickerHeight / 2
        let room = 2 * (bubbleTop - tapeBottom - 10)
        return max(0, min(need, room))
    }

    /// Short phones (the SE) get the one-line pills: Home's card size costs
    /// room those screens do not have.
    private static func compact(in size: CGSize) -> Bool { size.height < 700 }

    /// The switch, or the sentence, depending on whether the shortcuts that
    /// make a switch possible can exist on this build. See `FocusShortcut`:
    /// no app can turn on Do Not Disturb, and a switch that cannot work must
    /// not be drawn. Until the switch has been set up, a tap opens the setup
    /// sheet rather than running a shortcut that is not there.
    @ViewBuilder
    private func silenceControl(ink: Color, compact: Bool) -> some View {
        if FocusShortcut.isConfigured {
            Button {
                Task {
                    guard focus.installed else { showFocusSetup = true; return }
                    await focus.requestStatusAccess()
                    if focus.silenced { await focus.restoreIfOurs() }
                    else { await focus.silence() }
                }
            } label: {
                SitPill(glyph: "\u{263E}",
                        label: focus.silenced ? "Notifications off" : "Silence notifications",
                        subtitle: compact ? nil
                                  : focus.silenced ? "Do Not Disturb is on for this sit"
                                                   : "Turns on Do Not Disturb while you sit",
                        tint: focus.silenced ? AppColor.calmAccent : AppColor.textPrimary,
                        compact: compact) {
                    Toggle("", isOn: .constant(focus.silenced))
                        .labelsHidden()
                        .tint(AppColor.calmAccent)
                        .allowsHitTesting(false)
                        .scaleEffect(0.92)
                        .frame(width: 46)
                }
            }
            .buttonStyle(.plain)
        } else {
            Text("Turn on Do Not Disturb first, from Control Center.")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    /// Cancelling with 808's own silence still on would leave the phone quiet
    /// for a sit that never happened.
    private func cancel() {
        Task {
            await focus.restoreIfOurs()
            dismiss()
        }
    }

    // MARK: - The two states

    private func greeting(day: DayLight, in size: CGSize, lift: CGFloat) -> some View {
        // Pinned just above his head, wherever `ottoLift` has put it.
        let speaks = SitLayout.ottoTop(in: size) - 8 - lift
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            OttoSpeech(text: countdown == nil
                            ? "Ready when you are. Start any YouTube or Spotify audio first."
                            : "Get comfortable.",
                       tail: .bottom, size: 17,
                       ink: day.ink, stroke: day.ink.opacity(0.38),
                       fill: AppColor.backgroundPrimary.opacity(0.72),
                       speaking: .constant(false))
        }
        .frame(width: min(size.width - 56, 320), height: max(120, speaks))
        .position(x: size.width / 2, y: max(120, speaks) / 2)
    }

    /// He asks the question, so the list needs no title. The point aims left
    /// at his face, the same tail the onboarding questions use.
    private func asking(day: DayLight, in size: CGSize) -> some View {
        OttoSpeech(text: "What are we listening to?",
                   tail: .leading, size: 15,
                   ink: day.ink, stroke: day.ink.opacity(0.38),
                   fill: AppColor.backgroundPrimary.opacity(0.72),
                   speaking: .constant(false))
            .frame(maxWidth: size.width - 118, alignment: .leading)
            .position(x: 104 + (size.width - 118) / 2, y: 122)
    }

    private func readyControls(day: DayLight, compact: Bool) -> some View {
        let sound = SoundCatalog.title(for: soundID.isEmpty ? nil : soundID) ?? "Silence"
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button { choosingSound = true } label: {
                    SitPill(glyph: "\u{266A}", label: "Sound",
                            subtitle: compact ? nil : sound, compact: compact) {
                        HStack(spacing: 4) {
                            // One line on a short phone, so the choice moves
                            // to the right, where it was before the pills grew.
                            if compact {
                                Text(sound)
                                    .font(AppFont.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Text("\u{203A}")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                silenceControl(ink: day.ink, compact: compact)

                Button("Begin", action: begin)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
            // Its height, not its position: the slide in and out moves the
            // block, and Otto must not ride along with the animation.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, Self.controlsBottom)
    }

    /// "Open · Silence ›" — exactly what happens if you just tap Begin.
    private var defaultsLine: String {
        let sound = SoundCatalog.title(for: soundID.isEmpty ? nil : soundID) ?? "Silence"
        return "Open · \(sound)  ›"
    }

    /// Five seconds to put the phone down and sit (Aziz, 2026-09-22,
    /// `mockups/ready-countdown.html`, direction A). **Nothing new appears;
    /// things leave.** The pills slide down into the meadow, the tape goes,
    /// and the clock counts 5 to 1 in its own place and face while Otto says
    /// "Get comfortable." It used to wash the whole valley out to cream and
    /// put a brown number on it: the least 808-looking screen in the app, at
    /// the moment somebody is about to close their eyes.
    private func countingIn(_ n: Int, day: DayLight) -> some View {
        VStack(spacing: 4) {
            Text("\(max(n, 1))")
                .font(DisplayFont.display(60, .heavy))
                .monospacedDigit()
                .foregroundStyle(day.ink)
                .contentTransition(.numericText(countsDown: true))
                .frame(minWidth: 180)
            Text("starting in")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(day.inkSoft)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Starting in \(max(n, 1))")
    }

    /// Where Begin was.
    private var countdownCancel: some View {
        VStack {
            Spacer()
            Button("Cancel", action: cancelCountdown)
                .font(DisplayFont.display(15, .bold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
                .padding(.bottom, 40)
        }
    }

    private func begin() {
        countdownTask?.cancel()
        let timed = lengthMinutes != nil
        countdownTask = Task { @MainActor in
            // A timed sit ends with a notification, so this is the one moment
            // asking for it is about something. Asked BEFORE the countdown, so
            // the dialog never lands on somebody already settling in.
            if timed { await SessionEndNotice.requestPermissionIfNeeded() }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { countdown = 5 }
            while let n = countdown, n > 0 {
                // A cancelled sleep THROWS and `try?` swallows it, so without
                // this guard cancelling would fall straight through and start
                // the session anyway. Same trap that once killed guided audio
                // a second into a session.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.25)) { countdown = n - 1 }
            }
            guard !Task.isCancelled else { return }
            // Zero: he settles into sitting, then the sit takes over.
            settling = true
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { settling = false; return }
            startNow()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        settling = false
        withAnimation(.easeOut(duration: 0.2)) { countdown = nil }
    }

    private func startNow() {
        let id = soundID.isEmpty ? nil : soundID
        let planned = lengthMinutes.map { $0 * 60 }
        // Remembered for next time. Settings shows it as the default length.
        preferences.first?.defaultDurationSec = planned
        coordinator.begin(mode: SoundCatalog.mode(for: id),
                          trackID: nil,
                          plannedDurationSec: planned,
                          hapticsEnabled: preferences.first?.hapticsEnabled ?? true,
                          soundID: id)
        dismiss()
    }
}

/// One control on the meadow: a glyph in a roundel, a title with an optional
/// line under it, and whatever the row owns on the right. Cream rather than
/// clear, because the meadow underneath is a mid-tone green with flowers in
/// it and text has to survive that.
///
/// **Sized to Home's cards** (Melvin, 2026-09-23: "we want the buttons
/// 'sound' and 'silence notifications' to be a bit bigger, like closer to
/// the size of the banners in the home screen"). It was one compact line,
/// barely bigger than its own text — the material was right, the scale was
/// not, next to everything else 808 shows a wrist-free session.
/// `SessionSetupView.ottoLift` is the room this made for itself, and
/// `compact` is the one-line size for phones with no room to make.
struct SitPill<Trailing: View>: View {
    let glyph: String
    let label: String
    var subtitle: String? = nil
    var tint: Color = AppColor.textPrimary
    var compact = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: compact ? 12 : 14) {
            Text(glyph)
                .font(.system(size: compact ? 16 : 19))
                .foregroundStyle(tint)
                .frame(width: compact ? 32 : 42, height: compact ? 32 : 42)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DisplayFont.display(16.5, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 10 : 15)
        .background(AppColor.backgroundPrimary.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
}

/// The one-time add.
///
/// Two taps rather than the four-step app automation an earlier draft asked
/// for: a shortcut published to a signed iCloud link installs from the link
/// itself, with no Allow Untrusted Shortcuts detour. The sheet never appears
/// again afterwards.
///
/// **One link per tap.** Shortcuts takes the screen to show its Add button,
/// and 808 is in the background until the person comes back, so opening the
/// second link straight after the first (the first fix for "shortcut not
/// found") would be refused. The button walks the two in turn instead.
///
/// **Until the links exist** (DEBUG only; Release does not draw the switch),
/// the sheet says how to make the two by hand, opens the Shortcuts editor,
/// and takes "I made both" for an answer. That is also exactly how the links
/// get made, so testing the switch and publishing it are the same errand.
struct FocusSetupSheet: View {
    @ObservedObject private var focus = FocusShortcut.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// How many of the two links have been handed to Shortcuts.
    @State private var added = 0

    private var byHand: Bool { !FocusShortcut.hasInstallLinks }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One-time setup")
                .font(DisplayFont.display(22, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text(byHand
                 ? "Apple only lets Shortcuts switch Do Not Disturb. Make these two in the Shortcuts app, named exactly like this."
                 : "Apple only lets Shortcuts switch Do Not Disturb. Add our two once and this button works from then on.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                if byHand {
                    step(1, "**808 Silence**: Set Focus, Do Not Disturb, Turn On.")
                    step(2, "**808 Restore**: Set Focus, Do Not Disturb, Turn Off.")
                    step(3, "Come back here and tap I made both.")
                } else {
                    step(1, "Tap Add 808 Silence, then Add Shortcut in Shortcuts.", done: added >= 1)
                    step(2, "Come back and do the same for 808 Restore.", done: added >= 2)
                    step(3, "That's it. The switch works from then on.")
                }
            }
            .padding(.top, 18)

            Spacer()

            if byHand {
                Button("I made both") {
                    focus.markInstalled()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://create-shortcut") { openURL(url) }
                }
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            } else {
                Button(added == 0 ? "Add 808 Silence" : "Add 808 Restore") {
                    Task { await addNext() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button("Not now") { dismiss() }
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .padding(AppMetrics.screenPadding)
        .screenBackground()
        .presentationDetents([.height(byHand ? 360 : 330)])
    }

    /// Opens the next link. Only a link that actually opened counts, and the
    /// switch counts as set up only once both have.
    private func addNext() async {
        let link = added == 0 ? FocusShortcut.silenceInstallURL : FocusShortcut.restoreInstallURL
        guard await focus.openInstall(link) else { return }
        added += 1
        if added >= 2 {
            focus.markInstalled()
            dismiss()
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey, done: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? AppColor.calmAccent : AppColor.trace)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.accentGoldText)
                }
            }
            .frame(width: 20, height: 20)
            Text(text)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The sound list, as pills floating on the valley.
///
/// It is not a sheet and has no chrome of its own: the scene behind it is
/// the same one the Ready screen is showing, and this only changes what sits
/// on the meadow. **The list fades at both ends** rather than stopping on a
/// hard line, so it reads as part of the scene instead of a panel over it.
struct SoundChoiceList: View {
    @Binding var soundID: String
    /// Where the list starts, under Otto's corner perch.
    var top: CGFloat
    /// Called when Done is tapped. **Never the environment's `dismiss`**:
    /// this view carries no `.sheet`/`.fullScreenCover` of its own, so that
    /// would resolve to whatever presented the Ready screen itself — a
    /// fullScreenCover from Home — and Done would close the entire Ready
    /// screen instead of just leaving the sound list. That was the bug
    /// behind "choosing a sound sends you to the home page": picking a
    /// sound and tapping Done ended the whole session-setup flow. `onDone`
    /// is owned by `SessionSetupView`, which sets `choosingSound = false`,
    /// exactly like its own Back button already does.
    var onDone: () -> Void

    @StateObject private var tone = ToneEngine()

    /// Brainwave presets, deepest first (delta 2.5 → theta 6 → alpha 8).
    private var brainwave: [FrequencyPreset] {
        FrequencyCatalog.all.filter { $0.hasBeat }
            .sorted { ($0.beatHz ?? 0) < ($1.beatHz ?? 0) }
    }

    /// Pure tones, low to high (432 → 963).
    private var tones: [FrequencyPreset] {
        FrequencyCatalog.all.filter { !$0.hasBeat }
            .sorted { $0.carrierHz < $1.carrierHz }
    }

    private let ink = DayLight.at(0).ink

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    ForEach(GuidedCatalog.all) { guidedPill($0) }
                    pill(id: "", title: "Silence",
                         subtitle: "Just you, or bring your own audio",
                         glyph: "speaker.slash", tint: AppColor.calmAccent, badge: "DEFAULT")
                    label("Nature")
                    ForEach(NatureCatalog.all) {
                        pill(id: $0.id, title: $0.title, subtitle: $0.subtitle,
                             glyph: Self.natureGlyph($0.id), tint: AppColor.calmAccent)
                    }
                    label("Brainwave · deepest first")
                    ForEach(brainwave) {
                        pill(id: $0.id, title: $0.title, subtitle: $0.subtitle,
                             glyph: Self.waveGlyph($0.id), tint: AppColor.accentGoldText)
                    }
                    label("Tones · low to high")
                    ForEach(tones) {
                        pill(id: $0.id, title: $0.title, subtitle: $0.subtitle,
                             hz: String(Int($0.carrierHz)))
                    }
                }
                .padding(.horizontal, 16)
                // Clear of the mask's top fade, or the first pill arrives
                // half dissolved and reads as a rendering fault.
                .padding(.top, 24)
                .padding(.bottom, 96)
            }
            // Soft at both ends, so the scene keeps going behind it.
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.045),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 0.97)
            ], startPoint: .top, endPoint: .bottom))
        }
        .padding(.top, top)
        .overlay(alignment: .bottom) {
            Button("Done") { tone.stop(reason: "sound chosen"); onDone() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
        }
        .onDisappear { tone.stop(reason: "left the sound list") }
    }

    // MARK: - Pieces

    /// A section label, in the same cream as the pills.
    ///
    /// It was bare ink on the scene, which reads on the sky and disappears
    /// into the meadow's flowers the moment the list scrolls. A label that
    /// is legible in one part of a scroll and not another is not a label, so
    /// it carries the smallest possible piece of the pills' own material.
    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .kerning(1.0)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AppColor.backgroundPrimary.opacity(0.88), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .padding(.top, 12)
            .padding(.bottom, 1)
    }

    @ViewBuilder
    private func pill(id: String, title: String, subtitle: String,
                      glyph: String? = nil, tint: Color = AppColor.calmAccent,
                      hz: String? = nil, badge: String? = nil) -> some View {
        let chosen = soundID == id
        let playing = tone.playingID == id && !id.isEmpty
        Button { choose(id) } label: {
            HStack(spacing: 10) {
                if let hz {
                    Text(hz)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.accentGoldText)
                        .frame(width: 34, alignment: .leading)
                } else {
                    Image(systemName: glyph ?? "music.note")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DisplayFont.display(14.5))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if playing { SoundBars() }
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .kerning(0.6)
                        .foregroundStyle(AppColor.textOnAccent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppColor.accentGold, in: Capsule())
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(chosen ? Color(white: 1).opacity(0.99)
                               : AppColor.backgroundPrimary.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(chosen ? AppColor.accentGold : .clear, lineWidth: 2))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func guidedPill(_ preset: GuidedPreset) -> some View {
        let chosen = soundID == preset.id
        return Button { choose(preset.id) } label: {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.textOnAccent)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: [Color(red: 0.961, green: 0.851, blue: 0.651),
                                                        Color(red: 0.914, green: 0.725, blue: 0.475)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title)
                        .font(DisplayFont.display(14.5))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(preset.subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if tone.playingID == preset.id { SoundBars() }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(LinearGradient(colors: [Color(red: 1, green: 0.965, blue: 0.894),
                                                Color(red: 0.992, green: 0.937, blue: 0.847)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(chosen ? AppColor.accentGold : AppColor.accentGold.opacity(0.55),
                        lineWidth: chosen ? 2 : 1))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Tapping previews AND selects, which is what the rows did. There is no
    /// separate play button: twelve identical grey circles were the loudest
    /// thing on the old screen and every one did this.
    private func choose(_ id: String) {
        soundID = id
        if id.isEmpty { tone.stop(reason: "silence chosen"); return }
        if tone.playingID == id { tone.stop(reason: "preview stopped"); return }
        if let p = FrequencyCatalog.preset(id: id) { tone.play(p, method: .isochronic) }
        else if let np = NatureCatalog.preset(id: id) { tone.playNature(np) }
        else if let gp = GuidedCatalog.preset(id: id) { tone.playGuided(gp) }
    }

    /// Symbols, not emoji. Emoji arrive in full colour from a different
    /// palette and cannot take the sage and amber the rest of the sheet uses.
    private static func natureGlyph(_ id: String) -> String {
        switch id {
        case "rain":     return "cloud.rain.fill"
        case "ocean":    return "water.waves"
        case "forest":   return "tree.fill"
        case "campfire": return "flame.fill"
        default:         return "music.note"
        }
    }

    private static func waveGlyph(_ id: String) -> String {
        switch id {
        case "delta": return "moon.fill"
        case "theta": return "circle.hexagongrid.fill"
        case "alpha": return "sun.max.fill"
        default:      return "music.note"
        }
    }
}

/// Three bars, to say which sound is playing. It replaces twelve play
/// buttons: the control they offered is the pill itself, and the only thing
/// they reported that the pill could not is which one is sounding.
struct SoundBars: View {
    @State private var up = false
    private let heights: [CGFloat] = [6, 13, 9]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                Capsule()
                    .fill(AppColor.calmAccent)
                    .frame(width: 3, height: up ? h : h * 0.45)
                    .animation(.easeInOut(duration: 0.42).repeatForever()
                        .delay(Double(i) * 0.12), value: up)
            }
        }
        .frame(height: 13)
        .onAppear { up = true }
    }
}
