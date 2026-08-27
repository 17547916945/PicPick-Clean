//
//  SmartCleanupView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI

/// 截图与模糊照片归类视图
/// 截图（mediaSubtypes 识别）与模糊照片（Laplacian 方差）由用户手动确认删除
struct SmartCleanupView: View {

    @StateObject private var viewModel = SmartCleanupViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            content

            if !viewModel.isScanning {
                bottomDeleteBar
            }
        }
        .navigationTitle("截图与模糊")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.isScanning {
                    Button(viewModel.isAllSelected ? "取消全选" : "全选") {
                        if viewModel.isAllSelected {
                            viewModel.clearSelection()
                        } else {
                            viewModel.selectAll()
                        }
                    }
                    .disabled(viewModel.currentSectionTotal == 0)
                }
            }
        }
        .confirmationDialog(
            "移入待删除列表？",
            isPresented: $viewModel.confirmDelete,
            titleVisibility: .visible
        ) {
            Button("移入待删除列表", role: .destructive) {
                viewModel.deleteSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将 \(viewModel.selectedCount) 张照片移入待删除列表，照片仍保留在相册中，可随时恢复或永久删除。")
        }
        .sheet(isPresented: $viewModel.showPaywall) {
            PaywallView()
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .onChange(of: viewModel.section) { _ in
            viewModel.clearSelection()
        }
        .task {
            viewModel.loadScreenshots()
        }
    }

    // MARK: - Subviews

    private var sectionPicker: some View {
        Picker("分类", selection: $viewModel.section) {
            ForEach(SmartCleanupViewModel.Section.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.section {
        case .screenshots:
            if viewModel.screenshots.isEmpty {
                emptyState(icon: "camera.viewfinder", text: "没有截图")
            } else {
                grid(photos: viewModel.screenshots, badges: [:])
            }

        case .blurred:
            if viewModel.isScanning {
                blurScanningView
            } else if !viewModel.hasScannedBlur {
                blurIntroView
            } else if viewModel.blurredPhotos.isEmpty {
                emptyState(icon: "eye", text: "未发现模糊照片")
            } else {
                let badges = Dictionary(
                    uniqueKeysWithValues: viewModel.blurredPhotos.map { ($0.id, "\($0.blurPercent)% 模糊") }
                )
                grid(photos: viewModel.blurredPhotos.map { $0.photo }, badges: badges)
            }
        }
    }

    private func grid(photos: [PhotoItem], badges: [String: String]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    cell(for: photo, badge: badges[photo.id])
                }
            }
            .padding(4)
        }
    }

    private func cell(for photo: PhotoItem, badge: String?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geometry in
                PhotoThumbnailView(asset: photo.asset, size: geometry.size.width)
            }
            .aspectRatio(1, contentMode: .fit)

            // 模糊度标签
            if let badge = badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
                    .padding(6)
            }

            // 选中角标
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: viewModel.selectedIDs.contains(photo.id)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(.title3)
                        .foregroundColor(viewModel.selectedIDs.contains(photo.id) ? .blue : .white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .padding(6)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggleSelection(id: photo.id)
        }
    }

    private var blurIntroView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("检测模糊照片")
                .font(.headline)

            Text("使用 Laplacian 方差算法在本地分析当月照片，自动找出模糊不清的照片，由你确认后删除")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                viewModel.startBlurScan()
            } label: {
                Label("开始扫描", systemImage: "magnifyingglass")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var blurScanningView: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.blurProgress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)

            Text("正在分析 \(viewModel.blurScannedCount) / \(viewModel.blurTotalCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("模糊度检测全程本地运行，不上传任何数据")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("取消") {
                viewModel.cancelBlurScan()
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text(text)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomDeleteBar: some View {
        HStack {
            Text("已选 \(viewModel.selectedCount) 张 · \(viewModel.selectedSizeText)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button {
                viewModel.requestDeleteSelected()
            } label: {
                Label("删除", systemImage: "trash.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(viewModel.selectedCount > 0 ? Color.red : Color.gray)
                    )
            }
            .disabled(viewModel.selectedCount == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
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
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Preview

struct SmartCleanupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SmartCleanupView()
        }
    }
}
