//
//  PendingDeleteViewModel.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import SwiftUI
import Combine
import Photos

/// 待删除列表视图模型 - 双重安全删除的第二层（第一层是进入列表，第二层是系统「最近删除」）
/// 支持单张/批量恢复；永久删除时调用 PHPhotoLibrary.performChanges，iOS 会自动弹出系统确认弹窗
@MainActor
final class PendingDeleteViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var items: [PendingDeleteItem] = []
    @Published var assetsByID: [String: PHAsset] = [:]
    @Published var selectedIDs: Set<String> = []
    @Published var confirmPermanentDelete = false
    @Published var toastMessage: String?

    // MARK: - Services

    private let store = PendingDeleteStore.shared
    private let progressStore = CleaningProgressStore.shared
    private let statsStore = StorageStatsStore.shared
    private let photoService = PhotoService()
    private var cancellables = Set<AnyCancellable>()
    private var toastTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        store.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                self.items = items
                // 清理失效的选中项
                let validIDs = Set(items.map { $0.id })
                self.selectedIDs = self.selectedIDs.filter { validIDs.contains($0) }
                self.refreshAssets()
            }
            .store(in: &cancellables)

        items = store.items
        refreshAssets()
    }

    // MARK: - 资产解析

    /// 解析列表项对应的 PHAsset（供缩略图与删除使用，照片可能已不存在）
    func refreshAssets() {
        let all = photoService.fetchAssets(withLocalIdentifiers: items.map { $0.id })
        assetsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.localIdentifier, $0) })
    }

    // MARK: - Computed Properties

    var selectedCount: Int {
        selectedIDs.count
    }

    var isAllSelected: Bool {
        items.count > 0 && selectedCount == items.count
    }

    /// 列表合计可释放空间
    var totalSizeFormatted: String {
        photoService.formatFileSize(store.totalBytes)
    }

    /// 选中项合计大小
    var selectedSizeFormatted: String {
        let bytes = items.filter { selectedIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return photoService.formatFileSize(bytes)
    }

    // MARK: - 选择

    func toggleSelection(id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectAll() {
        selectedIDs = Set(items.map { $0.id })
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    // MARK: - 恢复

    /// 单张恢复
    func restore(_ item: PendingDeleteItem) {
        restore(ids: [item.id])
    }

    /// 批量恢复选中项（照片仍在相册中，只是移出待删除列表）
    func restoreSelected() {
        restore(ids: Array(selectedIDs))
    }

    private func restore(ids: [String]) {
        guard !ids.isEmpty else { return }
        store.remove(ids: ids)
        // 同步清理队列：恢复的照片重新变为未处理
        progressStore.resetStatuses(ids: ids)
        selectedIDs.removeAll()
        showToast("已恢复 \(ids.count) 张照片")
    }

    // MARK: - 永久删除

    func requestPermanentDelete() {
        guard selectedCount > 0 else { return }
        confirmPermanentDelete = true
    }

    /// 永久删除选中项：调用 performChanges，iOS 自动弹出系统确认弹窗
    /// 即使在此确认，照片仍会在系统「最近删除」中保留 30 天
    func permanentlyDeleteSelected() async {
        confirmPermanentDelete = false
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }

        // 解析资产（可能已被其他方式删除）
        let assets = photoService.fetchAssets(withLocalIdentifiers: ids)
        if assets.count < ids.count {
            let foundIDs = Set(assets.map { $0.localIdentifier })
            let missing = ids.filter { !foundIDs.contains($0) }
            store.remove(ids: missing)
            progressStore.resetStatuses(ids: missing)
            showToast("有 \(missing.count) 张照片已不在相册中，已从列表移除")
        }

        guard !assets.isEmpty else {
            selectedIDs.removeAll()
            return
        }

        let freedBytes = photoService.estimateSize(for: assets)
        let result = await photoService.deletePhotos(assets)

        if result.success > 0 {
            let deletedIDs = Set(assets.map { $0.localIdentifier })
            store.remove(ids: assets.map { $0.localIdentifier })
            progressStore.resetStatuses(ids: Array(deletedIDs))
            statsStore.recordFreedSpace(freedBytes)
            selectedIDs.removeAll()
            showToast("已永久删除 \(result.success) 张，释放 \(photoService.formatFileSize(freedBytes))。系统「最近删除」仍保留 30 天")
        } else {
            showToast("删除失败或已取消")
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }
}
