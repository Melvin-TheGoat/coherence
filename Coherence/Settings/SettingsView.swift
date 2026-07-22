import SwiftUI
import SwiftData

/// Phase-7 Settings/Profile. Reads + writes the signed-in User and its
/// Preferences, re-exposes the Purpose/Science pages, and offers sign-out +
/// account deletion. CloudKit sync is a separate (deferred) step.
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
                                 onDelete: { SessionStore.softDeleteCurrentUser(in: context); dismiss() })
                } else {
                    Text("No account").foregroundStyle(AppColor.textSecondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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

    private let durationOptions: [(String, Int?)] = [
        ("Open-ended", nil), ("2 min", 120), ("5 min", 300), ("10 min", 600), ("15 min", 900)
    ]

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Display name", text: Binding(
                    get: { user.displayName ?? "" },
                    set: { user.displayName = $0.isEmpty ? nil : $0 }
                ))
                if let email = user.email, !email.isEmpty {
                    LabeledContent("Apple ID", value: email)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Toggle("Product emails", isOn: $user.marketingOptIn)
            }

            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { prefs.themeValue },
                    set: { prefs.themeValue = $0 }
                )) {
                    Text("System").tag(Theme.system)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }
            }

            Section("Session") {
                Toggle("Haptics", isOn: $prefs.hapticsEnabled)
                Picker("Default length", selection: Binding(
                    get: { prefs.defaultDurationSec },
                    set: { prefs.defaultDurationSec = $0 }
                )) {
                    ForEach(durationOptions, id: \.0) { label, value in
                        Text(label).tag(value)
                    }
                }
            }

            Section("Reminders") {
                Toggle("Daily reminder", isOn: Binding(
                    get: { prefs.remindersEnabled },
                    set: { on in
                        prefs.remindersEnabled = on
                        if on && prefs.reminderTime == nil {
                            prefs.reminderTime = defaultReminderTime()
                        }
                        NotificationScheduler.apply(enabled: on, at: prefs.reminderTime)
                    }
                ))
                if prefs.remindersEnabled {
                    DatePicker("Time", selection: Binding(
                        get: { prefs.reminderTime ?? defaultReminderTime() },
                        set: { prefs.reminderTime = $0
                               NotificationScheduler.apply(enabled: true, at: $0) }
                    ), displayedComponents: .hourAndMinute)
                }
            }

            Section("About") {
                NavigationLink("Our Purpose") { docPage("PURPOSE") }
                NavigationLink("The Science") { docPage("SCIENCE") }
            }

            Section {
                Button("Sign out", action: onSignOut)
                Button("Delete account", role: .destructive) { confirmDelete = true }
            }
        }
        .tint(AppColor.accentGold)
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and sessions are removed after 30 days. Sign back in before then to restore them.")
        }
    }

    private func docPage(_ name: String) -> some View {
        ScrollView { MarkdownView(markdown: DocLoader.load(name)).padding() }
            .background(AppColor.backgroundPrimary)
    }

    private func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }
}
