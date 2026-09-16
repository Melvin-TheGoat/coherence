import SwiftUI
import SwiftData

/// Removing a session the user never meant to keep (Melvin, 2026-09-15:
/// "sometimes we create ones and immediately end them"). One dialog, one
/// action, shared by the results screen and both session lists, so the copy
/// and the consequences never drift apart.
enum SessionDeletion {
    /// Deletes the session, its stats and its reflection, and if it was posted
    /// to friends takes the post down too. Idempotent: a second call finds
    /// nothing and logs nothing.
    @MainActor
    static func delete(_ id: UUID, context: ModelContext, community: CommunityModel) {
        let reflections = (try? context.fetch(
            FetchDescriptor<SessionReflection>(predicate: #Predicate { $0.sessionID == id }))) ?? []
        let posted = reflections.contains { $0.visibility == "friends" }
        if posted {
            // Only when a post exists: `unpost` surfaces a CloudKit error in
            // the Friends tab, and "record not found" for a never-posted
            // session would be a false alarm.
            Task { await community.unpost(session: id) }
        }
        if SessionStore.deleteSession(id: id, in: context) {
            OttoChatStore.delete(key: OttoChatStore.key(for: id))
            Analytics.track(.sessionDeleted)
        }
    }
}

/// The confirmation, bound to the id awaiting deletion. Nil means nothing is
/// pending. `onDeleted` fires after the rows are gone, for a screen that must
/// leave (the results screen dismisses itself).
struct DeleteSessionDialog: ViewModifier {
    @Binding var pending: UUID?
    var onDeleted: ((UUID) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var community: CommunityModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete this session?",
            isPresented: Binding(get: { pending != nil },
                                 set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { id in
            Button("Delete session", role: .destructive) {
                SessionDeletion.delete(id, context: context, community: community)
                pending = nil
                onDeleted?(id)
            }
            Button("Keep it", role: .cancel) { pending = nil }
        } message: { _ in
            // Honest about the boundary: the Watch wrote a workout and mindful
            // minutes into Health, and those are the user's Health record,
            // not ours to remove.
            Text("It leaves your history, streak and awards. The workout stays in Health.")
        }
    }
}

extension View {
    func deleteSessionDialog(pending: Binding<UUID?>,
                             onDeleted: ((UUID) -> Void)? = nil) -> some View {
        modifier(DeleteSessionDialog(pending: pending, onDeleted: onDeleted))
    }
}
