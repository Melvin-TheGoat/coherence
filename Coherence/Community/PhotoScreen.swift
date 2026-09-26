import Foundation
import UIKit
#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif

/// On-device nudity screening for selfies and profile photos, guideline 1.2's
/// filter for images. Apple's Sensitive Content Analysis: the photo never
/// leaves the phone to be checked.
///
/// **Two conditions, both outside our code, decide whether it runs:**
/// 1. the `com.apple.developer.sensitivecontentanalysis.client` entitlement,
///    in the app since 2026-09-26, once the capability was ticked on both
///    App IDs (signing refuses it before that);
/// 2. the person has Sensitive Content Warning (or Communication Safety) on;
///    Apple only analyses when they do.
/// When either is missing the analyzer reports its policy as disabled and
/// this returns `.notScreened`, which lets the photo through: the report
/// button and manual removal remain the backstop, which is what 1.2 accepts.
enum PhotoScreen {
    enum Result: Equatable { case clean, sensitive, notScreened }

    static func check(_ image: UIImage) async -> Result {
        #if canImport(SensitiveContentAnalysis)
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled, let cg = image.cgImage else { return .notScreened }
        do {
            return try await analyzer.analyzeImage(cg).isSensitive ? .sensitive : .clean
        } catch {
            return .notScreened
        }
        #else
        return .notScreened
        #endif
    }
}
