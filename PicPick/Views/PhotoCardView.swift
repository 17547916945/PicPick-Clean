//
//  PhotoCardView.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import SwiftUI
import Photos
import UIKit

/// 卡片拖动轴向（水平滑动与垂直下拉互斥，避免斜滑误判）
private enum DragAxis {
    case horizontal
    case vertical
}

/// 照片卡片视图 - 减法相册式滑动卡片
/// 左滑 = 标记删除（红色 "DELETE ✕" 印章）/ 右滑 = 标记保留（绿色 "KEEP ✓" 印章）/ 下拉 = 添加到相册
struct PhotoCardView: View {

    let photo: PhotoItem
    /// 当前序号（从 1 开始，如 "12 / 345" 中的 12）
    let index: Int
    /// 队列总数
    let total: Int
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let onSwipeDown: () -> Void

    @State private var offset: CGSize = .zero
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var fileSize: String = ""

    /// 拖动轴向锁定
    @State private var dragAxis: DragAxis?
    /// 阈值震动是否已触发（每次拖动各方向只触发一次）
    @State private var impactedLeft = false
    @State private var impactedRight = false
    @State private var impactedDown = false

    // 滑动阈值（超过此距离触发操作）
    private let swipeThreshold: CGFloat = 100

    // PhotoService 实例用于获取文件大小
    private let photoService = PhotoService()

    // 触感反馈生成器
    @State private var impactMedium = UIImpactFeedbackGenerator(style: .medium)
    @State private var notificationFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isLoading {
                    loadingView
                } else if let image = image {
                    photoCardContent(image: image, size: geometry.size)
                } else {
                    errorView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.2))

            ProgressView()
                .scaleEffect(1.5)
        }
    }

    private var errorView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.2))

            VStack(spacing: 12) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)

                Text("无法加载图片")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
        }
    }

    private func photoCardContent(image: UIImage, size: CGSize) -> some View {
        ZStack {
            // 卡片背景
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

            // 照片铺满卡片
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // 滑动指示覆盖层（印章 + 下拉横幅）
            swipeOverlays

            // 底部信息栏（拍摄日期 + 序号）
            bottomInfoBar
        }
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(dragGesture(size: size))
    }

    /// 滑动指示覆盖层
    @ViewBuilder
    private var swipeOverlays: some View {
        ZStack {
            // 左滑 - 删除印章
            if offset.width < 0 {
                stampView(
                    text: "DELETE ✕",
                    color: .red,
                    rotation: -12,
                    progress: abs(offset.width) / swipeThreshold
                )
            }

            // 右滑 - 保留印章
            if offset.width > 0 {
                stampView(
                    text: "KEEP ✓",
                    color: .green,
                    rotation: 12,
                    progress: offset.width / swipeThreshold
                )
            }

            // 下拉 - 添加到相册横幅
            if offset.height < 0 {
                VStack {
                    downBanner(opacity: min(abs(offset.height) / swipeThreshold, 1))
                    Spacer()
                }
            }
        }
    }

    /// 印章视图（随拖动进度淡入 + 放大）
    private func stampView(text: String, color: Color, rotation: Double, progress: CGFloat) -> some View {
        let clamped = min(max(progress, 0), 1)
        return Text(text)
            .font(.system(size: 44, weight: .black, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            )
            .rotationEffect(.degrees(rotation))
            .scaleEffect(0.55 + 0.45 * clamped)
            .opacity(Double(clamped))
    }

    /// 下拉横幅
    private func downBanner(opacity: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
            Text("松手添加到相册")
        }
        .font(.headline)
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(Color.blue.opacity(0.9))
        )
        .padding(.top, 24)
        .opacity(Double(opacity))
    }

    /// 底部信息栏：左侧拍摄日期，右侧序号
    private var bottomInfoBar: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                dateChip
                Spacer()
                counterChip
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    /// 拍摄日期 chip（日期 + 时间 + 文件大小）
    @ViewBuilder
    private var dateChip: some View {
        if let date = photo.creationDate {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(date))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 4) {
                    Text(formatTime(date))

                    if !fileSize.isEmpty {
                        Text("·")
                            .opacity(0.6)
                        Text(fileSize)
                    }
                }
                .font(.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.6))
            )
        }
    }

    /// 序号 chip（如 "12 / 345"）
    private var counterChip: some View {
        Text("\(index) / \(total)")
            .font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.6))
            )
    }

    // MARK: - Gestures

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { gesture in
                let translation = gesture.translation
                lockAxisIfNeeded(translation)

                switch dragAxis {
                case .horizontal:
                    offset = CGSize(width: translation.width, height: 0)
                    handleHorizontalProgress(translation.width)
                case .vertical:
                    offset = CGSize(width: 0, height: translation.height)
                    handleVerticalProgress(translation.height)
                case nil:
                    offset = .zero
                }
            }
            .onEnded { gesture in
                handleSwipeEnd(translation: gesture.translation, size: size)
            }
    }

    /// 首次移动超过 20pt 时锁定拖动轴向
    private func lockAxisIfNeeded(_ translation: CGSize) {
        guard dragAxis == nil else { return }
        if abs(translation.width) > 20 || abs(translation.height) > 20 {
            dragAxis = abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical
        }
    }

    /// 水平拖动进度（跨阈值触发触感）
    private func handleHorizontalProgress(_ width: CGFloat) {
        if width < -swipeThreshold && !impactedLeft {
            impactedLeft = true
            impactMedium.impactOccurred()
        }
        if width > swipeThreshold && !impactedRight {
            impactedRight = true
            impactMedium.impactOccurred()
        }
    }

    /// 垂直拖动进度（跨阈值触发触感）
    private func handleVerticalProgress(_ height: CGFloat) {
        if height < -swipeThreshold && !impactedDown {
            impactedDown = true
            impactMedium.impactOccurred()
        }
    }

    /// 处理滑动结束
    private func handleSwipeEnd(translation: CGSize, size: CGSize) {
        defer { resetDragState() }

        switch dragAxis {
        case .horizontal:
            if translation.width < -swipeThreshold {
                // 左滑超过阈值 - 删除
                notificationFeedback.notificationOccurred(.warning)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    offset = CGSize(width: -size.width * 1.5, height: 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSwipeLeft()
                    offset = .zero
                }
            } else if translation.width > swipeThreshold {
                // 右滑超过阈值 - 保留
                notificationFeedback.notificationOccurred(.success)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    offset = CGSize(width: size.width * 1.5, height: 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSwipeRight()
                    offset = .zero
                }
            } else {
                // 未超过阈值 - 回弹
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    offset = .zero
                }
            }

        case .vertical:
            if translation.height < -swipeThreshold {
                // 下拉超过阈值 - 添加到相册
                impactMedium.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    offset = CGSize(width: 0, height: -size.height * 1.5)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onSwipeDown()
                    offset = .zero
                }
            } else {
                // 未超过阈值 - 回弹
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    offset = .zero
                }
            }

        case nil:
            // 未锁轴（点击类手势）- 回弹
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = .zero
            }
        }
    }

    /// 重置拖动状态（轴向 + 震动标记）
    private func resetDragState() {
        dragAxis = nil
        impactedLeft = false
        impactedRight = false
        impactedDown = false
    }

    // MARK: - Image Loading

    private func loadImage() async {
        isLoading = true

        // 加载图片
        let targetSize = CGSize(width: 1000, height: 1000)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let loadedImage = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: photo.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }

        // 获取文件大小
        let sizeInBytes = photoService.getFileSize(for: photo.asset)
        let formattedSize = photoService.formatFileSizeCompact(sizeInBytes)

        await MainActor.run {
            self.image = loadedImage
            self.fileSize = formattedSize
            self.isLoading = false
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Preview

struct PhotoCardView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoCardView(
            photo: PhotoItem(asset: PHAsset()),
            index: 12,
            total: 345,
            onSwipeLeft: {},
            onSwipeRight: {},
            onSwipeDown: {}
        )
        .padding()
    }
}
