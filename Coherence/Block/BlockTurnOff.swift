import SwiftUI

/// "Are you sure?" before a blocker is weakened (Melvin, 2026-10-06: "way
/// too easy to click x, then go to blockers and just turn the blockers off").
/// Switching an on blocker off, deleting it, and saving an edit to it all land
/// here first, holding apps right now or not (Melvin, 2026-10-07: turning it
/// off the night before must not be the easy way round). Otto sits in the
/// valley, put out, and the way through waits five seconds before it can be
/// tapped, so the decision is made on purpose rather than on reflex.
struct BlockTurnOffScreen: View {
    enum Action { case turnOff, delete, edit }

    let blocker: Blocker
    let action: Action
    /// Whether it is holding apps right now (no session yet in its window).
    let holdingNow: Bool
    /// Opens the + screen; the blocker stays on.
    let onMeditate: () -> Void
    /// Leaves it as it was.
    let onKeep: () -> Void
    /// Turns it off, or deletes it.
    let onConfirm: () -> Void

    static let waitSeconds = 5

    @State private var remaining: Int

    init(blocker: Blocker, action: Action, holdingNow: Bool,
         wait: Int = BlockTurnOffScreen.waitSeconds,
         onMeditate: @escaping () -> Void, onKeep: @escaping () -> Void,
         onConfirm: @escaping () -> Void) {
        self.blocker = blocker
        self.action = action
        self.holdingNow = holdingNow
        self.onMeditate = onMeditate
        self.onKeep = onKeep
        self.onConfirm = onConfirm
        _remaining = State(initialValue: wait)
    }

    var line: String {
        switch (action, holdingNow) {
        case (.turnOff, true):
            return "I'm holding your apps until you meditate. Turn off \(blocker.name) anyway?"
        case (.turnOff, false):
            return "Turn off \(blocker.name)? I won't hold your apps until you turn it back on."
        case (.delete, true):
            return "I'm holding your apps until you meditate. Delete \(blocker.name) anyway?"
        case (.delete, false):
            return "Delete \(blocker.name)? I won't hold these apps until you set it up again."
        case (.edit, true):
            return "I'm holding your apps until you meditate. Change \(blocker.name) anyway?"
        case (.edit, false):
            return "Are you sure you want to change \(blocker.name)?"
        }
    }

    private var confirmLabel: String {
        switch action {
        case .turnOff: return "Turn it off"
        case .delete: return "Delete it"
        case .edit: return "Save changes"
        }
    }

    private var keepLabel: String {
        switch action {
        case .turnOff: return "Keep it on"
        case .delete: return "Keep it"
        case .edit: return "Keep it as it was"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Otto's usual place and size on his screens (`HowLongScreen`).
            let ottoHeight = min(230, size.height * 0.28)
            let ottoBottom = size.height - (holdingNow ? 236 : 170)
            let ottoTop = ottoBottom - ottoHeight
            ZStack {
                ValleyScene(progress: 0, showsFigure: false, clock: true)
                VStack {
                    Spacer(minLength: 0)
                    let look = ValleyBubble.look(at: DayLight.clockProgress())
                    OttoSpeech(text: line, tail: .bottom, size: 19,
                               ink: look.ink, stroke: look.stroke,
                               fill: look.fill, alignment: .center,
                               speaking: .constant(false))
                }
                .frame(width: min(size.width - 56, 330), height: max(0, ottoTop - 8 - 110))
                .position(x: size.width / 2, y: 110 + max(0, ottoTop - 8 - 110) / 2)
                Image("OttoFrustratedSit")
                    .resizable()
                    .scaledToFit()
                    .frame(height: ottoHeight)
                    .position(x: size.width / 2, y: ottoBottom - ottoHeight / 2)
                VStack(spacing: 10) {
                    Spacer()
                    if holdingNow {
                        Button("Okay, let's meditate", action: onMeditate)
                            .buttonStyle(PrimaryButtonStyle())
                        pill(keepLabel, action: onKeep)
                    } else {
                        Button(keepLabel, action: onKeep)
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    // The way out waits, and sits smallest: a cream pill like
                    // Otto's other second choices, since bare text on the
                    // meadow could not be read over the flowers.
                    // Not `.disabled`: that fades the whole pill and lets the
                    // flowers show through it. The tap is ignored instead.
                    Button {
                        guard remaining == 0 else { return }
                        onConfirm()
                    } label: {
                        Text(remaining > 0 ? "\(confirmLabel) (\(remaining))" : confirmLabel)
                            .font(DisplayFont.display(15, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textSecondary.opacity(remaining > 0 ? 0.5 : 1))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 22)
                            .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                            .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .accessibilityLabel(remaining > 0 ? "\(confirmLabel), available in \(remaining) seconds" : confirmLabel)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.bottom, 12)
            }
        }
        .ignoresSafeArea(edges: .top)
        .statusBarHidden(false)
        .followsStatusBarRule()
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
            }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DisplayFont.display(17, .bold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppColor.backgroundPrimary.opacity(0.94), in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

extension BlockTurnOffScreen.Action: Identifiable {
    var id: Self { self }
}
