//
//  CleaningProgressStore.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation

/// 清理进度快照 - 断点继续的数据载体
struct CleaningSnapshot: Codable {
    /// 队列范围
    var startDate: Date
    var endDate: Date
    var isDateFilterEnabled: Bool
    /// 媒体类型（MediaType.rawValue）
    var mediaType: String
    /// 是否为盲盒会话（盲盒会话不持久化）
    var isBlindBox: Bool
    /// 当前处理到的序号
    var currentIndex: Int
    /// 每张照片的滑动状态（id -> "delete" / "keep"）
    var statuses: [String: String]
    var updatedAt: Date
}

/// 清理进度存储 - 记录用户清理进度，下次打开从上次中断的位置继续
final class CleaningProgressStore {

    static let shared = CleaningProgressStore()

    private let defaults = UserDefaults.standard
    private let snapshotKey = "CleaningProgress.snapshot"

    // MARK: - 读写

    func save(_ snapshot: CleaningSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    func load() -> CleaningSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(CleaningSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    func clear() {
        defaults.removeObject(forKey: snapshotKey)
    }

    // MARK: - 状态调整（供待删除列表的恢复/永久删除同步队列状态）

    /// 将指定照片的状态重置为未处理（恢复照片时调用）
    func resetStatuses(ids: [String]) {
        guard var snapshot = load() else { return }
        for id in ids {
            snapshot.statuses.removeValue(forKey: id)
        }
        save(snapshot)
    }
}
