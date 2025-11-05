//
//  PhotoItem.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import Foundation
import Photos
import SwiftUI

/// 照片项目模型 - 封装 PHAsset 和相关属性
struct PhotoItem: Identifiable, Equatable {
    let id: String
    let asset: PHAsset
    let creationDate: Date?
    var swipeStatus: SwipeStatus = .none

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate
    }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// 滑动状态枚举
enum SwipeStatus {
    case none       // 未处理
    case keep       // 保留（右滑）
    case delete     // 删除（左滑）
}

/// 相册权限状态
enum PhotoAuthorizationStatus {
    case notDetermined  // 未请求
    case restricted     // 受限制
    case denied         // 已拒绝
    case authorized     // 已授权
    case limited        // 有限访问（iOS 14+）
}

/// 删除结果
struct DeletionResult {
    let success: Int        // 成功删除数量
    let failed: Int         // 失败数量
    let errors: [Error]     // 错误列表
}

/// 媒体类型筛选
enum MediaType: String, CaseIterable, Identifiable {
    case allPhotos = "所有照片"
    case videosOnly = "仅视频"
    case screenshots = "仅截图"
    case livePhotos = "仅 Live Photos"
    case screenRecordings = "仅屏幕录制"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .allPhotos: return "photo.on.rectangle.angled"
        case .videosOnly: return "video.fill"
        case .screenshots: return "camera.viewfinder"
        case .livePhotos: return "livephoto"
        case .screenRecordings: return "record.circle"
        }
    }

    var emoji: String {
        switch self {
        case .allPhotos: return "📷"
        case .videosOnly: return "🎥"
        case .screenshots: return "📸"
        case .livePhotos: return "🎞️"
        case .screenRecordings: return "📱"
        }
    }
}
