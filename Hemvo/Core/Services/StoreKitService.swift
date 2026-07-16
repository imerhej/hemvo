//  StoreKitService.swift
//  Hemvo
//  Handles in-app purchases and subscription verification using StoreKit 2.

internal import StoreKit
internal import Foundation
internal import Combine
internal import OSLog

// MARK: - StoreKitService
@MainActor
final class StoreKitService: ObservableObject {

    static let shared = StoreKitService()

    // MARK: - Published
    @Published var products: [Product]             = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading: Bool                  = false

    /// Transaction id of the currently active subscription entitlement, if any.
    /// Sent to the verify-subscription Edge Function so the server can confirm
    /// the purchase with Apple before marking the household subscription active.
    @Published var currentTransactionID: UInt64?

    /// Expiration (= next renewal) date of the active subscription entitlement.
    @Published var subscriptionExpirationDate: Date?

    // MARK: - Transaction Listener
    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = startTransactionListener()
        Task { await loadProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products
    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: [StoreIDs.monthly, StoreIDs.annual])
                .sorted { $0.price < $1.price }
        } catch {
            Logger.store.error("Failed to load products: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Purchase
    func purchase(productID: String) async throws {
        guard let product = products.first(where: { $0.id == productID }) else {
            throw StoreKitError.productNotFound
        }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try verify(verification)
            await updateEntitlements()
            await transaction.finish()

        case .userCancelled:
            throw StoreKitError.userCancelled

        case .pending:
            break // Waiting for parental approval, etc.

        @unknown default:
            break
        }
    }

    // MARK: - Restore Purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            Logger.store.error("Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Check Active Subscription
    func hasActiveSubscription() async -> Bool {
        // Same path on device and simulator: reflect the real StoreKit
        // entitlement. The scheme's StoreKit configuration works in the
        // simulator too, so a simulated purchase reports as active and no
        // purchase reports as inactive. This keeps trial / active / expired
        // states — and the paywall itself — testable locally instead of
        // hardcoding every simulator user to "subscribed". New users are
        // still un-gated because the 7-day trial sets isSubscriptionActive.
        await updateEntitlements()
        return purchasedProductIDs.contains(StoreIDs.monthly) ||
               purchasedProductIDs.contains(StoreIDs.annual)
    }

    // MARK: - Update Entitlements
    @discardableResult
    func updateEntitlements() async -> Set<String> {
        var active = Set<String>()
        var latestTransactionID: UInt64?
        var latestExpiration: Date?
        for await result in Transaction.currentEntitlements {
            if let tx = try? verify(result), tx.revocationDate == nil {
                active.insert(tx.productID)
                if StoreIDs.all.contains(tx.productID) {
                    latestTransactionID = tx.id
                    latestExpiration    = tx.expirationDate
                }
            }
        }
        purchasedProductIDs = active
        currentTransactionID = latestTransactionID
        subscriptionExpirationDate = latestExpiration
        return active
    }

    // MARK: - Verify Transaction
    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitError.failedVerification
        case .verified(let value): return value
        }
    }

    // MARK: - Transaction Listener
    private func startTransactionListener() -> Task<Void, Error> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                do {
                    let tx = try self.verify(result)
                    await self.updateEntitlements()
                    await tx.finish()
                } catch {
                    Logger.store.error("Transaction listener error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Product Helpers
    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    func formattedPrice(for productID: String) -> String {
        product(for: productID)?.displayPrice ?? "—"
    }
}

// MARK: - StoreKitError
enum StoreKitError: LocalizedError {
    case productNotFound
    case failedVerification
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .productNotFound:    return "Product not found in the App Store."
        case .failedVerification: return "Purchase verification failed."
        case .userCancelled:      return "Purchase was cancelled."
        }
    }
}
