//
//  PhotoService.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import Foundation
import Photos
import Combine
import SwiftUI

/// 相册服务 - 处理所有 PhotoKit 相关操作
class PhotoService: ObservableObject {

    @Published var authorizationStatus: PhotoAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()

    // MARK: - 权限管理

    /// 请求相册访问权限
    func requestAuthorization() async -> PhotoAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let mappedStatus = mapAuthorizationStatus(status)

        await MainActor.run {
            self.authorizationStatus = mappedStatus
        }

        return mappedStatus
    }

    /// 检查当前权限状态
    func checkAuthorizationStatus() -> PhotoAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let mappedStatus = mapAuthorizationStatus(status)

        DispatchQueue.main.async {
            self.authorizationStatus = mappedStatus
        }

        return mappedStatus
    }

    private func mapAuthorizationStatus(_ status: PHAuthorizationStatus) -> PhotoAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        @unknown default:
            return .denied
        }
    }

    // MARK: - 照片获取

    /// 获取指定日期范围内的照片（支持媒体类型筛选）
    func fetchPhotos(from startDate: Date, to endDate: Date, mediaType: MediaType = .allPhotos) -> [PhotoItem] {
        let fetchOptions = PHFetchOptions()

        // 设置日期范围筛选
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!

        var predicates: [NSPredicate] = [
            NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                startOfDay as NSDate,
                endOfDay as NSDate
            )
        ]

        // 添加媒体类型筛选
        predicates.append(contentsOf: getMediaTypePredicates(for: mediaType))

        fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        // 按创建日期排序
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = fetchAssetsByMediaType(mediaType: mediaType, options: fetchOptions)

        var photos: [PhotoItem] = []
        assets.enumerateObjects { asset, _, _ in
            photos.append(PhotoItem(asset: asset))
        }

        return photos
    }

    /// 获取所有照片（无日期限制，支持媒体类型筛选）
    func fetchAllPhotos(mediaType: MediaType = .allPhotos) -> [PhotoItem] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        // 添加媒体类型筛选
        let predicates = getMediaTypePredicates(for: mediaType)
        if !predicates.isEmpty {
            fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let assets = fetchAssetsByMediaType(mediaType: mediaType, options: fetchOptions)

        var photos: [PhotoItem] = []
        assets.enumerateObjects { asset, _, _ in
            photos.append(PhotoItem(asset: asset))
        }

        return photos
    }

    // MARK: - 媒体类型筛选辅助方法

    /// 根据媒体类型获取对应的 Predicate
    private func getMediaTypePredicates(for mediaType: MediaType) -> [NSPredicate] {
        var predicates: [NSPredicate] = []

        switch mediaType {
        case .allPhotos:
            // 所有照片，不添加额外筛选
            break

        case .videosOnly:
            // 仅视频（mediaType == 2）
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))

        case .screenshots:
            // 截图：mediaSubtype 包含 screenshot 标记
            predicates.append(NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue))

        case .livePhotos:
            // Live Photos
            predicates.append(NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue))

        case .screenRecordings:
            // 屏幕录制：视频 + 特定标记
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
            // 屏幕录制通常会有特定的 metadata，这里使用视频类型作为基础筛选
            break
        }

        return predicates
    }

    /// 根据媒体类型获取 PHAsset
    private func fetchAssetsByMediaType(mediaType: MediaType, options: PHFetchOptions) -> PHFetchResult<PHAsset> {
        switch mediaType {
        case .videosOnly, .screenRecordings:
            // 视频类型
            return PHAsset.fetchAssets(with: .video, options: options)
        default:
            // 图片类型
            return PHAsset.fetchAssets(with: .image, options: options)
        }
    }

    // MARK: - 图片加载

    /// 加载照片缩略图（优化内存使用）
    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// 预加载图片（用于缓存）
    func preloadImages(for assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    /// 停止缓存图片
    func stopCachingImages(for assets: [PHAsset], targetSize: CGSize) {
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    // MARK: - 照片删除

    /// 批量删除照片
    func deletePhotos(_ assets: [PHAsset]) async -> DeletionResult {
        guard !assets.isEmpty else {
            return DeletionResult(success: 0, failed: 0, errors: [])
        }

        return await withCheckedContinuation { continuation in
            var errors: [Error] = []

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }) { success, error in
                if success {
                    continuation.resume(returning: DeletionResult(
                        success: assets.count,
                        failed: 0,
                        errors: []
                    ))
                } else {
                    if let error = error {
                        errors.append(error)
                    }
                    continuation.resume(returning: DeletionResult(
                        success: 0,
                        failed: assets.count,
                        errors: errors
                    ))
                }
            }
        }
    }

    // MARK: - 工具方法

    /// 计算照片预计占用空间
    func estimateSize(for assets: [PHAsset]) -> Int64 {
        let resources = assets.flatMap { asset in
            PHAssetResource.assetResources(for: asset)
        }

        let totalSize = resources.reduce(Int64(0)) { sum, resource in
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                return sum + size
            }
            return sum
        }

        return totalSize
    }

    /// 格式化文件大小
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
