//
//  HomeViewModel.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import SwiftUI
import Combine

/// 首页视图模型 - 清理进度环与统计卡片数据
@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var monthTotal = 0
    @Published private(set) var monthProcessed = 0
    @Published private(set) var cumulativeFreedBytes: Int64 = 0
    @Published private(set) var pendingDeleteCount = 0

    private let photoService = PhotoService()
    private let statsStore = StorageStatsStore.shared
    private let pendingDeleteStore = PendingDeleteStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        pendingDeleteCount = pendingDeleteStore.items.count
        pendingDeleteStore.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.pendingDeleteCount = items.count
            }
            .store(in: &cancellables)
    }

    /// 本月清理进度（0-1，用于进度环）
    var monthProgress: Double {
        guard monthTotal > 0 else { return 0 }
        return min(Double(monthProcessed) / Double(monthTotal), 1)
    }

    /// 累计释放（完整格式，如 "1.2 GB"）
    var freedFormatted: String {
        statsStore.formattedBytes(cumulativeFreedBytes)
    }

    /// 累计释放（紧凑格式，用于统计卡片）
    var freedCompact: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: cumulativeFreedBytes)
    }

    /// 刷新首页数据（每次出现时调用）
    func refresh() async {
        cumulativeFreedBytes = statsStore.cumulativeFreedBytes
        monthProcessed = statsStore.processedCount(inMonthContaining: Date())

        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let photos = photoService.fetchPhotos(from: startOfMonth, to: Date())
        monthTotal = photos.count
    }
}
