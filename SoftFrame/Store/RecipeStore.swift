import Foundation

/// 每个滤镜单独记住调节。只在主线程使用。
final class RecipeStore {
    private let defaults: UserDefaults
    private let lastKey = "softframe.lastFilterID"
    private let mapKey = "softframe.adjustments"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func current() -> FilterRecipe {
        let id = defaults.string(forKey: lastKey) ?? FilterCatalog.cream.id
        return recipe(for: id)
    }

    func recipe(for filterID: String) -> FilterRecipe {
        let definition = FilterCatalog.definition(id: filterID)
        guard let saved = loadMap()[definition.id] else {
            return .recommended(for: definition)
        }
        return FilterRecipe(
            filterID: definition.id,
            intensity: saved.intensity,
            grain: saved.grain,
            warmth: saved.warmth,
            skin: saved.skin
        ).clamped()
    }

    func save(_ recipe: FilterRecipe) {
        let recipe = recipe.clamped()
        var map = loadMap()
        map[recipe.filterID] = recipe.adjustments
        defaults.set(recipe.filterID, forKey: lastKey)
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: mapKey)
        }
    }

    private func loadMap() -> [String: FilterAdjustments] {
        guard let data = defaults.data(forKey: mapKey),
              let map = try? JSONDecoder().decode([String: FilterAdjustments].self, from: data) else {
            return [:]
        }
        return map
    }
}
