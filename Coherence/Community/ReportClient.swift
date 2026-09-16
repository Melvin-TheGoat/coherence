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
/// **Inert until deployed:** `endpoint` is empty, so nothing is sent. Deploy
/// the script (steps in its header), paste the /exec URL here, and tick the
/// 1.1 checklist item.
enum ReportClient {
    static let endpoint = ""
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
