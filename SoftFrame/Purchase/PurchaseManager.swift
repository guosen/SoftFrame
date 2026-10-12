import Combine
import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var displayPrice = ""
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var paywallFilterID: String?

    private var product: Product?
    private var updates: Task<Void, Never>?
    private let cacheKey = "softframe.unlocked"

    func start() {
        isUnlocked = UserDefaults.standard.bool(forKey: cacheKey)
        updates?.cancel()
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        do {
            let products = try await Product.products(for: [AppConfig.productID])
            product = products.first
            displayPrice = product?.displayPrice ?? ""
        } catch {
            if displayPrice.isEmpty {
                errorMessage = "价格暂时获取不到，请检查网络后再试。"
            }
        }
        await refreshEntitlements()
    }

    func purchase() async {
        if product == nil {
            await refresh()
        }
        guard let product else {
            errorMessage = "价格暂时获取不到，请检查网络后再试。"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled:
                break
            case .pending:
                errorMessage = "购买正在等待批准。"
            @unknown default:
                break
            }
        } catch {
            errorMessage = "购买没有完成，请再试一次。"
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isUnlocked {
                errorMessage = "没有找到已购买的项目。"
            }
        } catch {
            errorMessage = "恢复购买失败，请再试一次。"
        }
    }

    func canUse(_ filter: FilterDefinition) -> Bool {
        !filter.isPaid || isUnlocked
    }

    private func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == AppConfig.productID else { continue }
            if transaction.revocationDate == nil {
                unlocked = true
            }
        }
        setUnlocked(unlocked)
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            errorMessage = "购买结果无法验证。"
            return
        }
        if transaction.productID == AppConfig.productID, transaction.revocationDate == nil {
            setUnlocked(true)
            paywallFilterID = nil
        }
        await transaction.finish()
    }

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        UserDefaults.standard.set(value, forKey: cacheKey)
    }
}
