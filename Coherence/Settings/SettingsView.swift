import SwiftUI
import SwiftData

/// Settings, grouped by question (design review 2026-08): who you are, how you
/// practice, how the app looks, what we stand on. Destructive actions are
/// quarantined at the bottom — sign-out quiet, delete small and behind a
/// confirm. Reads + writes the signed-in User and its Preferences.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var users: [User]
    @Query private var preferences: [Preferences]

    var body: some View {
        NavigationStack {
            Group {
                if let user = currentUser, let prefs = preferences.first {
                    SettingsForm(user: user, prefs: prefs,
                                 onSignOut: { SessionStore.signOut(in: context); dismiss() },
                                 onDelete: {
                                     Analytics.track(.accountDeleted)
                                     SessionStore.softDeleteCurrentUser(in: context); dismiss() })
                } else {
                    Text("No account").foregroundStyle(AppColor.textSecondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppColor.accentGoldText)
                }
            }
        }
    }

    private var currentUser: User? {
        users.first { $0.appleUserID != "" && $0.deletedAt == nil } ?? users.first
    }
}

private struct SettingsForm: View {
    @Bindable var user: User
    @Bindable var prefs: Preferences
    let onSignOut: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var editingName = false
    #if DEBUG
    @EnvironmentObject private var store: Store
    @Environment(\.modelContext) private var context
    @State private var primerRows = 0
    @State private var primerMessage = ""
    @State private var cloudStatus = CloudStatus.unknown
    #endif

    private let durationOptions: [(String, Int?)] = [
        ("Open", nil), ("2 min", 120), ("5 min", 300), ("10 min", 600), ("15 min", 900)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileCard

                SectionHeader(title: "Practice")
                settingsCard {
                    row(icon: "timer", title: "Default length") {
                        Picker("", selection: Binding(
                            get: { prefs.defaultDurationSec },
                            set: { prefs.defaultDurationSec = $0 }
                        )) {
                            ForEach(durationOptions, id: \.0) { label, value in
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
                                NotificationScheduler.apply(enabled: on, at: prefs.reminderTime)
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

                SectionHeader(title: "Appearance")
                settingsCard {
                    row(icon: "circle.lefthalf.filled", title: "Theme") {
                        Picker("", selection: Binding(
                            get: { prefs.themeValue },
                            set: { prefs.themeValue = $0 }
                        )) {
                            Text("System").tag(Theme.system)
                            Text("Light").tag(Theme.light)
                            Text("Dark").tag(Theme.dark)
                        }
                        .tint(AppColor.textSecondary)
                    }
                }

                SectionHeader(title: "The foundation")
                settingsCard {
                    navRow(icon: "sparkles", title: "Why 808 exists", teal: true) { docPage("PURPOSE") }
                    divider
                    navRow(icon: "atom", title: "The science", teal: true) { docPage("SCIENCE") }
                    divider
                    navRow(icon: "lock.shield", title: "Privacy policy") { docPage("PRIVACY_POLICY") }
                    divider
                    navRow(icon: "doc.text", title: "Terms of service") { docPage("TERMS_OF_SERVICE") }
                }

                #if DEBUG
                freeTierDebugSection
                cloudKitDebugSection
                #endif

                accountFooter
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and sessions are removed after 30 days. Sign back in before then to restore them.")
        }
    }

    #if DEBUG
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
        SectionHeader(title: "Free tier (debug)")
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
        SectionHeader(title: "CloudKit (debug)")
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
                Text(initial)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentGoldText)
                    .frame(width: 42, height: 42)
                    .background(AppColor.accentGold.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName?.isEmpty == false ? user.displayName! : "Add your name")
                        .font(AppFont.callout.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
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
                Toggle("Product emails", isOn: $user.marketingOptIn)
                    .font(AppFont.caption)
                    .tint(AppColor.calmAccent)
            }
        }
        .card(padding: 14)
    }

    private var initial: String {
        String((user.displayName ?? "•").prefix(1)).uppercased()
    }

    // MARK: Building blocks

    private func settingsCard(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
            .background(AppColor.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(AppColor.textSecondary.opacity(0.1))
    }

    private func row(icon: String, title: String, subtitle: String? = nil, teal: Bool = false,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(teal ? AppColor.calmAccent : AppColor.accentGold)
                .frame(width: 30, height: 30)
                .background((teal ? AppColor.calmAccent : AppColor.accentGold).opacity(0.12),
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
            Button("Sign out") { confirmSignOut = true }
                .font(AppFont.callout.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
                // Signing out is allowed (paid or not), but it has to say what
                // it costs: the local data stays, the roaming stops. Without
                // this line a paid user could sign out, lose the phone, and
                // discover the streak they were paying to protect died with it.
                .confirmationDialog("Sign out?", isPresented: $confirmSignOut,
                                    titleVisibility: .visible) {
                    Button("Sign out", role: .destructive, action: onSignOut)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your sessions and streak stay on this phone, but they stop syncing to iCloud until you sign back in. A lost phone would mean losing them.")
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
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

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
