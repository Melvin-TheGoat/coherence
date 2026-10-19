import Foundation

/// Invite codes on the model (2026-10-18, mockup "808 Invite Codes"): my
/// code for the Invite sheet, looking a code up, joining with one, and the
/// friends who joined with mine. The rules live in `InviteCode` and
/// `CommunityStore`.
extension CommunityModel {

    /// A fresh code for this invite: every invite gets its own (Aziz,
    /// 2026-10-18), and every code sent before keeps working. Nil when one
    /// cannot be made yet: no profile, no network.
    @discardableResult
    func makeInviteCode() async -> String? {
        guard let store, hasProfile else { return nil }
        // A failure is the sheet's to show (it has its own "Try again"):
        // `errorText` would raise an alert behind it.
        guard let code = try? await store.newInviteCode() else { return nil }
        inviteCode = code
        Task { await store.subscribeToCodeJoins() }
        return code
    }

    /// Whose code this is, for "Aziz invited you". Needs iCloud, not a
    /// profile: onboarding asks before one exists.
    func lookUpInvite(_ raw: String) async -> Result<Profile, CommunityError> {
        if store == nil { await load() }
        guard let store else { return .failure(.unavailable) }
        guard InviteCode.normalize(raw) != nil else { return .failure(.inviteCodeUnknown) }
        do {
            guard let inviter = try await store.inviter(forCode: raw) else { return .failure(.inviteCodeUnknown) }
            if let mine = myID, inviter.id == mine { return .failure(.inviteCodeIsYours) }
            people[inviter.id] = inviter
            return .success(inviter)
        } catch let e as CommunityError {
            return .failure(e)
        } catch {
            return .failure(.unavailable)
        }
    }

    /// Keeps a found invite until there is a profile to join with, then
    /// joins at once when there already is one. Returns true when the two
    /// are friends now.
    @discardableResult
    func acceptInvite(code: String, from inviter: Profile) async -> Bool {
        guard let canonical = InviteCode.normalize(code) else { return false }
        PendingInvite.saved = PendingInvite(code: canonical, inviter: inviter.id,
                                            name: inviter.displayName, username: inviter.username)
        guard let store, hasProfile else { return false }
        await redeemPendingInvite(store)
        do { try await refreshLists(store) } catch { }
        return friends.contains(inviter.id)
    }

    /// Joins straight away, from Friends search, for someone who already has
    /// a profile. True when the two are friends now.
    func joinWithCode(_ code: String, inviter: Profile) async -> Bool {
        guard let store, hasProfile else { return false }
        do {
            try await store.redeem(code: code, myName: myAlertName)
            people[inviter.id] = inviter
            Analytics.track(.inviteCodeRedeemed)
            try? await refreshLists(store)
            return true
        } catch {
            errorText = Self.plain(error)
            return false
        }
    }

    /// Joins with the saved invite, once a profile exists. Clears it when it
    /// worked or can never work (an unknown code, my own); keeps it through
    /// a network failure to try again on the next refresh.
    func redeemPendingInvite(_ store: CommunityStore) async {
        // Several refreshes can start at once (launch, the profile screen,
        // the 10 s timer): only one redeems, so the join is counted once.
        guard let pending = PendingInvite.saved, hasProfile, !Self.redeeming else { return }
        Self.redeeming = true
        defer { Self.redeeming = false }
        do {
            let inviter = try await store.redeem(code: pending.code, myName: myAlertName)
            people[inviter.id] = inviter
            PendingInvite.saved = nil
            joinedInviter = pending
            Analytics.track(.inviteCodeRedeemed)
        } catch let e as CommunityError where e == .inviteCodeUnknown || e == .inviteCodeIsYours || e == .blocked {
            PendingInvite.saved = nil
        } catch {
            // Offline or similar: kept for the next refresh.
        }
    }

    @MainActor private static var redeeming = false

    /// Runs inside every list refresh: the pending invite, then my half for
    /// everyone who joined with my code.
    func refreshInvites(_ store: CommunityStore) async {
        await redeemPendingInvite(store)
        // Who joined is already among `friends`: the store counts a code
        // join as a friendship from the moment it is written.
        if let joined = try? await store.answerCodeJoins() {
            joinedWithCode = joined
        }
    }
}
