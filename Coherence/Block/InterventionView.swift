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

    private enum Step { case ask, breath, howLong }
    @State private var step: Step = .ask

    var body: some View {
        ZStack {
            switch step {
            case .ask:
                InterventionScene(kind: kind, context: context, doors: doors)
            case .breath:
                FirmBreath { withAnimation(.easeInOut(duration: 0.3)) { step = .howLong } }
                    .transition(.opacity)
            case .howLong:
                HowLongScreen(block: block, onMeditate: { onMeditate(nil) }, onClose: onClose)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
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
        .statusBarHidden(false)
    }

    /// What "Not now" does here: nothing on Strict, a breath first on Firm.
    private var doors: InterventionDoors {
        let strictness = block.strictnessNow()
        let left = block.passesLeftNow()
        let canPass = strictness != .strict && (left ?? 1) > 0
        let note: String? = {
            if strictness == .strict { return "Strict: a session is the way in." }
            if left == 0 { return "No passes left today." }
            return nil
        }()
        let shortest = block.holding().map(\.minimumMinutes).max() ?? 2
        return InterventionDoors(
            canPass: canPass,
            note: note,
            shortest: shortest,
            meditate: { onMeditate(nil) },
            meditateFor: { onMeditate($0) },
            notNow: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    step = strictness == .firm ? .breath : .howLong
                }
            })
    }
}

/// The two doors, handed to each scene so the scenes can label them.
struct InterventionDoors {
    let canPass: Bool
    let note: String?
    /// The shortest session that opens what is held, in minutes.
    var shortest = 2
    let meditate: () -> Void
    /// A timed session, for the screens that say they will keep time.
    var meditateFor: (Int) -> Void = { _ in }
    let notNow: () -> Void
}

// MARK: - The bottom of every screen

private struct DoorButtons: View {
    let doors: InterventionDoors
    var primary = "Okay, let's meditate"
    var secondary = "Not now"
    var ink: Color = AppColor.textPrimary

    var body: some View {
        VStack(spacing: 6) {
            Button(primary, action: doors.meditate)
                .buttonStyle(PrimaryButtonStyle())
            if doors.canPass {
                Button(secondary, action: doors.notNow)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if let note = doors.note {
                Text(note)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ink.opacity(0.7))
                    .frame(minHeight: 44)
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
            ValleyStage(pose: "OttoWave", line: "Got two minutes for me first?", doors: doors)
        case .textThread:
            TextThreadScene(doors: doors)
        case .faceTime:
            FaceTimeScene(doors: doors)
        case .breatheWithMe:
            BreatheWithMeScene(doors: doors)
        case .voiceNote:
            VoiceNoteScene(doors: doors)
        case .fridgeNote:
            FridgeNoteScene(doors: doors)
        case .stillThere:
            ValleyStage(pose: "OttoAwake", line: "It'll all still be there in two minutes.", doors: doors)
        case .wakingOtto:
            ValleyStage(pose: "OttoSit", line: "Zzz... oh, hey. Morning meditation?", doors: doors) { size, ottoTop in
                Text("z z")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(DayLight.at(0).inkSoft)
                    .position(x: size.width * 0.66, y: ottoTop + 18)
            }
        case .sign:
            SignScene(doors: doors)
        case .streak:
            ValleyStage(pose: "OttoSit",
                        line: "Your streak is at \(context.streak) days. Two minutes keeps it going.",
                        doors: doors) { size, _ in
                Label("\(context.streak)", systemImage: "flame.fill")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.streakBlushText)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(AppColor.backgroundPrimary.opacity(0.9), in: Capsule())
                    .position(x: size.width / 2, y: 72)
            }
        case .glow:
            ValleyStage(pose: "OttoFrustrated", line: "Help me glow? One session today.", doors: doors)
        case .twoDoors:
            TwoDoorsScene(doors: doors)
        case .countdown:
            CountdownScene(doors: doors)
        case .affirmation:
            AffirmationScene(doors: doors)
        case .bedtime:
            ValleyStage(progress: 0.96, pose: "OttoSit", dim: 0.6,
                        line: "Wind down with me? Five minutes, then sleep.",
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

    var body: some View {
        let day = DayLight.at(progress)
        GeometryReader { geo in
            let size = geo.size
            let ottoHeight = min(230, size.height * 0.28)
            let ottoBottom = size.height - 150
            let ottoTop = ottoBottom - ottoHeight
            ZStack {
                ValleyScene(progress: progress, showsFigure: false)
                Image(pose)
                    .resizable()
                    .scaledToFit()
                    .frame(height: ottoHeight)
                    .brightness(dim < 1 ? -(1 - dim) * 0.5 : 0)
                    .position(x: size.width / 2, y: ottoBottom - ottoHeight / 2)
                    .accessibilityHidden(true)
                if !line.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        // The bubble is always cream, so its words are always the
                        // daytime ink: at night the sky's own ink is pale, and
                        // the line vanished into its own bubble.
                        OttoLine(text: line, ink: DayLight.at(0).ink)
                    }
                    .frame(width: min(size.width - 56, 330), height: max(0, ottoTop - 8 - 110))
                    .position(x: size.width / 2, y: 110 + max(0, ottoTop - 8 - 110) / 2)
                }
                extra(size, ottoTop)
                VStack {
                    Spacer()
                    DoorButtons(doors: doors, primary: primary, secondary: secondary,
                                ink: progress > 0.6 ? AppColor.backgroundPrimary : day.ink)
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
    let ink: Color
    var body: some View {
        OttoSpeech(text: text, tail: .bottom, size: 19,
                   ink: ink, stroke: ink.opacity(0.38),
                   fill: AppColor.backgroundPrimary.opacity(0.86),
                   speaking: .constant(false))
            .id(text)
    }
}

// MARK: - 2. A text thread

private struct TextThreadScene: View {
    let doors: InterventionDoors
    @State private var shown = 0

    private let lines = ["yo it's otto", "quick meditation before the scroll?"]

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<min(shown, lines.count), id: \.self) { i in
                        ChatBubble(text: lines[i])
                    }
                    if shown < lines.count { TypingDots() }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            if shown >= lines.count {
                VStack(alignment: .trailing, spacing: 8) {
                    ReplyChip(text: "ok let's go", action: doors.meditate)
                    if doors.canPass {
                        ReplyChip(text: "later, open it", action: doors.notNow)
                    } else if let note = doors.note {
                        Text(note).font(.system(size: 14)).foregroundStyle(AppColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .task {
            for i in 1...lines.count {
                try? await Task.sleep(for: .seconds(i == 1 ? 0.6 : 1.3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { shown = i }
            }
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

private struct ChatBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColor.calmAccent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
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
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(AppColor.backgroundPrimary, in: Capsule())
                .overlay(Capsule().stroke(AppColor.accentGold, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. A FaceTime call

private struct FaceTimeScene: View {
    let doors: InterventionDoors
    @State private var answered = false
    /// Declined with no pass to fall back on: Otto takes it well, and the
    /// camera never turns on (the review of 2026-09-22 caught Decline opening
    /// it).
    @State private var declined = false
    @StateObject private var camera = FrontCamera()
    @State private var said = 0

    var body: some View {
        ZStack {
            if declined {
                ValleyStage(pose: "OttoAwake", line: "No worries. I'm here when you're ready.", doors: doors)
            } else if answered {
                answeredView
            } else {
                ringing
            }
        }
        .ignoresSafeArea()
        .onDisappear { camera.stop() }
    }

    private var ringing: some View {
        ZStack {
            LinearGradient(colors: [AppColor.textPrimary.opacity(0.92), AppColor.textPrimary],
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
                        if doors.canPass { doors.notNow() } else { withAnimation { declined = true } }
                    }
                    Spacer()
                    callButton("Accept", systemImage: "video.fill", color: Color(.systemGreen)) { answer() }
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 70)
            }
        }
    }

    private var answeredView: some View {
        ZStack {
            Color.black
            if camera.running {
                CameraPreview(session: camera.session)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Camera off")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Image("OttoTalk")
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .frame(width: 104, height: 140)
                        .background(LinearGradient(colors: [AppColor.sky, AppColor.calmAccentFill],
                                                   startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.trailing, 16)
                        .padding(.top, 60)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    if said >= 1 { ChatBubble(text: "yo, meditation o'clock") }
                    if said >= 2 { ChatBubble(text: "two minutes, i'll stay on") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                DoorButtons(doors: doors, secondary: "Hang up", ink: .white)
                    .padding(.bottom, 20)
            }
        }
        .task {
            for i in 1...2 {
                try? await Task.sleep(for: .seconds(i == 1 ? 0.8 : 1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { said = i }
            }
        }
    }

    private func answer() {
        withAnimation(.easeInOut(duration: 0.25)) { answered = true }
        Task { await camera.start() }
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

/// The front camera, for the call and nothing else: shown live, never
/// recorded or saved. Asks for the camera the first time a call is answered,
/// which is the one moment the request explains itself.
@MainActor
private final class FrontCamera: ObservableObject {
    let session = AVCaptureSession()
    @Published var running = false

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video),
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        let session = self.session
        await Task.detached { session.startRunning() }.value
        running = session.isRunning
    }

    func stop() {
        let session = self.session
        Task.detached { session.stopRunning() }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - 4. Breathe with me

private struct BreatheWithMeScene: View {
    let doors: InterventionDoors
    @State private var start = Date()

    var body: some View {
        let day = DayLight.at(0)
        GeometryReader { geo in
            let size = geo.size
            let ottoHeight = min(210, size.height * 0.25)
            let ottoBottom = size.height - 150
            ZStack {
                ValleyScene(progress: 0, showsFigure: false)
                BreathCircle(start: start)
                    .frame(width: 200, height: 200)
                    .position(x: size.width / 2, y: size.height * 0.30)
                TimelineView(.periodic(from: start, by: 0.5)) { context in
                    let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 10)
                    Text(t < 5 ? "Breathe in" : "Breathe out")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(day.ink)
                        .position(x: size.width / 2, y: size.height * 0.30)
                }
                Image("OttoSit")
                    .resizable()
                    .scaledToFit()
                    .frame(height: ottoHeight)
                    .position(x: size.width / 2, y: ottoBottom - ottoHeight / 2)
                VStack {
                    Text("One breath with me, then decide.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(day.ink)
                        .padding(.top, 70)
                    Spacer()
                    DoorButtons(doors: doors, ink: day.ink)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - 5. A voice note

private struct VoiceNoteScene: View {
    let doors: InterventionDoors
    @State private var playing: Date?

    private static let bars: [CGFloat] = [0.3, 0.6, 0.9, 0.5, 0.8, 0.35, 0.7, 1.0, 0.55, 0.4, 0.75, 0.3, 0.6, 0.45, 0.85, 0.5]
    private static let length: TimeInterval = 7

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader()
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    playing = Date()
                } label: {
                    TimelineView(.animation(paused: playing == nil)) { context in
                        let progress = playing.map { min(1, context.date.timeIntervalSince($0) / Self.length) } ?? 0
                        HStack(spacing: 10) {
                            Image(systemName: progress > 0 && progress < 1 ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                            HStack(alignment: .center, spacing: 3) {
                                ForEach(Self.bars.indices, id: \.self) { i in
                                    Capsule()
                                        .fill(.white.opacity(Double(i) / Double(Self.bars.count) < progress ? 1 : 0.45))
                                        .frame(width: 4, height: 26 * Self.bars[i])
                                }
                            }
                            Text("0:07").font(.system(size: 14, weight: .medium)).monospacedDigit()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppColor.calmAccent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Otto's voice note")
                Text("\"hey, it's me. two minutes, then it's all yours. promise.\"")
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            DoorButtons(doors: doors)
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
    }
}

// MARK: - 6. A note on the fridge

private struct FridgeNoteScene: View {
    let doors: InterventionDoors

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 6) {
                    Text("Sit first,\nscroll after.")
                        .font(.custom("MarkerFelt-Wide", size: 36))
                        .multilineTextAlignment(.center)
                    Text("O.")
                        .font(.custom("MarkerFelt-Wide", size: 28))
                }
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
            Spacer()
            DoorButtons(doors: doors)
        }
        .frame(maxWidth: .infinity)
        .background(AppColor.backgroundSecondary.ignoresSafeArea())
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
        let day = DayLight.at(0)
        GeometryReader { geo in
            let size = geo.size
            let ottoHeight = min(220, size.height * 0.27)
            let ottoBottom = size.height - 130
            ZStack {
                ValleyScene(progress: 0, showsFigure: false)
                Image("OttoCurious")
                    .resizable()
                    .scaledToFit()
                    .frame(height: ottoHeight)
                    .position(x: size.width / 2, y: ottoBottom - ottoHeight / 2)
                VStack {
                    Spacer(minLength: 0)
                    OttoLine(text: "What do you want more right now?", ink: day.ink)
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
                        doors: InterventionDoors(canPass: done && doors.canPass, note: done ? doors.note : nil,
                                                 shortest: doors.shortest, meditate: doors.meditate,
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
                .foregroundStyle(DayLight.at(0).ink)
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
        let n = max(2, doors.shortest)
        ValleyStage(pose: "OttoGreet", line: "",
                    doors: InterventionDoors(canPass: doors.canPass, note: doors.note, shortest: n,
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
    }
}

// MARK: - 19. One minute (as long as the shortest session that counts)

private struct OneMinuteScene: View {
    let doors: InterventionDoors
    var body: some View {
        let n = doors.shortest
        let line = n == 1 ? "Just one minute. I'll keep time." : "Just \(n) minutes. I'll keep time."
        ValleyStage(pose: "OttoSit", line: line,
                    doors: InterventionDoors(canPass: doors.canPass, note: doors.note, shortest: n,
                                             meditate: { doors.meditateFor(n) },
                                             meditateFor: doors.meditateFor, notNow: doors.notNow),
                    primary: n == 1 ? "One minute, go" : "\(n) minutes, go")
    }
}

// MARK: - 20. Otto asks why

private struct AskWhyScene: View {
    let doors: InterventionDoors
    @State private var answer: String?

    private static let replies: [(String, String)] = [
        ("Bored", "Bored is a good time to sit. Two minutes?"),
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

/// Firm: ten seconds of breathing with Otto before a pass (CONSISTENCY.md).
private struct FirmBreath: View {
    let onDone: () -> Void
    @State private var start = Date()

    var body: some View {
        let day = DayLight.at(0)
        GeometryReader { geo in
            ZStack {
                ValleyScene(progress: 0, showsFigure: false)
                BreathCircle(start: start)
                    .frame(width: 200, height: 200)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.34)
                TimelineView(.periodic(from: start, by: 0.25)) { context in
                    let t = context.date.timeIntervalSince(start)
                    VStack(spacing: 6) {
                        Text(t < 5 ? "Breathe in" : "Breathe out")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("\(max(0, 10 - Int(t)))")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(day.ink)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.34)
                }
                VStack {
                    Text("Ten seconds with me first.")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(day.ink)
                        .padding(.top, 80)
                    Spacer()
                    Image("OttoSit")
                        .resizable()
                        .scaledToFit()
                        .frame(height: min(210, geo.size.height * 0.25))
                        .padding(.bottom, 120)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            onDone()
        }
    }
}

/// "No worries. How long do you need?" (`mockups/block-v1.html`, section 2,
/// last screen). The apps open for that long, then Otto holds them again.
private struct HowLongScreen: View {
    @ObservedObject var block: BlockController
    let onMeditate: () -> Void
    let onClose: () -> Void

    @State private var minutes = 10
    private static let options = [5, 10, 15, 30, 60]

    var body: some View {
        let ink = DayLight.at(0).ink
        let left = block.passesLeftNow()
        GeometryReader { geo in
            let size = geo.size
            let ottoHeight = min(170, size.height * 0.19)
            // Seated on the near ridge, where the meadow begins, not afloat.
            let ottoBottom = size.height * 0.60
            let ottoTop = ottoBottom - ottoHeight
            ZStack {
                ValleyScene(progress: 0, showsFigure: false)
                VStack {
                    Spacer(minLength: 0)
                    OttoLine(text: "No worries. How long do you need?", ink: ink)
                }
                .frame(width: min(size.width - 56, 330), height: max(0, ottoTop - 8 - 110))
                .position(x: size.width / 2, y: 110 + max(0, ottoTop - 8 - 110) / 2)
                Image("OttoAwake")
                    .resizable()
                    .scaledToFit()
                    .frame(height: ottoHeight)
                    .position(x: size.width / 2, y: ottoBottom - ottoHeight / 2)
                VStack(spacing: 12) {
                    // Two rows: five labels in one run wrapped "15 min" onto
                    // two lines on a 402pt phone.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(Self.options, id: \.self) { m in
                            Button {
                                minutes = m
                            } label: {
                                Text(m == 60 ? "1 hour" : "\(m) min")
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(minutes == m ? AppColor.accentGold.opacity(0.2)
                                                             : AppColor.backgroundSecondary, in: Capsule())
                                    .overlay(Capsule().stroke(minutes == m ? AppColor.accentGold : .clear,
                                                              lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let left {
                        Text(left == 1 ? "1 pass left today" : "\(left) passes left today")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(16)
                .background(AppColor.backgroundPrimary.opacity(0.95),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .frame(width: size.width)
                .position(x: size.width / 2, y: ottoBottom + 12 + 70)
                VStack(spacing: 6) {
                    Spacer()
                    Button(minutes == 60 ? "Open my apps for an hour" : "Open my apps for \(minutes) min") {
                        block.takePass(minutes: minutes)
                        onClose()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Actually, let's meditate", action: onMeditate)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.8))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 12)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}
