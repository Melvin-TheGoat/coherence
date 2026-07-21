import SwiftUI

/// Pre-session setup: pick Regular vs Belly and a length, and — for belly — show the
/// posture coaching that actually makes the breathing signal readable. Supine reads
/// far better than seated (Hughes et al. 2020), and a bad wrist placement degrades to
/// a 2-signal result, so coaching posture here is what earns the third signal.
///
/// On Begin it triggers the Watch session through the coordinator and dismisses; the
/// home screen then shows status + (afterward) the results.
struct SessionSetupView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var belly = false
    /// Selected preset length in minutes; nil = open-ended (end from the Watch).
    /// Ignored while `isCustom` is on.
    @State private var durationMinutes: Int? = nil
    /// Custom length is active — use the typed `customText` instead of a preset.
    @State private var isCustom = false
    /// Free-typed custom length (minutes) as text, so the field can be empty mid-edit.
    @State private var customText = "20"
    @FocusState private var customFocused: Bool

    private let durationOptions: [Int?] = [2, 5, 10, 15, nil]

    /// Parsed, sanity-clamped custom length; nil if the field isn't a valid minute count.
    private var customValue: Int? {
        guard let n = Int(customText.trimmingCharacters(in: .whitespaces)), n >= 1 else { return nil }
        return min(n, 600)
    }

    /// The length actually used to start the session (nil = open-ended).
    private var effectiveMinutes: Int? { isCustom ? customValue : durationMinutes }

    /// Whether the current selection can start a session (a valid custom value, if custom).
    private var canBegin: Bool { !isCustom || customValue != nil }

    private let postureSteps = [
        "Lie down or recline — flat on your back works best.",
        "Rest your watch wrist flat on your belly, screen up.",
        "Breathe slowly into your belly: in for about 5 seconds, out for about 5 (~6 breaths a minute).",
        "Let your belly rise and fall, and keep the rest of your body still.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    modeSection
                    durationSection
                    if belly { postureCoaching }
                    beginButton
                }
                .padding()
            }
            .background(AppColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(AppColor.accentGold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { customFocused = false }.tint(AppColor.accentGold)
                }
            }
        }
    }

    // MARK: Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session type")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            modeCard(title: "Regular",
                     subtitle: "Stillness + heart rate. Sit or lie however you like.",
                     selected: !belly) { belly = false }
            modeCard(title: "Belly breathing",
                     subtitle: "Adds your breath, read from the watch on your belly. Lie back.",
                     selected: belly) { belly = true }
        }
    }

    private func modeCard(title: String, subtitle: String, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(AppColor.accentGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? AppColor.accentGold : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Length")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(durationOptions, id: \.self) { opt in
                    chip(label: opt.map { "\($0)m" } ?? "Open",
                         selected: !isCustom && opt == durationMinutes) {
                        isCustom = false
                        durationMinutes = opt
                    }
                }
                chip(label: "Custom", selected: isCustom) {
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
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 80)
                        .padding(.vertical, 8)
                        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.accentGold, lineWidth: 1))
                    Text("minutes")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                }
            }
            Text(helpText)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var helpText: String {
        if isCustom && customValue == nil { return "Type how many minutes you want." }
        return effectiveMinutes == nil
            ? "Open-ended — tap End on your Watch to finish."
            : "Your Watch buzzes and ends the session automatically."
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? AppColor.accentGold : AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(selected ? AppColor.backgroundPrimary : AppColor.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Posture coaching (belly only)

    private var postureCoaching: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Set up for belly breathing", systemImage: "figure.mind.and.body")
                .font(.headline)
                .foregroundStyle(AppColor.accentGold)
            ForEach(Array(postureSteps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColor.backgroundPrimary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(AppColor.accentGold))
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Begin

    private var beginButton: some View {
        Button {
            coordinator.begin(mode: "silence", trackID: nil,
                              plannedDurationSec: effectiveMinutes.map { $0 * 60 },
                              bellyBreathing: belly, hapticsEnabled: true)
            dismiss()
        } label: {
            Text("Begin on Apple Watch")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.accentGold)
        .disabled(!canBegin)
        .padding(.top, 4)
    }
}
