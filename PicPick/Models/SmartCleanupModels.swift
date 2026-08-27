//
//  SmartCleanupModels.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation

/// 模糊照片 - 由 Laplacian 方差算法检出，供用户手动确认删除
struct BlurredPhoto: Identifiable {
    let photo: PhotoItem
    /// Laplacian 方差值（越小越模糊，低于阈值即视为模糊照片）
    let variance: Double

    var id: String { photo.id }

    /// 模糊程度百分比（0-100，越高越模糊）
    var blurPercent: Int {
        let threshold = PhotoAnalysisService.blurVarianceThreshold
        guard variance < threshold else { return 0 }
        return Int((1 - variance / threshold) * 100)
    }
}
