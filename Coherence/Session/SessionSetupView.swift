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

    /// The one optional decision, behind the defaults line.
    @State private var showOptions = false
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The same valley, at the top of its day. Begin does not
                // change scenes: the controls clear, the ring fades up, and
                // the sun starts moving. Otto sits exactly where he will be
                // sitting a second later.
                ValleyScene(progress: 0, pose: .greeting)

                let day = DayLight.at(0)

                VStack(spacing: 6) {
                    Text("Ready when you are.")
                        .font(DisplayFont.display(24, .heavy))
                        .foregroundStyle(day.ink)
                    Text("Start your YouTube or Spotify audio first. 808 stays open the whole time.")
                        .font(AppFont.caption)
                        .foregroundStyle(day.inkSoft)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.175)

                VStack(spacing: 8) {
                    Spacer()
                    Button { showOptions = true } label: {
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
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .overlay { if countdown != nil { countdownOverlay } }
        .overlay(alignment: .topLeading) {
            Button("Cancel") { cancel() }
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(DayLight.at(0).ink.opacity(0.55))
                .padding(.horizontal, 20).padding(.top, 14)
        }
        .sheet(isPresented: $showOptions) { SessionOptionsView(soundID: $soundID) }
        .sheet(isPresented: $showFocusSetup) { FocusSetupSheet() }
        // NOT a permission prompt on appear. Somebody who opened this screen
        // is about to close their eyes, and a system dialog is the single
        // worst thing to put in front of them. The prompt comes when they
        // reach for the switch, which is the moment it is about anything.
        .onAppear { focus.refreshStatus() }
        // They can change Focus from Control Center while this screen is up,
        // so the switch is re-read rather than remembered.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { focus.refreshStatus() }
        }
    }

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

/// The sound sheet, opened from the "Open · Silence ›" line.
///
/// Ordering is the design (review 2026-08-05): the guided journey leads because
/// it is the only original content we own and the one asset worth paying for;
/// Silence sits under it as the stated DEFAULT, outside the scrolling list so
/// eleven sounds can never bury it; then three groups, each internally ordered
/// so scrolling reads as a spectrum rather than a menu — nature by familiarity,
/// brainwave deepest-first, tones low-to-high.
///
/// Every row previews. Selecting a sound with no way to hear it first meant
/// finding out mid-meditation.
struct SessionOptionsView: View {
    @Binding var soundID: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tone = ToneEngine()
    @EnvironmentObject private var store: Store
    @State private var showPlans = false
    @State private var plansPlan: SubscriptionPlan = .monthly

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sessions run open-ended. End yours whenever you're done, and anything you play in another app keeps playing.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(GuidedCatalog.all) { guidedCard($0) }

                    silenceCard

                    group("Nature", NatureCatalog.all.map {
                        (id: $0.id, title: $0.title, subtitle: $0.subtitle) })
                    group("Brainwave · deepest first", brainwave.map {
                        (id: $0.id, title: $0.title, subtitle: $0.subtitle) })
                    group("Tones · low to high", tones.map {
                        (id: $0.id, title: $0.title, subtitle: $0.subtitle) })
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { tone.stop(); dismiss() }.tint(AppColor.accentGoldText)
                }
            }
            .onDisappear { tone.stop() }
            .fullScreenCover(isPresented: $showPlans) {
                PaywallScreen(placement: "guided_lock", plan: $plansPlan) { _ in
                    showPlans = false
                }
            }
        }
    }

    // MARK: - Guided (leads; deliberately not shaped like a sound row)

    private func guidedCard(_ preset: GuidedPreset) -> some View {
        let selected = soundID == preset.id
        // The only content 808 owns, so the only content worth gating. Nature,
        // frequency, silence and anything the user plays in another app all
        // stay free.
        let unlocked = store.entitlements.guidedTrack
        return Button {
            guard unlocked else {
                Analytics.track(.lockedTapped(signal: "guided"))
                showPlans = true
                return
            }
            select(preset.id)
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(RadialGradient(colors: [AppColor.accentGold.opacity(0.55),
                                                      AppColor.accentGold.opacity(0.10)],
                                             center: .init(x: 0.5, y: 0.38),
                                             startRadius: 2, endRadius: 40))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColor.accentGold.opacity(0.5), lineWidth: 1)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColor.accentGoldText)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Guided journey")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(AppColor.accentGoldText)
                    Text(preset.title)
                        .font(AppFont.callout.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    // "narration", not "session" — the voice ends at 25:30 but
                    // the session keeps measuring until you end it on the Watch.
                    Text("\(preset.subtitle.replacingOccurrences(of: "· 25 min", with: "· \(preset.durationSec / 60) min narration"))")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                if unlocked {
                    previewButton(preset.id, prominent: true)
                    if selected { checkmark }
                } else {
                    LockPill()
                }
            }
            .padding(14)
            .background(
                LinearGradient(colors: [AppColor.accentGold.opacity(0.14),
                                        AppColor.accentGold.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColor.accentGold.opacity(selected ? 1 : 0.45),
                        lineWidth: selected ? 1.8 : 1))
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: - Silence (the default, pinned above the list)

    private var silenceCard: some View {
        let selected = soundID.isEmpty
        return Button { select("") } label: {
            HStack(spacing: 12) {
                Image(systemName: "speaker.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.accentGoldText)
                    .frame(width: 32, height: 32)
                    .background(AppColor.accentGold.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Silence")
                        .font(AppFont.callout.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Just the measurement, or your own audio")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                Text("DEFAULT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(AppColor.textOnAccent)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(AppColor.accentGold, in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(AppColor.accentGold.opacity(selected ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? AppColor.accentGold : AppColor.textSecondary.opacity(0.25),
                        lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: - Groups

    private func group(_ label: String,
                       _ items: [(id: String, title: String, subtitle: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: label)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().overlay(AppColor.textSecondary.opacity(0.1)) }
                    soundRow(id: item.id, title: item.title, subtitle: item.subtitle)
                }
            }
            .padding(.horizontal, 13)
            .background(AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func soundRow(id: String, title: String, subtitle: String) -> some View {
        Button { select(id) } label: {
            HStack(spacing: 12) {
                previewButton(id, prominent: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                if soundID == id { checkmark }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(CardButtonStyle())
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppColor.accentGoldText)
    }

    /// Audition without committing the whole session to it.
    private func previewButton(_ id: String, prominent: Bool) -> some View {
        let playing = tone.playingID == id
        let lit = playing || soundID == id
        return Button { preview(id) } label: {
            Image(systemName: playing ? "stop.fill" : "play.fill")
                .font(.system(size: prominent ? 11 : 10, weight: .bold))
                .foregroundStyle(lit ? AppColor.accentGold : AppColor.textSecondary)
                .frame(width: prominent ? 32 : 30, height: prominent ? 32 : 30)
                .background(Circle().stroke(
                    lit ? AppColor.accentGold : AppColor.textSecondary.opacity(0.3),
                    lineWidth: 1.5))
                .background(Circle().fill(playing ? AppColor.accentGold.opacity(0.12) : .clear))
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: - Actions

    private func select(_ id: String) {
        tone.stop(reason: "sound picked")
        soundID = id
    }

    /// Previewing also selects, so what you hear is what you'll get.
    private func preview(_ id: String) {
        if tone.playingID == id {
            tone.stop(reason: "preview stopped")
            return
        }
        soundID = id
        if let p = FrequencyCatalog.preset(id: id) {
            tone.play(p, method: .isochronic)
        } else if let np = NatureCatalog.preset(id: id) {
            tone.playNature(np)
        } else if let gp = GuidedCatalog.preset(id: id) {
            tone.playGuided(gp)
        }
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
