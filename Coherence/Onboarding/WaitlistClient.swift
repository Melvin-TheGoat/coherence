import Foundation

/// Sends the email typed on the no-Watch waitlist screen to the
/// "808 no watch waitlist" Google Sheet (`tools/nowatch-waitlist.gs`).
///
/// **Until this existed the screen's promise was unkeepable.** The email was
/// saved on the person's own phone and nowhere else (a "marketing export" that
/// was never built), so "we'll write when there's a version that doesn't need
/// a Watch" could never happen. Every address typed on 1.0 and 1.0.1 is lost.
///
/// This is the FIRST personal data the app sends to us, so it is declared in
/// `PrivacyInfo.xcprivacy` (Email Address, linked, marketing), named in both
/// copies of the privacy policy, and the App Privacy labels in App Store
/// Connect must add Email Address at the submission that ships it.
///
/// Rules it keeps:
/// - Sends ONLY what the person typed plus the app version. No install id, no
///   device, no location: an email is all it takes to write to someone.
/// - Never blocks onboarding. The request runs detached; a failure queues the
///   address and the next launch retries, so a subway signup still arrives.
/// - Never goes through `Analytics`. PostHog must never receive an email.
enum WaitlistClient {

    /// The web app's /exec URL. Empty means "not deployed": nothing is sent
    /// and nothing is queued, so a build with no endpoint behaves like 1.0.1.
    static let endpoint = ""

    /// Must equal `APP_TOKEN` in the script. Not a secret (it ships in the
    /// binary); it only keeps a bare scraper from filling the sheet.
    static let token = "808-nowatch-v1"

    private static let pendingKey = "waitlist.pending.v1"

    /// Stricter than the screen's "contains @ and ." gate, which lets the
    /// button enable while typing; this is what we are willing to send.
    static func isPlausible(_ email: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.count <= 254, !e.contains(" ") else { return false }
        let parts = e.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."),
              dot != domain.startIndex,
              domain.index(after: dot) != domain.endIndex else { return false }
        return true
    }

    /// The exact JSON body. Kept separate so a test can pin that nothing
    /// beyond these four keys ever leaves the phone.
    static func body(email: String, appVersion: String) -> Data {
        let payload: [String: String] = [
            "token": token,
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "source": "app",
            "app_version": appVersion,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }

    /// Called once, when onboarding finishes with an address on the screen.
    static func submit(_ email: String) {
        guard !endpoint.isEmpty, isPlausible(email) else { return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        queue(trimmed)
        Task.detached(priority: .utility) { await flush() }
    }

    /// Retries anything a previous launch could not deliver. Cheap when the
    /// queue is empty, which is almost always.
    static func flush() async {
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else { return }
        for email in pending() {
            if await post(email, to: url) { dequeue(email) }
        }
    }

    // MARK: - Private

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private static func post(_ email: String, to url: URL) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        // text/plain, like the website forms: Apps Script reads the raw body
        // either way, and it avoids a preflight on the redirect it answers with.
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body(email: email, appVersion: appVersion)
        do {
            // Apps Script runs doPost, then answers 302 to a googleusercontent
            // URL holding the JSON. URLSession follows it; any 2xx at the end
            // means the row was written (or was already there).
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            // A rejected address will never succeed; drop it rather than retry forever.
            if let error = reply?["error"] as? String, error == "bad email" { return true }
            return reply?["ok"] as? Bool ?? false
        } catch {
            return false
        }
    }

    private static func pending() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
    }

    private static func queue(_ email: String) {
        var list = pending()
        if !list.contains(where: { $0.caseInsensitiveCompare(email) == .orderedSame }) {
            list.append(email)
        }
        UserDefaults.standard.set(list, forKey: pendingKey)
    }

    private static func dequeue(_ email: String) {
        UserDefaults.standard.set(pending().filter { $0 != email }, forKey: pendingKey)
    }
}
