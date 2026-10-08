import Foundation

@main
struct ParserChecks {
    static func main() {
        let full = "支付宝\n支付成功\n￥28.50\n商户名称\n阳光咖啡\n付款方式\n招商银行(4132)\n支付时间\n2026-10-08 12:00:00\n交易单号\n2026100812345678"
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let payment = PaymentParser.parse(full, now: now)
        precondition(payment.amountInCents == 2850)
        precondition(payment.category == "餐饮")
        precondition(payment.paymentMethod == "招商银行(4132)")
        precondition(payment.reasons.isEmpty)
        precondition(PaymentParser.parse("支付成功\n￥20.00\n￥30.00").amountInCents == nil)
        precondition(PaymentParser.parse("实付金额：28.50\n原价￥35.00\n支付成功").amountInCents == 2850)
        precondition(!PaymentParser.parse(full + "\n退款成功", now: now).reasons.isEmpty)
        precondition(!PaymentParser.parse(full + "\n转账", now: now).reasons.isEmpty)
        precondition(!PaymentParser.parse(full + "\nUSD", now: now).reasons.isEmpty)
        precondition(PaymentParser.parse("支付成功\n优惠￥10.00").amountInCents == nil)
        precondition(PaymentParser.parse("实付金额：0.00").amountInCents == nil)
        let pocket = "支付宝小荷包（家庭小金库）\n−10.00\n自动扣款成功\n创建时间 2026-10-08 09:37:21\n付款方式 招商银行储蓄卡（1373）＞\n理由 自动攒\n对方账户 支付宝小荷包（家庭小金库）\n账单分类 账户存取"
        let saved = PaymentParser.parse(pocket, now: now)
        precondition(saved.amountInCents == 1000)
        precondition(saved.merchant == "支付宝小荷包(家庭小金库)")
        precondition(saved.paymentMethod == "招商银行储蓄卡(1373)")
        precondition(saved.date != nil && saved.paymentChannel == "支付宝")
        precondition(saved.reasons.isEmpty)
        let columnOrder = "创建时间\n付款方式\n对方账户\n服务详情\n2026-10-08 09:37:21\n-10.00\n自动扣款成功"
        let columnPayment = PaymentParser.parse(columnOrder, now: now)
        precondition(columnPayment.date != nil)
        precondition(columnPayment.merchant == nil)
        precondition(!PaymentParser.parse(full + "\n账户存取", now: now).reasons.isEmpty)
        precondition(!PaymentParser.parse(pocket.replacingOccurrences(of: "自动扣款成功", with: "待付款"), now: now).reasons.isEmpty)
        precondition(!PaymentParser.parse(pocket + "\n退款成功", now: now).reasons.isEmpty)
        print("Payment parser: all checks passed")
    }
}
