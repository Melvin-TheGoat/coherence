import SwiftUI
import WatchConnectivity
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
    @EnvironmentObject private var community: CommunityModel
    @Environment(\.dismiss) private var dismiss
    /// Oldest first, as `ShopTab` and `OttoAuraFigure` read it: there can be
    /// two rows (a bootstrap and a synced one), and `.first` of an unsorted
    /// query is whichever the store hands back.
    @Query(sort: \Preferences.createdAt) private var preferences: [Preferences]

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
    /// The sit is running HERE, over this screen, rather than in a cover of
    /// its own (Melvin, 2026-09-27: "the screen swipes down and then comes
    /// up"). Begin used to dismiss this cover, which slid down, and then the
    /// sit's cover slid up. Both screens are the same valley, so the sit
    /// fades in over it instead, and this screen closes when the sit ends.
    @State private var hosting = false

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
    #if DEBUG
    @State private var choosingSound = ProcessInfo.processInfo.environment["PREVIEW_SETUP"] == "sound"
    #else
    @State private var choosingSound = false
    #endif

    /// How this sit is kept (Melvin, 2026-09-27): on the phone, unmeasured,
    /// or measured by the Watch. Remembered, like the sound. The third card,
    /// recording one done elsewhere, is not a way to run a sit, so it is not
    /// stored here: it opens `logging`.
    @AppStorage("ready.sitKind") private var kindRaw = SitKind.unmeasured.rawValue
    private var kind: SitKind { SitKind(rawValue: kindRaw) ?? .unmeasured }
    /// Whether an Apple Watch is connected (`WatchLink`). The Watch measures
    /// only when it is chosen AND connected: a Watch that is not connected
    /// today never takes a sit, whatever was chosen.
    @ObservedObject private var watchLink = WatchLink.shared
    @State private var showWatchSetup = false
    /// Whether Otto's line is the Watch one or the YouTube one. They take
    /// turns, one per opening (`ready.lineTurn`), so neither goes missing
    /// for long.
    @State private var mentionsWatch = false
    @State private var lineTurnTaken = false
    /// What this sit will actually be: the choice, unless it asks for a Watch
    /// that is not connected right now.
    private var effectiveKind: SitKind {
        kind == .watch && !watchLink.connected ? .unmeasured : kind
    }
    /// The three cards, a state of this screen like the sound list.
    @State private var choosingKind = false
    /// Recording a sit done elsewhere: how long, and when it ended.
    @State private var logging = false
    @State private var logMinutes = 10
    @State private var logEnded = Date()
    /// The recorded session, open on its page for a photo and notes.
    @State private var loggedID: LoggedSession?
    @Environment(\.modelContext) private var context
    private var aside: Bool { choosingSound || choosingKind || logging }

    /// The two heights `ottoLift` is worked out from, measured as laid out.
    /// Seeded with what an iPhone 17 Pro measures, so the first frame is
    /// already right there and nothing visibly settles on the others.
    @State private var controlsHeight: CGFloat = 221
    @State private var pickerHeight: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let day = DayLight.now
            let lift = ottoLift(in: geo.size)
            ZStack {
                // ONE scene, for both states. Never rebuilt, never replaced:
                // it owns the Rive rig, and swapping it would restart him.
                ValleyScene(progress: 0, pose: settling ? .meditating : .greeting, clock: true,
                            ottoInCorner: aside, ottoLift: lift)

                if choosingKind {
                    asking("How are we meditating?", day: day, in: geo.size)
                    // Tall cards, in the middle of the screen (Melvin, 2026-09-27:
                    // "a lot bigger/taller and centered ... they are too high").
                    let cardHeight = min(340, geo.size.height * 0.38)
                    SitKindCards(kind: kind, watchPaired: Self.watchPaired, height: cardHeight) { picked in
                        switch picked {
                        case .record:
                            logEnded = Date()
                            choosingKind = false
                            logging = true
                        case .unmeasured, .watch:
                            kindRaw = picked.rawValue
                            choosingKind = false
                        }
                    }
                    .position(x: geo.size.width / 2,
                              y: max(geo.size.height / 2, Self.listTop + cardHeight / 2))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if logging {
                    asking("How long did you meditate?", day: day, in: geo.size)
                    LogSitCard(minutes: $logMinutes, ended: $logEnded, save: saveLog)
                        .padding(.top, Self.listTop)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if choosingSound {
                    asking("What are we listening to?", day: day, in: geo.size)
                    SoundChoiceList(soundID: $soundID, top: Self.listTop) {
                        choosingSound = false
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    greeting(day: day, in: geo.size, lift: lift)
                    if let countdown {
                        countingIn(countdown, day: day)
                            .position(x: geo.size.width / 2, y: Self.lengthY(in: geo.size, lift: lift, hat: hatRise(in: geo.size)))
                            .transition(.opacity)
                        countdownCancel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        SessionLengthPicker(minutes: $lengthMinutes, ink: day.ink, inkSoft: day.inkSoft)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pickerHeight = $0 }
                            .position(x: geo.size.width / 2, y: Self.lengthY(in: geo.size, lift: lift, hat: hatRise(in: geo.size)))
                            .transition(.opacity)
                        readyControls(day: day, compact: Self.compact(in: geo.size))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: choosingSound)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: choosingKind)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: logging)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: countdown == nil)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            // Counting in, the one way out is the Cancel pill where Begin
            // was; two Cancels on one screen is one too many.
            if countdown == nil, !hosting {
                Button(aside ? "Back" : "Cancel") {
                    if logging { logging = false; choosingKind = true }
                    else if choosingKind { choosingKind = false }
                    else if choosingSound { choosingSound = false }
                    else { cancel() }
                }
                .font(AppFont.callout.weight(.semibold))
                .onValley(soft: true)
                .padding(.horizontal, 20).padding(.top, 14)
            }
        }
        .overlay {
            if hosting, let session = coordinator.active {
                SessionActiveView(startedAt: session.startedAt,
                                  plannedDurationSec: session.plannedDurationSec,
                                  planChip: session.planChip) {
                    coordinator.endActiveSession()
                }
                .transition(.opacity)
            }
        }
        // The sit is over: close, straight to Home and the glow.
        .onChange(of: coordinator.active?.id) { _, id in
            if hosting, id == nil { dismiss() }
        }
        .sheet(isPresented: $showFocusSetup) { FocusSetupSheet() }
        // A shortcut answered x-error, which means it is not on this phone:
        // the setup steps come back, quietly (App Review pass, 2026-09-29).
        // `initial`: the flag is often raised while this screen is closed
        // (a restore failing as the sit ends), and must still open the steps
        // the next time the Ready screen appears (2026-09-30).
        .onChange(of: focus.setupNeeded, initial: true) { _, needed in
            guard needed else { return }
            focus.setupShown()
            showFocusSetup = true
        }
        .sheet(isPresented: $showWatchSetup) { WatchConnectSheet() }
        // The recorded sit's own page, for the photo or video that shows it
        // happened, and notes. Closing it closes this screen too.
        // A recorded sit is the end of this screen, so 808's own Do Not
        // Disturb (the Silence switch may have been on) goes back off here;
        // no sit of the coordinator's will ever end and restore it.
        .fullScreenCover(item: $loggedID, onDismiss: {
            Task { await FocusShortcut.shared.restoreIfOurs() }
            dismiss()
        }) { logged in
            SaveSessionView(sessionID: logged.id, mode: .edit) { loggedID = nil }
        }
        // NOT a permission prompt on appear. Somebody who opened this screen
        // is about to close their eyes, and a system dialog is the single
        // worst thing to put in front of them. (The Silence switch no longer
        // asks for anything at all: the Focus status read is gone, App Review
        // pass, 2026-09-29.)
        .onAppear {
            if !lineTurnTaken {
                lineTurnTaken = true
                let d = UserDefaults.standard
                let turn = d.integer(forKey: "ready.lineTurn") + 1
                d.set(turn, forKey: "ready.lineTurn")
                mentionsWatch = turn % 2 == 0
            }
            watchLink.refresh()
            if !lengthLoaded {
                lengthLoaded = true
                lengthMinutes = SessionLength.clamped(preferences.first?.defaultDurationSec.map { $0 / 60 })
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { watchLink.refresh() }
        }
        // Closed mid-count (swiped away, or dismissed from above): the count
        // must not run on and start a sit behind a screen that is gone.
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
        }
    }

    /// The timer's centre: the middle of the sky between the island and
    /// Otto's line, which is pinned to the top of his head and runs about 84pt
    /// tall. The same band the sit screen centres its headline in. When he is
    /// lifted the band is shorter, so the timer rises half as far as he does.
    private static func lengthY(in size: CGSize, lift: CGFloat, hat: CGFloat = 0) -> CGFloat {
        let bubbleTop = SitLayout.ottoTop(in: size) - 8 - 84 - lift - hat
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
        let hat = hatRise(in: size)
        let bubbleTop = SitLayout.ottoTop(in: size) - 8 - 84 - hat
        let tapeBottom = Self.lengthY(in: size, lift: 0, hat: hat) + pickerHeight / 2
        let room = 2 * (bubbleTop - tapeBottom - 10)
        return max(0, min(need, room))
    }

    /// How far his hat stands above his head, which his bubble (and the
    /// timer over it) rise by.
    private func hatRise(in size: CGSize) -> CGFloat {
        OttoRiveView.hatRise(OttoAuraFigure.previewHat ?? preferences.first?.wornHatIDValue,
                             size: SitLayout.ottoHeight(in: size))
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
                    if focus.silenced { await focus.turnOff() }
                    else { await focus.silence() }
                }
            } label: {
                SitPill(art: "sit-silence",
                        label: focus.silenced ? "Notifications off" : "Silence notifications",
                        subtitle: compact ? nil
                                  : focus.silenced ? "Do Not Disturb is on"
                                                   : "Do Not Disturb while you sit",
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
                .onValley(soft: true)
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
        let speaks = SitLayout.ottoTop(in: size) - 8 - lift - hatRise(in: size)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            OttoSpeech(text: countdown == nil ? readyLine : "Get comfortable.",
                       tail: .bottom, size: 17,
                       ink: ValleyBubble.now.ink, stroke: ValleyBubble.now.stroke,
                       fill: ValleyBubble.now.fill, alignment: .center,
                       speaking: .constant(false))
        }
        .frame(width: min(size.width - 56, 320), height: max(120, speaks))
        .position(x: size.width / 2, y: max(120, speaks) / 2)
    }

    /// What he says before Begin (Aziz, 2026-09-29): sometimes the YouTube
    /// line, sometimes the Apple Watch, alternating each time the screen
    /// opens. The Watch line only with a Watch paired.
    private var readyLine: String {
        // No app names (App Review pass, 2026-09-30): naming YouTube and
        // Spotify reads as an integration we don't have, and YouTube keeps
        // playing in the background only with Premium.
        let youtube = "Ready when you are. Start your own audio first if you like."
        // While Block holds apps, the one thing worth saying before Begin is
        // what opens them (Aziz, 2026-09-29).
        if FeatureFlags.block, !BlockController.shared.holding().isEmpty {
            return "Ready when you are. \(Blocker.sessionMinutes) minutes opens your apps."
        }
        guard mentionsWatch else { return youtube }
        switch watchLink.status {
        case .noWatch:
            return youtube
        case .notInstalled:
            return "Ready when you are. Put 808 on your Watch to see how you settle."
        case .connected:
            return kind == .watch
                ? "Ready when you are. Your Apple Watch will read how you settle."
                : "Ready when you are. Switch on your Watch below to see how you settle."
        }
    }

    /// He asks the question, so the list needs no title. The point aims left
    /// at his face, the same tail the onboarding questions use.
    private func asking(_ line: String, day: DayLight, in size: CGSize) -> some View {
        OttoSpeech(text: line,
                   tail: .leading, size: 15,
                   ink: ValleyBubble.now.ink, stroke: ValleyBubble.now.stroke,
                   fill: ValleyBubble.now.fill, alignment: .center,
                   speaking: .constant(false))
            .frame(maxWidth: size.width - 118, alignment: .leading)
            .position(x: 104 + (size.width - 118) / 2, y: 122)
    }

    private func readyControls(day: DayLight, compact: Bool) -> some View {
        let sound = SoundCatalog.title(for: soundID.isEmpty ? nil : soundID) ?? "Silence"
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                // Side by side, half width each, so adding the choice of how
                // to sit did not make the controls taller and push them over
                // Otto's lap (the first build stacked three pills).
                HStack(spacing: 10) {
                    Button { choosingKind = true } label: {
                        SitPill(art: effectiveKind.art, label: effectiveKind.pillTitle,
                                subtitle: compact ? nil : effectiveKind.line, compact: compact, half: true) {
                            chevron
                        }
                    }
                    .buttonStyle(.plain)
                    Button { choosingSound = true } label: {
                        SitPill(art: "sit-sound", label: "Sound",
                                subtitle: compact ? nil : sound, compact: compact, half: true) {
                            chevron
                        }
                    }
                    .buttonStyle(.plain)
                }

                silenceControl(ink: day.ink, compact: compact)

                watchControl

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

    /// Measure with the Apple Watch, yes or no (Aziz, 2026-09-28): a small
    /// switch under Silence notifications, deliberately smaller than the
    /// pills, because the same choice inside the Meditate card is easy to
    /// miss. It is `kindRaw`, the card's own value, so they cannot disagree.
    /// Nothing at all without a paired Watch; "Not connected" and Set up when
    /// the Watch is paired but 808 is not on it.
    @ViewBuilder
    private var watchControl: some View {
        switch watchLink.status {
        case .noWatch:
            EmptyView()
        case .connected:
            Button {
                let on = kind != .watch
                withAnimation(.snappy(duration: 0.2)) {
                    kindRaw = (on ? SitKind.watch : .unmeasured).rawValue
                }
                Analytics.track(.watchSwitch(on: on, source: "ready"))
            } label: {
                watchPill {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .labelStyle(WatchCheckLabelStyle())
                        .fixedSize()
                    Toggle("", isOn: .constant(kind == .watch))
                        .labelsHidden()
                        .tint(OnboardingGreen.fill)
                        .allowsHitTesting(false)
                        .scaleEffect(0.72)
                        .frame(width: 38, height: 24)
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Measure with Apple Watch")
            .accessibilityValue(kind == .watch ? "On" : "Off")
        case .notInstalled:
            Button {
                Analytics.track(.watchSetupOpened(source: "ready"))
                showWatchSetup = true
            } label: {
                watchPill {
                    Text("Not connected")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textSecondary)
                    Text("Set up")
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColor.skyDeep, in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func watchPill<Trailing: View>(@ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "applewatch")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Apple Watch")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize()
            trailing()
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 36)
        .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var chevron: some View {
        Text("\u{203A}")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppColor.textSecondary)
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
                .onValley(day)
                .contentTransition(.numericText(countsDown: true))
                .frame(minWidth: 180)
            Text("starting in")
                .font(AppFont.caption.weight(.semibold))
                .onValley(soft: true, day)
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
        hosting = true
        let haptics = preferences.first?.hapticsEnabled ?? true
        withAnimation(.easeInOut(duration: 0.5)) {
            if WatchDefault.measures(chosen: kind == .watch, connected: watchLink.connected) {
                coordinator.beginMeasured(mode: SoundCatalog.mode(for: id),
                                          plannedDurationSec: planned,
                                          hapticsEnabled: haptics, soundID: id)
            } else {
                coordinator.begin(mode: SoundCatalog.mode(for: id),
                                  trackID: nil,
                                  plannedDurationSec: planned,
                                  hapticsEnabled: haptics,
                                  soundID: id)
            }
        }
        // A phone start runs in the same turn; if nothing began, close as
        // before rather than leave the Ready screen stuck.
        if coordinator.active == nil { hosting = false; dismiss() }
    }
}

extension SessionSetupView {
    /// Whether this phone has a Watch to measure with. Read from the session
    /// WatchConnectivity already activated at launch; nothing is asked.
    static var watchPaired: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired
    }

    /// Writes a sit done without the app and opens its page.
    fileprivate func saveLog() {
        let seconds = logMinutes * 60
        let id = UUID()
        guard SessionStore.persistPhoneSession(id: id,
                                               startedAt: logEnded.addingTimeInterval(TimeInterval(-seconds)),
                                               mode: "silence", durationSec: seconds,
                                               source: "logged", in: context) != nil else { return }
        Analytics.track(.sessionLogged)
        loggedID = LoggedSession(id: id)
        // Logged sits never go through `SessionCoordinator`, so they miss its
        // `onSessionSaved` hook — republish how often I meditate here instead.
        Task { await community.syncPracticeStats(force: true) }
    }
}

struct LoggedSession: Identifiable { let id: UUID }

/// The three ways to keep a sit.
enum SitKind: String, CaseIterable {
    case unmeasured, watch, record

    var title: String {
        switch self {
        case .unmeasured: return "Meditate"
        case .watch: return "With Apple Watch"
        case .record: return "Record one"
        }
    }

    /// On the Ready screen's half-width pill, where "With Apple Watch" no
    /// longer fits once the pills grew (2026-09-27).
    var pillTitle: String {
        self == .watch ? "Apple Watch" : title
    }

    /// Under the title on the Ready screen's pill.
    var line: String {
        switch self {
        case .unmeasured: return "Timer only"
        case .watch: return "Measured"
        case .record: return "By hand"
        }
    }

    var card: String {
        switch self {
        case .unmeasured: return "Just you and a timer. Nothing is measured."
        case .watch: return "Your Watch reads your heart, stillness and breath."
        case .record: return "Meditated somewhere else? Add it here."
        }
    }

    /// Its object on a stone (`SitIcons/`, Melvin's sheet of 2026-09-27,
    /// `mockups/tabbar-icons/sit-icons-sheet.webp`), on the Ready screen's
    /// pill and on its tall card. They replaced SF Symbols and Unicode
    /// glyphs, which Melvin found "AI/generic".
    var art: String {
        switch self {
        case .unmeasured: return "sit-meditate"
        case .watch: return "sit-watch"
        case .record: return "sit-record"
        }
    }
}

/// Three tall cards side by side (Melvin, 2026-09-27: "three large vertical
/// rectangle buttons, with an icon in the upper middle, the title below it,
/// and a short description"), on the valley like the sound list.
struct SitKindCards: View {
    let kind: SitKind
    let watchPaired: Bool
    var height: CGFloat = 236
    let pick: (SitKind) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(SitKind.allCases, id: \.self) { k in
                let chosen = k == kind
                let dim = k == .watch && !watchPaired
                Button { pick(k) } label: {
                    VStack(spacing: 12) {
                        SitArt(name: k.art, size: 64)
                        Text(k.title)
                            .font(DisplayFont.display(17, .heavy))
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(dim ? "Needs a paired Apple Watch." : k.card)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(AppColor.backgroundPrimary.opacity(0.94),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AppColor.accentGold, lineWidth: chosen ? 2.5 : 0))
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
                    .opacity(dim ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(dim)
                .accessibilityLabel("\(k.title). \(k.card)")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Recording a sit done without the app: how long, when it ended, and a
/// word that a photo or video comes next and helps.
struct LogSitCard: View {
    @Binding var minutes: Int
    @Binding var ended: Date
    let save: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(1...240, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
                .clipped()
                Divider().overlay(AppColor.hairline)
                DatePicker("Finished", selection: $ended, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .tint(AppColor.accentGoldText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .background(AppColor.backgroundPrimary.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 2)

            Text("Next you can add a photo or video of your session. It's optional, but it helps show it happened.")
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(AppColor.backgroundPrimary.opacity(0.9), in: Capsule())

            Button("Save", action: save)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 18)
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
    /// The object on its stone (`SitArt`), where a glyph in a tinted circle
    /// used to be.
    let art: String
    let label: String
    var subtitle: String? = nil
    var compact = false
    /// Half the width, beside another pill: a smaller roundel and less
    /// padding, so the words keep their room.
    var half = false
    @ViewBuilder var trailing: Trailing

    /// Bigger since 2026-09-27 (Melvin: "make these buttons in the
    /// meditating screen bigger"): roundel 32/42 to 40/48, labels 15/16.5 to
    /// 17/18.5, 3 more points above and below. The Ready screen measures the
    /// block and lifts Otto to clear it, so nothing else had to move. A short
    /// phone (`compact`) keeps the old sizes; it has no sky to give.
    var body: some View {
        // Much smaller since 2026-09-28 (Melvin: "make the icons much
        // smaller in the meditation screen, like the moon and timer"): the
        // words carry the pill, the object only marks it.
        let roundel: CGFloat = compact ? 24 : (half ? 28 : 32)
        HStack(spacing: compact ? (half ? 8 : 11) : (half ? 9 : 13)) {
            SitArt(name: art, size: roundel)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DisplayFont.display(compact ? (half ? 15 : 16.5) : (half ? 17 : 18.5), .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(compact ? AppFont.caption : .system(size: 13.5, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, half ? 13 : 16)
        .padding(.vertical, compact ? 10 : 18)
        .background(AppColor.backgroundPrimary.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
}

/// One of the Ready screen's objects on a stone, fitted into a square.
struct SitArt: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: name) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
    /// switch counts as set up only once both have. Opening is not proof they
    /// were added, so an x-error from either shortcut later takes this back
    /// and brings the steps up again (App Review pass, 2026-09-29).
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

/// A green check before "Connected".
struct WatchCheckLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.foregroundStyle(OnboardingGreen.fill)
            configuration.title.foregroundStyle(OnboardingGreen.shade)
        }
        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
    }
}
