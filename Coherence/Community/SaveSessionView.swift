import SwiftUI
import SwiftData

/// **Save session**: Strava's iOS screen in Letterboxd's skin.
///
/// Mockups, in order: `mockups/save-session-v4.html` (Strava's real iOS
/// anatomy: Cancel-style exit top left, nothing top right, one filled button
/// pinned at the bottom), `v5` (the senior review: one big number, visibility
/// first, a portrait selfie tile, a button that names the block), `v6` (skin B,
/// bare text on hairlines, Aziz's pick 2026-09-15) and `v7` (a photo for every
/// sit, optional when private, shown on the calendar).
///
/// Top to bottom: the score as the one big thing, then who can see it, which
/// comes first because it decides whether the description and the selfie
/// exist at all (cause above effect), the title, the description friends
/// read, the photo tile, then Details: technique and private notes. Nothing
/// is boxed. Rules run edge to edge between sections and start at the text
/// within one. Gold lands three times, once per section: the score, the tile
/// when sharing needs a selfie, the button.
///
/// The button is never dead. While Friends is chosen and there is no selfie
/// it reads "Take your selfie" and opens the camera; once the shot exists it
/// reads "Save session". Skip (new sessions) keeps the session as Only you
/// with the default title, because the session is already stored and a
/// screen you cannot leave is hostile.
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
    /// A shot taken on this screen and not yet saved.
    @State private var newPhoto: UIImage?
    /// The photo already kept with the session. A retake replaces it.
    @State private var storedPhoto: UIImage?
    @State private var loaded = false
    /// What the session was saved as before this sheet opened, so an Only-you
    /// save only reaches iCloud when there is a post to take down.
    @State private var savedVisibility: Visibility = .private
    /// Set once the person taps the visibility menu, so iCloud finishing its
    /// load late never overrides their choice.
    @State private var userPicked = false

    @State private var saving = false
    @State private var showCamera = false
    @State private var showRules = false
    @State private var showClaim = false
    @State private var problem: String?

    /// Which field holds the keyboard, so Done can put it away.
    @FocusState private var focused: Field?
    private enum Field: Hashable { case title, publicNote, privateNote }

    enum Visibility: String { case friends, `private` }

    private var hasPhoto: Bool { newPhoto != nil || storedPhoto != nil }
    private var shownPhoto: UIImage? { newPhoto ?? storedPhoto }
    /// Friends needs a selfie (the BeReal rule) and there is none yet.
    private var needsSelfie: Bool { visibility == .friends && !hasPhoto }
    private var hairline: Color { AppColor.textSecondary.opacity(0.12) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statsHeader
                    bleed
                    visibilityRow
                    visibilityNote
                    titleRow(last: visibility == .private)
                    if visibility == .friends { descriptionRow }
                    bleed
                    PhotoTile(shown: shownPhoto, required: visibility == .friends,
                              onTap: { showCamera = true },
                              onSimulatorPick: { newPhoto = $0 })
                        .padding(.horizontal, AppMetrics.screenPadding)
                        .padding(.vertical, 12)
                    bleed
                    sectionHeader("Details")
                    techniqueRow
                    privateNotesRow
                    Color.clear.frame(height: 110)
                }
                // The camera is presented from here, one level below the
                // sheets on the stack, so it never competes with them.
                .fullScreenCover(isPresented: $showCamera) {
                    SelfieCamera { newPhoto = $0 }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .safeAreaInset(edge: .bottom) { dock }
            .navigationTitle("Save session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    switch mode {
                    case .new:  Button("Skip") { skip() }.disabled(saving)
                    case .edit: Button("Cancel") { onDone() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                        .font(AppFont.callout.weight(.semibold))
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

    // MARK: - Header

    /// One big number, two small facts. The screen exists to grade the sit,
    /// so the grade is the only thing at hero size; time and streak are the
    /// context beside it. Gold on the score and nowhere else in this section.
    private var statsHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            stat(label: "Score", value: score.map(String.init) ?? "–", unit: nil, hero: true)
            statDivider
            stat(label: "Time", value: "\(minutes)", unit: "min", hero: false)
            statDivider
            stat(label: "Streak", value: "\(streak)", unit: streak == 1 ? "day" : "days", hero: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }

    private var minutes: Int {
        max(1, Int((Double(session?.durationSec ?? 0) / 60).rounded()))
    }

    private func stat(label: String, value: String, unit: String?, hero: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(AppColor.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(hero ? .system(size: 40, weight: .heavy, design: .rounded)
                               : .system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(hero ? AppColor.accentGold : AppColor.textPrimary)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var statDivider: some View {
        Rectangle().fill(hairline).frame(width: 1, height: 34).padding(.horizontal, 14)
    }

    // MARK: - Rows

    private var bleed: some View {
        Rectangle().fill(hairline).frame(height: 1)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    /// A bare row: content on the page, a hairline under it that starts at
    /// the text, none under the last row of a section (the bleed follows).
    private func inset<Content: View>(last: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(.vertical, 13)
                .padding(.trailing, AppMetrics.screenPadding)
            if !last { Rectangle().fill(hairline).frame(height: 1) }
        }
        .padding(.leading, AppMetrics.screenPadding)
    }

    private func rowLabel(icon: String?, text: String, placeholder: Bool, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 16)
            }
            Text(text)
                .font(AppFont.callout)
                .foregroundStyle(placeholder ? AppColor.textSecondary : AppColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// First, because it governs the rows under it. Each option says what it
    /// means in a few words, so no caption is needed beneath the row.
    private var visibilityRow: some View {
        inset {
            Menu {
                Button { pick(.friends) } label: {
                    Text("Friends")
                    Text("selfie, title, score, time, streak")
                }
                Button { pick(.private) } label: {
                    Text("Only you")
                    Text("nothing leaves your phone")
                }
            } label: {
                rowLabel(icon: visibility == .friends ? "person.2" : "lock",
                         text: visibility == .friends ? "Friends can see this" : "Only you can see this",
                         placeholder: false, chevron: true)
            }
        }
    }

    private func pick(_ value: Visibility) {
        userPicked = true
        withAnimation(.easeOut(duration: 0.18)) { visibility = value }
    }

    /// Only when something stands between Friends and sharing.
    @ViewBuilder
    private var visibilityNote: some View {
        if visibility == .friends, loaded {
            Group {
                if score == nil {
                    caption("This session has no score on this phone, so it can't be shared. Save it as Only you.")
                } else {
                    switch community.phase {
                    case .needsUsername:
                        Button { showClaim = true } label: {
                            Text("Create your profile to share with friends")
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(AppColor.accentGoldText)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppMetrics.screenPadding)
                        .padding(.vertical, 8)
                    case .unavailable:
                        caption("Sharing needs iCloud on this iPhone. Save it as Only you for now.")
                    case .loading:
                        caption("Connecting to iCloud…")
                    case .ready:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.vertical, 8)
    }

    /// Bold rather than boxed, which is how Hevy and Nike mark the title.
    /// Prefilled with Strava's default ("Afternoon meditation"), so the
    /// placeholder is rarely seen.
    private func titleRow(last: Bool) -> some View {
        inset(last: last) {
            TextField("Title your session", text: $title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .focused($focused, equals: .title)
                .submitLabel(.done)
                .onChange(of: title) { _, new in
                    if new.count > CommunityStore.titleLimit { title = String(new.prefix(CommunityStore.titleLimit)) }
                }
        }
    }

    private var descriptionRow: some View {
        inset(last: true) {
            TextField("How'd it go? Friends will see this.", text: $publicNote, axis: .vertical)
                .lineLimit(2...5)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .focused($focused, equals: .publicNote)
                .onChange(of: publicNote) { _, new in
                    if new.count > CommunityStore.captionLimit {
                        publicNote = String(new.prefix(CommunityStore.captionLimit))
                    }
                }
        }
    }

    private var techniqueRow: some View {
        inset {
            Menu {
                Button("Unreported") { technique = nil }
                Divider()
                ForEach(MeditationMethod.loggable, id: \.id) { item in
                    Button(item.label) { technique = item.id }
                }
            } label: {
                rowLabel(icon: "sparkles",
                         text: MeditationMethod.label(for: technique) ?? "What did you practise?",
                         placeholder: technique == nil, chevron: true)
            }
        }
    }

    private var privateNotesRow: some View {
        inset(last: true) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 16)
                    .padding(.top, 3)
                TextField("Private notes. Only you can see these.", text: $privateNote, axis: .vertical)
                    .lineLimit(3...8)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($focused, equals: .privateNote)
            }
        }
    }

    // MARK: - The button

    private var dock: some View {
        Button { tapPrimary() } label: {
            Text(saving ? "Saving…" : (needsSelfie ? "Take your selfie" : "Save session"))
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canAct || saving)
        // Dimmed by colour, not opacity: a translucent button shows the form
        // scrolling underneath it.
        .saturation(canAct ? 1 : 0.2)
        .brightness(canAct ? 0 : -0.25)
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(AppColor.backgroundPrimary.ignoresSafeArea(edges: .bottom))
    }

    /// The button acts whenever acting helps. Missing selfie: it opens the
    /// camera. Only you: nothing can stop a local save. Friends with a selfie:
    /// it needs a score and a profile, which the note above explains.
    private var canAct: Bool {
        guard loaded else { return false }
        if needsSelfie { return true }
        if visibility == .private { return true }
        return community.phase == .ready && score != nil
    }

    private func tapPrimary() {
        if needsSelfie { showCamera = true; return }
        if visibility == .friends, !rulesAgreed { showRules = true } else { save() }
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
        if let kept = SessionStore.photo(for: sessionID, in: context) { storedPhoto = PhotoThumbs.full(kept) }

        savedVisibility = Visibility(rawValue: reflection?.visibility ?? "private") ?? .private
        switch mode {
        case .edit: visibility = savedVisibility
        case .new:  visibility = score == nil ? .private : .friends
        }
        // Usable BEFORE iCloud answers. Only you never needs the network.
        loaded = true

        await community.load()
        if mode == .new, !userPicked, community.phase == .unavailable { visibility = .private }
        // A post made before photos were kept with the session: show its
        // picture, so an edit does not look like the selfie went missing.
        if storedPhoto == nil, savedVisibility == .friends,
           let url = await community.post(forSession: sessionID)?.photoURL,
           let legacy = UIImage(contentsOfFile: url.path) {
            storedPhoto = legacy
        }
    }

    /// Leave without grading. The session is already stored; this records it
    /// as Only you under the default title and keeps anything already typed
    /// or shot, so nothing is lost and it can be shared later from results.
    private func skip() {
        guard let session else { onDone(); return }
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SessionStore.defaultTitle(for: session.startedAt) : title
        SessionStore.saveSession(sessionID: sessionID, title: finalTitle, publicNote: publicNote,
                                 privateNote: privateNote, visibility: Visibility.private.rawValue,
                                 technique: technique, in: context)
        persistPhotoIfTaken()
        onDone()
    }

    /// Writes a fresh shot to the session's photo row (a retake replaces in
    /// place) and returns whatever row the session now has.
    @discardableResult
    private func persistPhotoIfTaken() -> SessionPhoto? {
        if let newPhoto, let jpeg = PostPhoto.jpeg(newPhoto), let thumb = PostPhoto.thumbnail(newPhoto) {
            return SessionStore.savePhoto(sessionID: sessionID, jpeg: jpeg, thumbnail: thumb, in: context)
        }
        return SessionStore.photo(for: sessionID, in: context)
    }

    private func save() {
        guard let session else { onDone(); return }
        saving = true
        Task { @MainActor in
            let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? SessionStore.defaultTitle(for: session.startedAt) : title
            SessionStore.saveSession(sessionID: sessionID, title: finalTitle, publicNote: publicNote,
                                     privateNote: privateNote, visibility: visibility.rawValue,
                                     technique: technique, in: context)
            switch visibility {
            case .private:
                persistPhotoIfTaken()
                if savedVisibility == .friends { await community.unpost(session: sessionID) }
            case .friends:
                guard ContentFilter.check([finalTitle, publicNote]) == .ok else {
                    problem = CommunityError.contentBlocked.localizedDescription
                    saving = false
                    return
                }
                if let newPhoto, await PhotoScreen.check(newPhoto) == .sensitive {
                    problem = CommunityError.photoBlocked.localizedDescription
                    saving = false
                    return
                }
                let kept = persistPhotoIfTaken()
                // Always send the bytes when there are any: about 200 KB, and
                // it means a photo taken privately and shared later, or a
                // post whose picture was lost, both come out right.
                var photoURL: URL?
                if let newPhoto { photoURL = PostPhoto.prepare(newPhoto) }
                else if let data = kept?.jpeg { photoURL = PostPhoto.prepare(data: data) }
                if photoURL == nil, newPhoto != nil {
                    problem = "That selfie couldn't be read. Take another."
                    saving = false
                    return
                }
                let draft = CommunityStore.Draft(
                    score: score ?? 0,
                    minutes: minutes,
                    streak: streak,
                    technique: MeditationMethod.label(for: technique),
                    caption: publicNote,
                    photoURL: photoURL,
                    practicedAt: session.startedAt,
                    sessionID: sessionID.uuidString,
                    title: finalTitle,
                    sound: sound)
                guard await community.post(draft) else {
                    // The reflection says Friends but nothing went up; record
                    // it as private so the chip on results tells the truth.
                    SessionStore.saveSession(sessionID: sessionID, title: finalTitle, publicNote: publicNote,
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
