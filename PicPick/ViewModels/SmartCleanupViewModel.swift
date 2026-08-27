//
//  SmartCleanupViewModel.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import SwiftUI
import Combine
import Photos

/// 截图与模糊照片归类视图模型
/// 截图：PHAsset mediaSubtypes 直接识别；模糊：Core Image Laplacian 方差检测
/// 归类后由用户手动确认删除，全程本地运行
@MainActor
final class SmartCleanupViewModel: ObservableObject {

    // MARK: - 分类

    enum Section: String, CaseIterable, Identifiable {
        case screenshots = "截图"
        case blurred = "模糊照片"

        var id: String { rawValue }
    }

    // MARK: - Published Properties

    @Published var section: Section = .screenshots
    @Published var screenshots: [PhotoItem] = []
    @Published var blurredPhotos: [BlurredPhoto] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var blurScannedCount = 0
    @Published var blurTotalCount = 0
    @Published var hasScannedBlur = false
    @Published var confirmDelete = false
    @Published var toastMessage: String?
    @Published var showPaywall = false
    @Published private(set) var selectedSizeText: String = "0 KB"

    // MARK: - Services

    private let photoService = PhotoService()
    private let analysisService = PhotoAnalysisService()
    private let pendingDeleteStore = PendingDeleteStore.shared
    private let quotaService = DailyQuotaService.shared
    private let paywallService = PaywallService.shared
    private var scanTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// 模糊扫描进度（0-1）
    var blurProgress: Double {
        guard blurTotalCount > 0 else { return 0 }
        return Double(blurScannedCount) / Double(blurTotalCount)
    }

    /// 已选照片数量
    var selectedCount: Int {
        selectedIDs.count
    }

    /// 当前分类的照片总数（用于全选判断）
    var currentSectionTotal: Int {
        section == .screenshots ? screenshots.count : blurredPhotos.count
    }

    /// 是否已全选
    var isAllSelected: Bool {
        currentSectionTotal > 0 && selectedCount == currentSectionTotal
    }

    // MARK: - 截图

    func loadScreenshots() {
        screenshots = photoService.fetchScreenshots()
        refreshSelectedSize()
    }

    // MARK: - 模糊扫描

    func startBlurScan() {
        scanTask?.cancel()
        isScanning = true
        blurredPhotos = []
        blurScannedCount = 0
        blurTotalCount = 0
        hasScannedBlur = false

        scanTask = Task { [weak self] in
            await self?.runBlurScan()
        }
    }

    func cancelBlurScan() {
        scanTask?.cancel()
        isScanning = false
    }

    private func runBlurScan() async {
        // 扫描范围：当月照片（与清理队列一致），排除截图避免重复归类
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        var photos = photoService.fetchPhotos(from: startOfMonth, to: Date())
        photos.removeAll { $0.asset.mediaSubtypes.contains(.photoScreenshot) }
        blurTotalCount = photos.count

        let engine = BlurScanEngine(photoService: photoService, analysisService: analysisService)

        do {
            let results = try await engine.scan(photos: photos) { [weak self] scanned in
                self?.blurScannedCount = scanned
            }
            blurredPhotos = results
            hasScannedBlur = true
            showToast(results.isEmpty ? "未发现模糊照片 🎉" : "发现 \(results.count) 张模糊照片")
        } catch is CancellationError {
            showToast("已取消扫描")
        } catch {
            showToast("扫描失败: \(error.localizedDescription)")
        }

        isScanning = false
    }

    // MARK: - 选择

    func toggleSelection(id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        refreshSelectedSize()
    }

    func selectAll() {
        selectedIDs = section == .screenshots
            ? Set(screenshots.map { $0.id })
            : Set(blurredPhotos.map { $0.id })
        refreshSelectedSize()
    }

    func clearSelection() {
        selectedIDs.removeAll()
        refreshSelectedSize()
    }

    // MARK: - 删除

    func requestDeleteSelected() {
        guard selectedCount > 0 else { return }
        confirmDelete = true
    }

    /// 将选中的照片移入 App 内「待删除列表」（双重安全删除第一层，照片仍保留在相册中）
    func deleteSelected() {
        confirmDelete = false
        let deletedIDs = selectedIDs
        guard !deletedIDs.isEmpty else { return }

        let photos: [PhotoItem] = section == .screenshots
            ? screenshots.filter { deletedIDs.contains($0.id) }
            : blurredPhotos.filter { deletedIDs.contains($0.id) }.map { $0.photo }

        let items = photos.map { photo in
            PendingDeleteItem(
                id: photo.id,
                dateAdded: Date(),
                sizeBytes: photoService.getFileSize(for: photo.asset)
            )
        }

        // 免费额度检查（Pro 用户不限量）
        if !paywallService.isProUnlocked && items.count > quotaService.remainingToday {
            showPaywall = true
            showToast("今日免费清理额度已用完（\(AppConfig.freeDailyCleanLimit) 张/天），解锁 Pro 无限清理")
            return
        }
        quotaService.recordCleaning(count: items.count)

        pendingDeleteStore.add(items)

        selectedIDs.removeAll()
        refreshSelectedSize()

        if section == .screenshots {
            screenshots.removeAll { deletedIDs.contains($0.id) }
        } else {
            blurredPhotos.removeAll { deletedIDs.contains($0.id) }
        }
        showToast("已移入待删除列表（\(items.count) 张），可恢复或永久删除")
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

    // MARK: - Private Helpers

    private func selectedAssets() -> [PHAsset] {
        if section == .screenshots {
            return screenshots.filter { selectedIDs.contains($0.id) }.map { $0.asset }
        }
        return blurredPhotos.filter { selectedIDs.contains($0.id) }.map { $0.photo.asset }
    }

    /// 刷新选中照片的预计释放空间（缓存，避免每次渲染重新计算）
    private func refreshSelectedSize() {
        let assets = selectedAssets()
        selectedSizeText = photoService.formatFileSize(photoService.estimateSize(for: assets))
    }
}

// MARK: - 后台模糊扫描引擎（非隔离，运行在全局执行器）

/// 模糊照片扫描引擎：逐张计算 Laplacian 方差，低于阈值归为模糊
private struct BlurScanEngine {

    let photoService: PhotoService
    let analysisService: PhotoAnalysisService

    func scan(
        photos: [PhotoItem],
        progress: @MainActor @Sendable (Int) -> Void
    ) async throws -> [BlurredPhoto] {
        var results: [BlurredPhoto] = []

        for (index, photo) in photos.enumerated() {
            try Task.checkCancellation()

            if let cgImage = await photoService.loadAnalysisImage(for: photo.asset, maxDimension: 512),
               let variance = analysisService.laplacianVariance(of: cgImage),
               variance < PhotoAnalysisService.blurVarianceThreshold {
                results.append(BlurredPhoto(photo: photo, variance: variance))
            }
            await progress(index + 1)
        }

        // 最模糊的排在最前
        return results.sorted { $0.variance < $1.variance }
    }
}
