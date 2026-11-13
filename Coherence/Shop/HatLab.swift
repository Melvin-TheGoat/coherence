#if DEBUG
import SwiftUI

/// Every form, every stage, every hat, for review (Melvin, 2026-11-13). Otto
/// has thirteen looks and each of the four forms seven stages, times sixteen
/// hats and none: too many to reach by wearing them one at a time.
///
/// **Grid**: pick a hat (or all, or none) and a form (or all); every stage of
/// each is a small cell drawn by Home's own code path, `ValleyScene` with its
/// aura figure, rendered at a phone's size and cropped round him, so a hat
/// sits in a cell exactly where it sits on Home. **Shuffle**: one Home-sized
/// valley, a random form, stage and hat on every tap (or every 1.5 s).
///
/// The grid draws the real rigs by default. "Stills" swaps in the still
/// drawings, lighter when a screen holds dozens of cells; Otto has stills for
/// his seven stages only, so in stills mode his row shows those seven. The
/// shuffle always draws the rig.
///
/// Settings > Testing (debug) > Hat lab, or launch with `PREVIEW_HAT_LAB=1`.
/// For screenshots: `PREVIEW_HAT_LAB_HAT=<id|none|all>`,
/// `PREVIEW_HAT_LAB_FORM=<otto|redPanda|tiger|phoenix|dragon|all>`,
/// `PREVIEW_HAT_LAB_MODE=shuffle`, `PREVIEW_HAT_LAB_COLS=<n>` and
/// `PREVIEW_HAT_LAB_STILLS=1`.
struct HatLab: View {
    enum Mode: String { case grid, shuffle }

    static let allHats = "all"
    static let noHat = "none"

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var hat: String
    @State private var form: String
    @State private var stills: Bool
    @State private var columns: Int
    var closable = true

    init(closable: Bool = true) {
        let env = ProcessInfo.processInfo.environment
        _mode = State(initialValue: Mode(rawValue: env["PREVIEW_HAT_LAB_MODE"] ?? "") ?? .grid)
        _hat = State(initialValue: env["PREVIEW_HAT_LAB_HAT"] ?? HatCatalog.all.first?.id ?? Self.noHat)
        _form = State(initialValue: env["PREVIEW_HAT_LAB_FORM"] ?? Self.allHats)
        _stills = State(initialValue: env["PREVIEW_HAT_LAB_STILLS"] == "1")
        _columns = State(initialValue: Int(env["PREVIEW_HAT_LAB_COLS"] ?? "") ?? 4)
        self.closable = closable
    }

    private var hats: [String] {
        hat == Self.allHats ? HatCatalog.all.map(\.id) + [Self.noHat] : [hat]
    }

    private var forms: [Companion] {
        form == Self.allHats ? Companion.allCases : [Companion(rawValue: form) ?? .otto]
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            if mode == .grid {
                grid
            } else {
                HatLabShuffle()
            }
        }
        .background(Color(red: 0.93, green: 0.95, blue: 0.97).ignoresSafeArea())
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Mode", selection: $mode) {
                    Text("Grid").tag(Mode.grid)
                    Text("Shuffle").tag(Mode.shuffle)
                }
                .pickerStyle(.segmented)
                if closable {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .padding(.leading, 8)
                }
            }
            if mode == .grid {
                HStack(spacing: 4) {
                    Picker("Hat", selection: $hat) {
                        Text("All hats").tag(Self.allHats)
                        Text("No hat").tag(Self.noHat)
                        ForEach(HatCatalog.all) { Text($0.name).tag($0.id) }
                    }
                    Picker("Form", selection: $form) {
                        Text("All forms").tag(Self.allHats)
                        ForEach(Companion.allCases) { Text(Self.name($0)).tag($0.rawValue) }
                    }
                    Spacer(minLength: 0)
                }
                .pickerStyle(.menu)
                .lineLimit(1)
                HStack(spacing: 8) {
                    Toggle("Stills", isOn: $stills)
                        .toggleStyle(.button)
                    Spacer(minLength: 0)
                    Stepper("\(columns) across", value: $columns, in: 2...7)
                        .fixedSize()
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: Grid

    private var grid: some View {
        GeometryReader { geo in
            let width = (geo.size.width - 16 - CGFloat(columns - 1) * 4) / CGFloat(columns)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                    ForEach(hats, id: \.self) { h in
                        ForEach(forms) { f in
                            Text("\(Self.hatName(h)) · \(Self.name(f))")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.leading, 2)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 4), count: columns),
                                      alignment: .leading, spacing: 4) {
                                ForEach(steps(for: f), id: \.self) { step in
                                    HatLabCell(form: f, step: step, hat: h, stills: stills, width: width)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 24)
            }
        }
    }

    /// Otto's thirteen looks (his seven stages when drawing stills), a form's
    /// seven stages.
    private func steps(for form: Companion) -> [Int] {
        if form == .otto { return stills ? [1, 3, 5, 7, 9, 11, 13] : Array(1...13) }
        return Array(1...7)
    }

    static func name(_ form: Companion) -> String {
        form == .otto ? "Otto" : form.creature.capitalized
    }

    static func hatName(_ id: String) -> String {
        id == noHat ? "No hat" : HatCatalog.all.first { $0.id == id }?.name ?? id
    }

    static func stepName(form: Companion, step: Int) -> String {
        let stages = ["Withered", "Faded", "Stirring", "Steady", "Bright", "Radiant", "Nirvana"]
        if form == .otto {
            return step % 2 == 1 ? "\(step) \(stages[(step - 1) / 2])" : "look \(step)"
        }
        return "\(step) \(stages[step - 1])"
    }
}

/// One stage in a small valley: `ValleyScene` at a phone's size, as Home
/// draws it, scaled down and cropped round him.
struct HatLabCell: View {
    let form: Companion
    /// Otto's look (1...13) or a form's stage (1...7).
    let step: Int
    let hat: String
    var stills = false
    let width: CGFloat

    /// The iPhone 17 the composition is drawn at.
    static let phone = CGSize(width: 402, height: 874)

    /// The part of the phone-sized valley he and any hat can occupy: from
    /// well above his tuft (the wizard hat, the floating looks) to just
    /// under his cushion.
    static var crop: CGRect {
        let seated = SitLayout.ottoHeight(in: phone)
        let cushion = phone.height * 0.76
        let top = cushion - seated * 1.62
        return CGRect(x: 46, y: top, width: phone.width - 92, height: cushion + 26 - top)
    }

    var body: some View {
        let crop = Self.crop
        let s = width / crop.width
        VStack(spacing: 1) {
            scene
                .frame(width: Self.phone.width, height: Self.phone.height)
                .offset(x: -crop.minX, y: -crop.minY)
                .frame(width: crop.width, height: crop.height, alignment: .topLeading)
                .clipped()
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: crop.width * s, height: crop.height * s, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(HatLab.stepName(form: form, step: step))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var scene: some View {
        let stage: OttoAura.Stage = form == .otto
            ? OttoAura.Stage(rawValue: (step + 1) / 2) ?? .steady
            : OttoAura.Stage(rawValue: step) ?? .steady
        return ValleyScene(progress: 0, aura: stage, auraLook: form == .otto ? step : nil,
                           auraSnap: true, life: false,
                           auraForm: form, auraHat: hat, auraStills: stills)
    }
}

/// One Home-sized valley with a random form, stage and hat on every tap.
struct HatLabShuffle: View {
    struct Combo: Equatable {
        var form: Companion
        var step: Int
        var hat: String
    }

    @State private var combo = HatLabShuffle.random()
    @State private var autoplay = false

    static func random() -> Combo {
        let form = Companion.allCases.randomElement() ?? .otto
        let step = Int.random(in: 1...(form == .otto ? 13 : 7))
        let hat = (HatCatalog.all.map(\.id) + [HatLab.noHat]).randomElement() ?? HatLab.noHat
        return Combo(form: form, step: step, hat: hat)
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                ValleyScene(progress: 0,
                            aura: combo.form == .otto ? OttoAura.Stage(rawValue: (combo.step + 1) / 2) ?? .steady
                                                      : OttoAura.Stage(rawValue: combo.step) ?? .steady,
                            auraLook: combo.form == .otto ? combo.step : nil,
                            auraSnap: true, life: false,
                            auraForm: combo.form, auraHat: combo.hat)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            VStack(spacing: 8) {
                Text("\(HatLab.name(combo.form)) · \(HatLab.stepName(form: combo.form, step: combo.step)) · \(HatLab.hatName(combo.hat))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(ValleyGround.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white.opacity(0.88), in: Capsule())
                    .textSelection(.enabled)
                Toggle("Auto every 1.5 s", isOn: $autoplay)
                    .toggleStyle(.button)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .tint(ValleyGround.ink)
                    .background(Color.white.opacity(0.7), in: Capsule())
            }
            .padding(.top, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { next() }
        .task(id: autoplay) {
            guard autoplay else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, autoplay else { return }
                next()
            }
        }
        .onChange(of: combo) { _, c in
            NSLog("Hat lab: %@ step %d, %@", c.form.rawValue, c.step, c.hat)
        }
    }

    private func next() {
        var c = Self.random()
        while c == combo { c = Self.random() }
        combo = c
    }
}
#endif
