//
//  PhotoCardView.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import SwiftUI
import Photos

/// 照片卡片视图 - 类似 Tinder 的滑动卡片
struct PhotoCardView: View {

    let photo: PhotoItem
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    @State private var offset: CGSize = .zero
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var fileSize: String = ""

    // 滑动阈值（超过此距离触发操作）
    private let swipeThreshold: CGFloat = 100

    // PhotoService 实例用于获取文件大小
    private let photoService = PhotoService()

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

            // 照片
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width - 32, height: size.height - 32)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // 滑动指示器覆盖层
            swipeIndicatorOverlay

            // 日期标签
            if let date = photo.creationDate {
                dateLabel(date: date)
            }
        }
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                }
                .onEnded { gesture in
                    handleSwipeEnd(translation: gesture.translation)
                }
        )
    }

    /// 滑动指示器覆盖层
    private var swipeIndicatorOverlay: some View {
        ZStack {
            // 左滑删除指示器（红色）
            if offset.width < -50 {
                deleteIndicator
                    .opacity(Double(min(abs(offset.width) / swipeThreshold, 1.0)))
            }

            // 右滑保留指示器（绿色）
            if offset.width > 50 {
                keepIndicator
                    .opacity(Double(min(offset.width / swipeThreshold, 1.0)))
            }
        }
    }

    /// 删除指示器
    private var deleteIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.red.opacity(0.3))

            VStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text("删除")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
        }
    }

    /// 保留指示器
    private var keepIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.green.opacity(0.3))

            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("保留")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
    }

    /// 日期标签
    private func dateLabel(date: Date) -> some View {
        VStack {
            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(date))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    // 时间 + 文件大小
                    HStack(spacing: 4) {
                        Text(formatTime(date))
                            .foregroundColor(.white.opacity(0.8))

                        if !fileSize.isEmpty {
                            Text("·")
                                .foregroundColor(.white.opacity(0.5))

                            Text(fileSize)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.6))
                )

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Actions

    /// 处理滑动结束
    private func handleSwipeEnd(translation: CGSize) {
        if translation.width < -swipeThreshold {
            // 左滑超过阈值 - 删除
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = CGSize(width: -500, height: 0)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSwipeLeft()
                offset = .zero
            }

        } else if translation.width > swipeThreshold {
            // 右滑超过阈值 - 保留
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = CGSize(width: 500, height: 0)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSwipeRight()
                offset = .zero
            }

        } else {
            // 未超过阈值 - 回弹
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offset = .zero
            }
        }
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
            onSwipeLeft: {},
            onSwipeRight: {}
        )
        .padding()
    }
}
