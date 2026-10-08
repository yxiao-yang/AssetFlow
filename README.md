# AssetFlow

个人资产管理与记账 iOS App。当前版本支持支出录入、分类、日期、备注、本月合计、删除和本地保存。

## 运行

用 Xcode 打开 `AssetFlow.xcodeproj`，选择 iPhone 模拟器，按 Command + R。
最低系统版本为 iOS 17。真机运行时，在 Signing & Capabilities 中选择自己的开发团队。

## 技术

SwiftUI + SwiftData；金额以整数分存储。记录保存在本机，目前尚未实现账户、收入、转账、资产图表、备份或云同步。
