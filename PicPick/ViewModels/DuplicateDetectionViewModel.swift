//
//  DuplicateDetectionViewModel.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import SwiftUI
import Combine
import Photos

/// 重复/相似照片检测视图模型
/// Vision 特征向量 + 余弦相似度（阈值 0.85）聚类，全程本地运行
@MainActor
final class DuplicateDetectionViewModel: ObservableObject {

    // MARK: - 扫描范围

    enum ScanScope: String, CaseIterable, Identifiable {
        case currentMonth = "本月照片"
        case allPhotos = "全部照片"

        var id: String { rawValue }
    }

    // MARK: - Published Properties

    @Published var scanScope: ScanScope = .currentMonth
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var totalCount = 0
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var confirmKeepBest = false
    @Published var showPaywall = false

    // MARK: - Services

    private let photoService = PhotoService()
    private let analysisService = PhotoAnalysisService()
    private let pendingDeleteStore = PendingDeleteStore.shared
    private let quotaService = DailyQuotaService.shared
    private let paywallService = PaywallService.shared
    private var scanTask: Task<Void, Never>?
    private var pendingGroup: DuplicateGroup?
    private var toastTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// 扫描进度（0-1，特征提取与两两比较各占一半）
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(scannedCount) / Double(totalCount * 2)
    }

    /// 待确认分组的信息文案
    var pendingSummary: String {
        guard let group = pendingGroup else { return "" }
        let count = group.redundantPhotos.count
        let size = photoService.formatFileSize(
            photoService.estimateSize(for: group.redundantPhotos.map { $0.asset })
        )
        return "将保留最佳的一张，其余 \(count) 张移入待删除列表（可恢复），预计释放 \(size)"
    }

    /// 某分组删除其余可释放的空间
    func groupFreedSizeFormatted(_ group: DuplicateGroup) -> String {
        photoService.formatFileSize(
            photoService.estimateSize(for: group.redundantPhotos.map { $0.asset })
        )
    }

    // MARK: - Scanning

    func startScan() {
        scanTask?.cancel()
        isScanning = true
        scannedCount = 0
        totalCount = 0
        groups = []
        errorMessage = nil

        scanTask = Task { [weak self] in
            await self?.runScan()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    private func runScan() async {
        let photos = scanScope == .currentMonth ? photosForCurrentMonth() : photoService.fetchAllPhotos()
        totalCount = photos.count

        guard totalCount > 1 else {
            isScanning = false
            showToast(totalCount == 0 ? "没有可扫描的照片" : "照片数量不足，无需查重")
            return
        }

        let engine = DuplicateScanEngine(photoService: photoService, analysisService: analysisService)

        do {
            let result = try await engine.compute(photos: photos) { [weak self] scanned, total in
                self?.scannedCount = scanned
                self?.totalCount = total
            }
            groups = result
            showToast(result.isEmpty ? "未发现重复照片 🎉" : "发现 \(result.count) 组相似照片")
        } catch is CancellationError {
            showToast("已取消扫描")
        } catch {
            errorMessage = "扫描失败: \(error.localizedDescription)"
        }

        isScanning = false
    }

    private func photosForCurrentMonth() -> [PhotoItem] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return photoService.fetchPhotos(from: startOfMonth, to: Date())
    }

    // MARK: - 保留最佳

    func requestKeepBest(in group: DuplicateGroup) {
        pendingGroup = group
        confirmKeepBest = true
    }

    /// 一键「保留最佳，删除其余」：像素最高的一张保留，
    /// 其余移入 App 内「待删除列表」（双重安全删除第一层，照片仍保留在相册中）
    func keepBest() {
        confirmKeepBest = false
        guard let group = pendingGroup else { return }
        pendingGroup = nil

        let redundant = group.redundantPhotos
        let items = redundant.map { photo in
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
        groups.removeAll { $0.id == group.id }
        showToast("已保留最佳，其余 \(items.count) 张移入待删除列表")
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

// MARK: - 后台扫描引擎（非隔离，运行在全局执行器）

/// 重复照片扫描引擎：特征提取 → 两两余弦相似度 → 并查集聚类
private struct DuplicateScanEngine {

    let photoService: PhotoService
    let analysisService: PhotoAnalysisService

    /// 计算相似组
    /// - Parameter progress: 进度回调（当前步数, 总步数），总步数 = 2 × 照片数
    func compute(
        photos: [PhotoItem],
        progress: @MainActor @Sendable (Int, Int) -> Void
    ) async throws -> [DuplicateGroup] {
        let count = photos.count
        var vectors = [[Float]?](repeating: nil, count: count)

        // 阶段一：逐张提取特征向量
        for index in 0..<count {
            try Task.checkCancellation()
            if let cgImage = await photoService.loadAnalysisImage(for: photos[index].asset, maxDimension: 512),
               let vector = try? analysisService.extractFeatureVector(from: cgImage) {
                vectors[index] = vector
            }
            await progress(index + 1, count * 2)
        }

        // 阶段二：两两比较余弦相似度，超过阈值合并（并查集）
        var unionFind = UnionFind(count)
        for i in 0..<count {
            try Task.checkCancellation()
            guard let vectorI = vectors[i] else { continue }
            for j in (i + 1)..<count {
                guard let vectorJ = vectors[j] else { continue }
                if PhotoAnalysisService.cosineSimilarity(vectorI, vectorJ)
                    >= PhotoAnalysisService.similarityThreshold {
                    unionFind.union(i, j)
                }
            }
            await progress(count + i + 1, count * 2)
        }

        // 按并查集根聚合分组（只保留成功提取向量且 >= 2 张的组）
        var indicesByRoot: [Int: [Int]] = [:]
        for index in 0..<count where vectors[index] != nil {
            indicesByRoot[unionFind.find(index), default: []].append(index)
        }

        return indicesByRoot.values
            .filter { $0.count >= 2 }
            .map { DuplicateGroup(photos: $0.map { photos[$0] }) }
            .sorted { $0.photos.count > $1.photos.count }
    }
}
