import SwiftUI
import SwiftData

/// Home. Greets the user, shows their practice at a glance (streak / totals),
/// a prominent Begin CTA, and recent sessions. Navigation to setup, results,
/// calendar, history, and settings.
struct ContentView: View {
    @EnvironmentObject private var coordinator: SessionCoordinator
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    @State private var showSetup = false
    @State private var showCalendar = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var openSession: SessionRef?
    #if DEBUG
    @State private var showBreathingPreview =
        ProcessInfo.processInfo.environment["PREVIEW_BREATHING"] == "1"
    #endif

    private struct SessionRef: Identifiable { let id: UUID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summaryCard
                Button("Begin session") { showSetup = true }
                    .buttonStyle(PrimaryButtonStyle())
                if coordinator.lastSessionID != nil {
                    lastSessionCard
                }
                recent
                #if DEBUG
                Button("Preview breathing screen") { showBreathingPreview = true }
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                #endif
            }
            .padding(AppMetrics.screenPadding)
        }
        .screenBackground()
        #if DEBUG
        .fullScreenCover(isPresented: $showBreathingPreview) {
            SessionActiveView(bellyBreathing: true) { showBreathingPreview = false }
        }
        #endif
        .sheet(isPresented: $showSetup) { SessionSetupView() }
        .sheet(isPresented: $showCalendar) { SessionHistoryView() }
        .sheet(isPresented: $showHistory) { NavigationStack { AllSessionsView() } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $openSession) { ref in SessionResultsView(sessionID: ref.id) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("808").font(AppFont.hero).foregroundStyle(AppColor.accentGold)
                Text(greeting).font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            HStack(spacing: 18) {
                iconButton("calendar") { showCalendar = true }
                iconButton("gearshape") { showSettings = true }
            }
        }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let streak = StreakCalculator.streak(from: sessions.map(\.startedAt))
        return VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Your practice")
            HStack(spacing: 8) {
                StatTile(value: "\(streak.current)", label: "Day streak")
                divider
                StatTile(value: "\(streak.longest)", label: "Longest")
                divider
                StatTile(value: "\(sessions.count)", label: "Sessions")
            }
        }
        .card()
    }

    private var divider: some View {
        Rectangle().fill(AppColor.textSecondary.opacity(0.15)).frame(width: 1, height: 44)
    }

    private var lastSessionCard: some View {
        Button {
            if let id = coordinator.lastSessionID { openSession = SessionRef(id: id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last session saved").font(AppFont.callout.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Tap to see your evidence").font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppColor.accentGold)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Recent")
                Spacer()
                if !sessions.isEmpty {
                    Button("See all") { showHistory = true }
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentGold)
                }
            }
            if sessions.isEmpty {
                Text("No sessions yet — begin your first.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                ForEach(sessions.prefix(3)) { session in
                    Button { openSession = SessionRef(id: session.id) } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 14) {
            Image(systemName: session.bellyBreathing ? "wind" : "leaf")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColor.accentGold)
                .frame(width: 34, height: 34)
                .background(AppColor.accentGold.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.callout.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                Text("\(durationText(session.durationSec))\(session.bellyBreathing ? " · Belly breathing" : "")")
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppColor.textSecondary)
        }
        .card(padding: 14)
    }

    // MARK: - Helpers

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Rest well"
        }
    }

    private func durationText(_ sec: Int) -> String {
        sec >= 60 ? "\(sec / 60) min" : "\(sec) sec"
    }
}
