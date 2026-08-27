//
//  DuplicateGroup.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation

/// 相似照片分组 - 余弦相似度 >= 0.85 的照片归为一组
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]

    /// 组内最佳照片：像素最高（分辨率优先，相同则保留先出现者）
    var bestPhoto: PhotoItem? {
        photos.max { lhs, rhs in
            let lhsPixels = lhs.asset.pixelWidth * lhs.asset.pixelHeight
            let rhsPixels = rhs.asset.pixelWidth * rhs.asset.pixelHeight
            return lhsPixels < rhsPixels
        }
    }

    /// 除最佳外的其余照片（「保留最佳，删除其余」的待删除列表）
    var redundantPhotos: [PhotoItem] {
        guard let best = bestPhoto else { return [] }
        return photos.filter { $0.id != best.id }
    }
}

/// 并查集 - 用于相似照片聚类（相似对两两合并）
struct UnionFind {
    private var parent: [Int]

    init(_ count: Int) {
        parent = Array(0..<count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root {
            root = parent[root]
        }
        // 路径压缩
        var current = x
        while parent[current] != current {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        parent[rootA] = rootB
    }
}
