//
//  PhotoManagementViewModel.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import Foundation
import SwiftUI
import Combine
import Photos

/// 照片管理主视图模型
@MainActor
class PhotoManagementViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var photos: [PhotoItem] = []
    @Published var currentPhotoIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // 日期筛选（默认 = 当月，减法相册按月份整理）
    @Published var startDate: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @Published var endDate: Date = Date()
    @Published var isDateFilterEnabled: Bool = true

    // 媒体类型筛选
    @Published var selectedMediaType: MediaType = .allPhotos

    // 删除确认
    @Published var showDeleteConfirmation: Bool = false

    // 权限状态
    @Published var authorizationStatus: PhotoAuthorizationStatus = .notDetermined

    // 添加到相册（下拉手势）
    @Published var showAlbumPicker: Bool = false

    // 轻提示（2 秒自动消失）
    @Published var toastMessage: String?

    // 累计释放空间（跨启动持久化）
    @Published private(set) var cumulativeFreedBytes: Int64 = 0

    // 本次会话标记待删除的照片大小（缓存值，避免每次渲染重新计算）
    @Published private(set) var sessionMarkedBytes: Int64 = 0

    // App 内待删除列表数量（角标显示）
    @Published private(set) var pendingDeleteCount: Int = 0

    // 付费墙与每日免费额度
    @Published var showPaywall = false
    @Published private(set) var isProUnlocked = false
    @Published private(set) var quotaRemainingToday = AppConfig.freeDailyCleanLimit

    // MARK: - Services

    private let photoService = PhotoService()
    private let storageStatsStore = StorageStatsStore.shared
    private let pendingDeleteStore = PendingDeleteStore.shared
    private let progressStore = CleaningProgressStore.shared
    private let quotaService = DailyQuotaService.shared
    private let paywallService = PaywallService.shared
    private var toastTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 会话属性

    /// 是否为盲盒会话（盲盒会话不读写断点快照）
    private let isBlindBoxSession: Bool

    // MARK: - Computed Properties

    /// 当前显示的照片
    var currentPhoto: PhotoItem? {
        guard currentPhotoIndex < photos.count else { return nil }
        return photos[currentPhotoIndex]
    }

    /// 已处理的照片数量
    var processedCount: Int {
        currentPhotoIndex
    }

    /// 总照片数量
    var totalCount: Int {
        photos.count
    }

    /// 标记为删除的照片
    var photosToDelete: [PhotoItem] {
        photos.filter { $0.swipeStatus == .delete }
    }

    /// 标记为删除的照片数量
    var deleteCount: Int {
        photosToDelete.count
    }

    /// 是否还有照片需要处理
    var hasMorePhotos: Bool {
        currentPhotoIndex < photos.count
    }

    /// 进度百分比
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }

    /// 队列标题（顶部进度条）：当月 → "2026年8月"；自定义范围 → "7月27日 - 8月27日"；全部 → "全部照片"
    /// 盲盒会话加 🎁 前缀
    var queueTitle: String {
        let base: String
        if !isDateFilterEnabled {
            base = "全部照片"
        } else {
            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.year, .month], from: startDate)
            let endComponents = calendar.dateComponents([.year, .month], from: endDate)
            if startComponents.year == endComponents.year,
               startComponents.month == endComponents.month,
               let year = startComponents.year, let month = startComponents.month {
                base = "\(year)年\(month)月"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "M月d日"
                base = "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
            }
        }
        return isBlindBoxSession ? "🎁 \(base)" : base
    }

    /// 累计释放空间（格式化，如 "1.2 GB"）
    var cumulativeFreedFormatted: String {
        storageStatsStore.formattedBytes(cumulativeFreedBytes)
    }

    /// 本次会话标记可释放空间（格式化）
    var sessionMarkedFormatted: String {
        photoService.formatFileSize(sessionMarkedBytes)
    }

    // MARK: - Initialization

    /// - Parameters:
    ///   - startDate: 指定队列开始日期（盲盒等场景），nil 表示默认当月
    ///   - endDate: 指定队列结束日期
    ///   - isBlindBox: 是否为盲盒会话（不读写断点快照）
    init(startDate: Date? = nil, endDate: Date? = nil, isBlindBox: Bool = false) {
        isBlindBoxSession = isBlindBox

        if let startDate = startDate, let endDate = endDate {
            self.startDate = startDate
            self.endDate = endDate
            isDateFilterEnabled = true
        }

        cumulativeFreedBytes = storageStatsStore.cumulativeFreedBytes
        pendingDeleteCount = pendingDeleteStore.items.count

        pendingDeleteStore.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.pendingDeleteCount = items.count
            }
            .store(in: &cancellables)

        isProUnlocked = paywallService.isProUnlocked
        quotaService.refresh()
        quotaRemainingToday = quotaService.remainingToday

        paywallService.$isProUnlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unlocked in
                self?.isProUnlocked = unlocked
            }
            .store(in: &cancellables)

        quotaService.$usedToday
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.quotaRemainingToday = DailyQuotaService.shared.remainingToday
            }
            .store(in: &cancellables)

        checkAuthorization()
    }

    // MARK: - Authorization

    /// 检查权限状态
    func checkAuthorization() {
        authorizationStatus = photoService.checkAuthorizationStatus()
    }

    /// 请求相册权限
    func requestAuthorization() async {
        authorizationStatus = await photoService.requestAuthorization()

        if authorizationStatus == .authorized || authorizationStatus == .limited {
            await loadPhotos()
        }
    }

    // MARK: - Photo Loading

    /// 加载照片（自动应用断点快照：下次打开从上次中断的位置继续）
    func loadPhotos() async {
        isLoading = true
        errorMessage = nil

        do {
            let loadedPhotos: [PhotoItem]

            if isDateFilterEnabled {
                loadedPhotos = photoService.fetchPhotos(from: startDate, to: endDate, mediaType: selectedMediaType)
            } else {
                loadedPhotos = photoService.fetchAllPhotos(mediaType: selectedMediaType)
            }

            photos = loadedPhotos

            // 断点恢复：范围一致时恢复状态与序号
            applySnapshotIfMatches()

            updateSessionMarkedBytes()
            saveProgress()

            // 预加载前几张图片
            preloadNextImages()

        } catch {
            errorMessage = "加载照片失败: \(error.localizedDescription)"
            showError = true
        }

        isLoading = false
    }

    /// 刷新照片列表（保留断点进度）
    func refreshPhotos() async {
        await loadPhotos()
    }

    /// 重新开始：清除断点快照，从第一张重新清理
    func restartFromBeginning() async {
        progressStore.clear()
        for index in 0..<photos.count {
            photos[index].swipeStatus = .none
        }
        currentPhotoIndex = 0
        sessionMarkedBytes = 0
        await loadPhotos()
    }

    /// 预加载接下来的几张图片（优化性能）
    private func preloadNextImages(count: Int = 3) {
        let endIndex = min(currentPhotoIndex + count, photos.count)
        guard currentPhotoIndex < endIndex else { return }

        let assetsToPreload = photos[currentPhotoIndex..<endIndex].map { $0.asset }
        let targetSize = CGSize(width: 1000, height: 1000)

        photoService.preloadImages(for: assetsToPreload, targetSize: targetSize)
    }

    // MARK: - Swipe Actions

    /// 左滑 - 标记为删除
    func swipeLeft() {
        guard currentPhotoIndex < photos.count else { return }
        photos[currentPhotoIndex].swipeStatus = .delete
        updateSessionMarkedBytes()
        storageStatsStore.recordPhotoProcessed()
        moveToNextPhoto()
    }

    /// 右滑 - 标记为保留
    func swipeRight() {
        guard currentPhotoIndex < photos.count else { return }
        photos[currentPhotoIndex].swipeStatus = .keep
        storageStatsStore.recordPhotoProcessed()
        moveToNextPhoto()
    }

    /// 下拉 - 打开相册选择（添加到相册）
    func swipeDown() {
        guard currentPhotoIndex < photos.count else { return }
        showAlbumPicker = true
    }

    /// 移动到下一张照片
    private func moveToNextPhoto() {
        currentPhotoIndex += 1
        saveProgress()

        // 预加载下一批图片
        if currentPhotoIndex % 3 == 0 {
            preloadNextImages()
        }
    }

    /// 撤销上一个操作
    func undoLastSwipe() {
        guard currentPhotoIndex > 0 else { return }
        currentPhotoIndex -= 1
        photos[currentPhotoIndex].swipeStatus = .none
        storageStatsStore.unrecordPhotoProcessed()
        updateSessionMarkedBytes()
        saveProgress()
    }

    // MARK: - 添加到相册

    /// 将当前照片添加到指定相册（成功后标记保留并进入下一张）
    func addCurrentPhoto(to album: PhotoAlbum) async {
        showAlbumPicker = false
        guard currentPhotoIndex < photos.count else { return }

        let success = await photoService.add(photos[currentPhotoIndex].asset, to: album)

        if success {
            photos[currentPhotoIndex].swipeStatus = .keep
            moveToNextPhoto()
            showToast("已添加到「\(album.title)」")
        } else {
            showToast("添加失败，请重试")
        }
    }

    /// 新建相册并添加当前照片
    func createAlbumAndAddCurrentPhoto(named title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("相册名称不能为空")
            return
        }

        guard let album = await photoService.createAlbum(named: trimmed) else {
            showToast("创建相册失败")
            return
        }

        await addCurrentPhoto(to: album)
    }

    // MARK: - Date Filter

    /// 应用日期筛选
    func applyDateFilter() async {
        isDateFilterEnabled = true
        await loadPhotos()
    }

    /// 清除日期筛选
    func clearDateFilter() async {
        isDateFilterEnabled = false
        await loadPhotos()
    }

    // MARK: - Deletion（双重安全删除：先入 App 内待删除列表）

    /// 显示删除确认弹窗
    func showDeleteConfirmationDialog() {
        guard deleteCount > 0 else {
            errorMessage = "没有标记为删除的照片"
            showError = true
            return
        }
        showDeleteConfirmation = true
    }

    /// 执行清理：将标记删除的照片移入 App 内「待删除列表」
    /// 照片仍保留在系统相册中，可随时恢复；永久删除在待删除列表中执行
    func executeDelete() async {
        guard deleteCount > 0 else { return }

        showDeleteConfirmation = false

        let marked = photosToDelete
        let items = marked.map { photo in
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

        // 队列中清除这些照片的删除标记（已越过序号，不会重复出现）
        let markedIDs = Set(marked.map { $0.id })
        for index in photos.indices where markedIDs.contains(photos[index].id) {
            photos[index].swipeStatus = .none
        }

        sessionMarkedBytes = 0
        saveProgress()

        showToast("已移入待删除列表（\(items.count) 张），可随时恢复或永久删除")
    }

    /// 获取待删除照片的预计大小
    func getEstimatedDeletionSize() -> String {
        let assets = photosToDelete.map { $0.asset }
        let bytes = photoService.estimateSize(for: assets)
        return photoService.formatFileSize(bytes)
    }

    // MARK: - Image Loading

    /// 加载指定照片的图片
    func loadImage(for photo: PhotoItem, targetSize: CGSize) async -> UIImage? {
        await photoService.loadImage(for: photo.asset, targetSize: targetSize)
    }

    // MARK: - Reset

    /// 重置所有标记
    func resetAllMarks() {
        for index in 0..<photos.count {
            photos[index].swipeStatus = .none
        }
        currentPhotoIndex = 0
        sessionMarkedBytes = 0
        saveProgress()
    }

    // MARK: - Toast

    /// 显示轻提示（2 秒后自动消失）
    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    // MARK: - 断点继续

    /// 快照范围与当前队列一致时，恢复每张照片的状态与处理序号
    private func applySnapshotIfMatches() {
        guard !isBlindBoxSession,
              let snapshot = progressStore.load(),
              snapshot.isDateFilterEnabled == isDateFilterEnabled,
              snapshot.mediaType == selectedMediaType.rawValue,
              abs(snapshot.startDate.timeIntervalSince(startDate)) < 60,
              abs(snapshot.endDate.timeIntervalSince(endDate)) < 60 else {
            currentPhotoIndex = 0
            return
        }

        for index in photos.indices {
            guard let raw = snapshot.statuses[photos[index].id],
                  let status = SwipeStatus(rawValue: raw) else { continue }
            photos[index].swipeStatus = status
        }
        currentPhotoIndex = min(max(snapshot.currentIndex, 0), photos.count)
    }

    /// 保存断点快照（盲盒会话不持久化）
    private func saveProgress() {
        guard !isBlindBoxSession else { return }

        var statuses: [String: String] = [:]
        for photo in photos {
            switch photo.swipeStatus {
            case .delete:
                statuses[photo.id] = SwipeStatus.delete.rawValue
            case .keep:
                statuses[photo.id] = SwipeStatus.keep.rawValue
            case .none:
                break
            }
        }

        progressStore.save(CleaningSnapshot(
            startDate: startDate,
            endDate: endDate,
            isDateFilterEnabled: isDateFilterEnabled,
            mediaType: selectedMediaType.rawValue,
            isBlindBox: false,
            currentIndex: currentPhotoIndex,
            statuses: statuses,
            updatedAt: Date()
        ))
    }

    // MARK: - Private Helpers

    /// 重新计算本次会话标记待删除的照片大小（缓存，供顶部进度条实时展示）
    private func updateSessionMarkedBytes() {
        let assets = photosToDelete.map { $0.asset }
        sessionMarkedBytes = photoService.estimateSize(for: assets)
    }
}
