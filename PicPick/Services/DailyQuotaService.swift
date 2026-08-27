//
//  DailyQuotaService.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import Combine

/// 每日免费清理额度 - 免费用户每天限 50 张（AppConfig.freeDailyCleanLimit），Pro 用户无限量
/// 按自然日计算，跨天自动重置
final class DailyQuotaService: ObservableObject {

    static let shared = DailyQuotaService()

    @Published private(set) var usedToday: Int = 0

    private let defaults = UserDefaults.standard

    private init() {
        refresh()
    }

    /// 今日剩余额度
    var remainingToday: Int {
        max(AppConfig.freeDailyCleanLimit - usedToday, 0)
    }

    /// 重新读取今日用量（跨天时由调用方触发）
    func refresh() {
        usedToday = defaults.integer(forKey: keyForToday())
    }

    /// 记录一次清理（移入待删除列表的张数）
    func recordCleaning(count: Int) {
        let key = keyForToday()
        let newValue = defaults.integer(forKey: key) + count
        defaults.set(newValue, forKey: key)
        usedToday = newValue
    }

    private func keyForToday() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "DailyQuota.%04d-%02d-%02d", year, month, day)
    }
}
