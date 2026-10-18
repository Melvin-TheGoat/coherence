import SwiftUI

/// The Watch app, standing in the app's valley (2026-10-12, Aziz: "the UI is
/// current theme, and you should be able to set time limits and choose
/// audio from the apple watch"). Built to `mockups/watch-v2.html`.
///
/// The valley is the iPhone's own painting (`DayLight` and
/// `ValleyPainting.swift`, compiled into this target the way the home screen
/// widget compiles them), at the real hour, with Otto on his cushion at the
/// glow Home shows. Controls are the + screen's: sand pills for the length
/// and the sound, one gold Begin.
///
/// **No live biometrics anywhere**: evidence after, not during. **No
/// haptics**: the Watch plays none (CLAUDE.md), a timed session included;
/// the iPhone's bell and end notice mark the end when it is near.
struct WatchContentView: View {
    @EnvironmentObject private var manager: WatchSessionManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var picking: Choosing?

    enum Choosing: String, Identifiable {
        case length, sound
        var id: String { rawValue }
    }

    var body: some View {
        content
            .sheet(item: $picking) { which in
                switch which {
                case .length:
                    LengthPickerView(minutes: manager.lengthMinutes) { chosen in
                        manager.chooseLength(chosen)
                        picking = nil
                    }
                case .sound:
                    SoundPickerView(selectedID: $manager.soundID)
                }
            }
            #if DEBUG
            .onAppear {
                switch ProcessInfo.processInfo.environment["PREVIEW_WATCH_SCREEN"] {
                case "length": picking = .length
                case "sound": picking = .sound
                default: break
                }
            }
            #endif
            // Workouts gets turned on in the Health app on the iPhone while the
            // first-run screen waits here; notice it on the way back without a
            // tap (2026-09-30). Only while still locked out, so a session in
            // progress is never sent back to the first-run screen.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !manager.authorized {
                    manager.recheckAuthorization(explain: manager.authorizeHelp != nil)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !manager.authorized {
            authorizeScreen
        } else {
            switch manager.phase {
            case .idle:
                if manager.countdown != nil { AnyView(countdownScreen) }
                else { manager.phoneOnboarded ? AnyView(startScreen) : AnyView(setupScreen) }
            case .running: liveScreen
            case .sending: sendingScreen
            case .sent:    sentScreen
            }
        }
    }

    /// The sky at the real hour.
    private var nowHour: Double { WatchValley.quantize(DayLight.clockProgress()) }
    private var nowDay: DayLight { DayLight.at(nowHour) }

    // MARK: - First run

    /// Allow asks HealthKit. When Workouts was already declined (often on the
    /// iPhone during onboarding) HealthKit shows nothing, so the screen used
    /// to sit there as if Allow were broken (App Review, 2026-09-30). After
    /// an Allow that comes back without Workouts, the help replaces the intro
    /// line and the button becomes Try again, which asks again and re-reads
    /// the answer. Scrolls, because the help runs to four lines on a 41 mm
    /// Watch.
    private var authorizeScreen: some View {
        ZStack {
            WatchValley(hour: nowHour, stage: manager.ottoStage(), cushion: 0.46)
                .equatable()
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 8) {
                    Spacer(minLength: 96)
                    Text(manager.authorizeHelp ?? "808 measures with your heart rate and motion.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchPalette.sandInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(SandCard())
                    Button(manager.authorizeHelp == nil ? "Allow" : "Try again") {
                        // Asks again, not only re-reads (2026-09-30): once
                        // Workouts is decided HealthKit returns at once with
                        // no UI, so this is safe when denied.
                        Task { await manager.authorize() }
                    }
                    .buttonStyle(BeginButtonStyle())
                    // One message at a time: the help line, when there is
                    // one, already says what to do (2026-09-30).
                    if manager.authorizeHelp == nil, let msg = manager.statusMessage {
                        Text(msg)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .onSky(nowDay)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    // MARK: - Phone not set up yet

    /// The phone hasn't finished onboarding (or its user signed out), so a
    /// session started here would deliver into an app that can't receive it.
    /// Say what to do instead of offering a Begin that half-works.
    private var setupScreen: some View {
        ZStack {
            WatchValley(hour: nowHour, stage: manager.ottoStage(), cushion: 0.5)
                .equatable()
                .ignoresSafeArea()
            VStack(spacing: 4) {
                Spacer()
                Text("Set up 808 on your iPhone first.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchPalette.sandInk)
                Text("Finish the setup on your phone. This screen unlocks by itself.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchPalette.sandInkSoft)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(SandCard())
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Start

    private var startScreen: some View {
        ZStack {
            WatchValley(hour: nowHour, stage: manager.ottoStage(), cushion: 0.47)
                .equatable()
                .ignoresSafeArea()
            VStack(spacing: 7) {
                HStack {
                    Text("808")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2.4)
                        .onSky(nowDay)
                    Spacer()
                }
                Spacer(minLength: 0)
                // Surfaces a start refusal (no HR, not authorized) on the
                // screen the person is looking at. Three lines: the Workouts
                // help is one full sentence (2026-09-30).
                if let msg = manager.statusMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchPalette.sandInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(SandCard(radius: 10))
                }
                HStack(spacing: 6) {
                    ChoicePill(icon: "WatchIconLength",
                               title: manager.lengthMinutes.map { "\($0) min" } ?? "Open") {
                        picking = .length
                    }
                    ChoicePill(icon: "WatchIconSound",
                               title: SoundMenu.title(for: manager.soundID)) {
                        picking = .sound
                    }
                }
                Button("Begin") { manager.beginFromWatch() }
                    .buttonStyle(BeginButtonStyle())
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Countdown

    /// Five seconds to settle before the wrist starts measuring, matching the
    /// phone's countdown. A number, a line, a way out. No haptics.
    private var countdownScreen: some View {
        ZStack {
            WatchValley(hour: nowHour, stage: manager.ottoStage(), cushion: 0.8, sceneShare: 0.84)
                .equatable()
                .ignoresSafeArea()
            VStack(spacing: 4) {
                Text(manager.countdown.map(String.init) ?? "")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.15), value: manager.countdown)
                    .onSky(nowDay)
                Text("Get comfortable.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .onSky(nowDay)
                Spacer()
                Button("Cancel") { manager.cancelCountdown() }
                    .buttonStyle(SandButtonStyle())
            }
            // Into the bottom inset, so the button sits under Otto, not on him.
            .padding(.bottom, 6)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Live

    /// The iPhone's sit at Watch size: the sun runs from the real hour on to
    /// night over the session, and the ring hangs in the sky over Otto. A
    /// timed session draws its arc and counts down; an open one counts up
    /// with no arc, its sky moving over a nominal twenty minutes.
    private var liveScreen: some View {
        let planned = manager.params?.plannedDurationSec
        let elapsed = manager.elapsed
        let total = Double(planned ?? Self.openArcSec)
        let progress = min(1, Double(elapsed) / max(1, total))
        let start = DayLight.clockProgress(at: Date().addingTimeInterval(-Double(elapsed)))
        let hour = WatchValley.quantize(start + (1 - start) * progress)
        let day = DayLight.at(hour)
        let shown = planned.map { max(0, $0 - elapsed) } ?? elapsed

        return ZStack {
            WatchValley(hour: hour, stage: manager.ottoStage(), cushion: 0.8, sceneShare: 0.84)
                .equatable()
                .ignoresSafeArea()
            VStack(spacing: 4) {
                SitRing(progress: planned == nil ? nil : progress,
                        track: day.ringTrack,
                        time: Self.clock(shown),
                        label: planned == nil ? "open" : "left",
                        day: day)
                if let note = silentNote {
                    Text(note)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchPalette.sand)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.3)))
                }
                Spacer()
                Button("End") { manager.endByUser() }
                    .buttonStyle(SandButtonStyle())
            }
            // Into the bottom inset, so the button sits under Otto, not on him.
            .padding(.bottom, 6)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// An open session's sky reaches night after this long, as on the iPhone.
    static let openArcSec = 20 * 60

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// The honest one-liner when a wrist-started session wanted sound but the
    /// phone wasn't reachable: measurement is running, audio is not.
    private var silentNote: String? {
        guard manager.startedOnWatch, !manager.phoneLinked,
              manager.soundID?.isEmpty == false else { return nil }
        return "iPhone out of reach, silent"
    }

    // MARK: - Sending / sent

    private var sendingScreen: some View {
        ZStack {
            WatchValley(hour: nowHour, stage: manager.ottoStage(), cushion: 0.84, sceneShare: 0.84)
                .equatable()
                .ignoresSafeArea()
            VStack(spacing: 6) {
                Text("Sending")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .onSky(nowDay)
                SendingDots(color: nowDay.ink)
                Spacer()
            }
        }
    }

    private var sentScreen: some View {
        ZStack {
            WatchValley(hour: nowHour, stage: manager.ottoStage(), cushion: 0.84, sceneShare: 0.84)
                .equatable()
                .ignoresSafeArea()
            VStack(spacing: 3) {
                // An encode failure sends nothing and queues nothing, so it
                // must not read "Saved" (2026-09-30).
                Text(manager.sendFailed ? "Not sent" : (manager.deliveredImmediately ? "Delivered" : "Saved"))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text(manager.sendFailed
                     ? "Couldn't send this session."
                     : manager.deliveredImmediately
                     ? "Open 808 on your iPhone to see how you settled."
                     : "It'll reach your iPhone when it's back in range.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .onSky(nowDay)
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - The valley

/// The iPhone's valley at Watch size, Otto on his cushion. `cushion` is where
/// the cushion's bottom lands, as a share of the screen's height, so each
/// screen leaves room for what it shows.
///
/// Equatable on purpose: the live screen redraws every second, and the
/// painting (a canvas of flowers and grass) only needs redrawing when the
/// hour moves a step or Otto's stage changes.
struct WatchValley: View, Equatable {
    let hour: Double
    let stage: Int?
    let cushion: CGFloat
    /// The scene's height against the screen's: smaller draws Otto smaller.
    var sceneShare: CGFloat = 1.01

    /// The sky moves in small steps, not every second.
    static func quantize(_ hour: Double) -> Double {
        (min(max(hour, 0), 1) * 200).rounded() / 200
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // A scene a little taller than the screen keeps Otto about a
            // third of its height, the share the mockup was drawn at.
            let scene = CGSize(width: size.width, height: size.height * sceneShare)
            let s = SitLayout.scale(in: scene)
            let day = DayLight.at(hour)
            let grass = day.field.last ?? .green
            let originY = size.height * cushion - SitLayout.cushionBottom(in: scene)
            let seated = SitLayout.ottoHeight(in: scene)
            let canvas = seated * 0.95 / OttoStillCanvas.bodyShare
            ZStack(alignment: .topLeading) {
                // Above the scene, its own top colour; below it, the grass.
                (day.sky.first ?? .blue)
                Rectangle().fill(grass).colorMultiply(Color(white: day.light))
                    .frame(height: size.height)
                    .offset(y: originY + scene.height - 1)
                ZStack {
                    ValleySky(day: day, hour: hour, size: scene, scale: s)
                    ValleyClouds(day: day, hour: hour, size: scene, scale: s, time: 0)
                    ValleyLand(day: day, size: scene)
                    ZStack {
                        Meadow(scale: s).frame(width: scene.width, height: scene.height)
                        if stage != nil { Cushion.seated(in: scene, scale: s) }
                    }
                    .frame(width: scene.width, height: scene.height)
                    .colorMultiply(Color(white: day.light))
                    if let stage {
                        Image("WatchOtto\(stage)")
                            .resizable()
                            .scaledToFit()
                            .frame(width: canvas * OttoStillCanvas.aspect, height: canvas)
                            .offset(y: canvas * (1 - OttoStillCanvas.baseline))
                            // The two brightest float, as on Home.
                            .offset(y: stage >= 6 ? -seated * 0.05 : 0)
                            .frame(width: seated, height: seated, alignment: .bottom)
                            .colorMultiply(Color(white: day.light))
                            .position(x: scene.width / 2, y: SitLayout.seatedCentreY(in: scene))
                    }
                }
                .frame(width: scene.width, height: scene.height)
                // The meadow fades into plain grass below it, the way every
                // band of valley in the app ends (`fadesIntoMeadow`).
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [grass.opacity(0), grass], startPoint: .top, endPoint: .bottom)
                        .colorMultiply(Color(white: day.light))
                        .frame(height: scene.height * 0.18)
                }
                .offset(y: originY)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .drawingGroup()
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Words drawn straight on the sky take the hour's ink with a faint halo
    /// of the opposite shade, as `onValley()` does on the iPhone.
    func onSky(_ day: DayLight) -> some View {
        foregroundStyle(day.ink)
            .shadow(color: day.inkIsDark ? .white.opacity(0.55) : .black.opacity(0.4), radius: 3)
    }
}

// MARK: - Pieces

/// A sand card with the lip under it, the app's tile.
private struct SandCard: View {
    var radius: CGFloat = 14
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(WatchPalette.sand)
            .shadow(color: WatchPalette.sandLip, radius: 0, y: 2)
    }
}

/// Length or sound: the + screen's pill, at Watch size.
private struct ChoicePill: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchPalette.sandInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text("\u{203A}")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WatchPalette.sandInkSoft)
            }
            .padding(.leading, 6).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Capsule().fill(WatchPalette.sand)
                .shadow(color: WatchPalette.sandLip, radius: 0, y: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "WatchIconLength" ? "Length, \(title)" : "Sound, \(title)")
    }
}

/// The one gold thing: Begin, Done, Allow. The iPhone's lifted gold button.
private struct BeginButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(WatchPalette.beginInk)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Capsule().fill(WatchPalette.begin))
            .background(
                Capsule().fill(WatchPalette.beginLip).offset(y: configuration.isPressed ? 0 : 3)
            )
            .offset(y: configuration.isPressed ? 2 : 0)
            .padding(.bottom, 3)
    }
}

/// Cancel and End: a sand pill, quieter than Begin.
private struct SandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(WatchPalette.sandInk)
            .padding(.horizontal, 28)
            .frame(minHeight: 34)
            .background(Capsule().fill(WatchPalette.sand)
                .shadow(color: WatchPalette.sandLip, radius: 0, y: 2))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The ring in the sky: an empty track that is always there, and the sage
/// arc of a timed session closing over it, as on the iPhone's sit.
private struct SitRing: View {
    let progress: Double?
    let track: Color
    let time: String
    let label: String
    let day: DayLight

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 2.5)
                .stroke(track, lineWidth: 5)
            if let progress {
                Circle()
                    .inset(by: 2.5)
                    .trim(from: 0, to: max(0.0001, progress))
                    .stroke(WatchPalette.arc.opacity(0.3 + 0.6 * progress),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(time)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .onSky(day)
            .padding(.horizontal, 8)
        }
        .frame(width: 74, height: 74)
        .accessibilityElement(children: .combine)
    }
}

/// Three dots rising toward the iPhone while the payload goes.
private struct SendingDots: View {
    let color: Color
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(animate ? 0.25 : 1)
                    .animation(reduceMotion ? nil :
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                        value: animate)
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Length

/// The + screen's tape at Watch size: the Digital Crown or a drag slides it,
/// Open at the left end, then every minute from 5 to 120 (`SessionLength`).
/// The crown's detent is watchOS's own; the app plays no haptic.
///
/// **Smooth, then settles** (Aziz, 2026-10-18: "the swiping is super
/// glitchy"). The tape follows a CONTINUOUS position, from the crown's own
/// offset and from the drag measured from where it began, and springs onto
/// the nearest minute when the crown rests or the finger lifts. It used to
/// move only in whole-minute jumps, and the drag measured each step from the
/// already-moved position, so it ran away and stuttered.
///
/// Tapping the number lets the length be written, said or typed (the
/// system's own input: Scribble, dictation or the keyboard), five minutes to
/// ten hours, 0 for Open, like the + screen's typed length.
private struct LengthPickerView: View {
    let onDone: (Int?) -> Void
    /// The crown's detent: a whole tape index.
    @State private var detent: Double
    /// Where the tape is drawn, between ticks while it moves.
    @State private var position: Double
    @State private var dragStart: Double?
    /// A typed length the tape does not carry (a typed 300), shown until
    /// the tape moves again.
    @State private var typed: Int?
    @State private var typedOpen = false
    @State private var entry = ""
    @State private var padOpen = false

    init(minutes: Int?, onDone: @escaping (Int?) -> Void) {
        self.onDone = onDone
        let start = Double(SessionLength.nearestIndex(for: minutes))
        _detent = State(initialValue: start)
        _position = State(initialValue: start)
        if let minutes, !SessionLength.values.contains(minutes) { _typed = State(initialValue: minutes) }
    }

    private static var last: Double { Double(SessionLength.values.count - 1) }
    private var index: Int { min(max(Int(position.rounded()), 0), SessionLength.values.count - 1) }
    private var minutes: Int? {
        if typedOpen { return nil }
        return typed ?? SessionLength.values[index]
    }
    private var day: DayLight { DayLight.at(WatchValley.quantize(DayLight.clockProgress())) }

    private static let spacing: CGFloat = 9

    var body: some View {
        ZStack {
            WatchValley(hour: WatchValley.quantize(DayLight.clockProgress()), stage: nil, cushion: 0.78)
                .equatable()
                .ignoresSafeArea()
            VStack(spacing: 2) {
                number
                Text(minutes == nil ? "Open, end when you like" : (minutes == 1 ? "minute" : "minutes"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .onSky(day)
                tape
                    .padding(.top, 6)
                Spacer(minLength: 4)
                Button("Done") { onDone(minutes) }
                    .buttonStyle(BeginButtonStyle())
            }
            .padding(.horizontal, 4)
        }
        .focusable()
        .digitalCrownRotation(detent: $detent,
                              from: 0,
                              through: Self.last,
                              by: 1,
                              sensitivity: .medium,
                              isContinuous: false,
                              isHapticFeedbackEnabled: true,
                              onChange: { event in
                                  guard dragStart == nil else { return }
                                  position = min(max(event.offset, 0), Self.last)
                                  clearTyped()
                              },
                              onIdle: { settle(on: detent) })
        .onAppear { entry = Self.text(minutes) }
        .onChange(of: index) { _, _ in if typed == nil, !typedOpen { entry = Self.text(minutes) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Length")
        .accessibilityValue(SessionLength.words(minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settle(on: min(Double(index) + 1, Self.last))
            case .decrement: settle(on: max(Double(index) - 1, 0))
            @unknown default: break
            }
        }
    }

    /// The big number. Tapping it opens 808's own number pad (Aziz,
    /// 2026-10-18: "should only show numbers"): watchOS gives apps no
    /// numbers-only keyboard, so the system input offered letters too. The
    /// pencil says it can be tapped.
    private var number: some View {
        Button { padOpen = true } label: {
            HStack(alignment: .center, spacing: 4) {
                Text(Self.text(minutes))
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .onSky(day)
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .bold))
                    .onSky(day)
                    .opacity(0.7)
            }
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Length, \(SessionLength.words(minutes)). Tap to enter minutes")
        .sheet(isPresented: $padOpen) {
            MinutesPad { written in
                padOpen = false
                take(written)
            }
        }
    }

    private static func text(_ minutes: Int?) -> String { minutes.map(String.init) ?? "\u{221E}" }

    /// A written or typed length: 0 is Open, 1 to 4 is 5, at most 600.
    private func take(_ raw: String) {
        let (value, valid) = SessionLength.typed(raw)
        guard valid else { entry = Self.text(minutes); return }
        let target = Double(SessionLength.nearestIndex(for: value))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { position = target }
        detent = target
        typedOpen = value == nil
        typed = value.flatMap { SessionLength.values.contains($0) ? nil : $0 }
        entry = Self.text(value)
    }

    private func clearTyped() {
        if typed != nil || typedOpen {
            typed = nil
            typedOpen = false
        }
    }

    /// Springs the tape onto a whole minute, and keeps the crown there too.
    private func settle(on target: Double) {
        let t = min(max(target.rounded(), 0), Self.last)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { position = t }
        detent = t
    }

    /// Ticks on a sand strip, sliding under a fixed needle. A tick a minute,
    /// a number every five, ∞ at the left end. Dragging the strip works too.
    private var tape: some View {
        GeometryReader { geo in
            let mid = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                ForEach(Array(SessionLength.values.enumerated()), id: \.offset) { i, value in
                    let x = mid + (CGFloat(i) - CGFloat(position)) * Self.spacing
                    if x > -12, x < geo.size.width + 12 {
                        tick(value)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }
                Capsule()
                    .fill(WatchPalette.needle)
                    .frame(width: 3, height: geo.size.height - 8)
                    .position(x: mid, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            // Measured from where the finger came down, never from the
            // moved position, then flung with the finger's speed and settled
            // on a whole minute.
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { g in
                    if dragStart == nil { dragStart = position }
                    let start = dragStart ?? position
                    position = min(max(start - Double(g.translation.width / Self.spacing), 0), Self.last)
                    clearTyped()
                }
                .onEnded { g in
                    let start = dragStart ?? position
                    dragStart = nil
                    settle(on: start - Double(g.predictedEndTranslation.width / Self.spacing))
                })
        }
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(WatchPalette.sand)
            .shadow(color: WatchPalette.sandLip, radius: 0, y: 2))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func tick(_ value: Int?) -> some View {
        if let value {
            let labelled = value % 5 == 0
            VStack(spacing: 2) {
                Text(labelled ? "\(value)" : " ")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchPalette.sandInkSoft)
                    .fixedSize()
                RoundedRectangle(cornerRadius: 1)
                    .fill(labelled ? WatchPalette.sandInkSoft : WatchPalette.sandInkSoft.opacity(0.55))
                    .frame(width: 2, height: labelled ? 13 : 8)
            }
            .frame(height: 30, alignment: .bottom)
        } else {
            Text("\u{221E}")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(WatchPalette.sandInk)
                .frame(height: 30, alignment: .bottom)
        }
    }
}

// MARK: - Minutes pad

/// Numbers only: 1 to 9, delete, 0 and a check, with what has been typed
/// above. Up to three digits (600 is the longest length); 0 means Open, as
/// on the + screen. Sized from the screen, so it fits every Watch.
private struct MinutesPad: View {
    let onDone: (String) -> Void
    @State private var digits = ""

    private let keys: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "del", "0", "ok"]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let keyW = (geo.size.width - gap * 2) / 3
            let keyH = max(24, (geo.size.height - 34 - gap * 4) / 4)
            VStack(spacing: gap) {
                Text(digits.isEmpty ? "min" : digits + " min")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    // On the sheet's dark glass: white, dimmer before any digit.
                    .foregroundStyle(.white.opacity(digits.isEmpty ? 0.55 : 1))
                    .frame(height: 30)
                    .accessibilityLabel(digits.isEmpty ? "No minutes yet" : "\(digits) minutes")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(keyW), spacing: gap), count: 3), spacing: gap) {
                    ForEach(keys, id: \.self) { key in
                        Button { press(key) } label: { label(for: key) }
                            .buttonStyle(.plain)
                            .frame(width: keyW, height: keyH)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(key == "ok" ? WatchPalette.gold : WatchPalette.sand))
                            .opacity(key == "ok" && digits.isEmpty ? 0.45 : 1)
                            .disabled(key == "ok" && digits.isEmpty)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder private func label(for key: String) -> some View {
        switch key {
        case "del":
            Image(systemName: "delete.left").font(.system(size: 16, weight: .bold))
                .foregroundStyle(WatchPalette.sandInk)
                .accessibilityLabel("Delete")
        case "ok":
            Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy))
                .foregroundStyle(WatchPalette.sandInk)
                .accessibilityLabel("Done")
        default:
            Text(key).font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(WatchPalette.sandInk)
        }
    }

    private func press(_ key: String) {
        switch key {
        case "del": if !digits.isEmpty { digits.removeLast() }
        case "ok": onDone(digits)
        default:
            guard digits.count < 3 else { return }
            if digits == "0" { digits = key } else { digits += key }
        }
    }
}

// MARK: - Sound

/// The full catalog as the iPhone's pills, over the valley, scrolled with the
/// crown. Selection is remembered between sessions; audio plays from the
/// phone.
private struct SoundPickerView: View {
    @Binding var selectedID: String?
    @Environment(\.dismiss) private var dismiss

    private var day: DayLight { DayLight.at(WatchValley.quantize(DayLight.clockProgress())) }

    var body: some View {
        ZStack {
            WatchValley(hour: WatchValley.quantize(DayLight.clockProgress()), stage: nil, cushion: 0.78)
                .equatable()
                .blur(radius: 5)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    row(id: nil, title: "Silence", detail: "or your own")
                    ForEach(SoundMenu.groups) { group in
                        Text(group.name.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(WatchPalette.sandInk)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 7).fill(WatchPalette.sand))
                            .padding(.top, 4)
                        ForEach(group.entries) { entry in
                            row(id: entry.id, title: entry.title, detail: entry.detail)
                        }
                    }
                    Text("Plays from your iPhone")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .onSky(day)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Sound")
    }

    private func row(id: String?, title: String, detail: String?) -> some View {
        let isSelected = (selectedID ?? "").isEmpty ? id == nil : selectedID == id
        return Button {
            selectedID = id
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchPalette.sandInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchPalette.sandInkSoft)
                        .lineLimit(1)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(WatchPalette.chosen)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                Capsule().fill(WatchPalette.sand)
                    .shadow(color: WatchPalette.sandLip, radius: 0, y: 2)
            )
            .overlay(Capsule().strokeBorder(isSelected ? WatchPalette.begin : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
