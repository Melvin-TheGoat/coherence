import SwiftUI
import SwiftData
import StoreKit

/// Settings, grouped by question (design review 2026-08): who you are, how you
/// practice, how the app looks, what we stand on. Destructive actions are
/// quarantined at the bottom — sign-out quiet, delete small and behind a
/// confirm. Reads + writes the signed-in User and its Preferences.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var users: [User]
    @Query private var preferences: [Preferences]
    @EnvironmentObject private var community: CommunityModel

    var body: some View {
        NavigationStack {
            Group {
                if let user = currentUser, let prefs = preferences.first {
                    SettingsForm(user: user, prefs: prefs, onDone: { dismiss() },
                                 onSignOut: {
                                     AccountActions.signOut(in: context, community: community)
                                     dismiss()
                                 },
                                 onDelete: {
                                     AccountActions.deleteAccount(in: context, community: community)
                                     dismiss() })
                } else {
                    Text("No account").foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var currentUser: User? {
        users.first { $0.appleUserID != "" && $0.deletedAt == nil } ?? users.first
    }
}

// MARK: - Account actions, shared

/// Sign out, account deletion and the App Store's own membership sheets: the
/// ONE code path Settings and the launch paywall's Account page both run
/// (Melvin, 2026-09-29). The launch lock is the only 808 a lapsed or updating
/// member can reach, and App Review 5.1.1(v) wants deletion reachable from
/// inside the app, so these could not stay private to Settings, and two
/// copies would drift the first time one of them was touched.
@MainActor
enum AccountActions {
    static let signOutTitle = "Sign out?"
    /// Signing out is allowed (paid or not), but it has to say what it costs:
    /// the local data stays, the roaming stops. Without this line a paid user
    /// could sign out, lose the phone, and discover the streak they were
    /// paying to protect died with it.
    static let signOutMessage = "Your sessions and streak stay on this phone, but they stop syncing to iCloud until you sign back in. A lost phone would mean losing them."

    static let deleteTitle = "Delete your account?"
    /// The 30-day grace period is real, but it only covers the local account;
    /// a public Friends profile is not something we can leave sitting around
    /// in the meantime for other people to see. No mention of posts: there
    /// are none to delete since posting was removed (2026-09-27).
    ///
    /// **It says the subscription keeps billing** (Melvin, 2026-09-29, App
    /// Review 5.1.1(v)): deleting an account cannot cancel an App Store
    /// subscription, only the person can, and an app that lets someone delete
    /// their account without saying so leaves them paying for nothing. The
    /// dialog offers Manage subscription beside Delete.
    static var deleteMessage: String {
        let account = FeatureFlags.friends
            ? "Your account and sessions are removed after 30 days. Sign back in before then to restore them. Your Friends profile and connections are deleted right away."
            : "Your account and sessions are removed after 30 days. Sign back in before then to restore them."
        return account + " " + subscriptionNote
    }

    static let subscriptionNote = "Deleting your account doesn't cancel your subscription. Cancel it in the Settings app under your name, Subscriptions."

    /// Whether anybody is signed in with Apple on this phone. Sign out is
    /// offered only then (Melvin, 2026-09-29): with only the local account
    /// there is nothing to sign out of, and the button reset onboarding for
    /// no reason.
    static func isSignedIn(_ users: [User]) -> Bool {
        users.contains { !$0.appleUserID.isEmpty && $0.deletedAt == nil }
    }

    static func signOut(in context: ModelContext, community: CommunityModel) {
        Analytics.track(.signedOut)
        // A new anonymous person from here: the next one on this phone is not
        // them.
        Analytics.reset()
        SessionStore.signOut(in: context)
        OttoChatStore.deleteAll()
        // Friends forgets them on this phone too: the profile they had stops
        // showing and stops being published to, and the next person agrees
        // to the community rules for themselves.
        community.signedOut()
    }

    static func deleteAccount(in context: ModelContext, community: CommunityModel) {
        Analytics.track(.accountDeleted)
        Analytics.reset()
        SessionStore.softDeleteCurrentUser(in: context)
        OttoChatStore.deleteAll()
        // Friends: the public profile and everything it wrote go too, not
        // just the local sign-out (5.1.1(v)). The screen forgets them at
        // once; the deletion itself runs on without holding the screen, and
        // anything it cannot finish is retried (`CommunityModel.load`, and
        // `retryPendingDeletion` at every launch).
        Task { await community.deleteAccountData() }
    }

    /// A confirmation dialog's button runs as the dialog dismisses; Apple's
    /// subscription page asked for in the same moment can fail to present.
    /// This small wait lets the dialog finish first.
    static func afterDialog(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }
}

extension View {
    /// Apple's own membership sheets, presented by SwiftUI from the view
    /// that asks (Melvin, 2026-09-29). They used to be asked for through the
    /// window scene with every error swallowed, which from inside a sheet
    /// (Settings, the paywall's Account page) could silently present
    /// nothing. The subscription page is where "cancel" leads: 808 cannot
    /// cancel anything itself. A redeemed code arrives on
    /// `Transaction.updates`, which `Store` has listened to since launch.
    func membershipSheets(manage: Binding<Bool>, redeem: Binding<Bool>) -> some View {
        manageSubscriptionsSheet(isPresented: manage)
            .offerCodeRedemption(isPresented: redeem) { result in
                if case .failure(let error) = result {
                    print("Offer code redemption failed: \(error)")
                }
            }
    }
}

/// What a Restore found, said in one short alert (Melvin, 2026-09-29). A
/// Restore that finds nothing used to say nothing at all, which reads as a
/// button that does not work.
enum RestoreFeedback: Equatable {
    case restored, nothing, failed

    /// nil when the screen has nothing to add: a restore that worked on a
    /// screen that simply opens the app (the paywall).
    init?(entitled: Bool, synced: Bool, announceSuccess: Bool = false) {
        if entitled {
            guard announceSuccess else { return nil }
            self = .restored
        } else {
            self = synced ? .nothing : .failed
        }
    }

    var title: String {
        switch self {
        case .restored: return "Membership restored"
        case .nothing:  return "Nothing to restore"
        case .failed:   return "Couldn't reach the App Store"
        }
    }

    var message: String {
        switch self {
        case .restored: return "Everything in 808 is open."
        case .nothing:  return "Restore brings back a membership bought with this Apple ID. If you bought 808 with a different one, sign in with it in the App Store and restore again."
        case .failed:   return "Check your connection and try again."
        }
    }
}

extension View {
    /// The Restore alert, the same on every screen that restores.
    func restoreFeedbackAlert(_ feedback: Binding<RestoreFeedback?>) -> some View {
        alert(feedback.wrappedValue?.title ?? "",
              isPresented: Binding(get: { feedback.wrappedValue != nil },
                                   set: { if !$0 { feedback.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedback.wrappedValue?.message ?? "")
        }
    }
}

/// The launch paywall's Account page (Melvin, 2026-09-29). Somebody whose
/// membership lapsed, or who updated from the free 1.0, meets the paywall
/// before anything else, and without this they could not delete their
/// account, sign out, redeem a code or manage the subscription they are
/// being asked about (App Review 5.1.1(v)). Every action is Settings' own,
/// through `AccountActions`.
struct AccountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var community: CommunityModel
    @Query private var users: [User]

    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var restoring = false
    @State private var restoreFeedback: RestoreFeedback?
    @State private var showManageSubscriptions = false
    @State private var showRedeem = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        row(icon: "creditcard", title: "Manage subscription",
                            subtitle: "Change or cancel your plan with Apple") {
                            showManageSubscriptions = true
                        }
                        divider
                        row(icon: "ticket", title: "Redeem a code",
                            subtitle: "An offer code from a friend or a creator") {
                            showRedeem = true
                        }
                        divider
                        row(icon: "arrow.clockwise", title: restoring ? "Restoring…" : "Restore purchases",
                            subtitle: "Bought on another device, or reinstalled") {
                            restore()
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 4)
                    .whiteCard(radius: 16)

                    VStack(spacing: 10) {
                        if AccountActions.isSignedIn(users) {
                            Button("Sign out") { confirmSignOut = true }
                                .font(AppFont.callout.weight(.medium))
                                .foregroundStyle(AppColor.textSecondary)
                                .confirmationDialog(AccountActions.signOutTitle, isPresented: $confirmSignOut,
                                                    titleVisibility: .visible) {
                                    Button("Sign out", role: .destructive) {
                                        AccountActions.signOut(in: context, community: community)
                                        dismiss()
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text(AccountActions.signOutMessage)
                                }
                        }
                        Button("Delete account") { confirmDelete = true }
                            .font(AppFont.caption)
                            .foregroundStyle(.red.opacity(0.75))
                            .confirmationDialog(AccountActions.deleteTitle, isPresented: $confirmDelete,
                                                titleVisibility: .visible) {
                                Button("Delete account", role: .destructive) {
                                    AccountActions.deleteAccount(in: context, community: community)
                                    dismiss()
                                }
                                Button("Manage subscription") {
                                    AccountActions.afterDialog { showManageSubscriptions = true }
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(AccountActions.deleteMessage)
                            }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .whiteCard(radius: 16)
                }
                .padding(AppMetrics.screenPadding)
            }
            .background(ValleyGround.meadow.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .restoreFeedbackAlert($restoreFeedback)
        .membershipSheets(manage: $showManageSubscriptions, redeem: $showRedeem)
    }

    private var divider: some View {
        Divider().overlay(AppColor.textSecondary.opacity(0.1))
    }

    private func restore() {
        guard !restoring else { return }
        restoring = true
        Task { @MainActor in
            let synced = await store.restore()
            restoring = false
            let outcome = store.entitled ? "restored" : synced ? "nothing" : "failed"
            Analytics.track(.restore(source: "account", outcome: outcome))
            // A restored membership lifts the lock by itself (RootView reads
            // `entitled`), so there is nothing to say, only a page to close.
            if store.entitled { dismiss() } else {
                restoreFeedback = RestoreFeedback(entitled: false, synced: synced)
            }
        }
    }

    private func row(icon: String, title: String, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.callout).foregroundStyle(AppColor.textPrimary)
                    Text(subtitle).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
    }
}

private struct SettingsForm: View {
    @Bindable var user: User
    @Bindable var prefs: Preferences
    let onDone: () -> Void
    let onSignOut: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var showManageSubscriptions = false
    @State private var showRedeem = false
    @State private var editingName = false
    /// What the last Restore found (Melvin, 2026-09-29).
    @State private var restoreFeedback: RestoreFeedback?
    @EnvironmentObject private var store: Store
    #if DEBUG
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var primerRows = 0
    @State private var primerMessage = ""
    @State private var cloudStatus = CloudStatus.unknown
    @AppStorage(TestTabBar.storageKey) private var tabBarStyle = TestTabBar.debugDefault.rawValue
    #endif
    /// The Apple Watch switch: the same value as the Ready screen's. Outside
    /// the DEBUG block: the Watch section uses them in every build, and
    /// inside it the Release build did not compile.
    @AppStorage(WatchLink.choiceKey) private var sitKindRaw = SitKind.unmeasured.rawValue
    @ObservedObject private var watchLink = WatchLink.shared
    @State private var showWatchSetup = false

    private let durationOptions: [(String, Int?)] = [
        ("Open", nil), ("5 min", 300), ("10 min", 600), ("15 min", 900), ("20 min", 1200), ("30 min", 1800)
    ]

    /// The fixed choices, plus whatever length the Ready screen's tape or
    /// typed field last set, so a 37-minute default is not shown as blank.
    private var lengthOptions: [(String, Int?)] {
        guard let current = prefs.defaultDurationSec,
              !durationOptions.contains(where: { $0.1 == current }) else { return durationOptions }
        return durationOptions + [("\(current / 60) min", current)]
    }

    /// In the valley like Friends, Profile and the guide (Melvin, 2026-09-27:
    /// "Settings needs to also be on theme"): a band of sky with the title,
    /// sand cards on the grass, white headings between them. The pages it
    /// pushes keep their own bar and back button.
    ///
    /// **Done is pinned, not scrolled** (Melvin, 2026-09-28: "so dont have to
    /// scroll up everytime we want to leave"). It used to live inside the sky
    /// band, so it left the screen with the rest of the scroll content. Now
    /// it is an overlay on the `GeometryReader` itself, outside the
    /// `ScrollView`, so it stays put at the same spot the whole time — over
    /// the sky at the top and over the sand cards once you have scrolled
    /// past it. Its cream pill is what makes that work at either: the pill
    /// is its own background regardless of what is under it, the house style
    /// for any control floating on a scene ("a cream capsule is something
    /// you press").
    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        FriendsSky(height: top + 92, sceneHeight: (top + 92) / 0.62) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Settings")
                                    .font(DisplayFont.display(30, .heavy))
                                    .onValley()
                                Spacer()
                            }
                            .padding(.horizontal, AppMetrics.screenPadding)
                            .padding(.top, top + 10)
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                        settingsBody
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .background(ValleyGround.meadow.ignoresSafeArea())
                // Once the sky has scrolled away, meadow fades in behind the
                // clock and Done, so the cards pass under it instead of
                // colliding with the pill.
                .modifier(StatusBarScrim(height: top + 64, threshold: 60))

                // The ZStack already starts below the status bar, so the
                // pin needs only the title row's own 10pt, not `top` again.
                doneButton
                    .padding(.trailing, AppMetrics.screenPadding)
                    .padding(.top, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var doneButton: some View {
        Button("Done", action: onDone)
            .font(AppFont.callout.weight(.bold))
            .foregroundStyle(ValleyGround.ink)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(AppColor.backgroundPrimary.opacity(0.9), in: Capsule())
    }

    private var settingsBody: some View {
            VStack(alignment: .leading, spacing: 16) {
                profileCard

                GrassHeading(title: "Apple Watch")
                watchCard

                GrassHeading(title: "Practice")
                settingsCard {
                    row(icon: "timer", title: "Default length") {
                        Picker("", selection: Binding(
                            get: { prefs.defaultDurationSec },
                            set: { prefs.defaultDurationSec = $0 }
                        )) {
                            ForEach(lengthOptions, id: \.0) { label, value in
                                Text(label).tag(value)
                            }
                        }
                        .tint(AppColor.textSecondary)
                    }
                    divider
                    row(icon: "bell", title: "Daily reminder",
                        subtitle: prefs.remindersEnabled ? timeString(prefs.reminderTime) : nil) {
                        Toggle("", isOn: Binding(
                            get: { prefs.remindersEnabled },
                            set: { on in
                                prefs.remindersEnabled = on
                                if on { Analytics.track(.reminderEnabled) }
                                if on && prefs.reminderTime == nil {
                                    prefs.reminderTime = defaultReminderTime()
                                }
                                NotificationScheduler.apply(enabled: on, at: prefs.reminderTime) {
                                    // The OS said no: the switch must not
                                    // claim otherwise.
                                    prefs.remindersEnabled = false
                                }
                            }
                        )).labelsHidden().tint(AppColor.calmAccent)
                    }
                    if prefs.remindersEnabled {
                        DatePicker("Time", selection: Binding(
                            get: { prefs.reminderTime ?? defaultReminderTime() },
                            set: { prefs.reminderTime = $0
                                   NotificationScheduler.apply(enabled: true, at: $0) }
                        ), displayedComponents: .hourAndMinute)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.leading, 41)
                        .tint(AppColor.accentGoldText)
                    }
                    divider
                    row(icon: "hand.tap", title: "Haptics") {
                        Toggle("", isOn: $prefs.hapticsEnabled)
                            .labelsHidden().tint(AppColor.calmAccent)
                    }
                }

                GrassHeading(title: "Membership")
                settingsCard {
                    // Apple's own page (Melvin, 2026-09-29): the paywall's
                    // footnote says where to cancel, and this is the door to
                    // it from inside 808.
                    membershipRow(icon: "creditcard", title: "Manage subscription",
                                  subtitle: "Change or cancel your plan with Apple") {
                        showManageSubscriptions = true
                    }
                    divider
                    membershipRow(icon: "arrow.clockwise", title: "Restore purchases",
                                  subtitle: "Bought on another device, or reinstalled") {
                        Task {
                            let synced = await store.restore()
                            let outcome = store.entitled ? "restored" : synced ? "nothing" : "failed"
                            Analytics.track(.restore(source: "settings", outcome: outcome))
                            restoreFeedback = RestoreFeedback(entitled: store.entitled, synced: synced,
                                                              announceSuccess: true)
                        }
                    }
                    divider
                    membershipRow(icon: "ticket", title: "Redeem a code",
                                  subtitle: "An offer code from a friend or a creator") {
                        showRedeem = true
                    }
                }
                .restoreFeedbackAlert($restoreFeedback)

                GrassHeading(title: "The foundation")
                settingsCard {
                    membershipRow(icon: "envelope", title: "Give us feedback",
                                  subtitle: "Opens an email to us. Every message is read.") {
                        sendFeedback()
                    }
                    divider
                    navRow(icon: "sparkles", title: "Why 808 exists", teal: true) { docPage("PURPOSE") }
                    divider
                    navRow(icon: "atom", title: "The science", teal: true) { docPage("SCIENCE") }
                    divider
                    navRow(icon: "lock.shield", title: "Privacy policy") { docPage("PRIVACY_POLICY") }
                    divider
                    navRow(icon: "doc.text", title: "Terms of service") { docPage("TERMS_OF_SERVICE") }
                }

                #if DEBUG
                testingDebugSection
                freeTierDebugSection
                cloudKitDebugSection
                airPodsDebugSection
                blockDebugSection
                #endif

                accountFooter
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .whiteCard(radius: 16)
            }
            .padding(AppMetrics.screenPadding)
        .confirmationDialog(AccountActions.deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: onDelete)
            Button("Manage subscription") {
                AccountActions.afterDialog { showManageSubscriptions = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AccountActions.deleteMessage)
        }
        .membershipSheets(manage: $showManageSubscriptions, redeem: $showRedeem)
    }

    #if DEBUG
    // MARK: Testing (developer only, compiled out of Release)

    @AppStorage(DebugOtto.stageKey) private var debugOttoStage = 0

    /// Two things a phone that has finished onboarding cannot otherwise do:
    /// go through onboarding again, and see Otto in a state its own history
    /// has not reached.
    @ViewBuilder
    private var testingDebugSection: some View {
        GrassHeading(title: "Testing (debug)")
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Otto's state")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Picker("Otto's state", selection: $debugOttoStage) {
                        Text("Real history").tag(0)
                        ForEach(1...13, id: \.self) { look in
                            Text(DebugOtto.name(look: look)).tag(look)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColor.accentGoldText)
                }
                divider
                Button {
                    // The same reset sign-out does, without signing out:
                    // RootView puts onboarding back the moment it lands.
                    for row in (try? context.fetch(FetchDescriptor<Preferences>())) ?? [] {
                        row.onboardingComplete = false
                    }
                    OnboardingResume.clear()
                    try? context.save()
                    dismiss()
                } label: {
                    Text("Replay onboarding")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.accentGoldText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: CloudKit schema (developer only, compiled out of Release)

    /// Creates every field of every synced model so the Development schema is
    /// complete before it gets promoted. See `CloudSchemaPrimer` for why this
    /// is not optional busywork.
    /// The free-tier review controls. The review build simulates a purchase
    /// when the paywall's buy button is tapped (no products exist, so StoreKit
    /// cannot run a real one); this is the way back to free without
    /// reinstalling.
    @ViewBuilder
    private var freeTierDebugSection: some View {
        GrassHeading(title: "Free tier (debug)")
        settingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { store.previewEntitled },
                    set: { store.setPreviewEntitled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simulated purchase")
                            .font(AppFont.callout.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(store.previewEntitled
                             ? "Everything unlocked, as after buying. Turn off to review as a free user."
                             : "Reviewing as a free user. The paywall's buy button flips this on.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(AppColor.accentGold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var cloudKitDebugSection: some View {
        GrassHeading(title: "CloudKit (debug)")
        settingsCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(Persistence.mode.label)
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(Persistence.mode == .cloudKit
                                     ? AppColor.calmAccent : AppColor.accentGold)
                Text("Container: \(cloudStatus.container)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Text("iCloud account: \(cloudStatus.account)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                if let why = Persistence.mode.reason {
                    Text(why)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            divider
            Button {
                CloudSchemaPrimer.prime(in: context)
                primerRows = CloudSchemaPrimer.primedRowCount(in: context)
                primerMessage = "Primed. Wait for sync, then check CloudKit Console."
            } label: {
                debugRow(icon: "arrow.up.circle", title: "Prime CloudKit schema")
            }
            divider
            Button {
                let n = CloudSchemaPrimer.removePrimedRows(in: context)
                primerRows = CloudSchemaPrimer.primedRowCount(in: context)
                primerMessage = n == 0 ? "Nothing to remove." : "Removed \(n) primer rows."
            } label: {
                debugRow(icon: "trash", title: "Remove primer rows")
            }
            if primerRows > 0 || !primerMessage.isEmpty {
                divider
                VStack(alignment: .leading, spacing: 4) {
                    if primerRows > 0 {
                        Text("\(primerRows) primer rows present")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentGoldText)
                    }
                    if !primerMessage.isEmpty {
                        Text(primerMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            }
        }
        .onAppear {
            primerRows = CloudSchemaPrimer.primedRowCount(in: context)
            Task { cloudStatus = await CloudStatus.read() }
        }
    }

    /// The AirPods hardware probe (no-Watch path spike, 2026-09-14). The row
    /// only exists on iOS 26, where an iPhone can run its own workout session.
    /// The probe is the one place the iOS target reads a biometric, and it is
    /// compiled out of Release with the rest of this section.
    @ViewBuilder
    private var airPodsDebugSection: some View {
        if #available(iOS 26.0, *) {
            GrassHeading(title: "AirPods (debug)")
            settingsCard {
                navRow(icon: "airpodspro", title: "AirPods capture probe", teal: true) {
                    AirPodsProbeView()
                }
            }
        }
    }

    /// Every screen "Ask Otto" can lead to (the twenty intervention kinds
    /// plus the how-long screen), so it can be demoed on a phone with
    /// nothing real happening (`InterventionGalleryView`).
    @ViewBuilder
    private var blockDebugSection: some View {
        GrassHeading(title: "Block (debug)")
        settingsCard {
            navRow(icon: "bell.badge", title: "Otto's unblock screens", teal: true) {
                InterventionGalleryView()
            }
            divider
            // The tab bar test (2026-09-25), so the bars can be compared on
            // a phone.
            row(icon: "leaf", title: "Tab bar (test)") {
                Picker("", selection: $tabBarStyle) {
                    ForEach(TestTabBar.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden()
                .tint(AppColor.calmAccent)
            }
        }
    }

    private func debugRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColor.calmAccent)
                .frame(width: 24)
            Text(title)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    #endif

    // MARK: Profile

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // The empty person every profile starts with.
                ProfilePortrait(photoURL: nil, size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName?.isEmpty == false ? user.displayName! : "Add your name")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    if let handle = Username.display(user.username) {
                        Text(handle)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    // The bootstrap user (skipped sign-in) is not "Signed in
                    // with Apple", and a reviewer who skipped sign-in reads
                    // this line thirty seconds later. Say what is true.
                    Text(user.email?.isEmpty == false ? user.email!
                         : (user.appleUserID.isEmpty ? "Not signed in" : "Signed in with Apple"))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Button { editingName.toggle() } label: {
                    Text(editingName ? "Done" : "Edit")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGoldText)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(CardButtonStyle())
            }
            if editingName {
                TextField("Display name", text: Binding(
                    get: { user.displayName ?? "" },
                    set: { user.displayName = $0.isEmpty ? nil : $0 }
                ))
                .font(AppFont.callout)
                .padding(10)
                .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 6) {
                    Text("@").foregroundStyle(AppColor.textSecondary)
                    TextField("Username", text: Binding(
                        get: { user.username ?? "" },
                        set: { user.username = Username.normalize($0) }
                    ))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                .font(AppFont.callout)
                .padding(10)
                .background(AppColor.backgroundPrimary, in: RoundedRectangle(cornerRadius: 10))
                // "Product emails" was a switch here, and nothing ever read
                // it: no export, no mailing, and the no-Watch waitlist sends
                // its address the moment it is typed. A setting that does
                // nothing is a small lie in a product selling honesty, so the
                // row is gone (Melvin, 2026-09-29). `User.marketingOptIn`
                // stays in the synced schema, unread: dropping a stored
                // property is a migration hazard.
            }
        }
        .card(padding: 14)
    }

    private var initial: String {
        String((user.displayName ?? "•").prefix(1)).uppercased()
    }

    // MARK: Apple Watch

    /// Which Watch, whether it is connected, whether it measures, and how to
    /// connect one (Aziz, 2026-09-28). Settings is where somebody goes
    /// looking, so the section is here even without a Watch; the Ready
    /// screen shows nothing then.
    private var watchCard: some View {
        settingsCard {
            HStack(spacing: 11) {
                Image(systemName: "applewatch")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.calmAccent)
                    .frame(width: 30, height: 30)
                    .background(AppColor.calmAccent.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                WatchStatusLine(status: watchLink.status)
                Spacer()
            }
            .padding(.vertical, 10)
            if watchLink.connected {
                divider
                row(icon: "waveform.path.ecg", title: "Measure my sessions",
                    subtitle: "Heart rate, stillness and breathing", teal: true) {
                    Toggle("", isOn: Binding(
                        get: { sitKindRaw == SitKind.watch.rawValue },
                        set: { on in
                            sitKindRaw = (on ? SitKind.watch : .unmeasured).rawValue
                            Analytics.track(.watchSwitch(on: on, source: "settings"))
                        }
                    )).labelsHidden().tint(OnboardingGreen.fill)
                }
            }
            divider
            membershipRow(icon: "questionmark.circle", title: "How to connect",
                          subtitle: "Four steps, about a minute") {
                Analytics.track(.watchSetupOpened(source: "settings"))
                showWatchSetup = true
            }
        }
        .sheet(isPresented: $showWatchSetup) { WatchConnectSheet() }
        .onAppear { watchLink.refresh() }
    }

    // MARK: Membership

    private func membershipRow(icon: String, title: String, subtitle: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.callout).foregroundStyle(AppColor.textPrimary)
                    Text(subtitle).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
    }

    /// An email to us with the version and build filled in, so a report is
    /// answerable without a follow-up question.
    private func sendFeedback() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = "support@meditate808.com"
        parts.queryItems = [
            URLQueryItem(name: "subject", value: "808 feedback"),
            URLQueryItem(name: "body", value: "\n\n\n808 \(version) (\(build)) on iOS \(UIDevice.current.systemVersion)")
        ]
        if let url = parts.url { UIApplication.shared.open(url) }
    }

    // MARK: Building blocks

    private func settingsCard(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
            .whiteCard(radius: 16)
    }

    private var divider: some View {
        Divider().overlay(AppColor.textSecondary.opacity(0.1))
    }

    private func row(icon: String, title: String, subtitle: String? = nil, teal: Bool = false,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(teal ? AppColor.calmAccent : AppColor.accentGoldText)
                .frame(width: 30, height: 30)
                .background((teal ? AppColor.calmAccent : AppColor.accentGold).opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 7)
    }

    private func navRow(icon: String, title: String, teal: Bool = false,
                        @ViewBuilder destination: @escaping () -> some View) -> some View {
        NavigationLink { destination() } label: {
            row(icon: icon, title: title, teal: teal) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .buttonStyle(CardButtonStyle())
    }

    private var accountFooter: some View {
        VStack(spacing: 6) {
            // Only for somebody signed in with Apple: the local account has
            // nothing to sign out of (Melvin, 2026-09-29).
            if !user.appleUserID.isEmpty && user.deletedAt == nil {
                Button("Sign out") { confirmSignOut = true }
                    .font(AppFont.callout.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                    // What signing out costs is said first (`AccountActions`).
                    .confirmationDialog(AccountActions.signOutTitle, isPresented: $confirmSignOut,
                                        titleVisibility: .visible) {
                        Button("Sign out", role: .destructive, action: onSignOut)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(AccountActions.signOutMessage)
                    }
            }
            Button("Delete account") { confirmDelete = true }
                .font(AppFont.caption)
                .foregroundStyle(.red.opacity(0.75))

            // Who actually stands behind the app. The legal docs above name
            // Lock Out Inc. as the party you are agreeing with, and until now
            // nothing in the app itself said so: a policy that introduces a
            // company the product never mentions reads as boilerplate someone
            // pasted. Also the conventional home for the build number, which
            // is the first thing a support email needs.
            VStack(spacing: 3) {
                Text("808 is made by Lock Out Inc.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Text(Self.versionLine)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary.opacity(0.6))
                    .monospacedDigit()
                    // Seven taps on the version number flag this phone as a
                    // team device: every analytics event it sends carries
                    // `team_device = true`, and the PostHog internal-user
                    // filter drops it. Hidden because it is for the two
                    // founders, whose constant reinstalls each mint a fresh
                    // anonymous id and were polluting the launch dashboards.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTaps += 1
                        guard versionTaps >= 7 else { return }
                        versionTaps = 0
                        teamDevice.toggle()
                        Analytics.setTeamDevice(teamDevice)
                    }
                if teamDevice {
                    Text("Team device. Analytics from this phone are flagged.")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary.opacity(0.6))
                }
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    @State private var versionTaps = 0
    @State private var teamDevice = Analytics.isTeamDevice

    /// "Version 1.0 (202608251757)" from the bundle, never hardcoded: a
    /// hand-typed version is wrong the moment it is typed.
    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private func docPage(_ name: String) -> some View {
        ScrollView { MarkdownView(markdown: DocLoader.load(name)).padding() }
            .background(AppColor.backgroundPrimary)
    }

    private func timeString(_ date: Date?) -> String? {
        date?.formatted(date: .omitted, time: .shortened)
    }

    private func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }
}
