import Foundation

struct FilterAdjustments: Codable, Equatable {
    var intensity: Double
    var grain: Double
    var warmth: Double
    var skin: Double
}

struct FilterRecipe: Equatable {
    var filterID: String
    var intensity: Double
    var grain: Double
    var warmth: Double
    var skin: Double

    var filter: FilterDefinition {
        FilterCatalog.definition(id: filterID)
    }

    var adjustments: FilterAdjustments {
        FilterAdjustments(intensity: intensity, grain: grain, warmth: warmth, skin: skin)
    }

    static let initial = FilterRecipe(
        filterID: FilterCatalog.cream.id,
        intensity: 100,
        grain: FilterCatalog.cream.defaultGrain,
        warmth: FilterCatalog.cream.defaultWarmth,
        skin: FilterCatalog.cream.defaultSkin
    )

    static func recommended(for definition: FilterDefinition) -> FilterRecipe {
        FilterRecipe(
            filterID: definition.id,
            intensity: 100,
            grain: definition.defaultGrain,
            warmth: definition.defaultWarmth,
            skin: definition.defaultSkin
        )
    }

    func clamped() -> FilterRecipe {
        var copy = self
        copy.intensity = min(100, max(0, intensity))
        copy.grain = min(100, max(0, grain))
        copy.warmth = min(50, max(-50, warmth))
        copy.skin = min(30, max(0, skin))
        return copy
    }
}
