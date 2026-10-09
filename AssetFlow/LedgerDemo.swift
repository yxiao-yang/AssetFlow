#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Explicit debug-only, in-memory data for simulator visual checks.
@MainActor
enum LedgerDemo {
    static func seed(_ context: ModelContext) {
        let cal = Calendar.current
        let first = cal.dateInterval(of: .month, for: .now)!.start
        let today = cal.component(.day, from: .now)
        let samples: [(Int, String, String, Int, Bool)] = [
            (2850, "餐饮", "街角咖啡", today, false),
            (6800, "餐饮", "午间食堂", today, false),
            (600, "交通", "地铁出行", today, false),
            (12900, "购物", "生活超市", max(1, today - 1), false),
            (3500, "娱乐", "周末电影", max(1, today - 2), false),
            (420000, "住房", "十月房租", 1, false),
            (1580000, "工资", "十月工资", 1, true),
            (1800, "餐饮", "早餐", max(1, today - 3), false)
        ]
        for (amount, category, name, day, income) in samples {
            let date = cal.date(byAdding: .hour, value: 12, to: cal.date(byAdding: .day, value: day - 1, to: first)!)!
            let record = Expense(amountInCents: amount, category: category, note: name, date: date)
            record.isIncome = income
            record.merchant = name
            record.paymentMethod = income ? nil : "招商银行(4132)"
            context.insert(record)
        }
        let pending = Expense(amountInCents: 4600, category: "餐饮", note: "截图待确认", date: .now)
        pending.needsConfirmation = true
        pending.reviewReason = "未识别到扣款方式，请核对"
        if CommandLine.arguments.contains("--demo-pending-image") {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1290, height: 2796), format: format)
            pending.screenshotData = renderer.image { image in
                UIColor.white.setFill()
                image.fill(CGRect(x: 0, y: 0, width: 1290, height: 2796))
                ("示例账单\n支付成功\n-46.00\n支付时间 2026年10月7日 15:01:51" as NSString)
                    .draw(in: CGRect(x: 80, y: 100, width: 1100, height: 900),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
            }.pngData()
            pending.rawText = "示例截图，用于验证带原图的待确认页面导航。"
            pending.paymentChannel = "微信"
        }
        context.insert(pending)
        try? context.save()
    }
}
#endif
