import SwiftUI

func assetMoney(_ cents: Int, currency: String = "CNY", hidden: Bool = false) -> String {
    hidden ? "••••" : (Decimal(cents) / 100).formatted(.currency(code: currency))
}

extension AssetKind {
    var color: Color {
        switch self {
        case .debitCard: .blue
        case .passbook: .indigo
        case .stocks: .purple
        case .wechat: LedgerStyle.income
        case .alipayBalance: .cyan
        case .yuebao: .orange
        case .cash: .teal
        case .other: .gray
        }
    }
}

struct AssetAccountIcon: View {
    let kind: AssetKind
    var body: some View {
        Image(systemName: kind.icon).font(.system(size: 18, weight: .semibold))
            .foregroundStyle(kind.color).frame(width: 44, height: 44)
            .background(kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
