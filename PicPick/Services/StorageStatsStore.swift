//
//  StorageStatsStore.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation

/// 存储空间统计存储 - 持久化累计释放的空间（跨启动累计，用于顶部进度条展示）
final class StorageStatsStore {

    static let shared = StorageStatsStore()

    private let defaults = UserDefaults.standard
    private let freedBytesKey = "StorageStats.cumulativeFreedBytes"

    /// 累计释放的存储空间（字节）
    private(set) var cumulativeFreedBytes: Int64

    private init() {
        cumulativeFreedBytes = Int64(defaults.integer(forKey: freedBytesKey))
    }

    /// 记录一次成功删除释放的空间
    func recordFreedSpace(_ bytes: Int64) {
        guard bytes > 0 else { return }
        cumulativeFreedBytes += bytes
        defaults.set(cumulativeFreedBytes, forKey: freedBytesKey)
    }

    /// 格式化字节数（MB / GB 自适应，如 "156.8 MB"）
    func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - 每月处理计数（首页进度环数据源）

    /// 记录一次照片处理（滑动决策）
    func recordPhotoProcessed(on date: Date = Date()) {
        let key = processedKey(forMonthContaining: date)
        let value = defaults.integer(forKey: key) + 1
        defaults.set(value, forKey: key)
    }

    /// 撤销一次照片处理
    func unrecordPhotoProcessed(on date: Date = Date()) {
        let key = processedKey(forMonthContaining: date)
        let value = max(defaults.integer(forKey: key) - 1, 0)
        defaults.set(value, forKey: key)
    }

    /// 某月已处理照片数
    func processedCount(inMonthContaining date: Date) -> Int {
        defaults.integer(forKey: processedKey(forMonthContaining: date))
    }

    private func processedKey(forMonthContaining date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "StorageStats.processedCount.%04d-%02d", year, month)
    }
}
