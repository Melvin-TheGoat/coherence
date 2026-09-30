import Foundation

/// Emails a report to the team the moment it is filed, through the Apps Script
/// web app in `tools/community-reports.gs`, so guideline 1.2's "timely
/// response" does not depend on someone opening the CloudKit Console.
///
/// The `Report` record in CloudKit stays the record of truth; this is the
/// doorbell. Sends only ids, the kind and the reason the reporter picked or
/// typed. Never a name, handle, caption or photo: whoever reads the email
/// looks the post up in the Console.
///
/// **Live since 2026-09-29.** Deployed from Aziz's Google account as the
/// Apps Script project "808 friends reports" (web app, runs as him, anyone
/// may post; email permission only). Verified the same night: a GET answers,
/// a report with the token is accepted and emailed to support@meditate808.com,
/// a wrong token is refused. Editing the script means a NEW VERSION of this
/// same deployment, never a new deployment, or this URL stops working in
/// every shipped build.
enum ReportClient {
    static let endpoint = "https://script.google.com/macros/s/AKfycbz16p-AE4Wg7WXAGabuSHFWhhSioLqcXM1hUx-QYwGmqP9KOPZLju-NTsxVbxS6HTAV/exec"
    /// Must equal APP_TOKEN in the script. Not a secret; it keeps scrapers out.
    static let token = "808-reports-v1"

    static func body(reportID: String, target: String, kind: String, reason: String, appVersion: String) -> Data {
        let payload = ["token": token, "report_id": reportID, "target": target,
                       "kind": kind, "reason": String(reason.prefix(500)), "app_version": appVersion]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    static func send(reportID: String, target: String, kind: String, reason: String) {
        guard let url = URL(string: endpoint), !endpoint.isEmpty else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = body(reportID: reportID, target: target, kind: kind, reason: reason, appVersion: version)
        URLSession.shared.dataTask(with: request).resume()
    }
}
