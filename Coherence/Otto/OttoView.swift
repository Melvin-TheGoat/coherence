import SwiftUI
import SwiftData

/// Otto, the data interpreter: a chat about the person's own sessions.
/// Premium (the paid tier with the curves: free gives you the score, paid
/// gives you the evidence behind it, and Otto is the evidence, spoken).
///
/// Three states, decided in this order: the phone cannot run it (an honest
/// card, shown before any lock so nobody is sold a chat their phone cannot
/// run), the person is on free 808 (the same lock language as the curves),
/// or the chat. Mockup: `mockups/otto.html`.
///
/// Opened from two doors: the results screen (`sessionID` set, so the chat
/// opens on that session) and the Profile tab (nil, the last ten sessions).
struct OttoView: View {
    var sessionID: UUID? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @State private var paywallPlan: SubscriptionPlan = .monthly
    @State private var showPlans = false

    var body: some View {
        NavigationStack {
            Group {
                let availability = OttoAvailability.current()
                if availability != .available {
                    OttoUnavailableView(availability: availability)
                } else if !store.entitlements.otto {
                    OttoLockedView(trialEligible: store.trialEligible || store.state != .ready,
                                   trialDays: store.trialDays) {
                        Analytics.track(.lockedTapped(signal: "otto"))
                        showPlans = true
                    } onDismiss: {
                        dismiss()
                    }
                } else {
                    chat
                }
            }
            .screenBackground()
            .navigationTitle("Otto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
            // The purchase happens on PaywallScreen, which carries the legal
            // links guideline 3.1.2 requires; this screen only offers.
            .sheet(isPresented: $showPlans) {
                PaywallScreen(placement: "otto_lock", plan: $paywallPlan) { _ in showPlans = false }
            }
            .onAppear { Analytics.track(.ottoOpened) }
        }
    }

    @ViewBuilder
    private var chat: some View {
        if #available(iOS 26, *) {
            let loaded = OttoLoader.load(focus: sessionID, in: context)
            OttoChatView(instructions: OttoBrief.instructions(sessions: loaded.rows, focus: loaded.focus),
                         opening: OttoBrief.opening(focus: loaded.focus, sessionCount: loaded.rows.count),
                         suggestions: OttoBrief.suggestedQuestions(focus: loaded.focus, sessionCount: loaded.rows.count),
                         storeKey: OttoChatStore.key(for: loaded.focus == nil ? nil : sessionID))
        } else {
            OttoUnavailableView(availability: .needsUpdate)
        }
    }
}

// MARK: - Loading the person's sessions

/// Reads the last sessions off the phone's store into plain rows for the
/// brief. Stats are device-local (the 5.1.3 split), so a synced session
/// without local measurements reads as "not read", which is the truth.
enum OttoLoader {
    static func load(focus sessionID: UUID?, in context: ModelContext) -> (rows: [OttoBrief.SessionRow], focus: OttoBrief.SessionRow?) {
        var descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = OttoBrief.maxSessions
        var sessions = (try? context.fetch(descriptor)) ?? []
        if let sessionID, !sessions.contains(where: { $0.id == sessionID }),
           let extra = try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first {
            sessions.insert(extra, at: 0)
            sessions.sort { $0.startedAt > $1.startedAt }
            if sessions.count > OttoBrief.maxSessions { sessions.removeLast() }
        }
        let ids = sessions.map(\.id)
        let stats = ((try? context.fetch(FetchDescriptor<MeditationStats>())) ?? [])
            .filter { $0.sessionID.map(ids.contains) ?? false }
        let statsByID = Dictionary(stats.compactMap { s in s.sessionID.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
        let reflections = ((try? context.fetch(FetchDescriptor<SessionReflection>())) ?? [])
            .filter { $0.sessionID.map(ids.contains) ?? false }
        let reflectionByID = Dictionary(reflections.compactMap { r in r.sessionID.map { ($0, r) } }, uniquingKeysWith: { a, _ in a })

        let rows = sessions.map { session -> OttoBrief.SessionRow in
            let st = statsByID[session.id]
            let re = reflectionByID[session.id]
            return OttoBrief.SessionRow(
                date: session.startedAt,
                minutes: max(1, session.durationSec / 60),
                overallScore: st?.overallScore,
                startHR: st?.startHR,
                endHR: st?.endHR,
                meanHR: st?.meanHR,
                stillnessScore: st?.stillnessScore,
                doorwayRate: st?.breathDoorwayRate,
                doorwayHeldSec: st?.breathDoorwayHeldSec,
                technique: MeditationMethod.label(for: re?.technique),
                sound: SoundCatalog.title(for: session.frequencyID),
                rating: re?.rating,
                breakdown: st.flatMap { st in
                    SignalEngine.breakdown(stillnessScore: st.stillnessScore,
                                           heartRateTimeseries: st.heartRateTimeseries,
                                           hasDoorway: st.breathDoorwayRate != nil,
                                           durationSec: session.durationSec)
                })
        }
        let focus = sessionID.flatMap { id in
            sessions.firstIndex { $0.id == id }.map { rows[$0] }
        }
        return (rows, focus)
    }
}

// MARK: - The chat

@available(iOS 26, *)
struct OttoChatView: View {
    @State private var model: OttoModel
    @State private var draft = ""
    @FocusState private var focused: Bool
    let suggestions: [String]

    init(instructions: String, opening: String, suggestions: [String], storeKey: String) {
        _model = State(initialValue: OttoModel(instructions: instructions, opening: opening, storeKey: storeKey))
        self.suggestions = suggestions
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Runs on your iPhone. Nothing you say, and none of your numbers, leave the phone.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                        ForEach(model.messages) { message in
                            bubble(message)
                        }
                        // The suggestions stand until the first question.
                        if model.messages.count == 1 {
                            chips
                        }
                        if let note = model.note {
                            Text(note)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(AppMetrics.screenPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.last?.text) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            composer
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if model.hasHistory {
                    Menu {
                        Button("Start a new chat", systemImage: "square.and.pencil") { model.startOver() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .disabled(model.isResponding)
                    .accessibilityLabel("Chat options")
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: OttoMessage) -> some View {
        switch message.role {
        case .otto:
            HStack(alignment: .top, spacing: 10) {
                OttoMark(size: 26)
                    .padding(.top, 1)
                if message.isStreaming && message.text.isEmpty {
                    Text("•••")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.top, 2)
                } else {
                    Text(message.text)
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(AppColor.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColor.textSecondary.opacity(0.18), lineWidth: 1))
            }
        }
    }

    /// Neutral chips: tapping one is asking, and the one gold object on this
    /// screen is the send button.
    private var chips: some View {
        FlowChips(items: suggestions) { question in
            Task { await model.ask(question) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Otto", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentGoldText)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColor.textOnAccent)
                    .frame(width: 38, height: 38)
                    .background(AppColor.accentGold, in: Circle())
            }
            .buttonStyle(CardButtonStyle())
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(AppColor.backgroundPrimary)
    }

    private var canSend: Bool {
        !model.isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let q = draft
        draft = ""
        Task { await model.ask(q) }
    }
}

/// Suggested questions, wrapping onto as many lines as they need.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        // Three short questions fit two rows at phone width; a simple
        // two-row split keeps this free of a layout engine.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(AppFont.caption.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .overlay(Capsule().stroke(AppColor.textSecondary.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(CardButtonStyle())
            }
        }
        .padding(.leading, 36)
    }
}

// MARK: - The mark, the row

/// Otto, at the size a row or an avatar wants him.
///
/// **He is an asset now, not a drawing** (2026-09-19). He was hand-written SVG
/// paths parsed at runtime, which was the right call while he was a one-colour
/// line glyph that had to take the theme's tint. He is a full-colour character
/// as of this pass, and a character is art: `OttoArt`, `SVGPath` and their
/// tests are gone, and the illustrator's file now ships untouched.
///
/// He also carries no tint. The colour grammar is unchanged, it simply no
/// longer applies to him: amber is a measured score and sage is your body, and
/// Otto is neither. He is the one thing on screen that is just himself.
struct OttoMark: View {
    var size: CGFloat = 32
    var dimmed = false
    /// Eyes open. He looks at you in a row or an avatar, because that is
    /// someone waiting to be asked something; he closes them only where he is
    /// actually meditating.
    var pose: OttoPose = .awake

    var body: some View {
        Image(pose.asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

/// The poses that exist. Each one has a job and none of them is decorative;
/// a mascot that pulls a new face every message stops reading as a person.
enum OttoPose {
    /// Eyes closed, cross-legged. The default, and the streak card.
    case meditating
    /// Eyes open, looking at you. Rows, avatars, and listening in the chat.
    case awake
    /// Arms up, delighted. Awards ONLY, so that it still means something.
    case pleased
    /// Mid sentence. The written verdict, and his own replies.
    case talking
    /// Clipboard and pen, standing. **The onboarding questions only**, where
    /// he is asking rather than answering, in the corner the way Duolingo's
    /// owl stands beside its question (Melvin, 2026-09-20).
    case asking
    /// Seated, eyes open, mid wave. **The screen before a sit**, where he is
    /// greeting you rather than meditating: `.meditating` on that screen drew
    /// him with his eyes already shut, which is him practising while you are
    /// still picking a sound.
    case greeting
    /// His head alone. **The mark**: wherever the 808 flower used to sit next
    /// to the wordmark, and anywhere below about 40pt, where the full sitting
    /// figure is a brown smudge. It is the app icon's own crop, so the badge
    /// in the app and the icon on the home screen are visibly one object.
    case head

    var asset: String {
        switch self {
        case .meditating: return "OttoSit"
        case .awake:      return "OttoAwake"
        case .pleased:    return "OttoWave"
        case .talking:    return "OttoTalk"
        case .asking:     return "OttoAsk"
        case .greeting:   return "OttoGreet"
        case .head:       return "OttoHead"
        }
    }
}

/// Otto drawn large: the locked screen, the unavailable screen, an award.
struct OttoSlothSitting: View {
    var size: CGFloat = 96
    var pose: OttoPose = .meditating

    var body: some View {
        Image(pose.asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The entry row: on the results screen under the verdict, and on Profile
/// under the stats. A free user sees the same row with the Locked pill; the
/// tap still opens Otto, whose locked state does the explaining.
struct OttoRow: View {
    let title: String
    let subtitle: String
    var locked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                OttoMark(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                if locked {
                    LockPill()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppColor.accentGoldText)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(locked ? "\(title), locked" : title)
    }
}

// MARK: - Locked

/// The same lock language as the curves (`LockedUI.swift`): the pill, one
/// sentence naming the specific thing withheld, one gold call to action,
/// Not now underneath. This screen explains and offers; the purchase lives
/// on `PaywallScreen`.
struct OttoLockedView: View {
    var trialEligible: Bool = true
    var trialDays: Int = SubscriptionPlan.fallbackTrialDays
    let onSeePlans: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 14) {
                HStack { OttoSlothSitting(size: 104); Spacer() }
                HStack { LockPill(); Spacer() }
                Text("Otto reads your evidence back to you. Free 808 keeps the evidence closed.")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    point("Explains your score, number by number, from your own session.")
                    point("Compares this sit with your last ten.")
                    point("Answers the questions a new meditator has, and says what to try next.")
                }
                .padding(.top, 2)
                Text("Runs on your iPhone. Nothing you ask, and none of your numbers, leave the phone.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            VStack(spacing: 8) {
                Button(trialEligible ? TrialCopy.startButton(trialDays) : "See the plans", action: onSeePlans)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Not now", action: onDismiss)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, 6)
            }
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(AppColor.calmAccent).frame(width: 6, height: 6).padding(.top, 7)
            Text(text)
                .font(AppFont.note)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Not available on this phone

struct OttoUnavailableView: View {
    let availability: OttoAvailability

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            OttoSlothSitting(size: 104)
                .opacity(0.55)
            Text(OttoAvailability.headline)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(availability.detail)
                .font(AppFont.note)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Spacer()
        }
        .padding(AppMetrics.screenPadding)
        .frame(maxWidth: .infinity)
    }
}


// MARK: - How Otto moves on Home (direction B, 2026-09-20)

/// The idle: a breath. Six a minute, the pace the Watch orb breathes at and
/// the pace the score's doorway is built around, so the app breathes one way
/// everywhere. Scaled from the feet, so he swells rather than floats.
///
/// This is the SwiftUI fallback that ships before the Rive rig (BACKLOG.md,
/// "Otto animation, researched"): a pulse on the PNG. The wave and the talk
/// wait for the rig; when it lands this modifier goes and `RiveViewModel`
/// takes the same place with `breathing` on.
struct OttoBreathing: ViewModifier {
    @State private var swollen = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(swollen ? 1.035 : 1, anchor: .bottom)
            .onAppear {
                withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                    swollen = true
                }
            }
    }
}

extension View {
    func ottoBreathing() -> some View { modifier(OttoBreathing()) }
}

/// One line from Otto, with the tail pointing at him on the left.
struct OttoBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.callout)
            .foregroundStyle(AppColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColor.backgroundSecondary)
                    .shadow(color: AppColor.hairline, radius: 0, y: 3)
            }
            .overlay(alignment: .bottomLeading) {
                // The tail: a small rotated square tucked under the corner
                // nearest Otto's mouth.
                Rectangle()
                    .fill(AppColor.backgroundSecondary)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
                    .offset(x: -4, y: -12)
            }
            .accessibilityLabel("Otto says: \(text)")
    }
}
