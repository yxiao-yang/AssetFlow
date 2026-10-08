#if DEBUG
import Foundation
import SwiftData

@MainActor
enum AssetDemo {
    static func seed(_ context: ModelContext) {
        let start = Calendar.current.date(byAdding: .day, value: -20, to: .now)!
        let rows: [(String, AssetKind, Int, String)] = [
            ("招商银行储蓄卡", .debitCard, 2868000, "4132"),
            ("工商银行存折", .passbook, 5000000, ""),
            ("微信零钱", .wechat, 126800, ""),
            ("支付宝余额宝", .yuebao, 1868000, "")
        ]
        for (name, kind, amount, tail) in rows {
            let account = AssetAccount(name: name, kind: kind, lastFour: tail, createdAt: start)
            if kind == .passbook { account.managesTermDeposits = true }
            context.insert(account)
            context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: amount, date: start, note: "示例期初余额"))
            if kind == .passbook {
                context.insert(TermDeposit(accountID: account.id, name: "第一笔一年定期", principalInCents: 2000000,
                    annualRateText: "1.5", openedAt: Calendar.current.date(byAdding: .year, value: -1, to: .now)!,
                    maturityDate: Calendar.current.startOfDay(for: .now), note: "示例数据，未实际取出", createdAt: start))
                context.insert(TermDeposit(accountID: account.id, name: "第二笔三年定期", principalInCents: 2500000,
                    annualRateText: "2", openedAt: Calendar.current.date(byAdding: .month, value: -6, to: .now)!,
                    maturityDate: Calendar.current.date(byAdding: .month, value: 30, to: .now)!, note: "示例数据", createdAt: start))
            }
            if kind == .debitCard {
                context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: amount - 50000,
                    date: Calendar.current.date(byAdding: .day, value: -5, to: .now)!, note: "示例余额核对"))
            }
        }
        let stock = AssetAccount(name: "股票投资账户", kind: .stocks, institution: "示例券商", createdAt: start)
        context.insert(stock)
        let holding = StockHolding(accountID: stock.id, name: "示例股票持仓", symbol: "600000", quantityText: "1000", costPriceText: "36.20", priceText: "39.50")
        context.insert(holding)
        context.insert(AssetBalanceSnapshot(accountID: stock.id, amountInCents: 4120000, date: start, note: "示例证券估值，含现金"))
        try? context.save()
    }
}
#endif
