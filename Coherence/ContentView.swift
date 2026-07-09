import SwiftUI

/// Phase 0 placeholder. Confirms the app launches, the local ModelContainer is
/// injected, and colors resolve through the asset catalog (gold on near-black).
struct ContentView: View {
    var body: some View {
        ZStack {
            AppColor.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Coherence")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppColor.accentGold)
                Text("coherence as evidence, not a training score")
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
