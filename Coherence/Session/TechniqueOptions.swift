import SwiftUI

/// The options in the "what did you practice" menu, written once.
///
/// Melvin, 2026-09-18: "the options need to be the same as when you log it
/// for yourself. This is obvious." They were not: the Save session sheet
/// offered `MeditationMethod.loggable` and stopped, while the results card
/// also offered "Something else" with a free-text field under it. Two menus
/// built by hand from the same list drift the moment one is edited, so both
/// now use this, and a technique added anywhere appears in both.
///
/// It is menu CONTENT, not a control: the two screens dress their own
/// buttons (a bare row on Save session, a bordered box on results), and only
/// the list of choices has to match.
struct TechniqueOptions: View {
    /// nil = unreported, `MeditationMethod.ownID` = something else (the
    /// caller shows the free-text field), otherwise a method or variant id.
    let select: (String?) -> Void

    var body: some View {
        Button("Unreported") { select(nil) }
        Divider()
        ForEach(MeditationMethod.techniques, id: \.id) { item in
            Button(item.label) { select(item.id) }
        }
        Divider()
        // Every sound 808 offers, in the picker's own groups (Melvin,
        // 2026-09-22). Submenus, because twenty more flat rows would bury
        // the practices above them.
        ForEach(SoundMenu.groups) { group in
            Menu(group.name) {
                ForEach(group.entries) { entry in
                    Button(entry.title) { select(entry.id) }
                }
            }
        }
        Divider()
        Button("Something else") { select(MeditationMethod.ownID) }
    }
}
