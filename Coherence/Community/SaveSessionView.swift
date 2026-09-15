import SwiftUI
import SwiftData

/// **Save session**, Strava's Save Activity for a meditation (mockup
/// `mockups/friends-v2.html`, section 3). Opens by itself when a live session
/// lands, and again from the chip on the results screen to change who can see
/// a session.
///
/// Decisions (Aziz's v2 review items, taken at the mockup's recommendations
/// 2026-09-14 while they were unanswered; each is one line to change):
/// - the score sits at the top, the way Strava shows distance and time;
/// - Friends is the default for anyone with a profile, Only you otherwise;
/// - Friends needs a selfie (the BeReal rule), Only you needs nothing;
/// - private notes are the reflection's `note`, never posted.
///
/// Friends-gated: only reachable when `FeatureFlags.friends` is on.
struct SaveSessionView: View {
    enum Mode { case new, edit }

    let sessionID: UUID
    let mode: Mode
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var community: CommunityModel
    @Query private var users: [User]
    @AppStorage("community.rulesAgreed.v1") private var rulesAgreed = false

    @State private var session: Session?
    @State private var score: Int?
    @State private var streak = 0
    @State private var sound = "Silence"

    @State private var title = ""
    @State private var publicNote = ""
    @State private var privateNote = ""
    @State private var technique: String?
    @State private var visibility: Visibility = .friends
    @State private var selfie: UIImage?
    @State private var existingSelfie: URL?
    @State private var loaded = false

    @State private var saving = false
    @State private var showRules = false
    @State private var showClaim = false
    @State private var problem: String?

    enum Visibility: String { case friends, `private` }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    scoreBar
                        .padding(.horizontal, AppMetrics.screenPadding)
                        .padding(.top, 8)

                    label("Title")
                    field { TextField("Title", text: $title).font(AppFont.body) }

                    label("Who can see this")
                    visibilityPicker
                        .padding(.horizontal, AppMetrics.screenPadding)
                    visibilityNote
                        .padding(.horizontal, AppMetrics.screenPadding)
                        .padding(.top, 6)

                    if visibility == .friends {
                        label("Your selfie")
                        SelfieCapture(image: $selfie, existingURL: existingSelfie)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, AppMetrics.screenPadding)

                        field {
                            TextField("How did it go? Friends will see this", text: $publicNote, axis: .vertical)
                                .lineLimit(2...5)
                                .font(AppFont.callout)
                                .onChange(of: publicNote) { _, new in
                                    if new.count > CommunityStore.captionLimit {
                                        publicNote = String(new.prefix(CommunityStore.captionLimit))
                                    }
                                }
                        }
                        .padding(.top, 10)
                    }

                    label("Technique")
                    techniqueMenu
                        .padding(.horizontal, AppMetrics.screenPadding)

                    label("Private notes · only you")
                    field {
                        TextField("Anything you want to remember", text: $privateNote, axis: .vertical)
                            .lineLimit(3...8)
                            .font(AppFont.callout)
                    }

                    Color.clear.frame(height: 110)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                Button { tapSave() } label: {
                    Text(saving ? "Saving…" : "Save session")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave || saving)
                // Dimmed by colour, not opacity: a translucent button shows
                // the form scrolling underneath it.
                .saturation(canSave ? 1 : 0.2)
                .brightness(canSave ? 0 : -0.25)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(AppColor.backgroundPrimary.ignoresSafeArea(edges: .bottom))
            }
            .navigationTitle("Save session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .edit {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
                }
            }
            .sheet(isPresented: $showRules) {
                CommunityRulesSheet {
                    rulesAgreed = true
                    showRules = false
                    save()
                }
                .presentationDetents([.height(260)])
            }
            .sheet(isPresented: $showClaim) {
                NavigationStack {
                    CreateProfileView(model: community,
                                      suggested: users.first?.username ?? "",
                                      nickname: users.first?.displayName ?? "") { _ in showClaim = false }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showClaim = false } } }
                }
            }
            .alert("Couldn't share that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK") { problem = nil }
            } message: { Text(problem ?? "") }
            .task { await load() }
        }
        .interactiveDismissDisabled(mode == .new)
    }

    // MARK: - Pieces

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, 7)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(AppColor.textPrimary)
            .padding(12)
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, AppMetrics.screenPadding)
    }

    private var scoreBar: some View {
        HStack(spacing: 16) {
            ScoreRing(score: score.map { Double($0) / 100 }, size: 44, lineWidth: 4)
            stat(session.map { SessionListSupport.duration($0.durationSec) } ?? "–", "Time")
            stat("\(streak) day\(streak == 1 ? "" : "s")", "Streak")
            stat(sound, "Sound")
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(AppColor.textSecondary)
            Text(value).font(AppFont.callout.weight(.semibold)).foregroundStyle(AppColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private var visibilityPicker: some View {
        HStack(spacing: 4) {
            segment(.friends, "Friends", "person.2")
            segment(.private, "Only you", "lock")
        }
        .padding(4)
        .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func segment(_ value: Visibility, _ title: String, _ icon: String) -> some View {
        let on = visibility == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { visibility = value }
        } label: {
            Label(title, systemImage: icon)
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(on ? AppColor.textPrimary : AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(on ? AppColor.backgroundPrimary : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(on ? AppColor.accentGold.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var visibilityNote: some View {
        if visibility == .private {
            Text("Only you will see this session. You can share it later from its results.")
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        } else {
            switch community.phase {
            case .needsUsername:
                Button { showClaim = true } label: {
                    Text("Create your profile to share with friends")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGoldText)
                }
                .buttonStyle(.plain)
            case .unavailable:
                Text("Sharing needs iCloud on this iPhone. Save it as Only you for now.")
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            case .loading:
                Text("Connecting to iCloud…").font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            case .ready:
                Text("Your friends see the title, selfie, score, time and streak. Heart and breath stay on your phone.")
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var techniqueMenu: some View {
        Menu {
            Button("Unreported") { technique = nil }
            Divider()
            ForEach(MeditationMethod.loggable, id: \.id) { item in
                Button(item.label) { technique = item.id }
            }
        } label: {
            HStack {
                Text(MeditationMethod.label(for: technique) ?? "Unreported")
                    .font(AppFont.callout)
                    .foregroundStyle(technique == nil ? AppColor.textSecondary : AppColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(AppColor.textSecondary)
            }
            .padding(12)
            .background(AppColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Rules

    private var canSave: Bool {
        guard loaded else { return false }
        if visibility == .private { return true }
        return community.phase == .ready && (selfie != nil || existingSelfie != nil)
    }

    // MARK: - Load and save

    private func load() async {
        guard !loaded else { return }
        let sid = sessionID
        session = try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sid })).first
        let stats = try? context.fetch(FetchDescriptor<MeditationStats>(predicate: #Predicate { $0.sessionID == sid })).first
        score = stats?.overallScore.map { Int(($0 * 100).rounded()) }
        streak = StreakCalculator.streak(from: SessionStore.sessionStartDates(in: context)).current
        sound = SoundCatalog.title(for: session?.frequencyID) ?? "Silence"

        let reflection = SessionStore.reflection(for: sessionID, in: context)
        title = (reflection?.title).flatMap { $0.isEmpty ? nil : $0 }
            ?? SessionStore.defaultTitle(for: session?.startedAt ?? Date())
        publicNote = reflection?.publicNote ?? ""
        privateNote = reflection?.note ?? ""
        technique = reflection?.technique
            ?? (session?.mode == SessionMode.guided.rawValue ? MeditationMethod.guidedID : nil)

        await community.load()
        switch mode {
        case .edit:
            visibility = Visibility(rawValue: reflection?.visibility ?? "private") ?? .private
            if visibility == .friends { existingSelfie = await community.post(forSession: sessionID)?.photoURL }
        case .new:
            visibility = community.phase == .unavailable ? .private : .friends
        }
        loaded = true
    }

    private func tapSave() {
        if visibility == .friends, !rulesAgreed { showRules = true } else { save() }
    }

    private func save() {
        guard let session else { onDone(); return }
        saving = true
        Task { @MainActor in
            SessionStore.saveSession(sessionID: sessionID, title: title, publicNote: publicNote,
                                     privateNote: privateNote, visibility: visibility.rawValue,
                                     technique: technique, in: context)
            switch visibility {
            case .private:
                await community.unpost(session: sessionID)
            case .friends:
                var photo: URL?
                if let selfie {
                    guard let url = PostPhoto.prepare(selfie) else {
                        problem = "That selfie couldn't be read. Take another."
                        saving = false
                        return
                    }
                    photo = url
                }
                let draft = CommunityStore.Draft(
                    score: score ?? 0,
                    minutes: max(1, Int((Double(session.durationSec) / 60).rounded())),
                    streak: streak,
                    technique: MeditationMethod.label(for: technique),
                    caption: publicNote,
                    photoURL: photo,
                    practicedAt: session.startedAt,
                    sessionID: sessionID.uuidString,
                    title: title.isEmpty ? SessionStore.defaultTitle(for: session.startedAt) : title,
                    sound: sound)
                guard await community.post(draft) else {
                    // The reflection is saved as Friends but nothing went up;
                    // record it as private so the chip tells the truth.
                    SessionStore.saveSession(sessionID: sessionID, title: title, publicNote: publicNote,
                                             privateNote: privateNote, visibility: Visibility.private.rawValue,
                                             technique: technique, in: context)
                    problem = community.errorText ?? "Couldn't reach iCloud."
                    community.errorText = nil
                    saving = false
                    return
                }
            }
            saving = false
            onDone()
        }
    }
}
