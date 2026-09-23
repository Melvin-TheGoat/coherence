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
    /// Every photo and video the session currently keeps, in order. Add and
    /// remove (`addPhoto`/`removeItem`) write straight through
    /// `SessionStore` and refresh this list, so there is no separate
    /// "staged" copy to merge back in on Save (Melvin, 2026-09-23: several
    /// photos or videos, scrollable, each removable).
    @State private var mediaItems: [SessionPhoto] = []
    /// The library picker's own selection; consumed and cleared once each
    /// item has been read and added.
    @State private var pickedItems: [PhotosPickerItem] = []
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
    /// The kept item whose video is playing, if any.
    @State private var playingItem: SessionPhoto?
    @State private var showResults = false
    @State private var problem: String?

    /// Which field holds the keyboard, so Done can put it away.
    @FocusState private var focused: Field?
    private enum Field: Hashable { case title, publicNote, privateNote, techniqueNote }

    enum Visibility: String { case friends, `private` }

    var body: some View {
        GeometryReader { proxy in
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Pinned, not scrolled: scrolling it away ran the length and
                // the title straight through the status bar, and the X went
                // with them.
                skyBand(top: proxy.safeAreaInsets.top).zIndex(1)
                ScrollView {
                // Each question its own white card on the grass (Aziz,
                // 2026-09-22, `mockups/after-valley.html`), where they were
                // rows on cream split by hairlines.
                VStack(alignment: .leading, spacing: 10) {
                    feelSection.whiteCard(radius: 18)
                    whatSection.whiteCard(radius: 18)
                    if visibility == .friends { descriptionSection.whiteCard(radius: 18) }
                    notesSection.whiteCard(radius: 18)
                    mediaSection.whiteCard(radius: 18)
                    visibilitySection.whiteCard(radius: 18)
                    if score != nil { measurementsRow.whiteCard(radius: 18) }
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, AppMetrics.screenPadding)
                .padding(.top, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            dock
        }
        }
        .background(ValleyGround.meadow.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .font(AppFont.callout.weight(.semibold))
            }
        }
        .fullScreenCover(isPresented: $showCamera) { SelfieCamera { image in addPhoto(image, video: nil) } }
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
        .sheet(item: $playingItem) { item in
            if let data = item.video { VideoSheet(data: data) }
        }
        .fullScreenCover(isPresented: $showResults) {
            SessionResultsView(sessionID: sessionID)
        }
        .alert("Couldn't share that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
        .onChange(of: pickedItems) { _, items in Task { await addPicked(items) } }
        .task { await load() }
    }

    // MARK: - The sky band

    /// The valley's sky, the length as the one big number, and Otto's head on
    /// the edge of it, the way Profile wears him.
    private func skyBand(top: CGFloat) -> some View {
        let day = DayLight.at(0)
        // The scene is drawn taller than the band and cut off at its bottom,
        // so the words sit in sky and only a strip of meadow shows: at the
        // band's own height the horizon fell across the title. 0.53 is where
        // the scene's meadow begins, as a fraction of its height.
        let visible = top + Self.bandHeight
        let scene = (top + 150) / 0.53
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(minutes)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("min")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(day.inkSoft)
                }
                .foregroundStyle(day.ink)
                TextField("Title your session", text: $title)
                    .font(DisplayFont.display(18, .heavy))
                    .foregroundStyle(day.ink)
                    .focused($focused, equals: .title)
                    .submitLabel(.done)
                    .onChange(of: title) { _, new in
                        if new.count > CommunityStore.titleLimit {
                            title = String(new.prefix(CommunityStore.titleLimit))
                        }
                    }
                Text(when)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(day.inkSoft)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.top, 54)
            .padding(.trailing, 74)

            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(day.ink)
                    .frame(width: 34, height: 34)
                    .background(AppColor.backgroundPrimary.opacity(0.9), in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            }
            .padding(.leading, 12)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: Self.bandHeight, maxHeight: Self.bandHeight,
               alignment: .topLeading)
        // The valley the sit was in, running up under the status bar.
        .background(alignment: .top) {
            ValleyScene(progress: 0, showsFigure: false)
                .frame(height: scene)
                .frame(height: visible, alignment: .top)
                .clipped()
                .ignoresSafeArea(edges: .top)
                // Decoration only. `.clipped()` hides the scene's extra
                // height but does not stop it catching touches, and the band
                // sits above the list (`zIndex(1)`), so the invisible part lay
                // over the first card and swallowed every touch on the "How did
                // it feel?" slider (Melvin, 2026-09-23: "doesn't work at all").
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            OttoMark(size: 52, pose: .head)
                .padding(7)
                .background(AppColor.sky, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                .padding(.trailing, AppMetrics.screenPadding)
                .padding(.bottom, 8)
        }
    }

    private static let bandHeight: CGFloat = 196

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

    /// The inset inside every card on this page.
    private static let inset: CGFloat = 16

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Self.inset)
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
                    .foregroundStyle(rating == nil ? AppColor.textSecondary : AppColor.skyDeep)
                    .monospacedDigit()
                    .padding(.trailing, AppMetrics.screenPadding)
                    .padding(.top, 15)
            }
            RatingSlider(rating: $rating, range: 0...10)
                .padding(.horizontal, Self.inset)
            HStack {
                Text("Rough")
                Spacer()
                Text("The best")
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, Self.inset)
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
                        .foregroundStyle(AppColor.skyDeep)
                }
                .contentShape(Rectangle())
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 12)

            if technique == MeditationMethod.ownID {
                TextField("What did you do?", text: $techniqueNote, axis: .vertical)
                    .lineLimit(1...3)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($focused, equals: .techniqueNote)
                    .padding(.horizontal, Self.inset)
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
                .padding(.horizontal, Self.inset)
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
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 12)
        }
    }

    /// Any photo, any video, shared or not, as a scrollable row of everything
    /// the session keeps (Melvin, 2026-09-23: "you should be able to share
    /// multiple photos or videos... should be scrollable"), plus two small
    /// add tiles. Every tile is one height and its OWN shape, the rule the
    /// feed follows ("do not change the aspect ratio at all"), so what you
    /// add here is what your friends see.
    private static let mediaTileHeight: CGFloat = 104

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Photos and video")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(mediaItems, id: \.id) { item in
                        mediaThumb(item)
                    }
                    if mediaItems.count < SessionStore.maxPhotosPerSession {
                        Button { showCamera = true } label: { addTileLabel("camera") }
                            .buttonStyle(.plain)
                        PhotosPicker(selection: $pickedItems, maxSelectionCount: remainingSlots,
                                    matching: .any(of: [.images, .videos])) {
                            addTileLabel("photo.on.rectangle")
                        }
                    }
                }
                .padding(.horizontal, Self.inset)
            }
            .scrollIndicators(.hidden)
            if loadingMedia {
                Text("Getting it ready…")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 6)
            }
            Color.clear.frame(height: 12)
        }
    }

    private var remainingSlots: Int { max(1, SessionStore.maxPhotosPerSession - mediaItems.count) }

    /// One kept item: a video plays on tap; a remove badge sits over every
    /// tile, its own button so it never fights the play tap underneath it.
    private func mediaThumb(_ item: SessionPhoto) -> some View {
        let shot = PhotoThumbs.image(for: item)
        // A portrait shot's shape until the thumbnail has decoded.
        let aspect = shot.map { $0.size.width / max($0.size.height, 1) } ?? 0.75
        return Button {
            if item.video != nil { playingItem = item }
        } label: {
            Color.clear
                .frame(width: Self.mediaTileHeight * aspect, height: Self.mediaTileHeight)
                .overlay { if let shot { Image(uiImage: shot).resizable().scaledToFill() } }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if item.video != nil {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .padding(7)
                    }
                }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button { removeItem(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(5)
        }
    }

    /// The dashed empty tile, same shape whether it opens the camera or the
    /// library picker.
    private func addTileLabel(_ icon: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(AppColor.textSecondary.opacity(0.35))
            .frame(width: 56, height: Self.mediaTileHeight)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AppColor.textSecondary)
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
                    .foregroundStyle(AppColor.skyDeep)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.skyDeep)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Who can see it")
            HStack(spacing: 0) {
                visibilityPill(.private, icon: "lock", text: "Only you")
                visibilityPill(.friends, icon: "person.2", text: "Friends")
            }
            .padding(3)
            .background(ValleyGround.quiet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, Self.inset)
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
                .font(AppFont.callout.weight(.bold))
                .foregroundStyle(visibility == value ? .white : AppColor.meadowInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if visibility == value {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AppColor.skyDeep)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Only when something stands between Friends and sharing.
    @ViewBuilder
    private var visibilityNote: some View {
        if visibility == .friends, loaded {
            Group {
                switch community.phase {
                case .needsUsername:
                    Button { showClaim = true } label: {
                        Text("Create your profile to share with friends")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColor.skyDeep)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Self.inset)
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

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, Self.inset)
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
        .padding(.top, 26)
        .padding(.bottom, 10)
        // The grass fading up under Save, so the cards slide beneath it.
        // It must not catch touches: a gradient takes them across its whole
        // frame, even where it is clear, so the strip above Save swallowed
        // taps on whatever had scrolled under it, which was usually the
        // Choose and Selfie buttons (Melvin, 2026-09-23: "the button for take
        // a selfie ... sometimes like doesnt read that i clicked it").
        .background(
            LinearGradient(stops: [.init(color: ValleyGround.meadow.opacity(0), location: 0),
                                   .init(color: ValleyGround.meadow, location: 0.4)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    /// Only you can always be saved; Friends needs a profile, which the note
    /// above the button explains. **It never needs a score**: a post never
    /// carries one, whether or not the sit had one (2026-09-22, then made
    /// absolute 2026-09-23).
    private var canAct: Bool {
        guard loaded else { return false }
        if visibility == .private { return true }
        return community.phase == .ready
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

    /// Reads and adds every item the library picker returned, in order, up
    /// to whatever room is left. Each is persisted as it is read (`addPhoto`)
    /// rather than staged, so leaving the screen never loses one that was
    /// already added.
    private func addPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        loadingMedia = true
        defer { loadingMedia = false; pickedItems = [] }
        for item in items {
            guard mediaItems.count < SessionStore.maxPhotosPerSession else { break }
            // A still first: most picks are photos, and a video's poster
            // frame goes in the same place, so everything that draws a photo
            // keeps working without knowing there is a film behind it.
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                addPhoto(image, video: nil)
                continue
            }
            guard let movie = try? await item.loadTransferable(type: Movie.self) else {
                problem = "That one couldn't be read. Try another."
                continue
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            guard let exported = await SessionVideo.export(movie.url),
                  let poster = SessionVideo.posterFrame(movie.url) else {
                problem = "That video couldn't be saved. Try a shorter one."
                continue
            }
            addPhoto(poster, video: exported)
        }
    }

    @discardableResult
    private func addPhoto(_ image: UIImage, video: Data?) -> Bool {
        guard let jpeg = PostPhoto.jpeg(image), let thumb = PostPhoto.thumbnail(image) else { return false }
        guard let row = SessionStore.addPhoto(sessionID: sessionID, jpeg: jpeg, thumbnail: thumb,
                                              video: video, in: context) else {
            problem = "That's as many as a session can hold (\(SessionStore.maxPhotosPerSession))."
            return false
        }
        mediaItems.append(row)
        return true
    }

    private func removeItem(_ item: SessionPhoto) {
        SessionStore.removePhotoItem(id: item.id, in: context)
        mediaItems.removeAll { $0.id == item.id }
        if playingItem?.id == item.id { playingItem = nil }
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
        mediaItems = SessionStore.photos(for: sessionID, in: context)

        savedVisibility = Visibility(rawValue: reflection?.visibility ?? "private") ?? .private
        visibility = savedVisibility
        // Usable BEFORE iCloud answers. Only you never needs the network.
        loaded = true

        await community.load()
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
                if savedVisibility == .friends { await community.unpost(session: sessionID) }
            case .friends:
                guard ContentFilter.check([finalTitle, publicNote]) == .ok else {
                    problem = CommunityError.contentBlocked.localizedDescription
                    saving = false
                    return
                }
                // Every kept item, screened before anything goes up. A video
                // screens its poster frame, the same still `jpeg` always
                // holds (2026-09-22: "any photo and any video, for friends
                // and for yourself").
                for item in mediaItems {
                    guard let jpeg = item.jpeg, let img = UIImage(data: jpeg) else { continue }
                    if await PhotoScreen.check(img) == .sensitive {
                        problem = CommunityError.photoBlocked.localizedDescription
                        saving = false
                        return
                    }
                }
                // Always sends the CURRENT full list, in order: a post always
                // ends up matching exactly what this screen shows, add or
                // remove, rather than merging against whatever it had before.
                let media = mediaItems.compactMap { PostMediaPrep.draft(for: $0) }
                // No `score:` here (2026-09-23): a post never carries one, even
                // though this screen still knows the sit's score for its own
                // "See the measurements" row below.
                let draft = CommunityStore.Draft(
                    minutes: minutes,
                    streak: streak,
                    technique: MeditationMethod.label(for: technique),
                    caption: publicNote,
                    media: media,
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

// MARK: - Rating

/// A 1-to-10 rating control that starts unrated (a flat grey track, no
/// value implied) and answers to a tap ANYWHERE on the track as well as a
/// drag, which is the whole reason this isn't the system `Slider`.
///
/// **Why the system `Slider` read as "doesn't work at all":** a `UISlider`
/// (what SwiftUI's `Slider` is on iOS) only starts tracking a touch that
/// lands on its thumb, so a tap anywhere else on the track does nothing;
/// and a drag begun on it can still lose to the enclosing `ScrollView`'s own
/// pan gesture, a documented UIKit gotcha for sliders inside scroll views.
/// Neither failure is silent-but-stiff, it's silent-but-NOTHING, which is
/// exactly "doesn't work at all" from the tapping side.
///
/// `DragGesture(minimumDistance: 0)` sidesteps both: `onChanged` fires the
/// instant a finger touches down (so a tap moves the thumb there) and again
/// on every move after (so it also drags), and because it is SwiftUI's own
/// gesture attached directly to this view rather than routed through a
/// UIKit control, the descendant gesture wins against the scroll view by
/// default, with nothing extra to ask for.
private struct RatingSlider: View {
    @Binding var rating: Int?
    let range: ClosedRange<Int>

    private let trackHeight: CGFloat = 6
    private let thumbDiameter: CGFloat = 26
    private let rowHeight: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - thumbDiameter, 1)
            let center = thumbDiameter / 2 + travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColor.meadowInk.opacity(0.16))
                    .frame(height: trackHeight)
                Capsule()
                    // Sky, because rating is a choice; gold is kept for Save.
                    .fill(rating == nil ? AppColor.meadowInk.opacity(0.16) : AppColor.skyDeep)
                    .frame(width: center, height: trackHeight)
                Circle()
                    .fill(.white)
                    .overlay {
                        Circle().stroke(rating == nil ? AppColor.meadowInk.opacity(0.35) : AppColor.skyDeep,
                                       lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: center - thumbDiameter / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // The whole row is tappable, not just the thin drawn track: a
            // generous hit area, same reasoning as the selfie shutter's.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in set(from: drag.location.x, in: geo.size.width) }
            )
        }
        .frame(height: rowHeight)
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { Double(rating ?? midpoint) },
                                  set: { rating = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
        }
    }

    private var midpoint: Int { (range.lowerBound + range.upperBound) / 2 }

    /// Where the thumb sits: the real rating once there is one, otherwise
    /// the midpoint, purely for the "slide me" affordance. Never written
    /// back until the person actually touches the control.
    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let value = rating ?? midpoint
        return CGFloat(value - range.lowerBound) / CGFloat(span)
    }

    private func set(from x: CGFloat, in width: CGFloat) {
        rating = RatingSliderMath.value(atX: x, width: width,
                                        thumbDiameter: thumbDiameter, range: range)
    }
}

/// The position-to-value arithmetic behind `RatingSlider`, pulled out of the
/// view so it can be unit tested directly: the view itself only exercises
/// correctly under a live touch (a device, or an XCUITest), but the mapping
/// from a touch location to a 0-to-10 value is a pure function and this is
/// the binding the drag gesture writes through.
enum RatingSliderMath {
    static func value(atX x: CGFloat, width: CGFloat, thumbDiameter: CGFloat,
                      range: ClosedRange<Int>) -> Int {
        let travel = max(width - thumbDiameter, 1)
        let clamped = min(max(x - thumbDiameter / 2, 0), travel)
        let span = range.upperBound - range.lowerBound
        let raw = Double(clamped / travel) * Double(span)
        let value = range.lowerBound + Int(raw.rounded())
        return min(max(value, range.lowerBound), range.upperBound)
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

    /// Bytes already stored on a `SessionPhoto`, written out for `CKAsset`
    /// the same way a fresh export already is.
    static func tempFile(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("post-video-\(UUID().uuidString).mp4")
        do { try data.write(to: url) } catch { return nil }
        return url
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
