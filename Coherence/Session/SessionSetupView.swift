import SwiftUI
import SwiftData

/// Begin a session. Deliberately almost empty.
///
/// The MVP makes one promise — your Watch tracks the session and scores it —
/// and asks for nothing in return. No practice type, no length, no guidance,
/// no pre-session reading. Open-ended and silent are the defaults, stated on
/// one tappable line so nobody has to decide and nobody feels trapped.
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

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Ready when\nyou are.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your Watch tracks the whole session.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Spacer()

            Button("Begin", action: begin)
                .buttonStyle(PrimaryButtonStyle())

            // The defaults, stated rather than asked. Tap to change them.
            Button { showOptions = true } label: {
                Text(defaultsLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(AppMetrics.screenPadding)
        .padding(.bottom, 6)
        .screenBackground()
        .overlay(alignment: .topTrailing) {
            Button("Cancel") { dismiss() }
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .padding(AppMetrics.screenPadding)
        }
        .sheet(isPresented: $showOptions) { SessionOptionsView(soundID: $soundID) }
    }

    /// "Open · Silence ›" — exactly what happens if you just tap Begin.
    private var defaultsLine: String {
        let sound = SoundCatalog.title(for: soundID.isEmpty ? nil : soundID) ?? "Silence"
        return "Open · \(sound)  ›"
    }

    private func begin() {
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
                    Text("Sessions run open-ended. End yours from the Watch whenever you're done, and anything you play in another app keeps playing.")
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
                    Button("Done") { tone.stop(); dismiss() }.tint(AppColor.accentGold)
                }
            }
            .onDisappear { tone.stop() }
        }
    }

    // MARK: - Guided (leads; deliberately not shaped like a sound row)

    private func guidedCard(_ preset: GuidedPreset) -> some View {
        let selected = soundID == preset.id
        return Button { select(preset.id) } label: {
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
                        .foregroundStyle(AppColor.accentGold)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Guided journey")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(AppColor.accentGold)
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
                previewButton(preset.id, prominent: true)
                if selected { checkmark }
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
                    .foregroundStyle(AppColor.accentGold)
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
            .foregroundStyle(AppColor.accentGold)
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
