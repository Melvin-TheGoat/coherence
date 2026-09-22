import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

/// **The session screen**: everything you might say about a sit, on one page
/// (`mockups/after-session.html`, screen 1, Melvin's pick 2026-09-22).
///
/// It no longer opens itself after a session. A finished sit goes to Home and
/// plays Otto's glow; a toast above the tab bar opens this when they want it.
/// So this screen is somewhere you choose to be, and it may take its time.
///
/// Top to bottom: the sky band with the length as the one big number and
/// Otto's head as the mark, then how it felt (a slider out of ten, not
/// emojis), what you did (every technique AND every sound 808 offers), the
/// description friends read, private notes, photos or video, and who can see
/// it. Nothing is required. Gold lands twice: the slider's fill and Save.
///
/// The old version of this screen was Strava's, with visibility first and a
/// front-camera selfie required before anything could be posted. Both are
/// gone (Melvin: any photo, any video, for friends and for yourself).
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
    /// The words behind "Something else", kept and saved like the results
    /// card keeps them.
    @State private var techniqueNote: String = ""
    /// Out of ten. nil until the slider is touched, because a slider parked
    /// at five would file every unrated session as middling.
    @State private var rating: Int?
    @State private var visibility: Visibility = .private
    /// Media taken or picked on this screen and not yet saved.
    @State private var newPhoto: UIImage?
    @State private var newVideo: Data?
    /// What the session already keeps. Picking again replaces it.
    @State private var storedPhoto: UIImage?
    @State private var storedVideo: Data?
    @State private var pickedItem: PhotosPickerItem?
    @State private var loadingMedia = false
    @State private var loaded = false
    /// What the session was saved as before this screen opened, so an
    /// Only-you save only reaches iCloud when there is a post to take down.
    @State private var savedVisibility: Visibility = .private
    /// Set once they choose, so iCloud finishing its load late never
    /// overrides the choice.
    @State private var userPicked = false

    @State private var saving = false
    @State private var showCamera = false
    @State private var showRules = false
    @State private var showClaim = false
    @State private var playing = false
    @State private var showResults = false
    @State private var problem: String?

    /// Which field holds the keyboard, so Done can put it away.
    @FocusState private var focused: Field?
    private enum Field: Hashable { case title, publicNote, privateNote, techniqueNote }

    enum Visibility: String { case friends, `private` }

    private var hasMedia: Bool { newPhoto != nil || storedPhoto != nil }
    private var shownPhoto: UIImage? { newPhoto ?? storedPhoto }
    private var shownVideo: Data? { newVideo ?? storedVideo }
    private var hairline: Color { AppColor.textSecondary.opacity(0.12) }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Pinned, not scrolled: scrolling it away ran the length and
                // the title straight through the status bar, and the X went
                // with them.
                skyBand.zIndex(1)
                ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    feelSection
                    bleed
                    whatSection
                    bleed
                    if visibility == .friends { descriptionSection; bleed }
                    notesSection
                    bleed
                    mediaSection
                    bleed
                    visibilitySection
                    if score != nil { bleed; measurementsRow }
                    Color.clear.frame(height: 132)
                }
                .padding(.top, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            dock
        }
        .background(AppColor.backgroundPrimary.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .font(AppFont.callout.weight(.semibold))
            }
        }
        .fullScreenCover(isPresented: $showCamera) { SelfieCamera { newPhoto = $0; newVideo = nil } }
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
        .sheet(isPresented: $playing) {
            if let data = shownVideo { VideoSheet(data: data) }
        }
        .fullScreenCover(isPresented: $showResults) {
            SessionResultsView(sessionID: sessionID)
        }
        .alert("Couldn't share that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
        .onChange(of: pickedItem) { _, item in Task { await take(item) } }
        .task { await load() }
    }

    // MARK: - The sky band

    /// The valley's sky, the length as the one big number, and Otto's head on
    /// the edge of it, the way Profile wears him.
    private var skyBand: some View {
        let day = DayLight.at(0)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [day.sky[0], day.sky[1]], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(minutes)")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("min")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(day.ink)
                TextField("Title your session", text: $title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(day.ink)
                    .focused($focused, equals: .title)
                    .submitLabel(.done)
                    .onChange(of: title) { _, new in
                        if new.count > CommunityStore.titleLimit {
                            title = String(new.prefix(CommunityStore.titleLimit))
                        }
                    }
                Text(when)
                    .font(AppFont.caption)
                    .foregroundStyle(day.ink.opacity(0.7))
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 16)
            .padding(.trailing, 74)

            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(day.ink.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .background(AppColor.backgroundPrimary.opacity(0.7), in: Circle())
            }
            .padding(.leading, 12)
            .padding(.top, 10)
        }
        .frame(height: 168)
        .overlay(alignment: .bottomTrailing) {
            OttoMark(size: 52, pose: .head)
                .padding(9)
                .background(AppColor.backgroundPrimary, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                .padding(.trailing, AppMetrics.screenPadding)
                .offset(y: 26)
        }
    }

    private var minutes: Int {
        max(1, Int((Double(session?.durationSec ?? 0) / 60).rounded()))
    }

    /// "Today, 12:48 · Rain", which is the sit in one line.
    private var when: String {
        let date = session?.startedAt ?? Date()
        let day = Calendar.current.isDateInToday(date) ? "Today"
            : Calendar.current.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(.dateTime.weekday(.wide).day().month())
        return "\(day), \(date.formatted(date: .omitted, time: .shortened)) · \(sound)"
    }

    // MARK: - Sections

    private var bleed: some View {
        Rectangle().fill(hairline).frame(height: 1)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 15)
            .padding(.bottom, 2)
    }

    /// A slider out of ten (Melvin: a scroll bar, not emojis). It starts in
    /// the middle and greyed, and only becomes a rating once it is touched.
    private var feelSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionHeader("How did it feel?")
                Spacer()
                Text(rating.map { "\($0) / 10" } ?? "Not rated")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(rating == nil ? AppColor.textSecondary : AppColor.accentGoldText)
                    .monospacedDigit()
                    .padding(.trailing, AppMetrics.screenPadding)
                    .padding(.top, 15)
            }
            Slider(value: Binding(get: { Double(rating ?? 5) },
                                  set: { rating = Int($0.rounded()) }),
                   in: 0...10, step: 1)
                .tint(rating == nil ? AppColor.trace : AppColor.accentGold)
                .padding(.horizontal, AppMetrics.screenPadding)
            HStack {
                Text("Rough")
                Spacer()
                Text("The best")
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 14)
        }
    }

    /// Every technique and every sound (Melvin, 2026-09-22). The sounds are
    /// grouped the way the picker groups them, so the list stays walkable.
    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("What did you do?")
            Menu {
                TechniqueOptions { technique = $0 }
            } label: {
                HStack(spacing: 10) {
                    Text(MeditationMethod.label(for: technique) ?? "Pick a practice or a sound")
                        .font(AppFont.callout)
                        .foregroundStyle(technique == nil ? AppColor.textSecondary : AppColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.vertical, 12)

            if technique == MeditationMethod.ownID {
                TextField("What did you do?", text: $techniqueNote, axis: .vertical)
                    .lineLimit(1...3)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($focused, equals: .techniqueNote)
                    .padding(.horizontal, AppMetrics.screenPadding)
                    .padding(.bottom, 12)
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("What friends will read")
            TextField("How did it go?", text: $publicNote, axis: .vertical)
                .lineLimit(2...5)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .focused($focused, equals: .publicNote)
                .onChange(of: publicNote) { _, new in
                    if new.count > CommunityStore.captionLimit {
                        publicNote = String(new.prefix(CommunityStore.captionLimit))
                    }
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.vertical, 12)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Notes")
            TextField("Anything you want to remember. Only you can see this.",
                      text: $privateNote, axis: .vertical)
                .lineLimit(3...8)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .focused($focused, equals: .privateNote)
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.vertical, 12)
        }
    }

    /// Any photo, any video, shared or not. The tile is portrait, because a
    /// portrait shot in a landscape slot loses the face every time.
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Photo or video")
            HStack(spacing: 12) {
                if let shot = shownPhoto {
                    Button { if shownVideo != nil { playing = true } } label: {
                        Image(uiImage: shot)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 78, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                if shownVideo != nil {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 3)
                                        .padding(7)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                        Label(hasMedia ? "Choose another" : "Choose photo or video",
                              systemImage: "photo.on.rectangle")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.accentGoldText)
                    }
                    Button { showCamera = true } label: {
                        Label("Take a selfie", systemImage: "camera")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if loadingMedia {
                        Text("Getting it ready…")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.vertical, 12)
        }
    }

    /// A Watch session measured something; the curves are one tap in. The
    /// page itself is what you SAY about the sit, which is true of every
    /// session; measurements are true of some.
    private var measurementsRow: some View {
        Button { showResults = true } label: {
            HStack(spacing: 10) {
                Text("See the measurements")
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.accentGoldText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.accentGoldText)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Who can see it")
            HStack(spacing: 10) {
                visibilityPill(.private, icon: "lock", text: "Only you")
                visibilityPill(.friends, icon: "person.2", text: "Friends")
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.vertical, 12)
            visibilityNote
        }
    }

    private func visibilityPill(_ value: Visibility, icon: String, text: String) -> some View {
        Button {
            userPicked = true
            withAnimation(.easeOut(duration: 0.18)) { visibility = value }
        } label: {
            Label(text, systemImage: icon)
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(visibility == value ? AppColor.textPrimary : AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppColor.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(visibility == value ? AppColor.accentGold : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
    }

    /// Only when something stands between Friends and sharing.
    @ViewBuilder
    private var visibilityNote: some View {
        if visibility == .friends, loaded {
            Group {
                if score == nil {
                    caption(session?.isPhoneOnly == true
                            ? "A post carries a score, and nothing measured this sit. Save it as Only you."
                            : "This session has no score on this phone, so it can't be shared. Save it as Only you.")
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
                        .padding(.bottom, 8)
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
            .padding(.bottom, 8)
    }

    // MARK: - The button

    private var dock: some View {
        Button { tapPrimary() } label: {
            Text(saving ? "Saving…" : "Save")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canAct || saving)
        // Dimmed by colour, not opacity: a translucent button shows the form
        // scrolling underneath it.
        .saturation(canAct ? 1 : 0.2)
        .brightness(canAct ? 0 : -0.25)
        .padding(.horizontal, AppMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(AppColor.backgroundPrimary.ignoresSafeArea(edges: .bottom))
    }

    /// Only you can always be saved; Friends needs a score and a profile,
    /// which the note above the button explains.
    private var canAct: Bool {
        guard loaded else { return false }
        if visibility == .private { return true }
        return community.phase == .ready && score != nil
    }

    private func tapPrimary() {
        if visibility == .friends, !rulesAgreed { showRules = true } else { save() }
    }

    // MARK: - Media

    /// A movie handed over by the picker, as a file we can read.
    private struct Movie: Transferable {
        let url: URL
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("808-pick-\(UUID().uuidString).mov")
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: received.file, to: copy)
                return Movie(url: copy)
            }
        }
    }

    private func take(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        loadingMedia = true
        defer { loadingMedia = false }
        // A still first: most picks are photos, and a video's poster frame
        // goes in the same place, so everything that draws a photo keeps
        // working without knowing there is a film behind it.
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            newPhoto = image
            newVideo = nil
            return
        }
        guard let movie = try? await item.loadTransferable(type: Movie.self) else {
            problem = "That one couldn't be read. Try another."
            return
        }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        guard let exported = await SessionVideo.export(movie.url) else {
            problem = "That video couldn't be saved. Try a shorter one."
            return
        }
        newVideo = exported
        newPhoto = SessionVideo.posterFrame(movie.url) ?? newPhoto
        if newPhoto == nil {
            problem = "That video couldn't be saved. Try a shorter one."
            newVideo = nil
        }
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
        techniqueNote = reflection?.techniqueNote ?? ""
        rating = reflection?.rating
        technique = reflection?.technique
            // Whatever played is the likeliest answer to "what did you do",
            // and it is already known, so it starts there.
            ?? session?.frequencyID
            ?? (session?.mode == SessionMode.guided.rawValue ? MeditationMethod.guidedID : nil)
            ?? (session?.mode == SessionMode.silence.rawValue ? MeditationMethod.silenceID : nil)
        if let kept = SessionStore.photo(for: sessionID, in: context) {
            storedPhoto = PhotoThumbs.full(kept)
            storedVideo = kept.video
        }

        savedVisibility = Visibility(rawValue: reflection?.visibility ?? "private") ?? .private
        visibility = savedVisibility
        // Usable BEFORE iCloud answers. Only you never needs the network.
        loaded = true

        await community.load()
        // A post made before photos were kept with the session: show its
        // picture, so an edit does not look like the selfie went missing.
        if storedPhoto == nil, savedVisibility == .friends,
           let url = await community.post(forSession: sessionID)?.photoURL,
           let legacy = UIImage(contentsOfFile: url.path) {
            storedPhoto = legacy
        }
    }

    /// Writes fresh media to the session's photo row (a new pick replaces in
    /// place) and returns whatever row the session now has.
    @discardableResult
    private func persistMediaIfPicked() -> SessionPhoto? {
        if let newPhoto, let jpeg = PostPhoto.jpeg(newPhoto), let thumb = PostPhoto.thumbnail(newPhoto) {
            return SessionStore.savePhoto(sessionID: sessionID, jpeg: jpeg, thumbnail: thumb,
                                          video: newVideo, in: context)
        }
        return SessionStore.photo(for: sessionID, in: context)
    }

    private func save() {
        guard let session else { onDone(); return }
        saving = true
        Task { @MainActor in
            let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? SessionStore.defaultTitle(for: session.startedAt) : title
            let row = SessionStore.saveSession(sessionID: sessionID, title: finalTitle,
                                               publicNote: publicNote, privateNote: privateNote,
                                               visibility: visibility.rawValue,
                                               technique: technique, techniqueNote: techniqueNote,
                                               in: context)
            // `saveSession` keeps whatever rating was there; this screen owns
            // it now, so it writes it after.
            row.rating = rating
            try? context.save()
            switch visibility {
            case .private:
                persistMediaIfPicked()
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
                let kept = persistMediaIfPicked()
                // Always send the bytes when there are any: about 200 KB, and
                // it means a photo kept privately and shared later, or a post
                // whose picture was lost, both come out right. A video's
                // poster frame is what goes up for now; the feed cannot play
                // film yet.
                var photoURL: URL?
                if let newPhoto { photoURL = PostPhoto.prepare(newPhoto) }
                else if let data = kept?.jpeg { photoURL = PostPhoto.prepare(data: data) }
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
                                             technique: technique, techniqueNote: techniqueNote, in: context)
                    problem = community.errorText ?? "Couldn't reach iCloud."
                    community.errorText = nil
                    saving = false
                    return
                }
            }
            saving = false
            SessionDetails.clear(sessionID)
            onDone()
        }
    }
}

/// Keeping a video with a session: small enough to ride the same private
/// iCloud the sessions do, so half a minute at 540p and nothing more.
enum SessionVideo {
    static let maxSeconds: Double = 30

    static func export(_ url: URL, limit: Double = maxSeconds) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPreset960x540) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("808-video-\(UUID().uuidString).mp4")
        session.outputURL = out
        session.outputFileType = .mp4
        let duration = (try? await asset.load(.duration)) ?? .zero
        if CMTimeGetSeconds(duration) > limit {
            session.timeRange = CMTimeRange(start: .zero,
                                            duration: CMTime(seconds: limit, preferredTimescale: 600))
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { done.resume() }
        }
        defer { try? FileManager.default.removeItem(at: out) }
        guard session.status == .completed else { return nil }
        return try? Data(contentsOf: out)
    }

    /// The first readable frame, which becomes the session's still.
    static func posterFrame(_ url: URL) -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1.5, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.3, preferredTimescale: 600),
                                                  actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Plays a kept video. Written to a temp file first, because AVPlayer reads
/// files and the video lives in the store as bytes.
private struct VideoSheet: View {
    let data: Data

    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                VideoPlayer(player: AVPlayer(url: url))
            } else {
                ProgressView().tint(AppColor.calmAccent)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("808-play-\(UUID().uuidString).mp4")
            try? data.write(to: file)
            url = file
        }
        .onDisappear { if let url { try? FileManager.default.removeItem(at: url) } }
    }
}
