import SwiftUI

/// The Watch app's four screens: a real start screen (Begin + sound choice),
/// the live session, sending, and delivered. Sessions can begin from the wrist
/// or from the phone; either way the pipeline is identical.
///
/// **No live biometrics anywhere** — evidence after, not during. The only
/// "status" the live screen shows is a teal measuring dot.
struct WatchContentView: View {
    @EnvironmentObject private var manager: WatchSessionManager
    @State private var showSoundPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .sheet(isPresented: $showSoundPicker) {
            NavigationStack {
                SoundPickerView(selectedID: $manager.soundID)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !manager.authorized {
            authorizeScreen
        } else {
            switch manager.phase {
            case .idle:    manager.phoneOnboarded ? AnyView(startScreen) : AnyView(setupScreen)
            case .running: liveScreen
            case .sending: sendingScreen
            case .sent:    sentScreen
            }
        }
    }

    // MARK: - First run

    private var authorizeScreen: some View {
        VStack(spacing: 10) {
            markRow
            Spacer()
            Text("808 measures with your heart rate and motion.")
                .font(.system(size: 13))
                .foregroundStyle(WatchPalette.inkMuted)
                .multilineTextAlignment(.center)
            Button("Allow") { Task { await manager.authorize() } }
                .buttonStyle(.borderedProminent)
                .tint(WatchPalette.gold)
                .foregroundStyle(.black)
            if let msg = manager.statusMessage {
                Text(msg).font(.system(size: 11))
                    .foregroundStyle(WatchPalette.inkMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Phone not set up yet

    /// The phone hasn't finished onboarding (or its user signed out), so a
    /// session started here would deliver into an app that can't receive it.
    /// Say what to do instead of offering a Begin that half-works.
    private var setupScreen: some View {
        VStack(spacing: 10) {
            markRow
            Spacer()
            Image(systemName: "iphone.gen3")
                .font(.system(size: 26))
                .foregroundStyle(WatchPalette.calm)
            Text("Set up 808 on your iPhone first.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WatchPalette.ink)
                .multilineTextAlignment(.center)
            Text("Open the app on your phone and finish the setup. This screen unlocks by itself.")
                .font(.system(size: 11))
                .foregroundStyle(WatchPalette.inkMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Start

    private var startScreen: some View {
        VStack(spacing: 6) {
            markRow

            Spacer(minLength: 2)

            Button(action: { manager.beginFromWatch() }) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.91, green: 0.77, blue: 0.35),
                                     Color(red: 0.79, green: 0.60, blue: 0.17),
                                     Color(red: 0.66, green: 0.49, blue: 0.11)],
                            center: .init(x: 0.34, y: 0.30),
                            startRadius: 4, endRadius: 90))
                        .shadow(color: WatchPalette.gold.opacity(0.45), radius: 14, y: 6)
                    Text("Begin")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchPalette.onGold)
                }
                .frame(width: 108, height: 108)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 2)

            Button(action: { showSoundPicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.calm)
                    Text(SoundMenu.title(for: manager.soundID))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchPalette.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchPalette.inkMuted)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(WatchPalette.surface, in: Capsule())
            }
            .buttonStyle(.plain)

            // Surfaces a start refusal (no HR, not authorized) on the screen
            // the user is actually looking at.
            if let msg = manager.statusMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(WatchPalette.gold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var markRow: some View {
        HStack(spacing: 6) {
            LogoMark(color: WatchPalette.gold, lineWidthRatio: 0.09)   // heavier stroke at watch sizes
                .frame(width: 17, height: 17)
            Text("808")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(WatchPalette.gold)
        }
    }

    // MARK: - Live

    private var liveScreen: some View {
        ZStack {
            BreathingOrb(elapsed: manager.elapsed)

            VStack {
                HStack(spacing: 5) {
                    Circle().fill(WatchPalette.calm).frame(width: 5, height: 5)
                    Text(silentNote ?? "measuring")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.inkMuted)
                }
                Spacer()
                Button(action: { manager.endByUser() }) {
                    Text("End")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchPalette.warn)
                        .padding(.horizontal, 38)
                        .padding(.vertical, 10)
                        .background(WatchPalette.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)
        }
    }

    /// The honest one-liner when a wrist-started session wanted sound but the
    /// phone wasn't reachable: measurement is running, audio is not.
    private var silentNote: String? {
        guard manager.startedOnWatch, !manager.phoneLinked,
              manager.soundID?.isEmpty == false else { return nil }
        return "iPhone out of reach · silent"
    }

    // MARK: - Sending / sent

    private var sendingScreen: some View {
        VStack(spacing: 12) {
            PhoneStream()
            Text("Scoring your session")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.ink)
            Text("Your evidence is on its way\nto your iPhone.")
                .font(.system(size: 11))
                .foregroundStyle(WatchPalette.inkMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var sentScreen: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundStyle(WatchPalette.gold)
            Text(manager.deliveredImmediately ? "Delivered" : "Saved")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.ink)
            Text(manager.deliveredImmediately
                 ? "Open 808 to see it."
                 : "It'll reach your iPhone\nwhen it's back in range.")
                .font(.system(size: 11))
                .foregroundStyle(WatchPalette.inkMuted)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - The breathing orb

/// Elapsed time inside a teal orb that breathes at 6/min (5 s in, 5 s out) —
/// the resonance pace, so a glance at the wrist is itself a pacing cue.
/// Holds still under Reduce Motion.
private struct BreathingOrb: View {
    let elapsed: Int
    @State private var inhale = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Same three layers as the phone's pacer orb, at watch scale: a
            // soft outer bloom, a solid inner glow, then the defining ring.
            // The single thin gradient this replaced read as a bare outline.
            Circle()
                .fill(WatchPalette.calm.opacity(0.18))
                .frame(width: 150, height: 150)
                .blur(radius: 16)
            Circle()
                .fill(RadialGradient(
                    colors: [WatchPalette.calm.opacity(0.60), WatchPalette.calm.opacity(0.10)],
                    center: .center, startRadius: 4, endRadius: 66))
                .frame(width: 124, height: 124)
            Circle()
                .stroke(WatchPalette.calm.opacity(0.55), lineWidth: 1.5)
                .frame(width: 124, height: 124)
            Text(timeString(elapsed))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchPalette.ink)
        }
        .frame(width: 150, height: 150)
        .scaleEffect(reduceMotion ? 1 : (inhale ? 1.05 : 0.86))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                inhale = true
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Sending animation

/// Gold dots streaming from the wrist up into a phone outline.
private struct PhoneStream: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(WatchPalette.inkMuted.opacity(0.6), lineWidth: 2)
                .frame(width: 30, height: 50)
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(WatchPalette.gold)
                        .frame(width: 5, height: 5)
                        .offset(y: animate ? -30 : 12)
                        .opacity(animate ? 0 : 1)
                        .animation(reduceMotion ? nil :
                            .linear(duration: 1.4)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.45),
                            value: animate)
                }
            }
            .frame(height: 26)
        }
        .onAppear { animate = true }
    }
}

// MARK: - Sound picker

/// The full catalog, one crown-scrollable list in the sound sheet's shipped
/// order. Selection is remembered between sessions; audio plays from the phone.
private struct SoundPickerView: View {
    @Binding var selectedID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(id: nil, title: "Silence", detail: nil)
            } footer: {
                Text("Plays from your iPhone")
                    .font(.system(size: 10))
                    .foregroundStyle(WatchPalette.inkMuted)
            }
            ForEach(SoundMenu.groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        row(id: entry.id, title: entry.title, detail: entry.detail)
                    }
                } header: {
                    Text(group.name.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(WatchPalette.inkMuted)
                }
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
            HStack(spacing: 8) {
                // Explicit light ink, not the asset colors: inside the
                // sheet's List the catalog ink resolved near-black on the
                // black screen (the rows were unreadable on-device).
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchPalette.ink)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(WatchPalette.inkMuted)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(WatchPalette.gold)
                }
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? WatchPalette.gold.opacity(0.16) : WatchPalette.surface))
    }
}
