import SwiftUI
import FamilyControls

/// The Block tab (`mockups/block-v1.html`, section 1, approved 2026-09-22):
/// the valley on top with Otto holding his clipboard and saying the title,
/// the blockers as cream cards on the grass, and presets underneath, the way
/// Brainrot lays out its own.
///
/// Mindful day is already here for everyone, set up and waiting (Melvin,
/// 2026-09-22): picking its apps and flipping its switch is the whole setup.
/// Switching a blocker on asks, in order, for what it needs and does not have
/// yet: the paid tier, Screen Time access, notifications, and the apps.
struct BlockTab: View {
    @ObservedObject var block: BlockController
    let entitlements: Entitlements
    /// The free-week offer. Block is paid.
    let onPaywall: () -> Void

    @State private var editing: EditRequest?
    @State private var accessDenied = false

    /// The editor, for an existing blocker or one made from a preset.
    struct EditRequest: Identifiable {
        let blocker: Blocker
        /// Open Apple's app picker straight away: the switch was flipped on a
        /// blocker with no apps yet.
        var pickApps = false
        var id: UUID { blocker.id }
    }

    private static let day = DayLight.at(0)
    private static let meadow = day.field[1]

    var body: some View {
        GeometryReader { proxy in
            let sceneHeight = proxy.safeAreaInsets.top + proxy.size.height * 0.46
            ScrollView {
                VStack(spacing: 0) {
                    scene(width: proxy.size.width, height: sceneHeight, topInset: proxy.safeAreaInsets.top)
                    VStack(alignment: .leading, spacing: 14) {
                        if !block.authorized { accessCard }
                        if let problem = block.problem { noticeCard(problem, settings: false) }
                        if block.authorized, !block.notificationsAllowed,
                           block.state.blockers.contains(where: { $0.isOn }) {
                            noticeCard("Notifications are off, so Otto can't answer from a held app. Turn them on for 808 in Settings, or open 808 when an app is held.",
                                       settings: true)
                        }
                        ForEach(block.state.blockers) { blocker in
                            BlockerCard(blocker: blocker, block: block,
                                        onToggle: { toggle(blocker, to: $0) },
                                        onOpen: { editing = EditRequest(blocker: blocker) })
                        }
                        // One gold thing: until Screen Time is allowed, that
                        // is the Allow button, and adding steps down.
                        if block.authorized {
                            addButton.buttonStyle(PrimaryButtonStyle())
                        } else {
                            addButton.buttonStyle(SecondaryButtonStyle())
                        }
                        presets
                    }
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.top, -sceneHeight * 0.10)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
        }
        .background(Self.meadow.ignoresSafeArea())
        .sheet(item: $editing) { request in
            BlockerEditor(original: request.blocker,
                          isNew: block.blocker(request.blocker.id) == nil,
                          pickOnAppear: request.pickApps,
                          block: block,
                          onSave: save,
                          onDelete: { block.delete($0); editing = nil })
        }
        .alert("Screen Time is off for 808", isPresented: $accessDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Otto needs Screen Time to hold your apps. Turn it on for 808 in Settings, under Screen Time.")
        }
        .onAppear { block.refresh() }
    }

    private var addButton: some View {
        Button {
            editing = EditRequest(blocker: .preset(.custom))
        } label: {
            Label("Add a blocker", systemImage: "plus")
        }
    }

    // MARK: - The scene

    private func scene(width: CGFloat, height: CGFloat, topInset: CGFloat) -> some View {
        let ink = Self.day.ink
        let ottoHeight = min(200, height * 0.42)
        let ottoBottom = height * 0.80
        return ZStack(alignment: .top) {
            ValleyScene(progress: 0, showsOtto: false)
                .frame(width: width, height: height)
            Image(OttoPose.asking.asset)
                .resizable()
                .scaledToFit()
                .frame(height: ottoHeight)
                .position(x: width / 2, y: ottoBottom - ottoHeight / 2)
                .accessibilityLabel("Otto, holding his clipboard")
            VStack {
                Spacer(minLength: 0)
                OttoSpeech(text: ottoLine, tail: .bottom, size: 17,
                           ink: ink, stroke: ink.opacity(0.38),
                           fill: AppColor.backgroundPrimary.opacity(0.82),
                           speaking: .constant(false))
                    .id(ottoLine)
            }
            .frame(width: min(width - 56, 330),
                   height: max(0, ottoBottom - ottoHeight - 6 - (topInset + 12)))
            .padding(.top, topInset + 12)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// What Otto says, from the state, never generated.
    private var ottoLine: String {
        let now = Date()
        if !block.authorized {
            return "Let me hold the apps that pull you in. I need Screen Time for that."
        }
        let set = block.state.blockers.filter { $0.isOn && $0.hasApps }
        if set.isEmpty {
            return "Pick the apps that pull you in, and I'll hold them until you've meditated."
        }
        if !block.holding(at: now).isEmpty {
            return "I'm holding your apps. A short session and they're yours."
        }
        if set.contains(where: { BlockRules.activePass($0.id, in: block.state, at: now) != nil }) {
            return "Enjoy your few minutes. I'll hold them again after."
        }
        let releasedToday = set.contains { blocker in
            guard let window = blocker.openWindow(at: now) else { return false }
            return BlockRules.released(blocker.id, window: window, in: block.state)
        }
        if releasedToday {
            return "You meditated, so your apps are open. Nice one."
        }
        return "I'll hold your apps when your next window opens."
    }

    // MARK: - Cards

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Let Otto hold your apps")
                .font(DisplayFont.display(18))
                .foregroundStyle(AppColor.textPrimary)
            Text("808 uses Screen Time to hold the apps you pick. You choose them, and nothing about them leaves your phone.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow Screen Time") {
                Task {
                    if !(await block.requestAuthorization()) { accessDenied = true }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }

    private func noticeCard(_ text: String, settings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if settings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColor.accentGoldText)
            }
        }
        .card()
    }

    private var presets: some View {
        let kinds: [BlockerKind] = [.mindfulDay, .mindfulMorning, .windDown, .focusHours, .dailyLimit]
            .filter { kind in kind != .mindfulDay || !block.state.blockers.contains { $0.kind == .mindfulDay } }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(DisplayFont.display(17))
                .foregroundStyle(AppColor.backgroundPrimary)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .padding(.top, 8)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(kinds, id: \.self) { kind in
                        let preset = Blocker.preset(kind)
                        Button {
                            editing = EditRequest(blocker: preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(AppColor.textPrimary)
                                Text(preset.scheduleLine())
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 150, height: 58, alignment: .topLeading)
                            .padding(14)
                            .background(AppColor.backgroundPrimary.opacity(0.92),
                                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Turning on

    /// Everything a blocker needs to hold, asked for in order, only when
    /// missing: the paid tier, Screen Time, notifications, then the apps.
    private func toggle(_ blocker: Blocker, to on: Bool) {
        guard on else { block.setOn(blocker.id, false); return }
        guard BlockAccess.allowed(entitlements) else { onPaywall(); return }
        Task {
            if !block.authorized {
                guard await block.requestAuthorization() else { accessDenied = true; return }
            }
            await block.requestNotificationsIfNeeded()
            if blocker.hasApps {
                block.setOn(blocker.id, true)
            } else {
                var draft = blocker
                draft.isOn = true
                editing = EditRequest(blocker: draft, pickApps: true)
            }
        }
    }

    private func save(_ draft: Blocker, _ selection: FamilyActivitySelection?) {
        var saved = draft
        if saved.isOn && !BlockAccess.allowed(entitlements) {
            saved.isOn = false
            block.save(saved, selection: selection)
            editing = nil
            onPaywall()
            return
        }
        block.save(saved, selection: selection)
        editing = nil
        if saved.isOn {
            Task { await block.requestNotificationsIfNeeded() }
        }
    }
}

/// One blocker on the grass: its name, when it holds, its apps, a switch, and
/// what it is doing right now.
private struct BlockerCard: View {
    let blocker: Blocker
    @ObservedObject var block: BlockController
    let onToggle: (Bool) -> Void
    let onOpen: () -> Void

    var body: some View {
        // Not a Button: a switch inside a button's label loses its taps to
        // the button. The card opens on a tap anywhere but the switch.
        VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(blocker.name)
                            .font(DisplayFont.display(18))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(blocker.scheduleLine())
                            .font(.system(size: 13))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(get: { blocker.isOn }, set: onToggle))
                        .labelsHidden()
                        .tint(AppColor.accentGold)
                }
                HStack(spacing: 8) {
                    PickedApps(selection: block.selection(for: blocker.id), hasApps: blocker.hasApps)
                    Spacer(minLength: 8)
                    Text(status)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.trailing)
                }
            }
            .card()
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens this blocker's settings")
    }

    private var status: String {
        let now = Date()
        guard blocker.hasApps else { return "Pick your apps" }
        guard blocker.isOn else { return "Off" }
        if block.holds(blocker, at: now) { return "Holding until you meditate" }
        if let pass = BlockRules.activePass(blocker.id, in: block.state, at: now) {
            let minutes = max(1, Int((pass.end.timeIntervalSince(now) / 60).rounded(.up)))
            return "Open for \(minutes) more min"
        }
        if let window = blocker.openWindow(at: now) {
            if BlockRules.released(blocker.id, window: window, in: block.state) {
                return "Open, you meditated"
            }
            if blocker.dailyLimitMinutes != nil { return "Counting today's minutes" }
        }
        return "Waiting for its window"
    }

    private var statusColor: Color {
        block.holds(blocker, at: Date()) ? AppColor.accentGoldText : AppColor.textSecondary
    }
}

/// The picked apps as their own icons. Screen Time draws these from tokens
/// on the phone; 808 never learns what they are.
struct PickedApps: View {
    let selection: FamilyActivitySelection
    let hasApps: Bool

    var body: some View {
        let apps = Array(selection.applicationTokens.prefix(5))
        let categories = Array(selection.categoryTokens.prefix(max(0, 5 - apps.count)))
        let shown = apps.count + categories.count
        let more = selection.pickedCount - shown
        HStack(spacing: 6) {
            if selection.isEmptySelection {
                Image(systemName: hasApps ? "app.badge.checkmark" : "plus.app")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.textSecondary)
                Text(hasApps ? "Your apps" : "No apps yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(apps, id: \.self) { token in
                    Label(token).labelStyle(.iconOnly).font(.system(size: 26))
                }
                ForEach(categories, id: \.self) { token in
                    Label(token).labelStyle(.iconOnly).font(.system(size: 26))
                }
                if more > 0 {
                    Text("+\(more)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }
}
