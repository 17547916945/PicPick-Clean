# PicPick App Store 上架准备指南

## 一、隐私政策托管（GitHub Pages）

1. 仓库已包含 `docs/privacy-policy/index.html`（中文隐私政策模板，已强调「所有处理均在本地完成，不上传任何数据，不收集任何信息」）。
2. 将仓库推送到 GitHub，在仓库 Settings → Pages 中：
   - Source 选择 **Deploy from a branch**
   - Branch 选择 `main` / `docs` 目录
3. 得到地址 `https://<用户名>.github.io/<仓库名>/privacy-policy`（如 `https://zruiii.github.io/PicPick/privacy-policy`）。
4. 把该地址填入 `PicPick/Config.swift` 的 `AppConfig.privacyPolicyURL`。
5. 在 App Store Connect 的「App 隐私」页面填同样的链接。
   - 若也可用 Notion 托管：发布 Notion 页面 → Share → Publish to web → 使用公开链接。

## 二、截图准备（重点：清理前后存储空间对比数字）

要求：iPhone 6.9 英寸（1320×2868）与 6.5 英寸（1284×2778）两套，共最多 10 张。

建议截图脚本（模拟器或真机操作）：

| 顺序 | 画面 | 要点 |
|---|---|---|
| 1 | 首页进度环 | 环中心「累计释放 1.2 GB」，下方「本月已处理 128 / 345」——**数字对比是核心卖点** |
| 2 | 清理前截图 | 顶部进度条「已处理 0 / 345」+ 卡片「1 / 345」，示意待清理量大 |
| 3 | 清理后截图 | 完成页 + toast「已移入待删除列表（45 张），可随时恢复」 |
| 4 | 待删除列表 | 列表头「45 张待删除 · 合计 620 MB」，突出可释放空间数字 |
| 5 | 重复照片 | 「发现 3 组相似照片 · 可释放 180 MB」 |
| 6 | 截图与模糊 | 网格选中批量删除，底部「已选 32 张 · 450 MB」 |
| 7 | 照片盲盒 | 盲盒动画 + 「抽中 2024年3月 · 86 张」 |
| 8 | 设置页 | 「所有照片处理均在本地完成，不上传任何数据，不收集任何信息」 |

技巧：
- 用模拟器造数据：把几十张照片拖进模拟器相册，重复拖拽制造重复照片。
- 数字对比放截图中心或标题位，避免过多文字遮挡。
- 纯色背景 + 系统字体，符合苹果设计规范。

## 三、App Store Connect 审核检查清单

- [ ] **隐私权限描述**：Info.plist 已配置（本项目通过 `INFOPLIST_KEY_*` 生成）：
  - `NSPhotoLibraryUsageDescription`：「需要访问您的相册，帮您快速整理和清理照片」
  - `NSPhotoLibraryAddUsageDescription`：「需要此权限来保存清理后的照片」
- [ ] **App 隐私「营养标签」**：选择「不收集数据」（Data Not Collected）——因为 App 确实无网络上传、无账号、无统计 SDK。
- [ ] **内购**：App Store Connect → 订阅/内购 创建非消耗型商品，ID 与 `AppConfig.proProductID` 一致（`lichao.PicPick.pro.unlock`）。
- [ ] **内购宣传合规**：付费墙文案不夸大，明示「一次性买断，永久解锁」。
- [ ] **删除权限说明**：审核指南 4.8.3 要求——App 内的删除需明确告知用户照片去向。本项目流程：标记 → 待删除列表（可恢复）→ 系统确认弹窗 → 系统「最近删除」30 天兜底，符合要求。
- [ ] **隐私政策链接**：App 设置页内可访问（`SettingsView` 已内置 `Link`）。
- [ ] **免费额度**：免费用户每日 50 张，超额引导付费墙；Pro 无限量。审核演示时额度耗尽后可从设置页查看状态。

## 四、测试内购（StoreKit Configuration）

Xcode 16：File → New → StoreKit Configuration File，创建与 `AppConfig.proProductID` 同名的非消耗型商品；Scheme → Run → Options → StoreKit Configuration 选中该文件，即可在模拟器完整测试购买/恢复流程。
