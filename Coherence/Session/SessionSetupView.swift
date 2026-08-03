import SwiftUI
import WatchConnectivity

/// Pre-session setup, v4 (design review 2026-08): everything on the table, one
/// glance each. Practice cards carry the science ("2 signals / 3 signals"),
/// length is one chip row, the four sound worlds are always visible as a 2×2
/// grid, and the selected category's tracks fill the space between the grid
/// and the pinned coherence row + Begin button — scrolling inside their box,
/// never pushing the layout around.
///
/// Belly posture coaching (supine ≫ seated, Hughes et al. 2020): a one-line
/// teal reminder above Begin, plus the full steps behind the ⓘ on the card.
struct SessionSetupView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @StateObject private var tone = ToneEngine()
    private enum SoundCategory: CaseIterable { case silence, guided, frequency, nature }
    @State private var soundCategory: SoundCategory = .silence
    /// Selected preset id within the lit category (nil = silence).
    @State private var soundID: String? = nil
    /// Delivery for beat presets: false = Speaker (isochronic), true = Headphones (binaural).
    @State private var headphones = false

    @State private var belly = false
    @State private var showPostureSheet = false
    /// Opt-in camera coherence check (Phase 9): a ~45 s finger-on-camera pulse
    /// read before and after the session, shown as a differential.
    @AppStorage("coherenceCheckEnabled") private var coherenceCheck = false
    /// Presenting the BEFORE read; Begin continues when it closes.
    @State private var showPreMeasure = false
    @State private var preSnapshot: CoherenceAnalyzer.Snapshot?
    /// Selected preset length in minutes; nil = open-ended (end from the Watch).
    @State private var durationMinutes: Int? = 10
    @State private var isCustom = false
    @State private var customText = "20"
    @FocusState private var customFocused: Bool

    private let durationOptions: [Int?] = [2, 5, 10, 15, nil]

    private var customValue: Int? {
        guard let n = Int(customText.trimmingCharacters(in: .whitespaces)), n >= 1 else { return nil }
        return min(n, 600)
    }

    private var effectiveMinutes: Int? { isCustom ? customValue : durationMinutes }

    private var activeGuided: GuidedPreset? {
        soundCategory == .guided ? GuidedCatalog.preset(id: soundID) : nil
    }

    private var canBegin: Bool { activeGuided != nil || !isCustom || customValue != nil }

    private let postureSteps = [
        "Lie down or recline — flat on your back works best.",
        "Rest your watch wrist flat on your belly, screen up.",
        "Breathe slowly into your belly: in for about 5 seconds, out for about 5 (~6 breaths a minute).",
        "Let your belly rise and fall, and keep the rest of your body still.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            grabber
            titleRow
            practiceSection
            if activeGuided == nil { lengthSection } else { guidedLengthNote }
            soundGridSection
            trackBox
            coherenceRow
            if belly {
                Text("Lie back · watch wrist flat on your belly · ~6 breaths/min")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.calmAccent)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            beginButton
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.bottom, 10)
        .screenBackground()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { customFocused = false }.tint(AppColor.accentGold)
            }
        }
        .onDisappear { tone.stop(reason: "setup closed") }
        .sheet(isPresented: $showPostureSheet) { postureSheet }
        .fullScreenCover(isPresented: $showPreMeasure, onDismiss: {
            // Whether the read succeeded, failed, or was cancelled, the
            // meditation goes ahead — the check never blocks the session.
            startSession(pre: preSnapshot)
        }) {
            CoherenceMeasureView(label: "Before") { snap in
                preSnapshot = snap
            }
        }
    }

    // MARK: - Header

    private var grabber: some View {
        HStack {
            Spacer()
            Capsule().fill(AppColor.textSecondary.opacity(0.25)).frame(width: 40, height: 4)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("New session")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            watchStatus
        }
    }

    /// Quiet reassurance the Watch will answer — before you commit to lying down.
    private var watchStatus: some View {
        let wc = WCSession.isSupported() ? WCSession.default : nil
        let installed = wc?.isWatchAppInstalled ?? false
        let reachable = wc?.isReachable ?? false
        let (text, color): (String, Color) = reachable
            ? ("Watch ready", AppColor.calmAccent)
            : installed ? ("Watch will wake", AppColor.textSecondary)
                        : ("Watch not paired", AppColor.textSecondary)
        return HStack(spacing: 5) {
            Text(text).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            Circle().fill(color).frame(width: 7, height: 7)
        }
    }

    // MARK: - Practice

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: "Practice")
            HStack(spacing: 10) {
                practiceCard(icon: "leaf", title: "Regular",
                             line1: "Sit any way you like",
                             signals: "2 signals", detail: "stillness + heart",
                             selected: !belly) { belly = false }
                practiceCard(icon: "wind", title: "Belly breathing",
                             line1: "Lie back, watch on belly",
                             signals: "3 signals", detail: "+ breath wave",
                             selected: belly, info: true) { belly = true }
            }
        }
    }

    private func practiceCard(icon: String, title: String, line1: String,
                              signals: String, detail: String, selected: Bool,
                              info: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? AppColor.accentGold : AppColor.textSecondary)
                    Spacer()
                    if info {
                        // A tap gesture nested in a Button gets swallowed —
                        // it needs to be its own button with a real target.
                        Button { showPostureSheet = true } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(width: 30, height: 24, alignment: .trailing)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(line1)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                (Text(signals).foregroundStyle(selected ? AppColor.accentGold : AppColor.textSecondary).bold()
                 + Text(" · \(detail)").foregroundStyle(AppColor.textSecondary))
                    .font(.caption2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppColor.accentGold.opacity(0.08) : AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? AppColor.accentGold : .clear, lineWidth: 1.5))
        }
        .buttonStyle(CardButtonStyle())
    }

    private var postureSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Set up for belly breathing", systemImage: "figure.mind.and.body")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.calmAccent)
            ForEach(Array(postureSteps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColor.backgroundPrimary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(AppColor.calmAccent))
                    Text(step)
                        .font(.footnote)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            Text("Sitting up reads poorly — the app measures your breath from your belly's rise and fall, which is clearest lying down.")
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenBackground()
        .presentationDetents([.medium])
    }

    // MARK: - Length

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: "Length")
            HStack(spacing: 6) {
                ForEach(durationOptions, id: \.self) { opt in
                    chip(label: opt.map { "\($0)" } ?? "Open",
                         selected: !isCustom && opt == durationMinutes) {
                        isCustom = false
                        durationMinutes = opt
                    }
                }
                chip(label: "⋯", selected: isCustom) {
                    isCustom = true
                    customFocused = true
                }
            }
            if isCustom {
                HStack(spacing: 8) {
                    TextField("20", text: $customText)
                        .keyboardType(.numberPad)
                        .focused($customFocused)
                        .multilineTextAlignment(.center)
                        .font(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 68)
                        .padding(.vertical, 6)
                        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.accentGold, lineWidth: 1))
                    Text("minutes").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    if customValue == nil {
                        Text("Type how many minutes").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
    }

    private var guidedLengthNote: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: "Length")
            Label {
                Text("This journey sets its own length — about \((activeGuided?.durationSec ?? 0) / 60) minutes. Your Watch ends with the narration.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } icon: {
                Image(systemName: "clock")
                    .foregroundStyle(AppColor.accentGold)
            }
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(selected ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? AppColor.accentGold : AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .foregroundStyle(selected ? AppColor.textOnAccent : AppColor.textSecondary)
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: - Sound: 2×2 category grid

    private var soundGridSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionHeader(title: "Sound")
                Spacer()
                Text("tap ▶ to preview")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                categoryCard(.silence, icon: "speaker.slash", title: "Silence",
                             line: "just the measurement")
                categoryCard(.guided, icon: "waveform.and.mic", title: "Guided",
                             line: "\(GuidedCatalog.all.count) journey · 25 min")
                categoryCard(.frequency, icon: "waveform.path", title: "Frequency",
                             line: "\(FrequencyCatalog.all.count) tones")
                categoryCard(.nature, icon: "cloud.rain", title: "Nature",
                             line: "\(NatureCatalog.all.count) scenes")
            }
        }
    }

    private func categoryCard(_ category: SoundCategory, icon: String, title: String, line: String) -> some View {
        let selected = soundCategory == category
        return Button { selectCategory(category) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? AppColor.accentGold : AppColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(selected ? AppColor.accentGold.opacity(0.16) : AppColor.textSecondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(line)
                        .font(.system(size: 9))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? AppColor.accentGold.opacity(0.08) : AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? AppColor.accentGold : .clear, lineWidth: 1.5))
        }
        .buttonStyle(CardButtonStyle())
    }

    private func selectCategory(_ category: SoundCategory) {
        tone.stop(reason: "category switch")
        soundCategory = category
        switch category {
        case .silence:   soundID = nil
        case .guided:    soundID = GuidedCatalog.all.first?.id
        case .frequency: soundID = FrequencyCatalog.all.first?.id
        case .nature:    soundID = NatureCatalog.all.first?.id
        }
    }

    // MARK: - Track box (fills the space above the pinned bottom)

    private var trackBox: some View {
        Group {
            switch soundCategory {
            case .silence:
                VStack {
                    Spacer()
                    Text("No sound — just you, your breath,\nand the measurement.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            case .guided:
                trackList(GuidedCatalog.all.map { ($0.id, $0.title, $0.subtitle) })
            case .frequency:
                VStack(spacing: 0) {
                    trackList(FrequencyCatalog.all.map { ($0.id, $0.title, $0.subtitle) })
                    if let p = FrequencyCatalog.preset(id: soundID), p.hasBeat {
                        deliveryPicker
                    }
                }
            case .nature:
                trackList(NatureCatalog.all.map { ($0.id, $0.title, $0.subtitle) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func trackList(_ items: [(id: String, title: String, subtitle: String)]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().overlay(AppColor.textSecondary.opacity(0.1)) }
                    trackRow(id: item.id, title: item.title, subtitle: item.subtitle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
    }

    private func trackRow(id: String, title: String, subtitle: String) -> some View {
        let selected = soundID == id
        let previewing = tone.playingID == id
        return Button {
            tone.stop(reason: "track picked")
            soundID = id
        } label: {
            HStack(spacing: 11) {
                Button { previewToggle(id) } label: {
                    Image(systemName: previewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(previewing || selected ? AppColor.accentGold : AppColor.textSecondary)
                        .frame(width: 27, height: 27)
                        .background(Circle().stroke(
                            previewing || selected ? AppColor.accentGold : AppColor.textSecondary.opacity(0.35),
                            lineWidth: 1.5))
                }
                .buttonStyle(CardButtonStyle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppColor.accentGold)
                }
            }
            .padding(.vertical, 9)
        }
        .buttonStyle(CardButtonStyle())
    }

    private var deliveryPicker: some View {
        VStack(spacing: 4) {
            Picker("Delivery", selection: $headphones) {
                Text("Speaker").tag(false)
                Text("Headphones").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: headphones) { _, _ in restartPreviewIfPlaying() }
            Text(headphones ? "Binaural — put headphones in." : "Isochronic — plays on the speaker.")
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// Preview a specific row's sound (selecting it too, so what you hear is
    /// what you'll get).
    private func previewToggle(_ id: String) {
        if tone.playingID == id {
            tone.stop(reason: "preview stopped")
            return
        }
        soundID = id
        if let p = FrequencyCatalog.preset(id: id) {
            tone.play(p, method: headphones ? .binaural : .isochronic)
        } else if let np = NatureCatalog.preset(id: id) {
            tone.playNature(np)
        } else if let gp = GuidedCatalog.preset(id: id) {
            tone.playGuided(gp)
        }
    }

    private func restartPreviewIfPlaying() {
        guard let id = soundID, tone.playingID == id,
              let p = FrequencyCatalog.preset(id: id) else { return }
        tone.play(p, method: headphones ? .binaural : .isochronic)
    }

    // MARK: - Coherence check (pinned above Begin)

    private var coherenceRow: some View {
        Button { coherenceCheck.toggle() } label: { coherenceRowBody }
            .buttonStyle(CardButtonStyle())
    }

    private var coherenceRowBody: some View {
        HStack(spacing: 11) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColor.calmAccent)
                .frame(width: 30, height: 30)
                .background(AppColor.calmAccent.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Coherence check")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("45-second pulse read, before & after")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $coherenceCheck)
                .labelsHidden()
                .tint(AppColor.calmAccent)
                // The row itself toggles; the switch is a visual affordance.
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColor.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Begin

    private var beginButton: some View {
        Button {
            tone.stop(reason: "begin tapped")   // stop preview; the coordinator plays during the session
            preSnapshot = nil
            if coherenceCheck {
                showPreMeasure = true      // Begin continues when the read closes
            } else {
                startSession(pre: nil)
            }
        } label: {
            Text(coherenceCheck ? "Measure, then begin" : "Begin on Apple Watch")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canBegin)
        .opacity(canBegin ? 1 : 0.5)
    }

    private func startSession(pre: CoherenceAnalyzer.Snapshot?) {
        let mode: String
        switch soundCategory {
        case .silence:   mode = "silence"
        case .guided:    mode = "guided"
        case .frequency: mode = "frequency"
        case .nature:    mode = "nature"
        }
        // A guided track owns the session length; otherwise the picked length rules.
        let planned = activeGuided.map { $0.durationSec } ?? effectiveMinutes.map { $0 * 60 }
        coordinator.begin(mode: mode, trackID: nil,
                          plannedDurationSec: planned,
                          bellyBreathing: belly,
                          preCoherence: pre, coherenceCheck: coherenceCheck,
                          hapticsEnabled: true,
                          soundID: soundID, headphones: headphones)
        dismiss()
    }
}
