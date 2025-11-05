//
//  PicPickApp.swift
//  PicPick
//
//  Created by ZhaRui on 2025/11/5.
//

import SwiftUI

@main
struct PicPickApp: App {
    var body: some Scene {
        WindowGroup {
            PhotoManagementView()
                .preferredColorScheme(nil) // 支持系统自动切换暗黑模式
        }
    }
}
