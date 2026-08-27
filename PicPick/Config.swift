//
//  Config.swift
//  PicPick
//
//  Created on 2026-08-27.
//

import Foundation

/// 全局品牌配置 - 上架前集中修改此处（参考 SwipeClean 的 Config.swift 思路）
enum AppConfig {

    // MARK: - 品牌

    static let appName = "PicPick"
    static let appTagline = "减法相册式照片清理"

    // MARK: - 隐私政策（App Store 审核要求：需在 App 内可访问）

    /// 使用 GitHub Pages 托管（docs/privacy-policy/index.html 已准备好模板），
    /// 上架前替换为你的实际地址：
    /// https://<你的GitHub用户名>.github.io/PicPick/privacy-policy
    static let privacyPolicyURL = URL(string: "https://zruiii.github.io/PicPick/privacy-policy")!

    // MARK: - 免费额度与内购

    /// 免费用户每日清理额度（张/天）
    static let freeDailyCleanLimit = 50

    /// Pro 一次性买断商品 ID（非消耗型）
    /// 需在 App Store Connect → 订阅/内购 中创建同名商品
    static let proProductID = "lichao.PicPick.pro.unlock"

    // MARK: - 版本信息

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
