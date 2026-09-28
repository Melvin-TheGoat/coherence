import Foundation

/// The hats Otto can wear in the shop, bought with points earned by
/// meditating (`OttoPoints`, one point per minute). On theme for a calm
/// meditation app with a sloth: nothing branded or loud, just things a
/// small animal sitting still might actually wear.
///
/// **Prices are spread so the first is within reach of one sit and the
/// last is a standing practice.** The beanie costs about two short
/// ten-minute sessions; the golden crown costs roughly what a few weeks of
/// daily twenty-to-thirty-minute sessions add up to. Prices ascend down the
/// list; `HatCatalogTests` pins both the spread and that every id is unique.
enum HatCatalog {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        /// In points (`OttoPoints`), one point per minute meditated.
        let price: Int
    }

    static let all: [Item] = [
        Item(id: "beanie", name: "Beanie", price: 20),
        Item(id: "sunhat", name: "Straw Sun Hat", price: 60),
        Item(id: "bucket", name: "Bucket Hat", price: 120),
        // The horns, the halo and the wanderer's hat came with Melvin's art
        // (2026-09-27): the sheet drew ten, and a dark straw hat on its own.
        Item(id: "horns", name: "Little Horns", price: 180),
        Item(id: "leafcrown", name: "Leaf Crown", price: 220),
        Item(id: "flowercrown", name: "Flower Crown", price: 350),
        Item(id: "monkhat", name: "Monk's Woven Hat", price: 500),
        Item(id: "wanderer", name: "Wanderer's Hat", price: 650),
        Item(id: "enso", name: "Ensō Hat", price: 700),
        Item(id: "wizardhat", name: "Wizard Hat", price: 750),
        // A halo is the nearest thing to enlightenment a sloth can wear.
        Item(id: "halo", name: "Halo", price: 900),
        Item(id: "goldcrown", name: "Golden Crown", price: 1000)
    ]

    static func item(_ id: String) -> Item? {
        all.first { $0.id == id }
    }
}
