//
//  SettingsView.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import SwiftUI

/// 设置页 - 隐私声明、免费额度、内购解锁、关于
struct SettingsView: View {

    @StateObject private var paywallService = PaywallService.shared
    @StateObject private var quotaService = DailyQuotaService.shared
    @State private var showPaywall = false

    var body: some View {
        List {
            privacySection
            quotaSection
            purchaseSection
            aboutSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            quotaService.refresh()
        }
    }

    // MARK: - Sections

    /// 隐私声明（App Store 审核必查项）
    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("所有照片处理均在本地完成，不上传任何数据，不收集任何信息", systemImage: "lock.shield.fill")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("· 重复检测：Vision 特征提取，本地余弦相似度计算\n· 模糊检测：Core Image Laplacian 本地分析\n· 无账号系统、无第三方统计 SDK、无任何网络上传")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            Link(destination: AppConfig.privacyPolicyURL) {
                Label("隐私政策", systemImage: "doc.text")
            }
        } header: {
            Text("隐私")
        } footer: {
            Text("照片仅通过系统 PhotoKit 在本机处理，删除操作由 iOS 系统保护")
        }
    }

    /// 每日免费额度
    private var quotaSection: some View {
        Section {
            HStack {
                Label("今日已清理", systemImage: "calendar.badge.clock")
                Spacer()
                if paywallService.isProUnlocked {
                    Text("无限量（Pro）")
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                } else {
                    Text("\(quotaService.usedToday) / \(AppConfig.freeDailyCleanLimit) 张")
                        .foregroundColor(quotaService.remainingToday > 0 ? .primary : .red)
                }
            }

            if !paywallService.isProUnlocked {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Label("解锁无限量清理", systemImage: "sparkles")
                        Spacer()
                        Text(paywallService.productDisplayPrice)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("免费额度")
        } footer: {
            if !paywallService.isProUnlocked {
                Text("免费用户每天可清理 \(AppConfig.freeDailyCleanLimit) 张照片，解锁 Pro 后不限量")
            }
        }
    }

    /// 内购
    private var purchaseSection: some View {
        Section {
            if paywallService.isProUnlocked {
                Label("PicPick Pro 已解锁", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("购买 PicPick Pro（一次性买断）", systemImage: "crown.fill")
                }
            }

            Button {
                Task { await paywallService.restore() }
            } label: {
                HStack {
                    Label("恢复购买", systemImage: "arrow.clockwise")
                    if paywallService.isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(paywallService.isLoading)
        } header: {
            Text("Pro 会员")
        }
    }

    /// 关于
    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("\(AppConfig.appVersion) (\(AppConfig.buildNumber))")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("简介")
                Spacer()
                Text(AppConfig.appTagline)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("关于 \(AppConfig.appName)")
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
        }
    }
}
