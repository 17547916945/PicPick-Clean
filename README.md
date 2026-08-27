# PicPick - 「减法相册」式 iOS 照片清理应用

基于 [zruiii/PicPick](https://github.com/zruiii/PicPick) 开发的减法相册（SubAlbum）风格照片清理 App：卡片式滑动整理 + 全本地智能识别 + 双重安全删除，**所有照片处理均在设备本地完成，不上传任何数据，不收集任何信息**。

## ✨ 功能特性

### 核心整理（减法相册式交互）
- **左滑**：标记删除，红色 "DELETE ✕" 印章动画 + 触感反馈滑出
- **右滑**：标记保留，绿色 "KEEP ✓" 印章动画滑出
- **下拉**：添加到指定相册（支持新建相册）
- 卡片底部显示拍摄日期与序号（如 "12 / 345"）
- 顶部进度条：当月已处理 / 总数 + 累计释放空间（MB/GB）

### 智能识别（全程本地运行）
- **重复/相似照片**：Vision `VNGenerateImageFeaturePrintRequest` 提取特征向量 + 余弦相似度（阈值 0.85）聚类，每组一键「保留最佳，删除其余」
- **截图归类**：`PHAsset.mediaSubtypes` 直接识别
- **模糊检测**：Core Image Laplacian 方差算法
- **首页进度环**：动画展示累计释放空间与本月整体清理进度

### 特色与安全
- **照片盲盒**：随机抽取一个有照片的月份开始整理（参考减法相册 4.0.3）
- **双重安全删除**：标记照片先进入 App 内「待删除列表」（可单张/批量恢复）→ 永久删除时调用 `PHPhotoLibrary.performChanges` 并弹出 iOS 系统确认弹窗 → 系统「最近删除」再兜底 30 天
- **断点继续**：清理进度持久化，下次打开从上次中断的位置继续

### 商业化
- 免费用户每日清理额度 50 张；PicPick Pro 一次性买断（StoreKit 2）解锁无限量
- 设置页内置隐私声明与隐私政策链接（GitHub Pages 模板见 `docs/privacy-policy/`）

## 🛠 技术栈

- **框架**: SwiftUI + Combine
- **照片处理**: PhotoKit
- **智能分析**: Vision（特征提取）、Core Image（模糊检测）、Accelerate（vDSP 相似度加速）
- **内购**: StoreKit 2（非消耗型一次性买断）
- **架构模式**: MVVM
- **最低版本**: iOS 16.6 / Xcode 16+

## 📂 项目结构

```
PicPick/
├── Config.swift               # 全局品牌配置（商品 ID、隐私政策链接、额度）
├── Models/                    # 数据模型层
│   ├── PhotoItem.swift        # 照片模型 + 滑动状态
│   ├── PhotoAlbum.swift       # 用户相册模型
│   ├── DuplicateGroup.swift   # 相似照片分组 + 并查集
│   ├── SmartCleanupModels.swift
│   └── PendingDeleteItem.swift
├── Services/                  # 服务层
│   ├── PhotoService.swift     # PhotoKit 封装（权限/加载/删除/相册）
│   ├── PhotoAnalysisService.swift  # Vision 特征向量 + 余弦相似度 + Laplacian 模糊度
│   ├── StorageStatsStore.swift     # 累计释放空间 + 每月处理计数
│   ├── PendingDeleteStore.swift    # App 内待删除列表（第一层安全）
│   ├── CleaningProgressStore.swift # 断点继续快照
│   ├── DailyQuotaService.swift     # 每日免费额度
│   └── PaywallService.swift        # StoreKit 2 内购
├── ViewModels/                # 视图模型层
└── Views/                     # 视图层
    ├── HomeView.swift         # 首页：进度环 + 功能入口
    ├── PhotoManagementView.swift    # 滑动清理主界面
    ├── PhotoCardView.swift    # 三向手势卡片
    ├── DuplicateDetectionView.swift # 重复照片
    ├── SmartCleanupView.swift # 截图与模糊
    ├── PendingDeleteView.swift      # 待删除列表
    ├── BlindBoxView.swift     # 照片盲盒
    ├── SettingsView.swift     # 设置（隐私声明）
    └── PaywallView.swift      # 付费墙
docs/
├── privacy-policy/index.html  # GitHub Pages 隐私政策模板
└── appstore-screenshots-guide.md # 上架截图与审核检查清单
```

## 🚀 上架前必改配置（`PicPick/Config.swift`）

```swift
// 1. 隐私政策地址（GitHub Pages 发布后替换）
static let privacyPolicyURL = URL(string: "https://<你的用户名>.github.io/PicPick/privacy-policy")!

// 2. Pro 商品 ID（与 App Store Connect 创建的非消耗型商品一致）
static let proProductID = "lichao.PicPick.pro.unlock"
```

详细上架步骤（GitHub Pages 开启、截图脚本、审核检查清单、StoreKit 本地调试）见 `docs/appstore-screenshots-guide.md`。

## 📱 使用指南

- **开始清理**：默认按月整理，左滑删除 / 右滑保留 / 下拉归档 / 底部撤销
- **清理按钮**：把标记照片移入「待删除列表」（仍在相册中，可恢复）
- **待删除列表**：单张/批量恢复，或永久删除（系统确认弹窗 + 「最近删除」30 天兜底）
- **照片盲盒**：随机月份开盒整理
- **筛选**：本月（默认）/ 最近 7 天 / 30 天 / 90 天 / 一年 / 自定义 / 全部照片

## 📄 许可证

本项目仅供学习和参考使用。
