//
//  PaywallService.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import StoreKit

/// StoreKit 2 内购服务 - 一次性买断（非消耗型）解锁无限量清理
/// 商品 ID 见 AppConfig.proProductID，需在 App Store Connect 创建；
/// 本地调试可用 Xcode 的 StoreKit 配置文件（Product → Scheme → StoreKit Configuration）
@MainActor
final class PaywallService: ObservableObject {

    static let shared = PaywallService()

    // MARK: - Published Properties

    @Published private(set) var product: Product?
    @Published private(set) var isProUnlocked = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Services

    private var updatesTask: Task<Void, Never>?

    private init() {
        // 监听交易更新（退款、家庭共享等场景）
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update,
                   transaction.productID == AppConfig.proProductID {
                    self?.isProUnlocked = true
                }
            }
        }

        Task { await refreshEntitlements() }
        Task { await loadProducts() }
    }

    // MARK: - 商品

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [AppConfig.proProductID])
            product = products.first
        } catch {
            errorMessage = "无法加载商品信息，请检查网络后重试"
        }
    }

    /// 商品展示价格（如 ¥18.00）
    var productDisplayPrice: String {
        product?.displayPrice ?? "—"
    }

    // MARK: - 权益

    /// 刷新 Pro 解锁状态（基于当前权益，买断后永久有效）
    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == AppConfig.proProductID {
                unlocked = true
                break
            }
        }
        isProUnlocked = unlocked
    }

    // MARK: - 购买

    func purchase() async {
        guard let product = product else {
            errorMessage = "商品信息未加载，请检查网络后重试"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    isProUnlocked = true
                    await transaction.finish()
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "购买等待处理中（如家长同意），完成后自动解锁"
            @unknown default:
                break
            }
        } catch {
            errorMessage = "购买失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 恢复购买

    func restore() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "恢复购买失败，请稍后重试"
        }
    }
}
