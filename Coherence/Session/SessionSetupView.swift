import SwiftUI
import SwiftData

/// Begin a session. Deliberately almost empty.
///
/// One promise: sit down and 808 sits with you. No practice type, no length,
/// no guidance, no pre-session reading. Open-ended and silent are the
/// defaults, stated on one tappable line so nobody has to decide and nobody
/// feels trapped.
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

    /// Seconds left before the session starts, or nil when not counting.
    /// Phone-initiated sessions only: starting from the wrist means you are
    /// already sitting, so the Watch's own Begin stays immediate (Melvin,
    /// 2026-09-01).
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?

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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ONE scene, for both states. Never rebuilt, never replaced:
                // it owns the Rive rig, and swapping it would restart him.
                ValleyScene(progress: 0, pose: .greeting, ottoInCorner: choosingSound)

                let day = DayLight.at(0)

                if choosingSound {
                    asking(day: day, in: geo.size)
                    SoundChoiceList(soundID: $soundID, top: Self.listTop)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    greeting(day: day, in: geo.size)
                    readyControls(day: day)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: choosingSound)
        }
        .ignoresSafeArea()
        .overlay { if countdown != nil { countdownOverlay } }
        .overlay(alignment: .topLeading) {
            Button(choosingSound ? "Back" : "Cancel") {
                if choosingSound { choosingSound = false } else { cancel() }
            }
            .font(AppFont.callout.weight(.semibold))
            .foregroundStyle(DayLight.at(0).ink.opacity(0.55))
            .padding(.horizontal, 20).padding(.top, 14)
        }
        .sheet(isPresented: $showFocusSetup) { FocusSetupSheet() }
        // NOT a permission prompt on appear. Somebody who opened this screen
        // is about to close their eyes, and a system dialog is the single
        // worst thing to put in front of them. The prompt comes when they
        // reach for the switch, which is the moment it is about anything.
        .onAppear { focus.refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { focus.refreshStatus() }
        }
    }

    /// Where the sound list starts. Below Otto's corner perch, so his face is
    /// never behind a pill.
    private static let listTop: CGFloat = 196

    /// The switch, or the sentence, depending on whether the shortcut that
    /// makes a switch possible exists on this build. See `FocusShortcut`:
    /// no app can turn on Do Not Disturb, and a switch that cannot work must
    /// not be drawn.
    @ViewBuilder
    private func silenceControl(ink: Color) -> some View {
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
                        tint: focus.silenced ? AppColor.calmAccent : AppColor.textPrimary) {
                    Toggle("", isOn: .constant(focus.silenced))
                        .labelsHidden()
                        .tint(AppColor.calmAccent)
                        .allowsHitTesting(false)
                        .scaleEffect(0.82)
                        .frame(width: 42)
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

    private func greeting(day: DayLight, in size: CGSize) -> some View {
        let speaks = SitLayout.ottoTop(in: size) - 8
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            OttoSpeech(text: "Ready when you are. Start any YouTube or Spotify audio first.",
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

    private func readyControls(day: DayLight) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Button { choosingSound = true } label: {
                SitPill(glyph: "\u{266A}", label: "Sound") {
                    HStack(spacing: 2) {
                        Text(SoundCatalog.title(for: soundID.isEmpty ? nil : soundID) ?? "Silence")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                        Text("\u{203A}")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            silenceControl(ink: day.ink)

            Button("Begin", action: begin)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    /// "Open · Silence ›" — exactly what happens if you just tap Begin.
    private var defaultsLine: String {
        let sound = SoundCatalog.title(for: soundID.isEmpty ? nil : soundID) ?? "Silence"
        return "Open · \(sound)  ›"
    }

    /// Five seconds to put the phone down and sit, then the Watch is told to
    /// start. Tapping Begin used to start measuring while you were still
    /// getting comfortable, and the first half-minute of every phone-started
    /// session was the motion of settling in.
    private var countdownOverlay: some View {
        ZStack {
            AppColor.backgroundPrimary.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(countdown.map(String.init) ?? "")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGoldText)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("Get comfortable.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                Button("Cancel") { cancelCountdown() }
                    .font(AppFont.caption.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.top, 26)
            }
        }
        .transition(.opacity)
    }

    private func begin() {
        countdownTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { countdown = 5 }
        countdownTask = Task { @MainActor in
            while let n = countdown, n > 0 {
                // A cancelled sleep THROWS and `try?` swallows it, so without
                // this guard cancelling would fall straight through and start
                // the session anyway. Same trap that once killed guided audio
                // a second into a session.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.15)) { countdown = n - 1 }
            }
            guard !Task.isCancelled else { return }
            startNow()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation(.easeOut(duration: 0.2)) { countdown = nil }
    }

    private func startNow() {
        let id = soundID.isEmpty ? nil : soundID
        coordinator.begin(mode: SoundCatalog.mode(for: id),
                          trackID: nil,
                          plannedDurationSec: nil,          // open-ended, always
                          hapticsEnabled: preferences.first?.hapticsEnabled ?? true,
                          soundID: id)
        dismiss()
    }
}

/// One control on the meadow: a glyph, a label, and whatever the row owns on
/// the right. Cream rather than clear, because the meadow underneath is a
/// mid-tone green with flowers in it and text has to survive that.
struct SitPill<Trailing: View>: View {
    let glyph: String
    let label: String
    var tint: Color = AppColor.textPrimary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(glyph)
                .font(.system(size: 15))
                .foregroundStyle(tint.opacity(0.65))
                .frame(width: 18)
            Text(label)
                .font(DisplayFont.display(14.5))
                .foregroundStyle(tint)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppColor.backgroundPrimary.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
}

/// The one-time add.
///
/// Two taps rather than the four-step app automation an earlier draft asked
/// for: a shortcut published to a signed iCloud link installs from the link
/// itself, with no Allow Untrusted Shortcuts detour. The sheet never appears
/// again afterwards.
struct FocusSetupSheet: View {
    @ObservedObject private var focus = FocusShortcut.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One-time setup")
                .font(DisplayFont.display(22, .heavy))
                .foregroundStyle(AppColor.textPrimary)
            Text("Apple only lets Shortcuts switch Do Not Disturb. Add ours once and this button works from then on.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                step(1, "Tap Add shortcut below.")
                step(2, "Shortcuts opens. Tap Add. Do it for both.")
                step(3, "You land back here, silenced.")
            }
            .padding(.top, 18)

            Spacer()

            Button("Add shortcut") {
                Task {
                    await focus.openInstall(FocusShortcut.silenceInstallURL)
                    focus.markInstalled()
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Not now") { dismiss() }
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .padding(AppMetrics.screenPadding)
        .screenBackground()
        .presentationDetents([.height(380)])
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.accentGoldText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(AppColor.trace))
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

    @StateObject private var tone = ToneEngine()
    @Environment(\.dismiss) private var dismiss

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
            Button("Done") { tone.stop(reason: "sound chosen"); dismiss() }
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
