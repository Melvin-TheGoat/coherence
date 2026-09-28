import SwiftUI
import SwiftData

/// A saved session, SHOWN — never edited here (`mockups/session-view.html`,
/// section 1, option A, with option C's Watch card, Melvin's pick, 2026-09-27).
///
/// Tapping a session (Home's Recent rows, Profile's week log) used to open
/// straight into `SaveSessionView`'s edit form. That put a person into a form
/// the instant they wanted to look back at something they already did. This
/// screen is the feed post that used to open here, turned inward: who, when,
/// the sound, the title, the numbers, then every photo and video, what was
/// practised, and your private notes — with Edit one tap away, top right, and
/// the full evidence one tap further in when a Watch measured any.
///
/// Read-only by construction: nothing on it is a text field. `SaveSessionView`
/// (opened from Edit or from the "Add how that felt" toast) still owns every
/// question a person answers about a sit; this owns what is SAID about it.
struct SessionView: View {
    let sessionID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var community: CommunityModel

    @State private var session: Session?
    @State private var stats: MeditationStats?
    @State private var privateNote = ""
    @State private var technique: String?
    @State private var title = ""
    @State private var rating: Int?
    @State private var displayName = "Your practice"
    @State private var dayStreak = 0
    @State private var media: [SessionPhoto] = []
    @State private var mediaIndex = 0
    @State private var loaded = false

    @State private var editing = false
    @State private var showResults = false
    @State private var playingItem: SessionPhoto?
    @State private var pendingDelete: UUID?

    private static let bandHeight: CGFloat = 128
    /// How far the identity card rises onto the band's bottom, the way
    /// Home's cards rise onto its own scene.
    private static let overlap: CGFloat = 42
    /// The inset inside every card's own text, matching `SaveSessionView`.
    private static let inset: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let session {
                    ScrollView {
                        VStack(spacing: 0) {
                            band(width: proxy.size.width, topInset: proxy.safeAreaInsets.top)
                            VStack(alignment: .leading, spacing: 10) {
                                identityCard(session)
                                // The Watch's readings lead, straight under
                                // who and when (`mockups/apple-watch/`).
                                if let stats { measurementsCard(stats, session: session) }
                                whatCard(session)
                                if !privateNote.isEmpty { notesCard }
                            }
                            .padding(.horizontal, AppMetrics.screenPadding)
                            .padding(.top, -Self.overlap)
                            .padding(.bottom, 24)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(edges: .top)
                    .background(ValleyGround.meadow.ignoresSafeArea())
                } else {
                    ProgressView()
                        .tint(AppColor.calmAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ValleyGround.meadow.ignoresSafeArea())
                }
            }
        }
        .task { await load() }
        // Edit opens through this screen's OWN sheet, never a second one
        // stacked on ContentView's presenter: a session opened for viewing
        // must still be able to reach the form it used to open into.
        .fullScreenCover(isPresented: $editing, onDismiss: { loaded = false; Task { await load() } }) {
            SaveSessionView(sessionID: sessionID, mode: .edit) { editing = false }
        }
        .fullScreenCover(isPresented: $showResults) {
            SessionResultsView(sessionID: sessionID)
        }
        .sheet(item: $playingItem) { item in
            if let data = item.video { VideoSheet(data: data) }
        }
        .deleteSessionDialog(pending: $pendingDelete) { _ in dismiss() }
    }

    // MARK: - The band

    /// The valley the sit was in, running up under the status bar, the same
    /// recipe `SaveSessionView` draws its own sky with: `ValleyScene`, cut to
    /// a band and faded into the page's own meadow, with nobody standing in
    /// it. Close, Edit and the ⋯ menu sit on top of it.
    private func band(width: CGFloat, topInset: CGFloat) -> some View {
        let height = topInset + Self.bandHeight
        return ZStack(alignment: .top) {
            ValleyScene(progress: 0, showsFigure: false, clock: true)
                .frame(width: width, height: height)
                .fadesIntoMeadow()
            HStack {
                closeButton
                Spacer(minLength: 8)
                HStack(spacing: 8) { editPill; moreMenu }
            }
            .padding(.horizontal, 14)
            .padding(.top, topInset + 8)
        }
        .frame(width: width, height: height)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ValleyGround.ink)
                .frame(width: 34, height: 34)
                .background(AppColor.backgroundPrimary.opacity(0.9), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .accessibilityLabel("Close")
    }

    private var editPill: some View {
        Button { editing = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
                Text("Edit").font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(ValleyGround.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColor.backgroundPrimary.opacity(0.9), in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(role: .destructive) { pendingDelete = sessionID } label: {
                Label("Delete session", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ValleyGround.ink)
                .frame(width: 34, height: 34)
                .background(AppColor.backgroundPrimary.opacity(0.9), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
        .accessibilityLabel("More")
    }

    // MARK: - Who, when, the title, the stats, the media

    private func identityCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProfilePortrait(photoURL: FeatureFlags.friends ? community.profile?.avatarURL : nil, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(whenLine(session))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.inset)
            .padding(.top, 14)

            Text(title)
                .font(DisplayFont.display(19, .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, Self.inset)
                .padding(.top, 10)

            HStack(spacing: 0) {
                stat("Time", "\(minutes(session))m", accent: true)
                if let rating { stat("Felt", "\(rating)/10") }
                stat("Day streak", "\(dayStreak)")
            }
            .padding(.horizontal, Self.inset)
            .padding(.top, 12)
            .padding(.bottom, media.isEmpty ? 15 : 12)

            if !media.isEmpty {
                mediaPager
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
        }
        .whiteCard(radius: 20)
    }

    private func stat(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(accent ? AppColor.accentGoldText : AppColor.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Today at 7:42 AM · Rain": the relative day, the time, and what played.
    private func whenLine(_ session: Session) -> String {
        let day = SessionListSupport.relativeDay(session.startedAt)
        let time = session.startedAt.formatted(date: .omitted, time: .shortened)
        let sound = SoundCatalog.title(for: session.frequencyID) ?? "Silence"
        return "\(day) at \(time) · \(sound)"
    }

    private func minutes(_ session: Session) -> Int { max(1, session.durationSec / 60) }

    /// Every photo and video the session kept, swiped across, with the "N of
    /// M" count and the system page dots the mockup draws. A video shows its
    /// first frame with a play glyph; tapping it plays in place.
    private var mediaPager: some View {
        TabView(selection: $mediaIndex) {
            ForEach(Array(media.enumerated()), id: \.element.id) { i, item in
                mediaFrame(item).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: media.count > 1 ? .always : .never))
        .frame(height: 240)
        .overlay(alignment: .topTrailing) {
            if media.count > 1 {
                Text("\(mediaIndex + 1) of \(media.count)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.38), in: Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func mediaFrame(_ item: SessionPhoto) -> some View {
        Button {
            if item.video != nil { playingItem = item }
        } label: {
            ZStack {
                if let image = PhotoThumbs.full(item) ?? PhotoThumbs.image(for: item) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    AppColor.hairline
                }
                if item.video != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .buttonStyle(.plain)
        .disabled(item.video == nil)
    }

    // MARK: - What you did, and the sound

    /// "What you did" only when a technique was reported; "Sound" always,
    /// because a session's sound is never truly absent — Silence is as much
    /// an answer as Rain is (the same reasoning `MinutesRow`'s subtitle uses).
    private func whatCard(_ session: Session) -> some View {
        let techniqueLabel = MeditationMethod.label(for: technique)
        let sound = SoundCatalog.title(for: session.frequencyID) ?? "Silence"
        return VStack(alignment: .leading, spacing: 0) {
            if let techniqueLabel {
                kvRow("What you did", techniqueLabel)
                Rectangle().fill(AppColor.hairline).frame(height: 1)
                    .padding(.horizontal, Self.inset)
            }
            kvRow("Sound", sound)
        }
        .whiteCard(radius: 18)
    }

    private func kvRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(AppFont.callout.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 13)
    }

    // MARK: - Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Notes")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("Only you")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text(privateNote)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .whiteCard(radius: 18)
    }

    // MARK: - What a Watch measured

    /// "Your body": the score ring and the three readings in words, the
    /// graphs one tap in (`BodyCard`). Only built when `stats` exists.
    private func measurementsCard(_ stats: MeditationStats, session: Session) -> some View {
        BodyCard(readings: BodyReadings(stats), score: stats.overallScore,
                 seeGraphs: { showResults = true }, inset: Self.inset)
            .whiteCard(radius: 18)
    }

    // MARK: - Load

    private func load() async {
        guard !loaded else { return }
        let sid = sessionID
        guard let s = try? context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.id == sid })).first else {
            loaded = true
            return
        }
        session = s
        stats = try? context.fetch(FetchDescriptor<MeditationStats>(
            predicate: #Predicate { $0.sessionID == sid })).first

        let reflection = SessionStore.reflection(for: sid, in: context)
        privateNote = reflection?.note ?? ""
        technique = reflection?.technique
        rating = reflection?.rating
        title = (reflection?.title).flatMap { $0.isEmpty ? nil : $0 }
            ?? SessionStore.defaultTitle(for: s.startedAt)
        media = SessionStore.photos(for: sid, in: context)
        mediaIndex = 0

        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        let user = users.first { $0.appleUserID != "" && $0.deletedAt == nil } ?? users.first
        let friendsProfile = FeatureFlags.friends ? community.profile : nil
        displayName = (user?.displayName?.isEmpty == false ? user!.displayName! : nil)
            ?? friendsProfile.flatMap { $0.displayName.isEmpty ? nil : $0.displayName }
            ?? "Your practice"

        // The streak as of THIS session's own day, not today's: only the
        // sessions up through it existed yet, from that day's point of view.
        let priorDates = SessionStore.sessionStartDates(in: context).filter { $0 <= s.startedAt }
        dayStreak = StreakCalculator.streak(from: priorDates, today: s.startedAt).current

        loaded = true
    }
}
