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

    // MARK: - 智能分析支持

    /// 获取所有截图照片（PHAsset mediaSubtypes 直接识别）
    func fetchScreenshots() -> [PhotoItem] {
        fetchAllPhotos(mediaType: .screenshots)
    }

    /// 加载用于本地分析的图片（限制尺寸，节省内存，不上传任何数据）
    func loadAnalysisImage(for asset: PHAsset, maxDimension: CGFloat = 1024) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast

            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: maxDimension, height: maxDimension),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    /// 按 localIdentifier 批量获取 PHAsset（供待删除列表使用，照片可能已不存在）
    func fetchAssets(withLocalIdentifiers identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            .enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
        return assets
    }

    // MARK: - 相册管理

    /// 获取用户的普通相册（不含系统智能相册，用于「下拉添加到相册」）
    func fetchUserAlbums() -> [PhotoAlbum] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        )

        var albums: [PhotoAlbum] = []
        collections.enumerateObjects { collection, _, _ in
            albums.append(PhotoAlbum(
                collection: collection,
                estimatedCount: collection.estimatedAssetCount
            ))
        }
        return albums
    }

    /// 将照片添加到指定相册
    func add(_ asset: PHAsset, to album: PhotoAlbum) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                if let changeRequest = PHAssetCollectionChangeRequest(for: album.collection) {
                    changeRequest.addAssets([asset] as NSArray)
                }
            }) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// 新建相册并返回，失败返回 nil
    func createAlbum(named title: String) async -> PhotoAlbum? {
        await withCheckedContinuation { continuation in
            var localIdentifier: String?

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                localIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
            }) { success, _ in
                guard success, let identifier = localIdentifier else {
                    continuation.resume(returning: nil)
                    return
                }
                let collections = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [identifier],
                    options: nil
                )
                let album = collections.firstObject.map {
                    PhotoAlbum(collection: $0, estimatedCount: $0.estimatedAssetCount)
                }
                continuation.resume(returning: album)
            }
        }
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

    /// 获取单个照片的文件大小
    func getFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        let size = resources.reduce(Int64(0)) { sum, resource in
            if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                return sum + fileSize
            }
            return sum
        }
        return size
    }

    /// 格式化文件大小
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 格式化文件大小（简洁版，如 "6.2M"）
    func formatFileSizeCompact(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.isAdaptive = true

        // 获取格式化后的字符串，去掉空格
        let formattedString = formatter.string(fromByteCount: bytes)
        return formattedString.replacingOccurrences(of: " ", with: "")
    }
}
