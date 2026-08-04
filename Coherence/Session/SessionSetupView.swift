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
        coordinator.begin(mode: soundID.isEmpty ? "silence" : "frequency",
                          trackID: nil,
                          plannedDurationSec: nil,          // open-ended, always
                          hapticsEnabled: preferences.first?.hapticsEnabled ?? true,
                          soundID: soundID.isEmpty ? nil : soundID)
        dismiss()
    }
}

/// The escape hatch: the only decision the MVP still offers. Sound is kept
/// pending Melvin and Aziz's call on whether audio survives at all — if it
/// doesn't, this screen and the line that opens it both go.
struct SessionOptionsView: View {
    @Binding var soundID: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tone = ToneEngine()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sessions run open-ended — end yours from the Watch whenever you're done.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.bottom, 6)

                    SectionHeader(title: "Sound")
                    soundRow(id: "", title: "Silence", subtitle: "just the measurement")
                    ForEach(NatureCatalog.all) { preset in
                        soundRow(id: preset.id, title: preset.title, subtitle: preset.subtitle)
                    }
                    ForEach(FrequencyCatalog.all) { preset in
                        soundRow(id: preset.id, title: preset.title, subtitle: preset.subtitle)
                    }
                }
                .padding(AppMetrics.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { tone.stop(); dismiss() }.tint(AppColor.accentGold)
                }
            }
            .onDisappear { tone.stop() }
        }
    }

    private func soundRow(id: String, title: String, subtitle: String) -> some View {
        Button {
            soundID = id
            tone.stop()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.callout.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                if soundID == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.accentGold)
                }
            }
            .card(padding: 14)
        }
        .buttonStyle(CardButtonStyle())
    }
}
