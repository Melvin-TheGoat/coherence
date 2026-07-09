import SwiftUI

/// Phase 0 placeholder for the Watch app. Live heart rate arrives in Phase 1.
struct WatchContentView: View {
    var body: some View {
        ZStack {
            AppColor.backgroundPrimary
                .ignoresSafeArea()
            Text("Coherence")
                .font(.headline)
                .foregroundStyle(AppColor.accentGold)
        }
    }
}

#Preview {
    WatchContentView()
}
