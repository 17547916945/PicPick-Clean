//
//  BlindBoxView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI

/// 照片盲盒视图 - 随机抽取一个月份开始整理，让清理变得有趣
/// （参考减法相册 4.0.3「照片盲盒」功能）
struct BlindBoxView: View {

    @StateObject private var viewModel = BlindBoxViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // 盲盒动画
            blindBox

            // 提示
            Text("随机抽取一个月份，从随机日期开始整理照片")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // 抽中的结果卡片
            if let month = viewModel.pickedMonth {
                resultCard(month)
            }

            Spacer()

            // 开启按钮
            Button {
                Task { await viewModel.draw() }
            } label: {
                Label(
                    viewModel.pickedMonth == nil ? "开启盲盒" : "再来一次",
                    systemImage: "gift.fill"
                )
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(Color.pink)
                )
            }
            .disabled(viewModel.isDrawing)
            .padding(.bottom, 40)
        }
        .navigationTitle("照片盲盒")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .background {
            // 隐藏的跳转：抽中月份后进入对应月份的清理队列
            NavigationLink(
                isActive: Binding(
                    get: { viewModel.pickedMonth != nil },
                    set: { if !$0 { viewModel.pickedMonth = nil } }
                )
            ) {
                if let month = viewModel.pickedMonth {
                    PhotoManagementView(
                        startDate: month.start,
                        endDate: month.end,
                        isBlindBox: true
                    )
                }
            } label: {
                EmptyView()
            }
            .hidden()
        }
    }

    // MARK: - Subviews

    /// 盲盒主体（抽取时摇晃动画）
    private var blindBox: some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.12))
                .frame(width: 220, height: 220)

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 110))
                .foregroundColor(.brown)
                .scaleEffect(viewModel.isDrawing ? 1.18 : 1.0)
                .rotationEffect(.degrees(viewModel.isDrawing ? -10 : 0))
                .animation(
                    .easeInOut(duration: 0.35).repeatForever(autoreverses: true),
                    value: viewModel.isDrawing
                )

            if viewModel.isDrawing {
                ProgressView()
                    .offset(y: 130)
            }
        }
        .frame(height: 220)
    }

    private func resultCard(_ month: BlindBoxViewModel.PickedMonth) -> some View {
        VStack(spacing: 8) {
            Text("🎉 抽中 \(month.title)")
                .font(.headline)

            Text("该月共 \(month.count) 张照片，点击下方按钮进入清理")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .padding(.horizontal)
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Preview

struct BlindBoxView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BlindBoxView()
        }
    }
}
