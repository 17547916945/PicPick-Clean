//
//  PhotoAlbum.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import Photos

/// 用户相册模型 - 封装 PHAssetCollection，用于「下拉添加到相册」功能
struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let collection: PHAssetCollection
    /// 相册内大致照片数量（estimatedAssetCount 无需遍历即可获得）
    let estimatedCount: Int

    init(collection: PHAssetCollection, estimatedCount: Int = 0) {
        self.id = collection.localIdentifier
        self.title = collection.localizedTitle ?? "未命名相册"
        self.collection = collection
        self.estimatedCount = estimatedCount
    }
}
