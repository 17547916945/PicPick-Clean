//
//  PendingDeleteItem.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation

/// App 内「待删除列表」条目 - 照片在被永久删除前的安全暂存
/// 此时照片仍保留在系统相册中，可随时恢复；永久删除后由系统「最近删除」兜底 30 天
struct PendingDeleteItem: Identifiable, Codable, Equatable {
    /// PHAsset localIdentifier
    let id: String
    /// 加入待删除列表的时间
    let dateAdded: Date
    /// 照片文件大小（用于统计可释放空间）
    let sizeBytes: Int64
}
