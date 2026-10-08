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
        let yield = "账单详情\n余额宝〉\n0.16\n交易成功\n创建时间 2026-10-08 03:05:12\n服务详情\n余额宝-攒着-收益发放\n账单分类 投资理财"
        let income = PaymentParser.parse(yield, now: now)
        precondition(income.isIncome && income.category == "理财收益")
        precondition(income.amountInCents == 16 && income.date != nil)
        precondition(income.merchant == "余额宝" && income.paymentMethod == "余额宝" && income.paymentChannel == "支付宝")
        precondition(income.reasons.isEmpty)
        precondition(!payment.isIncome && !saved.isIncome)
        precondition(!PaymentParser.parse(yield.replacingOccurrences(of: "交易成功", with: "待付款"), now: now).reasons.isEmpty)
        precondition(!PaymentParser.parse(yield.replacingOccurrences(of: "0.16", with: "-0.16"), now: now).reasons.isEmpty)
        precondition(!PaymentParser.parse(yield + "\n退款", now: now).reasons.isEmpty)
        precondition(PaymentParser.parse(yield + "\n0.20", now: now).amountInCents == nil)
        precondition(!PaymentParser.parse(yield.replacingOccurrences(of: "收益发放", with: "转入"), now: now).isIncome)
        precondition(!PaymentParser.parse(yield.replacingOccurrences(of: "2026-10-08 03:05:12", with: "2026-99-99 03:05:12"), now: now).reasons.isEmpty)
        let shop = "账单详情\n好想来零食乐园\n-4.20\n交易成功\n支付时间 2026-10-06 14:03:17\n付款方式 招商银行信用卡（5550）＞\n商品说明 示例门店\n收款方全称 示例零食店（个体工商户）\n账单管理"
        let snack = PaymentParser.parse(shop, now: now)
        precondition(snack.amountInCents == 420 && !snack.isIncome && snack.reasons.isEmpty)
        precondition(snack.merchant == "好想来零食乐园" && snack.category == "餐饮" && snack.paymentChannel == "支付宝")
        precondition(snack.paymentMethod == "招商银行信用卡(5550)")
        let noodle = shop.replacingOccurrences(of: "好想来零食乐园", with: "示例板面").replacingOccurrences(of: "-4.20", with: "-15.00").replacingOccurrences(of: "示例零食店（个体工商户）", with: "*某（个人）")
        let meal = PaymentParser.parse(noodle, now: now)
        precondition(meal.amountInCents == 1500 && meal.merchant == "示例板面" && meal.reasons.isEmpty && meal.category == "餐饮")
        precondition(PaymentParser.parse("收款方全称 某个体商户").merchant == "某个体商户")
        precondition(!PaymentParser.parse(shop.replacingOccurrences(of: "交易成功", with: "支付失败"), now: now).reasons.isEmpty)
        let wechat = "账单\n美团\n-275.00\n当前状态 支付成功\n支付时间 2026年10月7日 15:01:51\n商品 示例影院足道·养生SPA\n门店-美团微信小程序\n商户全称 示例平台科技有限公司\n收单机构 财付通\n支付方式 零钱\n交易单号 4500000469202610074416438248"
        let wx = PaymentParser.parse(wechat, now: now)
        precondition(wx.amountInCents == 27500 && !wx.isIncome && wx.reasons.isEmpty)
        precondition(wx.date != nil && wx.merchant == "美团" && wx.paymentChannel == "微信")
        precondition(wx.paymentMethod == "零钱" && wx.category == "娱乐")
        precondition(wx.productDescription?.contains("养生SPA") == true)
        precondition(wx.productDescription?.contains("科技有限公司") == false)
        print("Payment parser: all checks passed")
    }
}
