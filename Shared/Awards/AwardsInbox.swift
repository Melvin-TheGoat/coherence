import Foundation

/// Remembers which awards have already been announced, so the unlock moment
/// fires exactly once each.
///
/// This is the ONLY thing about awards that is stored, and it is deliberately
/// local (UserDefaults, never CloudKit). It is a UI bookkeeping detail, not a
/// record of achievement: the awards themselves are derived from history, so
/// losing this file costs nothing but a repeated animation.
///
/// **Backfill lands silently.** On the first run, everything already earned is
/// marked announced without showing anything. Melvin and Aziz have months of
/// history and would otherwise be handed a dozen unlock screens in a row on
/// launch, which would cheapen the one that matters.
public enum AwardsInbox {
    private static let announcedKey = "awardsAnnounced.v1"
    private static let lastCheckKey = "awardsLastCheck.v1"

    private static var announced: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: announcedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: announcedKey) }
    }

    /// The watermark. Anything earned at or before it is history, not news.
    private static var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckKey) }
    }

    /// Awards to celebrate: earned SINCE the last look, and not already shown.
    ///
    /// The watermark is what makes backfill silent, and a plain "seed once on
    /// first launch" flag is not enough. Sessions arrive asynchronously, from
    /// SwiftData and later from iCloud, so the first look can easily happen
    /// against an empty history and every real award would then queue up as
    /// news. Dating the decision fixes that: an award earned by a session from
    /// last Tuesday is not something that just happened, whenever the row
    /// happens to show up.
    public static func pending(from earned: [AwardEngine.Earned]) -> [AwardEngine.Earned] {
        guard let since = lastCheck else { return [] }
        let announced = announced
        return earned
            .filter { item in
                guard item.isEarned, let at = item.earnedAt else { return false }
                return at > since && !announced.contains(item.award.id)
            }
            .sorted { ($0.earnedAt ?? .distantPast) < ($1.earnedAt ?? .distantPast) }
    }

    public static func markAnnounced(_ id: String) {
        announced.insert(id)
    }

    /// Call before the first `pending`. On a fresh install this drops the
    /// watermark at now, so nothing already earned announces. Afterwards it
    /// does nothing: moving it forward on every check would swallow an award
    /// earned between two looks.
    public static func seedIfNeeded(with earned: [AwardEngine.Earned]) {
        guard lastCheck == nil else { return }
        lastCheck = Date()
        announced = announced.union(earned.filter(\.isEarned).map(\.award.id))
    }

    #if DEBUG
    /// So the unlock screen can be reviewed without inventing a fresh history.
    public static func resetForPreview() {
        UserDefaults.standard.removeObject(forKey: announcedKey)
        UserDefaults.standard.removeObject(forKey: lastCheckKey)
    }
    #endif
}
