import StoreKit
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    let store: RecipeStore
    let purchases = PurchaseManager()
    let saver = PhotoSaver()
    @Published var recipe: FilterRecipe
    @Published var showSettings = false

    init(store: RecipeStore = RecipeStore()) {
        self.store = store
        recipe = store.current()
        saver.onTenthSave = { [weak self] in
            self?.requestReview()
        }
    }

    func start() async {
        purchases.start()
        if recipe.filter.isPaid && !purchases.isUnlocked {
            apply(.recommended(for: FilterCatalog.cream))
        }
    }

    func selectFilter(_ id: String) {
        let definition = FilterCatalog.definition(id: id)
        guard purchases.canUse(definition) else {
            purchases.paywallFilterID = definition.id
            return
        }
        apply(store.recipe(for: definition.id))
    }

    func update(_ recipe: FilterRecipe) {
        apply(recipe.clamped())
    }

    func restoreRecommended() {
        apply(.recommended(for: recipe.filter))
    }

    func unlockChanged() {
        if recipe.filter.isPaid && !purchases.isUnlocked {
            apply(store.recipe(for: FilterCatalog.cream.id))
        }
    }

    private func apply(_ recipe: FilterRecipe) {
        let recipe = recipe.clamped()
        self.recipe = recipe
        store.save(recipe)
    }

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
    }
}
