//
//  PhotoManagementView.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import SwiftUI

/// 照片管理主视图
struct PhotoManagementView: View {

    @StateObject private var viewModel = PhotoManagementViewModel()
    @State private var showFilter = false

    var body: some View {
        NavigationView {
            ZStack {
                // 背景渐变
                backgroundGradient

                VStack(spacing: 0) {
                    // 顶部进度和操作栏
                    topBar

                    // 主内容区域
                    mainContent

                    // 底部操作栏
                    bottomBar
                }
            }
            .navigationTitle("PicPick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showFilter) {
                FilterView(
                    startDate: $viewModel.startDate,
                    endDate: $viewModel.endDate,
                    isDateFilterEnabled: $viewModel.isDateFilterEnabled,
                    selectedMediaType: $viewModel.selectedMediaType,
                    onApply: {
                        await viewModel.loadPhotos()
                    }
                )
            }
            .alert("提示", isPresented: $viewModel.showError) {
                Button("确定", role: .cancel) {}
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .overlay {
                if viewModel.showDeleteConfirmation {
                    deleteConfirmationOverlay
                }
            }
            .task {
                await initializeApp()
            }
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.05),
                Color.purple.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            // 进度条
            progressBar

            // 进度信息
            progressInfo
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)

                // 进度
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * viewModel.progress, height: 8)
                    .animation(.spring(response: 0.3), value: viewModel.progress)
            }
        }
        .frame(height: 8)
    }

    private var progressInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .foregroundColor(.blue)
                .font(.subheadline)

            Text("已处理 \(viewModel.processedCount)/\(viewModel.totalCount) 张")
                .font(.subheadline)
                .fontWeight(.medium)

            if viewModel.deleteCount > 0 {
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("删除 \(viewModel.deleteCount) 张")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .fontWeight(.medium)

                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("节省 \(viewModel.deletedPhotosSizeFormatted)")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            loadingView
        } else {
            switch viewModel.authorizationStatus {
            case .notDetermined, .denied, .restricted:
                authorizationView
            case .authorized, .limited:
                if viewModel.photos.isEmpty {
                    emptyView
                } else if viewModel.hasMorePhotos, let currentPhoto = viewModel.currentPhoto {
                    cardStackView(currentPhoto: currentPhoto)
                } else {
                    completionView
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("正在加载照片...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var authorizationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            VStack(spacing: 12) {
                Text("需要访问相册")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("PicPick 需要访问您的照片库来帮助您管理照片")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if viewModel.authorizationStatus == .denied {
                Button {
                    openSettings()
                } label: {
                    Label("前往设置", systemImage: "gear")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                }
            } else {
                Button {
                    Task {
                        await viewModel.requestAuthorization()
                    }
                } label: {
                    Text("授权访问")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            VStack(spacing: 12) {
                Text("没有找到照片")
                    .font(.title2)
                    .fontWeight(.bold)

                if viewModel.isDateFilterEnabled {
                    Text("在选定的日期范围内没有找到照片，请尝试调整筛选条件")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        Task {
                            await viewModel.clearDateFilter()
                        }
                    } label: {
                        Label("清除筛选", systemImage: "xmark.circle")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                    }
                } else {
                    Text("相册中没有照片")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cardStackView(currentPhoto: PhotoItem) -> some View {
        ZStack {
            // 卡片堆叠效果 - 显示下一张的预览
            if viewModel.currentPhotoIndex + 1 < viewModel.photos.count {
                let nextPhoto = viewModel.photos[viewModel.currentPhotoIndex + 1]
                PhotoCardView(
                    photo: nextPhoto,
                    onSwipeLeft: {},
                    onSwipeRight: {}
                )
                .id(nextPhoto.id) // 强制重新创建视图
                .scaleEffect(0.95)
                .offset(y: 10)
                .opacity(0.5)
                .allowsHitTesting(false)
            }

            // 当前卡片
            PhotoCardView(
                photo: currentPhoto,
                onSwipeLeft: {
                    viewModel.swipeLeft()
                },
                onSwipeRight: {
                    viewModel.swipeRight()
                }
            )
            .id(currentPhoto.id) // 添加唯一标识，强制 SwiftUI 在照片改变时重新创建视图
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 12) {
                Text("全部完成")
                    .font(.title)
                    .fontWeight(.bold)

                Text("您已处理完所有照片")
                    .font(.body)
                    .foregroundColor(.secondary)

                if viewModel.deleteCount > 0 {
                    Text("\(viewModel.deleteCount) 张照片已标记为删除")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
            }

            VStack(spacing: 12) {
                if viewModel.deleteCount > 0 {
                    Button {
                        viewModel.showDeleteConfirmationDialog()
                    } label: {
                        Label("删除标记的照片", systemImage: "trash.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: 300)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red)
                            )
                    }
                }

                Button {
                    Task {
                        await viewModel.refreshPhotos()
                    }
                } label: {
                    Label("重新开始", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: 300)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            // 撤销按钮
            Button {
                viewModel.undoLastSwipe()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title2)

                    Text("撤销")
                        .font(.headline)
                }
                .foregroundColor(viewModel.currentPhotoIndex > 0 ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(viewModel.currentPhotoIndex > 0 ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                )
            }
            .disabled(viewModel.currentPhotoIndex == 0)

            // 清理按钮
            Button {
                viewModel.showDeleteConfirmationDialog()
            } label: {
                HStack(spacing: 10) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trash.circle.fill")
                            .font(.title2)

                        if viewModel.deleteCount > 0 {
                            Text("\(viewModel.deleteCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(Color.red))
                                .offset(x: 8, y: -8)
                        }
                    }

                    Text("清理")
                        .font(.headline)
                }
                .foregroundColor(viewModel.deleteCount > 0 ? .red : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(viewModel.deleteCount > 0 ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                )
            }
            .disabled(viewModel.deleteCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showFilter = true
            } label: {
                Label("筛选", systemImage: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task {
                    await viewModel.refreshPhotos()
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - Computed Properties

    /// 是否有激活的筛选条件
    private var hasActiveFilter: Bool {
        viewModel.isDateFilterEnabled || viewModel.selectedMediaType != .allPhotos
    }

    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.showDeleteConfirmation = false
                }

            DeleteConfirmationView(
                photoCount: viewModel.deleteCount,
                estimatedSize: viewModel.getEstimatedDeletionSize(),
                onConfirm: {
                    await viewModel.executeDelete()
                },
                onCancel: {
                    viewModel.showDeleteConfirmation = false
                }
            )
            .padding()
        }
    }

    // MARK: - Actions

    private func initializeApp() async {
        viewModel.checkAuthorization()

        if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
            await viewModel.loadPhotos()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

struct PhotoManagementView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoManagementView()
    }
}
