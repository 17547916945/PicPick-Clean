//
//  BlindBoxViewModel.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation
import SwiftUI
import Combine

/// 照片盲盒视图模型 - 随机抽取一个有照片的月份，从随机日期开始整理，让清理变得有趣
/// （参考减法相册 4.0.3「照片盲盒」功能）
@MainActor
final class BlindBoxViewModel: ObservableObject {

    // MARK: - 抽中结果

    struct PickedMonth: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let start: Date
        let end: Date
        let count: Int
    }

    // MARK: - Published Properties

    @Published var isDrawing = false
    @Published var pickedMonth: PickedMonth?
    @Published var errorMessage: String?

    private let photoService = PhotoService()

    // MARK: - Drawing

    /// 开启盲盒：随机抽取一个有照片的月份
    func draw() async {
        isDrawing = true
        pickedMonth = nil
        errorMessage = nil

        // 制造开盒悬念动画的时长
        try? await Task.sleep(nanoseconds: 800_000_000)

        let photos = photoService.fetchAllPhotos()
        guard !photos.isEmpty else {
            errorMessage = "相册中没有照片，无法开启盲盒"
            isDrawing = false
            return
        }

        // 按月份分组
        let calendar = Calendar.current
        var groups: [DateComponents: [PhotoItem]] = [:]
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            groups[components, default: []].append(photo)
        }

        guard let entry = groups.randomElement() else {
            errorMessage = "没有可用的照片月份"
            isDrawing = false
            return
        }

        let components = entry.key
        let year = components.year ?? 0
        let month = components.month ?? 0

        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let end: Date
        if let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: start),
           let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonthStart) {
            // 当月只到今天
            end = min(monthEnd, Date())
        } else {
            end = Date()
        }

        pickedMonth = PickedMonth(
            title: "\(year)年\(month)月",
            start: start,
            end: end,
            count: entry.value.count
        )
        isDrawing = false
    }
}
