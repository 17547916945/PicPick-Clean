//
//  PendingDeleteView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI

/// 待删除列表视图 - 双重安全删除
/// 照片进入此列表后仍在系统相册中，可单张/批量恢复；
/// 「永久删除」调用 PHPhotoLibrary.performChanges，iOS 弹出系统确认弹窗，
/// 且照片在系统「最近删除」中仍保留 30 天
struct PendingDeleteView: View {

    @StateObject private var viewModel = PendingDeleteViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.items.isEmpty {
                emptyView
            } else {
                itemList
                bottomBar
            }
        }
        .navigationTitle("待删除")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "永久删除选中的照片？",
            isPresented: $viewModel.confirmPermanentDelete,
            titleVisibility: .visible
        ) {
            Button("永久删除（最近删除保留 30 天）", role: .destructive) {
                Task { await viewModel.permanentlyDeleteSelected() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除 \(viewModel.selectedCount) 张照片，预计释放 \(viewModel.selectedSizeFormatted)。iOS 会再次弹出系统确认框，且照片在系统「最近删除」中仍可恢复 30 天。")
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .task {
            viewModel.refreshAssets()
        }
    }

    // MARK: - Subviews

    private var itemList: some View {
        List {
            Section {
                ForEach(viewModel.items) { item in
                    itemRow(item)
                }
            } header: {
                Text("\(viewModel.items.count) 张待删除 · 合计 \(viewModel.totalSizeFormatted)")
            } footer: {
                Text("照片仍在系统相册中，可随时恢复；永久删除后系统「最近删除」再保留 30 天")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func itemRow(_ item: PendingDeleteItem) -> some View {
        HStack(spacing: 12) {
            // 选中圈
            Button {
                viewModel.toggleSelection(id: item.id)
            } label: {
                Image(systemName: viewModel.selectedIDs.contains(item.id)
                      ? "checkmark.circle.fill"
                      : "circle")
                    .font(.title3)
                    .foregroundColor(viewModel.selectedIDs.contains(item.id) ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            // 缩略图
            if let asset = viewModel.assetsByID[item.id] {
                PhotoThumbnailView(asset: asset, size: 56)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(Image(systemName: "questionmark"))
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(item.dateAdded))
                    .font(.subheadline)

                Text(photoSizeFormatter(item.sizeBytes))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 单张恢复
            Button {
                viewModel.restore(item)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                if viewModel.isAllSelected {
                    viewModel.clearSelection()
                } else {
                    viewModel.selectAll()
                }
            } label: {
                Text(viewModel.isAllSelected ? "取消全选" : "全选")
                    .font(.subheadline.weight(.medium))
            }

            Spacer()

            // 批量恢复
            Button {
                viewModel.restoreSelected()
            } label: {
                Label("恢复 (\(viewModel.selectedCount))", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            }
            .disabled(viewModel.selectedCount == 0)

            // 永久删除
            Button {
                viewModel.requestPermanentDelete()
            } label: {
                Label("永久删除", systemImage: "trash.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(viewModel.selectedCount > 0 ? Color.red : Color.gray))
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

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("待删除列表为空")
                .font(.headline)

            Text("左滑标记删除的照片会先出现在这里，确认无误后再永久删除")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func photoSizeFormatter(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Preview

struct PendingDeleteView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PendingDeleteView()
        }
    }
}
