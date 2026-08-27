//
//  DuplicateDetectionView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI
import Photos

/// 重复/相似照片检测视图
/// 每组可一键「保留最佳，删除其余」，全程本地分析
struct DuplicateDetectionView: View {

    @StateObject private var viewModel = DuplicateDetectionViewModel()

    var body: some View {
        VStack(spacing: 0) {
            scopeBar

            if viewModel.isScanning {
                scanningView
            } else {
                groupsContent
            }
        }
        .navigationTitle("重复照片")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "保留最佳，删除其余？",
            isPresented: $viewModel.confirmKeepBest,
            titleVisibility: .visible
        ) {
            Button("移入待删除列表", role: .destructive) {
                viewModel.keepBest()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(viewModel.pendingSummary)
        }
        .sheet(isPresented: $viewModel.showPaywall) {
            PaywallView()
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .onChange(of: viewModel.scanScope) { _ in
            viewModel.startScan()
        }
        .task {
            viewModel.startScan()
        }
    }

    // MARK: - Subviews

    private var scopeBar: some View {
        HStack(spacing: 12) {
            Picker("范围", selection: $viewModel.scanScope) {
                ForEach(DuplicateDetectionViewModel.ScanScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isScanning)

            Button {
                viewModel.startScan()
            } label: {
                Label("重扫", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
            }
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)

            Text("正在本地分析 \(min(viewModel.scannedCount, viewModel.totalCount)) / \(viewModel.totalCount) 张照片")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("特征提取 + 余弦相似度比对，不上传任何数据")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("取消") {
                viewModel.cancelScan()
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var groupsContent: some View {
        if viewModel.groups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)

                Text("未发现重复照片")
                    .font(.headline)

                Text("余弦相似度阈值 0.85，全程本地分析")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(viewModel.groups) { group in
                        groupRow(group)
                    }
                } header: {
                    Text("发现 \(viewModel.groups.count) 组相似照片")
                } footer: {
                    Text("每组「保留最佳」将保留像素最高的一张，其余移入待删除列表，可随时恢复")
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func groupRow(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 组内缩略图
            HStack(spacing: 8) {
                ForEach(Array(group.photos.prefix(4))) { photo in
                    PhotoThumbnailView(asset: photo.asset, size: 72)
                }
                if group.photos.count > 4 {
                    Text("+\(group.photos.count - 4)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }

            // 信息 + 操作
            HStack {
                Text("\(group.photos.count) 张相似")
                    .font(.subheadline)

                Text("·")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("可释放 \(viewModel.groupFreedSizeFormatted(group))")
                    .font(.subheadline)
                    .foregroundColor(.orange)

                Spacer()

                Button {
                    viewModel.requestKeepBest(in: group)
                } label: {
                    Text("保留最佳")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.red))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = viewModel.toastMessage {
            Text(toast)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(Color.black.opacity(0.85))
                )
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - 照片缩略图（本地 PHImageManager 加载）

/// 通用照片缩略图视图，供重复检测与截图/模糊列表复用
struct PhotoThumbnailView: View {
    let asset: PHAsset
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView())
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: asset.localIdentifier) {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true

            let targetSize = CGSize(width: size * 2, height: size * 2)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - Preview

struct DuplicateDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DuplicateDetectionView()
        }
    }
}
