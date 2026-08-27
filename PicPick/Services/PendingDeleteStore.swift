//
//  PendingDeleteStore.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import Combine

/// App 内「待删除列表」存储 - 双重安全删除的第一层保护
/// 删除的照片先进入此列表（仍保留在系统相册），可单张/批量恢复，
/// 只有在此列表中选择「永久删除」才会真正调用 PHPhotoLibrary.performChanges
final class PendingDeleteStore: ObservableObject {

    static let shared = PendingDeleteStore()

    @Published private(set) var items: [PendingDeleteItem] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "PendingDelete.items"

    private init() {
        load()
    }

    // MARK: - 增删

    /// 批量加入待删除列表（按 id 去重）
    func add(_ newItems: [PendingDeleteItem]) {
        var existingIDs = Set(items.map { $0.id })
        for item in newItems where !existingIDs.contains(item.id) {
            items.append(item)
            existingIDs.insert(item.id)
        }
        save()
    }

    /// 从待删除列表移除（恢复照片，照片仍在相册中不受影响）
    func remove(ids: [String]) {
        let idSet = Set(ids)
        items.removeAll { idSet.contains($0.id) }
        save()
    }

    func contains(id: String) -> Bool {
        items.contains { $0.id == id }
    }

    // MARK: - 统计

    var count: Int { items.count }

    /// 合计大小（可释放空间）
    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    // MARK: - 持久化

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PendingDeleteItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }
}
