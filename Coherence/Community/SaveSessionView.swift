import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import os

/// **The session screen**: everything you might say about a sit, on one page
/// (`mockups/after-session.html`, screen 1, Melvin's pick 2026-09-22).
///
/// It no longer opens itself after a session. A finished sit goes to Home and
/// plays Otto's glow; a toast above the tab bar opens this when they want it.
/// So this screen is somewhere you choose to be, and it may take its time.
///
/// Top to bottom: the sky band with the length as the one big number and
/// Otto's head as the mark, then how it felt (a slider out of ten, not
/// emojis), what you did (every technique AND every sound 808 offers),
/// private notes, and photos or video. Nothing is required. Gold lands twice:
/// the slider's fill and Save.
///
/// **Posting removed entirely** (Melvin, 2026-09-27: "get rid of the feed, no
/// more posting with photos/videos since its a big privacy policy change").
/// This page used to ask who could see it and, for Friends, a description and
/// a reserved username; none of that exists here any more. Everything on it
/// is private — this is your own record of the sit, kept on this phone (and,
/// for the ones that sync, in your own iCloud).
struct SaveSessionView: View {
    enum Mode { case new, edit }

    let sessionID: UUID
    let mode: Mode
    let onDone: () -> Void

    @Environment(\.modelContext) private var context

    @State private var session: Session?
    @State private var score: Int?
    /// The Watch's readings, when it measured this session.
    @State private var bodyReadings: BodyReadings?
    @State private var measuredScore: Double?
    @State private var streak = 0
    @State private var sound = "Silence"

    @State private var title = ""
    @State private var privateNote = ""
    @State private var technique: String?
    /// The words behind "Something else", kept and saved like the results
    /// card keeps them.
    @State private var techniqueNote: String = ""
    /// Out of ten. nil until the slider is touched, because a slider parked
    /// at five would file every unrated session as middling.
    @State private var rating: Int?
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
    /// How far a picked video's preparation has got, while it runs.
    @State private var videoProgress: Double?
    @State private var loaded = false

    @State private var saving = false
    @State private var showCamera = false
    /// The kept item whose video is playing, if any.
    @State private var playingItem: SessionPhoto?
    @State private var showResults = false
    @State private var problem: String?

    /// Which field holds the keyboard, so Done can put it away.
    @FocusState private var focused: Field?
    private enum Field: Hashable { case title, privateNote, techniqueNote }

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
                    notesSection.whiteCard(radius: 18)
                    mediaSection.whiteCard(radius: 18)
                    if let readings = bodyReadings {
                        BodyCard(readings: readings, score: measuredScore, seeGraphs: { showResults = true }, inset: Self.inset)
                            .whiteCard(radius: 18)
                    }
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
        .sheet(item: $playingItem) { item in
            if let data = item.video { VideoSheet(data: data) }
        }
        .fullScreenCover(isPresented: $showResults) {
            SessionResultsView(sessionID: sessionID)
        }
        .alert("Couldn't save that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
        .onChange(of: pickedItems) { _, items in Task { await addPicked(items) } }
        .task { await load() }
    }

    // MARK: - The sky band

    /// The valley's sky, the length as the one big number, and Otto's head on
    /// the edge of it, the way Profile wears him.
    private func skyBand(top: CGFloat) -> some View {
        let day = DayLight.now
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
            ValleyScene(progress: 0, showsFigure: false, clock: true)
                .frame(height: scene)
                .frame(height: visible, alignment: .top)
                .clipped()
                .fadesIntoMeadow()
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
                .overlay(Circle().stroke(AppColor.backgroundSecondary, lineWidth: 3))
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
                        // `.current`: the original file, as it is. The default
                        // lets Photos convert a video to a "compatible" format
                        // before handing it over, which for a phone's 4K clip
                        // is most of a minute of spinner, and then we convert
                        // it again anyway.
                        PhotosPicker(selection: $pickedItems, maxSelectionCount: remainingSlots,
                                    matching: .any(of: [.images, .videos]),
                                    preferredItemEncoding: .current) {
                            addTileLabel("photo.on.rectangle")
                        }
                    }
                }
                .padding(.horizontal, Self.inset)
            }
            .scrollIndicators(.hidden)
            if loadingMedia {
                Text(videoProgress.map { "Preparing your video… \(Int(($0 * 100).rounded()))%" }
                     ?? "Getting it ready…")
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

    // MARK: - The button

    private var dock: some View {
        Button { save() } label: {
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

    private var canAct: Bool { loaded }

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
            // A video is read as a FILE and never as `Data`: asking for Data
            // first (to see whether it was a photo) pulled the whole clip into
            // memory before anything else happened. A Live Photo offers an
            // image as well as its movie, and is kept as the photo.
            let types = item.supportedContentTypes
            let isVideo = types.contains { $0.conforms(to: .movie) } && !types.contains { $0.conforms(to: .image) }
            if isVideo {
                await addVideo(item)
                continue
            }
            // A still: most picks are photos, and a video's poster frame goes
            // in the same place, so everything that draws a photo keeps
            // working without knowing there is a film behind it.
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                addPhoto(image, video: nil)
                continue
            }
            if types.contains(where: { $0.conforms(to: .movie) }) {
                await addVideo(item)
            } else {
                problem = "That one couldn't be read. Try another."
            }
        }
    }

    /// Up to five minutes (Melvin, 2026-09-27: "at least allow like 90s
    /// videos, maybe even like 5 minutes"). The length is checked the moment
    /// the file is in hand, so a clip that is too long is turned away at once
    /// instead of after a minute of converting it (a 37-second clip used to
    /// convert and then fail under a message that blamed its length).
    private func addVideo(_ item: PhotosPickerItem) async {
        guard let movie = try? await item.loadTransferable(type: Movie.self) else {
            problem = "That video couldn't be read. Try another."
            return
        }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        if let seconds = await SessionVideo.duration(of: movie.url), seconds > SessionVideo.maxSeconds + 0.5 {
            problem = "Videos can be up to 5 minutes, and that one is \(SessionVideo.clock(seconds)). Trim it in Photos, then add it again."
            return
        }
        videoProgress = 0
        defer { videoProgress = nil }
        guard let exported = await SessionVideo.export(movie.url, progress: { videoProgress = $0 }),
              let poster = SessionVideo.posterFrame(movie.url) else {
            problem = "That video couldn't be added. Try it again, or try another."
            return
        }
        addPhoto(poster, video: exported)
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
        if let stats {
            bodyReadings = BodyReadings(stats)
            measuredScore = stats.overallScore
        }
        streak = StreakCalculator.streak(from: SessionStore.sessionStartDates(in: context)).current
        sound = SoundCatalog.title(for: session?.frequencyID) ?? "Silence"

        let reflection = SessionStore.reflection(for: sessionID, in: context)
        title = (reflection?.title).flatMap { $0.isEmpty ? nil : $0 }
            ?? SessionStore.defaultTitle(for: session?.startedAt ?? Date())
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
        loaded = true
    }

    private func save() {
        guard let session else { onDone(); return }
        saving = true
        Task { @MainActor in
            let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? SessionStore.defaultTitle(for: session.startedAt) : title
            // `publicNote` and `visibility` are left at their stored defaults
            // ("" and "private"): posting is gone, so nothing here ever writes
            // anything but a private record any more.
            let row = SessionStore.saveSession(sessionID: sessionID, title: finalTitle,
                                               publicNote: "", privateNote: privateNote,
                                               visibility: "private",
                                               technique: technique, techniqueNote: techniqueNote,
                                               in: context)
            // `saveSession` keeps whatever rating was there; this screen owns
            // it now, so it writes it after.
            row.rating = rating
            try? context.save()
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

/// Keeping a video with a session. It rides the private iCloud the sessions
/// do, and a posted one goes to the public database, so every clip is kept
/// to about 40 MB whatever its length: short clips stay sharp, long ones
/// trade detail for length.
enum SessionVideo {
    /// Five minutes (Melvin, 2026-09-27). It was half a minute.
    static let maxSeconds: Double = 300

    private static let log = Logger(subsystem: "com.lockout.meditate808", category: "video")

    /// Measured on a real 4K iPhone clip (2026-09-27): 960x540 runs about
    /// 4.8 Mbps, 640x480 about 2.7, Medium (360 by 640) about 1. So a
    /// minute at 540p, two at 480p and five at 360p all land near 36 to
    /// 40 MB. At 540p throughout, five minutes was about 180 MB.
    static func preset(forSeconds seconds: Double) -> String {
        if seconds <= 60 { return AVAssetExportPreset960x540 }
        if seconds <= 120 { return AVAssetExportPreset640x480 }
        return AVAssetExportPresetMediumQuality
    }

    static func duration(of url: URL) async -> Double? {
        guard let d = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let s = CMTimeGetSeconds(d)
        return s.isFinite ? s : nil
    }

    /// "7:12", for telling someone how long their clip is.
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func export(_ url: URL, progress: @escaping @MainActor (Double) -> Void = { _ in }) async -> Data? {
        let asset = AVURLAsset(url: url)
        let seconds = await duration(of: url) ?? 0
        guard let session = AVAssetExportSession(asset: asset, presetName: preset(forSeconds: seconds)) else {
            log.error("no export session for a \(seconds, privacy: .public) s clip")
            return nil
        }
        // Past the limit only by rounding; the caller already turned away
        // anything longer.
        if seconds > maxSeconds {
            session.timeRange = CMTimeRange(start: .zero,
                                            duration: CMTime(seconds: maxSeconds, preferredTimescale: 600))
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("808-video-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        if #available(iOS 18, *) {
            let watcher = Task {
                for await state in session.states(updateInterval: 0.25) {
                    if case .exporting(let p) = state { await progress(p.fractionCompleted) }
                }
            }
            defer { watcher.cancel() }
            do {
                try await session.export(to: out, as: .mp4)
            } catch {
                log.error("export failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        } else {
            session.outputURL = out
            session.outputFileType = .mp4
            let watcher = Task {
                while !Task.isCancelled {
                    await progress(Double(session.progress))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { done.resume() }
            }
            watcher.cancel()
            guard session.status == .completed else {
                log.error("export failed: \(String(describing: session.error), privacy: .public)")
                return nil
            }
        }
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
///
/// Not `private`: `SessionView` plays a kept item's video the same way.
struct VideoSheet: View {
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
