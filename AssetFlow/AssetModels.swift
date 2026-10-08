import Foundation
import SwiftData

enum AssetKind: String, CaseIterable, Identifiable {
    case debitCard, passbook, stocks, wechat, alipayBalance, yuebao, cash, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .debitCard: "储蓄卡"
        case .passbook: "存折"
        case .stocks: "股票账户"
        case .wechat: "微信零钱"
        case .alipayBalance: "支付宝余额"
        case .yuebao: "余额宝"
        case .cash: "现金"
        case .other: "其他资产"
        }
    }
    var icon: String {
        switch self {
        case .debitCard: "creditcard.fill"
        case .passbook: "book.closed.fill"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .wechat: "bubble.left.and.bubble.right.fill"
        case .alipayBalance: "wallet.pass.fill"
        case .yuebao: "leaf.fill"
        case .cash: "banknote.fill"
        case .other: "square.stack.3d.up.fill"
        }
    }
}

@Model
final class AssetAccount {
    var id: UUID = UUID()
    var name: String
    var kindRaw: String
    var currencyCode: String = "CNY"
    var depositStyle: String = "活期"
    var annualRateText: String?
    var maturityDate: Date?
    var institution: String
    var lastFour: String
    var note: String
    var createdAt: Date
    var archivedAt: Date?
    var kind: AssetKind { AssetKind(rawValue: kindRaw) ?? .other }
    init(name: String, kind: AssetKind, institution: String = "", lastFour: String = "", note: String = "", createdAt: Date = .now) {
        self.name = name; self.kindRaw = kind.rawValue; self.institution = institution
        self.lastFour = lastFour; self.note = note; self.createdAt = createdAt
    }
}

@Model
final class AssetBalanceSnapshot {
    var accountID: UUID
    var amountInCents: Int
    var date: Date
    var note: String
    init(accountID: UUID, amountInCents: Int, date: Date = .now, note: String) {
        self.accountID = accountID; self.amountInCents = amountInCents; self.date = date; self.note = note
    }
}

@Model
final class StockHolding {
    var accountID: UUID
    var name: String
    var symbol: String
    var quantityText: String
    var costPriceText: String
    var priceText: String
    var updatedAt: Date
    var quoteSource: String?
    var quoteDate: Date?
    var quoteStatus: String?
    init(accountID: UUID, name: String, symbol: String, quantityText: String, costPriceText: String, priceText: String) {
        self.accountID = accountID; self.name = name; self.symbol = symbol; self.quantityText = quantityText
        self.costPriceText = costPriceText; self.priceText = priceText; self.updatedAt = .now
    }
    var marketValue: Int { AssetMath.positionValue(quantityText, priceText: priceText) ?? 0 }
    var costValue: Int { AssetMath.positionValue(quantityText, priceText: costPriceText) ?? 0 }
    var profit: Int { marketValue - costValue }
}

@Model
final class AssetTransfer {
    var receivedInCents: Int
    var fromID: UUID
    var toID: UUID
    var amountInCents: Int
    var date: Date
    var note: String
    init(fromID: UUID, toID: UUID, amountInCents: Int, receivedInCents: Int, date: Date = .now, note: String) {
        self.receivedInCents = receivedInCents; self.fromID = fromID; self.toID = toID; self.amountInCents = amountInCents; self.date = date; self.note = note
    }
}

@Model
final class AssetFXRate {
    var marketDate: String?
    var rateText: String
    var date: Date
    var source: String
    init(rateText: String, date: Date = .now, source: String = "手动录入") {
        self.rateText = rateText; self.date = date; self.source = source
    }
}
