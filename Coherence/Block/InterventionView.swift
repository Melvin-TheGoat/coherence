import SwiftUI
import AVFoundation

/// One of Otto's twenty screens (`mockups/block-v1.html`, section 3, approved
/// 2026-09-22), opened by the "Otto wants a word" notification the shield's
/// Ask Otto button sends. Every one ends in the same two doors: meditate now,
/// which starts a session straight away (Melvin, 2026-09-22), or "Not now",
/// which asks how long.
///
/// Chill but convincing. He asks, he never scolds, and every line is written
/// here, never generated.
struct InterventionView: View {
    let kind: InterventionKind
    let context: InterventionContext
    @ObservedObject var block: BlockController
    /// Start a session now: open-ended, or timed for the screens that
    /// promise to keep time.
    let onMeditate: (Int?) -> Void
    /// Done: a pass was taken, or they closed it.
    let onClose: () -> Void
    /// The unblock-screens gallery (Settings > DEBUG, so every screen can be
    /// rehearsed on a phone with nothing real happening): tells
    /// `HowLongScreen` to skip `BlockController.takePass`, so it never
    /// touches Screen Time. Defaults to the real flow.
    let rehearsal: Bool

    private enum Step { case ask, howLong }
    @State private var step: Step

    init(kind: InterventionKind, context: InterventionContext, block: BlockController,
         onMeditate: @escaping (Int?) -> Void, onClose: @escaping () -> Void,
         rehearsal: Bool = false, startOnHowLong: Bool = false) {
        self.kind = kind
        self.context = context
        self.block = block
        self.onMeditate = onMeditate
        self.onClose = onClose
        self.rehearsal = rehearsal
        _step = State(initialValue: startOnHowLong ? .howLong : .ask)
    }

    var body: some View {
        ZStack {
            switch step {
            case .ask:
                InterventionScene(kind: kind, context: context, doors: doors)
            case .howLong where kind == .fridgeNote:
                StickyHowLongScreen(block: block, onMeditate: { onMeditate(nil) }, onClose: onClose,
                                    rehearsal: rehearsal)
                    .transition(.opacity)
            case .howLong where kind == .voiceNote:
                NoteHowLongScreen(block: block, onMeditate: { onMeditate(nil) }, onClose: onClose,
                                  rehearsal: rehearsal)
                    .transition(.opacity)
            case .howLong:
                HowLongScreen(block: block, onMeditate: { onMeditate(nil) }, onClose: onClose,
                              rehearsal: rehearsal,
                              line: HowLongScreen.line(after: kind, context: context),
                              meditateLabel: HowLongScreen.meditateLabel(after: kind),
                              pose: HowLongScreen.pose(after: kind))
                    .transition(.opacity)
            }
        }
        // No close button (Melvin, 2026-10-07): the X let someone dismiss
        // Otto without answering him and walk into the Block tab. His screens
        // are left by "Okay, let's meditate" (the + screen, which can still be
        // closed) or "Not now" (how long). The rehearsal gallery keeps it, so
        // a tester can leave without taking a pretend pass.
        .overlay(alignment: .topLeading) {
            if rehearsal {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppColor.backgroundPrimary.opacity(0.85), in: Circle())
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                .accessibilityLabel("Close")
            }
        }
        .statusBarHidden(false)
        .followsStatusBarRule()
        // Otto's words tick as they type, as they do in onboarding (Aziz,
        // 2026-10-04: "make sure the typing animation and haptics are here").
        // Home and a sit stay silent; this is a screen he is talking on.
        .environment(\.typingHaptics, true)
    }

    /// "Not now" always goes straight to how long: there is no strict mode,
    /// no ten-second breath and no daily limit on it (Aziz, 2026-09-22).
    private var doors: InterventionDoors {
        InterventionDoors(
            canPass: true,
            meditate: { onMeditate(nil) },
            meditateFor: { onMeditate($0) },
            notNow: {
                withAnimation(.easeInOut(duration: 0.3)) { step = .howLong }
            },
            pass: { minutes in
                // The gallery rehearses with nothing real happening, as the
                // how-long screen does.
                if !rehearsal { block.takePass(minutes: minutes) }
                onClose()
            })
    }
}

/// The two doors, handed to each scene so the scenes can label them.
struct InterventionDoors {
    /// Whether "Not now" shows. Always, except while the countdown screen is
    /// still counting.
    let canPass: Bool
    /// The shortest session that opens what is held, in minutes.
    var shortest = Blocker.sessionMinutes
    let meditate: () -> Void
    /// A timed session, for the screens that say they will keep time.
    var meditateFor: (Int) -> Void = { _ in }
    let notNow: () -> Void
    /// Opens the held apps for this many minutes and closes Otto, for a
    /// screen that asks how long itself (the text thread, 2026-10-04).
    var pass: (Int) -> Void = { _ in }
}

// MARK: - The bottom of every screen

private struct DoorButtons: View {
    let doors: InterventionDoors
    var primary = "Okay, let's meditate"
    var secondary = "Not now"
    var ink: Color = AppColor.textPrimary

    var body: some View {
        VStack(spacing: 10) {
            Button(primary, action: doors.meditate)
                .buttonStyle(PrimaryButtonStyle())
            if doors.canPass {
                // A cream pill, like the how-long screen's: as bare text it
                // sat on the meadow's flowers and could not be read
                // (2026-09-23), and a pill reads on every scene these share.
                Button(action: doors.notNow) {
                    Text(secondary)
                        .font(DisplayFont.display(15, .bold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.bottom, 12)
    }
}

// MARK: - The scenes

private struct InterventionScene: View {
    let kind: InterventionKind
    let context: InterventionContext
    let doors: InterventionDoors

    var body: some View {
        switch kind {
        case .standing:
            // Aziz, 2026-10-04: "Are you sure? You haven't meditated yet",
            // the second half only when it is true.
            ValleyStage(pose: "OttoWave",
                        line: context.meditatedToday ? "Are you sure? Meditate with me first?"
                                                     : "Are you sure? You haven't meditated yet.",
                        doors: doors)
        case .textThread:
            TextThreadScene(doors: doors, meditatedToday: context.meditatedToday)
        case .faceTime:
            FaceTimeScene(doors: doors, meditatedToday: context.meditatedToday)
        case .breatheWithMe:
            BreatheWithMeScene(doors: doors, meditatedToday: context.meditatedToday)
        case .voiceNote:
            VoiceNoteScene(doors: doors, meditatedToday: context.meditatedToday)
        case .fridgeNote:
            FridgeNoteScene(doors: doors, meditatedToday: context.meditatedToday)
        case .stillThere:
            ValleyStage(pose: "OttoAwake", line: "It'll all still be there after you meditate.", doors: doors)
        case .wakingOtto:
            ValleyStage(pose: "OttoSit", line: "Zzz... oh, hey. Morning meditation?", doors: doors) { size, ottoTop in
                Text("z z")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .onValley(soft: true)
                    .position(x: size.width * 0.66, y: ottoTop + 18)
            }
        case .sign:
            SignScene(doors: doors)
        case .streak:
            ValleyStage(pose: "OttoSit",
                        line: "Your streak is at \(context.streak) days. Meditate first to keep it going.",
                        doors: doors) { size, _ in
                Label("\(context.streak)", systemImage: "flame.fill")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.streakBlushText)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(AppColor.backgroundPrimary.opacity(0.9), in: Capsule())
                    .position(x: size.width / 2, y: 72)
            }
        case .glow:
            ValleyStage(pose: OttoAuraFigure.asset(.faded), line: "Help me glow? One session today.", doors: doors)
        case .twoDoors:
            TwoDoorsScene(doors: doors)
        case .countdown:
            CountdownScene(doors: doors)
        case .affirmation:
            AffirmationScene(doors: doors)
        case .bedtime:
            ValleyStage(progress: 0.96, pose: "OttoSit", dim: 0.6,
                        line: "Wind down with me? Meditate first, then sleep.",
                        doors: doors, primary: "Okay, let's wind down")
        case .sticker:
            StickerScene(doors: doors)
        case .valley:
            ValleyStage(pose: "OttoGreet", line: "It's quiet out here. Come sit a minute.", doors: doors)
        case .friend:
            let name = context.friendWhoSat ?? "A friend"
            ValleyStage(pose: "OttoAwake", line: "\(name) already meditated today. Join them?",
                        doors: doors) { size, _ in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppColor.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 15, weight: .bold))
                        Text("meditated today").font(.system(size: 13))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .foregroundStyle(AppColor.textPrimary)
                .padding(12)
                .background(AppColor.backgroundPrimary.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .position(x: size.width / 2, y: 130)
            }
        case .oneMinute:
            OneMinuteScene(doors: doors)
        case .askWhy:
            AskWhyScene(doors: doors)
        }
    }
}

/// Otto standing or sitting in the valley with a line over his head: the
/// shape most of the twenty take.
private struct ValleyStage<Extra: View>: View {
    var progress: Double = 0
    let pose: String
    var dim: Double = 1
    let line: String
    let doors: InterventionDoors
    var primary = "Okay, let's meditate"
    var secondary = "Not now"
    /// Anything the scene adds, given the size and where Otto's head is.
    var extra: (CGSize, CGFloat) -> Extra

    init(progress: Double = 0, pose: String, dim: Double = 1, line: String, doors: InterventionDoors,
         primary: String = "Okay, let's meditate", secondary: String = "Not now",
         @ViewBuilder extra: @escaping (CGSize, CGFloat) -> Extra) {
        self.progress = progress
        self.pose = pose
        self.dim = dim
        self.line = line
        self.doors = doors
        self.primary = primary
        self.secondary = secondary
        self.extra = extra
    }

    /// The hour drawn: the real one, unless the scene asks for its own (the
    /// sleepy one is night on purpose).
    private var hour: Double { progress == 0 ? DayLight.clockProgress() : progress }

    var body: some View {
        let day = DayLight.at(hour)
        GeometryReader { geo in
            let size = geo.size
            let ottoHeight = min(230, size.height * 0.28)
            let ottoBottom = size.height - 150
            let ottoTop = ottoBottom - ottoHeight
            ZStack {
                ValleyScene(progress: progress, showsFigure: false, clock: progress == 0)
                // The aura drawings share one padded canvas (light around him,
                // room under him), so they are drawn taller to put the sloth
                // himself at `ottoHeight`, with his baseline on `ottoBottom`.
                let aura = pose.hasPrefix("OttoAura")
                let drawn = aura ? ottoHeight / OttoAuraFigure.bodyShare : ottoHeight
                let bottom = aura ? ottoBottom + drawn * (1 - OttoAuraFigure.baseline) : ottoBottom
                Image(pose)
                    .resizable()
                    .scaledToFit()
                    .frame(height: drawn)
                    .brightness(dim < 1 ? -(1 - dim) * 0.5 : 0)
                    .position(x: size.width / 2, y: bottom - drawn / 2)
                    .accessibilityHidden(true)
                if !line.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        // Home's bubble at this scene's hour: cream glass and
                        // dark words by day, dark glass and pale words at night.
                        OttoLine(text: line, progress: hour)
                    }
                    .frame(width: min(size.width - 56, 330), height: max(0, ottoTop - 8 - 110))
                    .position(x: size.width / 2, y: 110 + max(0, ottoTop - 8 - 110) / 2)
                }
                extra(size, ottoTop)
                VStack {
                    Spacer()
                    DoorButtons(doors: doors, primary: primary, secondary: secondary,
                                ink: hour > 0.6 ? AppColor.backgroundPrimary : day.ink)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

extension ValleyStage where Extra == EmptyView {
    init(progress: Double = 0, pose: String, dim: Double = 1, line: String, doors: InterventionDoors,
         primary: String = "Okay, let's meditate", secondary: String = "Not now") {
        self.init(progress: progress, pose: pose, dim: dim, line: line, doors: doors,
                  primary: primary, secondary: secondary) { _, _ in EmptyView() }
    }
}

/// His line, in the bubble the valley screens use.
private struct OttoLine: View {
    let text: String
    let progress: Double
    var body: some View {
        let look = ValleyBubble.look(at: progress)
        OttoSpeech(text: text, tail: .bottom, size: 19,
                   ink: look.ink, stroke: look.stroke,
                   fill: look.fill, alignment: .center,
                   speaking: .constant(false))
            .id(text)
    }
}

// MARK: - 2. A text thread

/// Otto texts you (Aziz, 2026-10-04): blue bubbles, one at a time, each
/// after its typing dots, and the replies right under his last text rather
/// than down at the bottom of the screen. What you tap is sent as your own
/// text before anything happens, so it reads as a conversation.
///
/// "I'm busy" is not the end of it: he says once that a few minutes could
/// help, then asks how long you need, 5, 10 or 30 minutes, which opens the
/// held apps for that long (`doors.pass`), or "actually nvm", which goes to
/// the + screen like every other "let's meditate".
private struct TextThreadScene: View {
    let doors: InterventionDoors
    let meditatedToday: Bool

    private struct Message: Identifiable, Equatable {
        let id = UUID()
        let mine: Bool
        let text: String
    }
    private enum Replies { case none, first, howLong }

    @State private var messages: [Message] = []
    @State private var typing = false
    @State private var replies: Replies = .none
    /// Set once a reply is tapped, so a second tap does nothing.
    @State private var answered = false

    private var opener: String {
        meditatedToday
            ? "want to do a quick meditation before you open this?"
            : "you haven't meditated today. want to do one before you open this?"
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { m in
                            ChatBubble(text: m.text, mine: m.mine)
                                .frame(maxWidth: .infinity, alignment: m.mine ? .trailing : .leading)
                        }
                        if typing { TypingDots() }
                        replyOptions
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { scroll.scrollTo("end", anchor: .bottom) }
                }
                .onChange(of: replies) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { scroll.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .keepsDarkStatusBar()
        .task {
            await otto("yo it's otto", wait: 0.6)
            await otto(opener, wait: 1.3)
            show(.first)
        }
    }

    @ViewBuilder private var replyOptions: some View {
        switch replies {
        case .none:
            EmptyView()
        case .first:
            options([
                ("yeah you're right, let's meditate", { meditate("yeah you're right, let's meditate") }),
                ("i'm busy right now, i need the app", { busy() }),
            ])
        case .howLong:
            options([
                ("5 min", { open(5) }),
                ("10 min", { open(10) }),
                ("30 min", { open(30) }),
                ("actually nvm, i'll meditate", { meditate("actually nvm, i'll meditate") }),
            ])
        }
    }

    private func options(_ list: [(String, () -> Void)]) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(list.indices, id: \.self) { i in
                ReplyChip(text: list[i].0, action: list[i].1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: The conversation

    private func otto(_ text: String, wait: Double) async {
        withAnimation(.easeOut(duration: 0.2)) { typing = true }
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            typing = false
            messages.append(Message(mine: false, text: text))
        }
        // A tap as each text lands, the way a message arriving feels.
        WelcomeHaptics.tick()
    }

    private func show(_ next: Replies) {
        withAnimation(.easeOut(duration: 0.25)) { replies = next }
    }

    /// Your reply, sent as your own text, with the options taken away.
    private func send(_ text: String) -> Bool {
        guard !answered else { return false }
        answered = true
        withAnimation(.easeOut(duration: 0.25)) {
            replies = .none
            messages.append(Message(mine: true, text: text))
        }
        return true
    }

    private func meditate(_ reply: String) {
        guard send(reply) else { return }
        Task { @MainActor in
            await otto("let's go. i'll meet you there", wait: 0.7)
            try? await Task.sleep(for: .seconds(0.6))
            doors.meditate()
        }
    }

    private func busy() {
        guard send("i'm busy right now, i need the app") else { return }
        Task { @MainActor in
            await otto("okay...", wait: 0.9)
            await otto("just so you know, you could feel so much better after even a few minutes", wait: 1.4)
            await otto("how long do you need?", wait: 1.0)
            answered = false
            show(.howLong)
        }
    }

    private func open(_ minutes: Int) {
        guard send("\(minutes) min") else { return }
        Task { @MainActor in
            await otto("ok, it's open for \(minutes) min. i'll be here", wait: 0.8)
            try? await Task.sleep(for: .seconds(0.9))
            doors.pass(minutes)
        }
    }
}

private struct ChatHeader: View {
    var body: some View {
        VStack(spacing: 4) {
            Image("OttoHead")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .background(AppColor.sky.opacity(0.35), in: Circle())
            Text("Otto")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColor.hairline).frame(height: 0.5)
        }
    }
}

/// One text. Otto's are blue with white words (Aziz, 2026-10-04: "make it
/// blue"); yours are sand with dark words, on the right.
private struct ChatBubble: View {
    let text: String
    var mine = false
    var body: some View {
        Text(text)
            .font(.system(size: 17))
            .foregroundStyle(mine ? AppColor.textPrimary : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(mine ? AppColor.backgroundSecondary : AppColor.skyDeep,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 290, alignment: mine ? .trailing : .leading)
            .transition(.scale(scale: 0.85, anchor: mine ? .trailing : .leading).combined(with: .opacity))
    }
}

private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(AppColor.textSecondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(t * 6 - Double(i) * 0.8)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColor.backgroundSecondary, in: Capsule())
        }
    }
}

private struct ReplyChip: View {
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.skyDeep)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(AppColor.backgroundPrimary, in: Capsule())
                .overlay(Capsule().stroke(AppColor.skyDeep, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. A FaceTime call

/// Otto "calls" you. One camera view, two states: the camera starts only
/// on Accept, and permission is asked only then, because a Block
/// notification opens this screen and nobody has chosen anything while it
/// rings (App Review 5.1.1, 2026-09-29). Live preview only, nothing
/// recorded or saved (`NSCameraUsageDescription`). Decline never touches
/// the camera.
///
/// **Ringing**: a soft dark card fills the screen with the call card on
/// top. The camera is off, even when access was granted before.
///
/// **Answered**: Otto full screen in the valley, exactly as every other
/// intervention screen draws him (`ValleyStage`), his lines arriving in
/// `OttoSpeech` bubbles one after another. The camera shrinks to a small
/// mirrored self-view in the top right, FaceTime's own shape. No camera,
/// denied, or restricted keeps a neutral placeholder there instead.
private struct FaceTimeScene: View {
    let doors: InterventionDoors
    let meditatedToday: Bool
    @State private var answered: Bool
    @StateObject private var camera = FrontCamera()

    /// `PREVIEW_FACETIME_ANSWERED=1` (DEBUG) opens straight into the
    /// answered state, so it can be reviewed on the simulator (which has no
    /// camera to accept a call with) without any UI automation.
    init(doors: InterventionDoors, meditatedToday: Bool) {
        self.doors = doors
        self.meditatedToday = meditatedToday
        var startAnswered = false
        #if DEBUG
        if ProcessInfo.processInfo.environment["PREVIEW_FACETIME_ANSWERED"] == "1" {
            startAnswered = true
        }
        #endif
        _answered = State(initialValue: startAnswered)
    }

    /// Whether this person already said yes to the camera, so it may run
    /// while the call rings without asking.
    private static var cameraAllowed: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// The self-view's size once answered, FaceTime's own shape.
    private static let pip = CGSize(width: 100, height: 136)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if answered {
                    answeredView
                }
                // ONE camera view for both states, drawn in the same place
                // in the tree either way, so Accept only moves and shrinks it
                // (see `FaceTimeCameraPreview` for why a second preview froze
                // the screen).
                cameraView
                    .frame(width: answered ? Self.pip.width : size.width,
                           height: answered ? Self.pip.height : size.height)
                    .clipShape(RoundedRectangle(cornerRadius: answered ? 16 : 0, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: answered ? 16 : 0, style: .continuous)
                        .stroke(.white.opacity(answered ? 0.5 : 0), lineWidth: 1.5))
                    .shadow(color: .black.opacity(answered ? 0.22 : 0), radius: 10, y: 4)
                    .position(answered ? CGPoint(x: size.width - 66, y: 128)
                                       : CGPoint(x: size.width / 2, y: size.height / 2))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if !answered {
                    ringing
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        // Your face is on while it rings, like a real call (Aziz,
        // 2026-10-04), but only once the camera is already allowed: the
        // permission prompt is never raised by a screen that opened from a
        // notification before anything was tapped (App Review 5.1.1,
        // 2026-09-29). The first call asks on Accept; every call after it
        // rings with your face. Keyed so an allowed camera started while
        // ringing is not restarted by Accept; `start()` is idempotent
        // anyway, and checks for a cancelled task.
        .task(id: answered || Self.cameraAllowed) {
            if answered || Self.cameraAllowed { await camera.start() }
        }
        .onDisappear { camera.stop() }
    }

    /// Your live mirrored camera, full screen while ringing (once allowed)
    /// and small once answered; a soft dark card while ringing before the
    /// camera is allowed, and a neutral placeholder once answered while it
    /// starts or when it cannot run.
    @ViewBuilder
    private var cameraView: some View {
        if camera.ready {
            FaceTimeCameraPreview(session: camera.session)
        } else if answered {
            ZStack {
                AppColor.backgroundSecondary
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppColor.textSecondary)
            }
        } else {
            LinearGradient(colors: [AppColor.textPrimary.opacity(0.92), AppColor.textPrimary],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var ringing: some View {
        ZStack {
            // Keeps the call card legible over the dark card behind it.
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.05), .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Image("OttoHead")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .background(AppColor.sky.opacity(0.5), in: Circle())
                    .padding(.top, 120)
                Text("Otto")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                // Not "FaceTime Video": Apple's trademark and a copy of its
                // own call screen are an App Review 5.2.5 risk. Otto's call
                // is his own.
                Text("Video call")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                HStack {
                    callButton("Decline", systemImage: "phone.down.fill", color: Color(.systemRed)) {
                        doors.notNow()
                    }
                    Spacer()
                    callButton("Accept", systemImage: "video.fill", color: Color(.systemGreen)) { answer() }
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 70)
            }
        }
    }

    /// Once answered he asks, as the standing screen does (Aziz,
    /// 2026-10-04): one line, then "Okay, let's meditate" or "Yes, I really
    /// do", which is the "Not now" and leads to the frustrated how-long
    /// screen. It used to say "five minutes, i'll stay on", which promised
    /// a call that ends the moment the session starts.
    private var answeredView: some View {
        ValleyStage(pose: "OttoTalk",
                    line: meditatedToday
                        ? "Are you sure you need this right now?"
                        : "Are you sure you need this right now? You haven't meditated yet today.",
                    doors: doors, secondary: "Yes, I really do")
    }

    /// The camera view shrinks into the corner the way FaceTime's does, and
    /// flipping `answered` is what starts the camera (the `.task(id:)`).
    private func answer() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { answered = true }
    }

    private func callButton(_ label: String, systemImage: String, color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(color, in: Circle())
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. Breathe with me

/// Onboarding's breath (`BreathExerciseScreen`): Otto breathing in, holding
/// and breathing out on the water's 4, 2, 4, then the two doors. It replaced
/// a circle and looping in / out words in the valley (Melvin, 2026-09-29:
/// "that ones a lot better"). The doors wait for the breath, as Continue
/// does in onboarding. There is no close button (2026-10-07).
/// One breath with Otto, then he settles into the valley and asks (Aziz,
/// 2026-10-04): the breath is onboarding's (in 4, hold 2, out 4, the water
/// rising and falling), and when it ends the white page fades into the
/// valley with Otto sitting on his cushion, eyes closed, and the question in
/// his bubble over the two usual doors. "You haven't meditated yet today" is
/// said only when it is true, as in the text thread.
private struct BreatheWithMeScene: View {
    let doors: InterventionDoors
    let meditatedToday: Bool
    @State private var settled = false
    /// The breath fades to white first, THEN the valley comes up: fading one
    /// into the other drew two Ottos at once, the big breathing one and the
    /// smaller one on his cushion (2026-10-04).
    @State private var breathGone = false

    private var line: String {
        meditatedToday
            ? "Is this app really that important right now?"
            : "You haven't meditated yet today. Is this app really that important right now?"
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if settled {
                ValleyStage(pose: "OttoSit", line: line, doors: doors)
                    .transition(.opacity)
            } else {
                BreathExerciseScreen(title: "One breath with me, then decide.", onFinished: {
                    // A beat on "Nicely done" before the valley comes up.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.1))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeIn(duration: 0.35)) { breathGone = true }
                        try? await Task.sleep(for: .seconds(0.4))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.7)) { settled = true }
                    }
                }) {
                    EmptyView()
                }
                .opacity(breathGone ? 0 : 1)
                // A white page: keep the status bar dark after dark
                // (2026-09-30). On this branch only, so the valley after it
                // follows the hour again.
                .keepsDarkStatusBar()
                .transition(.opacity)
            }
        }
    }
}

// MARK: - 5. A written note

/// A short letter from Otto on lined paper (App Review pass, 2026-09-29,
/// Aziz: "restyle as a written note"). It was a voice note: a play button,
/// a waveform and "0:07" that played nothing, which a reviewer reads as a
/// broken feature. Same words, now simply written down. The case keeps its
/// name, `voiceNote`, so saved state and the gallery still line up.
private struct VoiceNoteScene: View {
    let doors: InterventionDoors
    let meditatedToday: Bool

    /// Just the P.S. (Aziz, 2026-10-04: "P.S., you still haven't meditated
    /// today -Otto", and the "hey, it's me... promise." note above it cut).
    /// With a session today that would be untrue, so it asks instead.
    private var lines: [String] {
        meditatedToday
            ? ["P.S. meditate", "with me first?"]
            : ["P.S. you still", "haven't meditated", "today."]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LinedNote(lines: lines, signature: "-Otto") {
                Image("OttoHead")
                    .resizable()
                    .scaledToFit()
            }
            Spacer()
            DoorButtons(doors: doors)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .keepsDarkStatusBar()
    }
}

/// "Not now" after the note gets a second note, not the valley (Aziz,
/// 2026-10-04): "slightly disappointed, but if you insist. -Otto", with
/// frustrated Otto peeking in and the usual 5, 10, 30 and "let's meditate".
private struct NoteHowLongScreen: View {
    @ObservedObject var block: BlockController
    let onMeditate: () -> Void
    let onClose: () -> Void
    var rehearsal = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LinedNote(lines: ["slightly", "disappointed,", "but if you", "insist."], signature: "-Otto") {
                // His frustrated sitting drawing, cut to head and shoulders.
                Image("OttoFrustratedSit")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84, alignment: .top)
                    .clipped()
            }
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(HowLongScreen.options, id: \.self) { m in
                        Button {
                            // The gallery rehearses with nothing real happening.
                            if !rehearsal { block.takePass(minutes: m) }
                            onClose()
                        } label: {
                            Text("\(m) min")
                                .font(DisplayFont.display(16, .bold))
                                .lineLimit(1)
                                .foregroundStyle(AppColor.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(AppColor.backgroundSecondary, in: Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open my apps for \(m) minutes")
                    }
                }
                .padding(.bottom, 4)
                Button("Nah, actually let's meditate", action: onMeditate)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 12)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .keepsDarkStatusBar()
    }
}

/// A note from Otto on ruled paper with a red margin, tilted a little, with
/// Otto (`peek`) at its corner. Shared by the note screen and its "Not now".
private struct LinedNote<Peek: View>: View {
    let lines: [String]
    let signature: String
    @ViewBuilder var peek: () -> Peek

    private static var rule: CGFloat { 38 }
    /// A ruled line for every written one, the signature, and one spare.
    private var rows: Int { lines.count + 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The paper: cream, ruled, a red margin line.
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { _ in
                    Rectangle().fill(AppColor.skyDeep.opacity(0.28))
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                        .padding(.top, Self.rule - 1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            Rectangle().fill(Color(red: 0.86, green: 0.45, blue: 0.42).opacity(0.5))
                .frame(width: 1.5)
                .padding(.leading, 44)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.custom("MarkerFelt-Wide", size: 25))
                        .frame(height: Self.rule, alignment: .bottom)
                }
                Text(signature)
                    .font(.custom("MarkerFelt-Wide", size: 25))
                    .frame(height: Self.rule, alignment: .bottom)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 28)
            }
            .foregroundStyle(AppColor.textPrimary)
            .padding(.leading, 58)
            .padding(.top, 20 - 8)
        }
        .frame(width: 290, height: 20 + Self.rule * CGFloat(rows) + 18, alignment: .top)
        .background(AppColor.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 10)
        .rotationEffect(.degrees(2))
        .overlay(alignment: .bottomTrailing) {
            peek()
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(-8))
                .offset(x: 30, y: 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A note from Otto: " + lines.joined(separator: " ") + " " + signature)
    }
}

// MARK: - 6. A note on the fridge

/// A sticky note (Aziz, 2026-10-04): "Reminder: meditate today", and when
/// there is a session today, "Reminder: five minutes first". Its "Not now"
/// is a second sticky note (`StickyHowLongScreen`).
private struct FridgeNoteScene: View {
    let doors: InterventionDoors
    let meditatedToday: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            StickyNote(text: meditatedToday ? "Reminder:\nmeditate\nfirst" : "Reminder:\nmeditate\ntoday")
            Spacer()
            DoorButtons(doors: doors)
        }
        .frame(maxWidth: .infinity)
        .background(AppColor.backgroundSecondary.ignoresSafeArea())
        .keepsDarkStatusBar()
    }
}

/// "Not now" after the sticky note: a second one, "Make sure to meditate
/// later", over the usual 5, 10, 30 and "let's meditate" (Aziz, 2026-10-04).
private struct StickyHowLongScreen: View {
    @ObservedObject var block: BlockController
    let onMeditate: () -> Void
    let onClose: () -> Void
    var rehearsal = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            StickyNote(text: "Make sure to\nmeditate\nlater")
            Spacer()
            PassOptions(block: block, onMeditate: onMeditate, onClose: onClose, rehearsal: rehearsal)
        }
        .frame(maxWidth: .infinity)
        .background(AppColor.backgroundSecondary.ignoresSafeArea())
        .keepsDarkStatusBar()
    }
}

/// A yellow sticky note, tilted, with Otto peeking from behind its corner.
private struct StickyNote: View {
    let text: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(text)
                .font(.custom("MarkerFelt-Wide", size: 34))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 250, height: 250)
                .background(AppColor.accentGold.opacity(0.55))
                .background(AppColor.backgroundPrimary)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 10)
                .rotationEffect(.degrees(-3))
            Image("OttoHead")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(10))
                .offset(x: 46, y: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A sticky note from Otto: " + text.replacingOccurrences(of: "\n", with: " "))
    }
}

/// The usual answers to "Not now", for the note screens that keep their own
/// look: 5, 10 or 30 min, each opening the apps at once, and "let's meditate".
private struct PassOptions: View {
    @ObservedObject var block: BlockController
    let onMeditate: () -> Void
    let onClose: () -> Void
    var rehearsal = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(HowLongScreen.options, id: \.self) { m in
                    Button {
                        // The gallery rehearses with nothing real happening.
                        if !rehearsal { block.takePass(minutes: m) }
                        onClose()
                    } label: {
                        Text("\(m) min")
                            .font(DisplayFont.display(16, .bold))
                            .lineLimit(1)
                            .foregroundStyle(AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(AppColor.backgroundPrimary, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open my apps for \(m) minutes")
                }
            }
            .padding(.bottom, 4)
            Button("Nah, actually let's meditate", action: onMeditate)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.bottom, 12)
    }
}

// MARK: - 9. Otto's sign

private struct SignScene: View {
    let doors: InterventionDoors
    var body: some View {
        ValleyStage(pose: "OttoWave", line: "", doors: doors) { size, ottoTop in
            Text("Meditate\nfirst :)")
                .font(.custom("MarkerFelt-Wide", size: 28))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.textSecondary, lineWidth: 3))
                .rotationEffect(.degrees(-4))
                .position(x: size.width / 2, y: max(150, ottoTop - 70))
        }
    }
}

// MARK: - 12. Two doors, playful

private struct TwoDoorsScene: View {
    let doors: InterventionDoors
    var body: some View {
        let day = DayLight.now
        GeometryReader { geo in
            let size = geo.size
            let ottoHeight = min(220, size.height * 0.27)
            let ottoBottom = size.height - 130
            ZStack {
                ValleyScene(progress: 0, showsFigure: false, clock: true)
                let drawn = ottoHeight / OttoAuraFigure.bodyShare
                Image(OttoAuraFigure.asset(.steady))
                    .resizable()
                    .scaledToFit()
                    .frame(height: drawn)
                    .position(x: size.width / 2,
                              y: ottoBottom + drawn * (1 - OttoAuraFigure.baseline) - drawn / 2)
                VStack {
                    Spacer(minLength: 0)
                    OttoLine(text: "What do you want more right now?", progress: DayLight.clockProgress())
                }
                .frame(width: min(size.width - 56, 330), height: max(0, ottoBottom - ottoHeight - 8 - 110))
                .position(x: size.width / 2, y: 110 + max(0, ottoBottom - ottoHeight - 8 - 110) / 2)
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Button("Calm", action: doors.meditate)
                            .buttonStyle(PrimaryButtonStyle())
                        if doors.canPass {
                            Button("The scroll", action: doors.notNow)
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.bottom, 30)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - 13. The countdown

private struct CountdownScene: View {
    let doors: InterventionDoors
    @State private var start = Date()
    private static let seconds = 10

    var body: some View {
        TimelineView(.periodic(from: start, by: 0.25)) { context in
            let left = max(0, Self.seconds - Int(context.date.timeIntervalSince(start)))
            let done = left == 0
            ValleyStage(pose: "OttoSit", line: done ? "Still want it? Up to you." : "Breathe with me while it counts.",
                        doors: InterventionDoors(canPass: done, shortest: doors.shortest, meditate: doors.meditate,
                                                 meditateFor: doors.meditateFor, notNow: doors.notNow),
                        primary: "Sit instead", secondary: "Open my apps") { size, _ in
                VStack(spacing: 4) {
                    Text("\(left)")
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(done ? "Your call" : "Counting down")
                        .font(.system(size: 15, weight: .medium))
                }
                .onValley()
                .position(x: size.width / 2, y: 118)
            }
        }
    }
}

// MARK: - 14. An affirmation

private struct AffirmationScene: View {
    let doors: InterventionDoors

    private static let lines = [
        "I start my day on purpose.",
        "I choose where my attention goes.",
        "A clear head is my first win today.",
        "I can be calm and busy at once.",
    ]

    private var line: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return Self.lines[day % Self.lines.count]
    }

    var body: some View {
        let n = doors.shortest
        ValleyStage(pose: "OttoGreet", line: "",
                    doors: InterventionDoors(canPass: doors.canPass, shortest: n,
                                             meditate: { doors.meditateFor(n) },
                                             meditateFor: doors.meditateFor, notNow: doors.notNow),
                    primary: "Sit with it, \(n) min") { size, ottoTop in
            VStack(spacing: 6) {
                Text("Today's line")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
                Text(line)
                    .font(DisplayFont.display(24))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(AppColor.backgroundPrimary.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .position(x: size.width / 2, y: max(170, ottoTop - 80))
        }
    }
}

// MARK: - 16. A sticker

private struct StickerScene: View {
    let doors: InterventionDoors
    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
            VStack(alignment: .leading, spacing: 10) {
                Image("OttoSit")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 170)
                    .shadow(color: .white, radius: 0, x: 2, y: 2)
                    .shadow(color: .white, radius: 0, x: -2, y: -2)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
                ChatBubble(text: "sent you a sticker. join me?")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            DoorButtons(doors: doors)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .keepsDarkStatusBar()
    }
}

// MARK: - 19. One minute (as long as the shortest session that counts)

private struct OneMinuteScene: View {
    let doors: InterventionDoors
    var body: some View {
        let n = doors.shortest
        let line = "Meditate first. I'll keep time."
        ValleyStage(pose: "OttoSit", line: line,
                    doors: InterventionDoors(canPass: doors.canPass, shortest: n,
                                             meditate: { doors.meditateFor(n) },
                                             meditateFor: doors.meditateFor, notNow: doors.notNow),
                    primary: "Let's meditate")
    }
}

// MARK: - 20. Otto asks why

private struct AskWhyScene: View {
    let doors: InterventionDoors
    @State private var answer: String?

    private static let replies: [(String, String)] = [
        ("Bored", "Bored is a good time to sit. Meditate first?"),
        ("Checking something", "It'll still be there after a short session."),
        ("Habit", "Habits are why I'm here. One quick session?"),
    ]

    var body: some View {
        let line = answer.flatMap { a in Self.replies.first { $0.0 == a }?.1 } ?? "What are you opening it for?"
        ValleyStage(pose: "OttoAsk", line: line, doors: doors) { size, ottoTop in
            if answer == nil {
                HStack(spacing: 8) {
                    ForEach(Self.replies, id: \.0) { reply in
                        Button(reply.0) { withAnimation(.easeOut(duration: 0.2)) { answer = reply.0 } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                    }
                }
                .position(x: size.width / 2, y: size.height - 180)
            }
        }
    }
}

// MARK: - Not now

/// "Fine. How long do you need?" (`mockups/block-v1.html`, section 2, last
/// screen). The apps open for that long, then Otto holds them again.
private struct HowLongScreen: View {
    @ObservedObject var block: BlockController
    let onMeditate: () -> Void
    let onClose: () -> Void
    /// The unblock-screens gallery: skip the real pass and Screen Time call.
    var rehearsal = false
    /// What Otto says, and the meditate button, after the screen that led
    /// here (`line(after:)`).
    var line = "Fine... how much time do you need?"
    var meditateLabel = "Nah, actually let's meditate"
    var pose = "OttoFrustratedSit"

    /// The standing screen asks "Are you sure?", so its "Not now" gets a
    /// reply to that (Aziz, 2026-10-04). Every other screen gets the usual.
    /// Each screen's reply to "Not now" lives with the screens
    /// (`InterventionKind.notNowReply`, Shared, tested).
    static func line(after kind: InterventionKind, context: InterventionContext) -> String {
        kind.notNowReply(context)
    }

    /// Frustrated after most screens; awake and easy after the gentle ones,
    /// whose reply is not a complaint.
    static func pose(after kind: InterventionKind) -> String {
        switch kind {
        case .wakingOtto, .affirmation, .valley, .askWhy, .bedtime: return "OttoAwake"
        default: return "OttoFrustratedSit"
        }
    }

    static func meditateLabel(after kind: InterventionKind) -> String {
        kind == .standing ? "Nvm, let's meditate" : "Nah, actually let's meditate"
    }

    /// One row, three choices, each opening the apps for that long at once
    /// (Aziz, 2026-10-04: 5, 10, 30, matching the text thread; it was 10, 20,
    /// 30 with a separate "Open my apps" button).
    static let options = [5, 10, 30]

    // Otto put out by the "Not now" (Aziz, 2026-10-04): sitting, arms down,
    // a sideways look and a small frown, the drawing from
    // `mockups/otto-v3/otto-frustrated.png` (`pose`, by the screen before).

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // His usual place and size, as every other Otto screen draws him
            // (`ValleyStage`), sitting in the meadow rather than small and
            // high in front of the mountains (Aziz, 2026-10-04).
            let ottoHeight = min(230, size.height * 0.28)
            let ottoBottom = size.height - 150
            let ottoTop = ottoBottom - ottoHeight
            ZStack {
                ValleyScene(progress: 0, showsFigure: false, clock: true)
                VStack {
                    Spacer(minLength: 0)
                    OttoLine(text: line, progress: DayLight.clockProgress())
                }
                .frame(width: min(size.width - 56, 330), height: max(0, ottoTop - 8 - 110))
                .position(x: size.width / 2, y: 110 + max(0, ottoTop - 8 - 110) / 2)
                Image(pose)
                    .resizable()
                    .scaledToFit()
                    .frame(height: ottoHeight)
                    .position(x: size.width / 2, y: ottoBottom - ottoHeight / 2)
                VStack(spacing: 10) {
                    Spacer()
                    // Low, just above the buttons it sets, rather than
                    // straight under Otto (Melvin, 2026-09-23).
                    HStack(spacing: 8) {
                        ForEach(Self.options, id: \.self) { m in
                            Button {
                                // The unblock-screens gallery rehearses this
                                // screen with nothing real happening: skip the
                                // real pass so it can never touch a real
                                // blocker or Screen Time.
                                if !rehearsal { block.takePass(minutes: m) }
                                onClose()
                            } label: {
                                Text("\(m) min")
                                    .font(DisplayFont.display(16, .bold))
                                    .lineLimit(1)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                                    .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open my apps for \(m) minutes")
                        }
                    }
                    .padding(.bottom, 4)
                    Button(meditateLabel, action: onMeditate)
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 12)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}
