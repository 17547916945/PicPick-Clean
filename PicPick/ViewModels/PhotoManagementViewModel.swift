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

    // 日期筛选
    @Published var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var endDate: Date = Date()
    @Published var isDateFilterEnabled: Bool = false

    // 媒体类型筛选
    @Published var selectedMediaType: MediaType = .allPhotos

    // 删除确认
    @Published var showDeleteConfirmation: Bool = false

    // 权限状态
    @Published var authorizationStatus: PhotoAuthorizationStatus = .notDetermined

    // MARK: - Services

    private let photoService = PhotoService()

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

    // MARK: - Initialization

    init() {
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

    /// 加载照片
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
            currentPhotoIndex = 0

            // 预加载前几张图片
            preloadNextImages()

        } catch {
            errorMessage = "加载照片失败: \(error.localizedDescription)"
            showError = true
        }

        isLoading = false
    }

    /// 刷新照片列表
    func refreshPhotos() async {
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
        moveToNextPhoto()
    }

    /// 右滑 - 标记为保留
    func swipeRight() {
        guard currentPhotoIndex < photos.count else { return }
        photos[currentPhotoIndex].swipeStatus = .keep
        moveToNextPhoto()
    }

    /// 移动到下一张照片
    private func moveToNextPhoto() {
        currentPhotoIndex += 1

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

    // MARK: - Deletion

    /// 显示删除确认弹窗
    func showDeleteConfirmationDialog() {
        guard deleteCount > 0 else {
            errorMessage = "没有标记为删除的照片"
            showError = true
            return
        }
        showDeleteConfirmation = true
    }

    /// 执行批量删除
    func executeDelete() async {
        guard deleteCount > 0 else { return }

        isLoading = true

        let assetsToDelete = photosToDelete.map { $0.asset }
        let result = await photoService.deletePhotos(assetsToDelete)

        isLoading = false
        showDeleteConfirmation = false

        if result.success > 0 {
            // 删除成功，重新加载照片
            await loadPhotos()

            // 显示成功消息
            errorMessage = "成功删除 \(result.success) 张照片"
            showError = true

        } else {
            // 删除失败
            let errorDetails = result.errors.map { $0.localizedDescription }.joined(separator: ", ")
            errorMessage = "删除失败: \(errorDetails)"
            showError = true
        }
    }

    /// 获取待删除照片的预计大小
    func getEstimatedDeletionSize() -> String {
        let assets = photosToDelete.map { $0.asset }
        let bytes = photoService.estimateSize(for: assets)
        return photoService.formatFileSize(bytes)
    }

    /// 获取当前已标记删除照片的内存大小（用于实时显示）
    var deletedPhotosSizeFormatted: String {
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
    }
}
