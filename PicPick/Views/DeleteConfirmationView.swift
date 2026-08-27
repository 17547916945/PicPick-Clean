//
//  DeleteConfirmationView.swift
//  PicPick
//
//  Created on 2025-11-05.
//

import SwiftUI

/// 删除确认弹窗视图
struct DeleteConfirmationView: View {

    let photoCount: Int
    let estimatedSize: String
    let onConfirm: () async -> Void
    let onCancel: () -> Void

    @State private var isDeleting = false

    var body: some View {
        VStack(spacing: 24) {
            // 警告图标
            warningIcon

            // 标题
            Text("确认清理")
                .font(.title2)
                .fontWeight(.bold)

            // 信息内容
            VStack(spacing: 12) {
                infoRow(
                    icon: "photo.on.rectangle.angled",
                    text: "将 \(photoCount) 张照片移入待删除列表"
                )

                infoRow(
                    icon: "internaldrive",
                    text: "永久删除后预计释放 \(estimatedSize)"
                )

                warningText
            }

            // 按钮组
            actionButtons
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .disabled(isDeleting)
        .overlay {
            if isDeleting {
                deletingOverlay
            }
        }
    }

    // MARK: - Subviews

    private var warningIcon: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.1))
                .frame(width: 80, height: 80)

            Image(systemName: "trash.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)

            Text(text)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal)
    }

    private var warningText: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text("双重安全删除")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }

            Text("照片将先进入 App 内「待删除列表」，仍保留在相册中，可随时恢复。永久删除时才真正移除，且系统「最近删除」还会再保留 30 天。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
        )
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // 取消按钮
            Button {
                onCancel()
            } label: {
                Text("取消")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                    )
            }

            // 确认清理按钮
            Button {
                Task {
                    await confirmDelete()
                }
            } label: {
                Text("移入待删除列表")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                    )
            }
        }
        .padding(.horizontal)
    }

    private var deletingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("正在删除...")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("请勿关闭应用")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }

    // MARK: - Actions

    private func confirmDelete() async {
        isDeleting = true
        await onConfirm()
        isDeleting = false
    }
}

// MARK: - Preview

struct DeleteConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            DeleteConfirmationView(
                photoCount: 42,
                estimatedSize: "156.8 MB",
                onConfirm: {},
                onCancel: {}
            )
            .padding()
        }
    }
}
