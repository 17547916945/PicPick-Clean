//
//  PaywallView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI

/// 付费墙 - 一次性买断解锁无限量清理（StoreKit 2）
struct PaywallView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var paywallService = PaywallService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                // 图标
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 110, height: 110)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                }

                // 标题
                VStack(spacing: 8) {
                    Text("PicPick Pro")
                        .font(.largeTitle.weight(.bold))

                    Text("一次买断，永久解锁")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // 权益列表
                VStack(alignment: .leading, spacing: 14) {
                    benefitRow(icon: "infinity", text: "无限量清理，不设每日上限")
                    benefitRow(icon: "square.on.square", text: "无限使用重复照片、截图与模糊检测")
                    benefitRow(icon: "lock.shield", text: "依然全程本地处理，隐私不变")
                }
                .padding(.horizontal, 32)

                Spacer()

                // 购买按钮
                VStack(spacing: 12) {
                    Button {
                        Task { await paywallService.purchase() }
                    } label: {
                        Text(paywallService.isLoading
                             ? "处理中..."
                             : "立即解锁 \(paywallService.productDisplayPrice)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.orange)
                            )
                    }
                    .disabled(paywallService.isLoading)
                    .padding(.horizontal, 32)

                    Button {
                        Task { await paywallService.restore() }
                    } label: {
                        Text("恢复购买")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .disabled(paywallService.isLoading)

                    Text("购买即表示同意隐私政策，所有处理仍在本地完成")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { paywallService.errorMessage != nil },
                set: { if !$0 { paywallService.errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                if let errorMessage = paywallService.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: paywallService.isProUnlocked) { unlocked in
                if unlocked {
                    dismiss()
                }
            }
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 28)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView()
    }
}
