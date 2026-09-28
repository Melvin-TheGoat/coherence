#if DEBUG
import SwiftUI

/// One hat on all thirteen of Otto's looks at once, for checking a hat's fit
/// from Withered to Nirvana in a single screenshot (2026-09-27). Launch with
/// `PREVIEW_HAT_GALLERY=<hat id>`; `all` pages through every hat, one per tap.
struct HatGallery: View {
    let firstID: String
    @State private var index = 0
    @StateObject private var rig = OttoRigHolder()

    private var ids: [String] {
        firstID == "all" ? HatCatalog.all.map(\.id) : [firstID]
    }

    var body: some View {
        let id = ids[index % ids.count]
        VStack(spacing: 6) {
            Text(id).font(.headline).padding(.top, 54)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 0) {
                ForEach(1...13, id: \.self) { look in
                    VStack(spacing: 0) {
                        OttoAuraFigure(stage: OttoAura.Stage(rawValue: (look + 1) / 2) ?? .steady,
                                       look: look, size: 72, rig: rig, hatID: id)
                            .frame(width: 96, height: 150, alignment: .bottom)
                            .clipped()
                        Text("\(look)").font(.caption2)
                    }
                }
            }
            Spacer()
        }
        .background(Color(red: 0.62, green: 0.76, blue: 0.86))
        .contentShape(Rectangle())
        .onTapGesture { index += 1 }
    }
}
#endif
