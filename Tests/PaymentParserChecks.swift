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
        print("Payment parser: 10 checks passed")
    }
}
