//
//  HomeView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI

/// 首页 - 累计释放空间动画进度环 + 功能入口
struct HomeView: View {

    @StateObject private var viewModel = HomeViewModel()
    @State private var animatedProgress: Double = 0

    private let actionColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    progressRing
                    statsCards
                    actionGrid
                    privacyFootnote
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PicPick")
        }
        .onAppear {
            Task { await viewModel.refresh() }
        }
    }

    // MARK: - Subviews

    /// 动画进度环：中心显示累计释放空间，环表示本月整体清理进度
    private var progressRing: some View {
        VStack(spacing: 16) {
            ZStack {
                // 背景环
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 18)

                // 进度环
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: animatedProgress)

                // 中心数字
                VStack(spacing: 4) {
                    Text(viewModel.freedFormatted)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text("累计释放")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
            }
            .frame(width: 210, height: 210)

            Text("本月已处理 \(viewModel.monthProcessed) / \(viewModel.monthTotal)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedProgress = viewModel.monthProgress
            }
        }
        .onChange(of: viewModel.monthProgress) { newValue in
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedProgress = newValue
            }
        }
    }

    private var statsCards: some View {
        HStack(spacing: 12) {
            statCard(title: "本月照片", value: "\(viewModel.monthTotal)", icon: "photo.on.rectangle.angled", color: .blue)
            statCard(title: "已处理", value: "\(viewModel.monthProcessed)", icon: "checkmark.circle", color: .green)
            statCard(title: "累计释放", value: viewModel.freedCompact, icon: "internaldrive", color: .orange)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
    }

    private var actionGrid: some View {
        LazyVGrid(columns: actionColumns, spacing: 12) {
            NavigationLink {
                PhotoManagementView()
            } label: {
                actionCard(title: "开始清理", subtitle: "左删右留下拉归档", icon: "hand.draw.fill", color: .blue)
            }
            .buttonStyle(.plain)

            NavigationLink {
                DuplicateDetectionView()
            } label: {
                actionCard(title: "重复照片", subtitle: "本地相似度检测", icon: "square.on.square", color: .orange)
            }
            .buttonStyle(.plain)

            NavigationLink {
                SmartCleanupView()
            } label: {
                actionCard(title: "截图与模糊", subtitle: "快速批量归类", icon: "camera.viewfinder", color: .purple)
            }
            .buttonStyle(.plain)

            NavigationLink {
                BlindBoxView()
            } label: {
                actionCard(title: "照片盲盒", subtitle: "随机月份，有趣整理", icon: "gift.fill", color: .pink)
            }
            .buttonStyle(.plain)

            NavigationLink {
                PendingDeleteView()
            } label: {
                actionCard(
                    title: "待删除列表",
                    subtitle: viewModel.pendingDeleteCount > 0
                        ? "\(viewModel.pendingDeleteCount) 张待确认"
                        : "双重安全，可恢复",
                    icon: "tray.full.fill",
                    color: .red
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SettingsView()
            } label: {
                actionCard(title: "设置", subtitle: "隐私 · 额度 · Pro", icon: "gearshape.fill", color: .gray)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionCard(title: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
    }

    private var privacyFootnote: some View {
        Label("所有照片处理均在本地完成，不上传任何数据", systemImage: "lock.shield.fill")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }
}

// MARK: - Preview

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
