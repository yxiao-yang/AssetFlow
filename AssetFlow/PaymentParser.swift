import Foundation

struct RecognizedPayment {
    var amountInCents: Int?
    var merchant: String?
    var paymentChannel: String?
    var paymentMethod: String?
    var transactionID: String?
    var date: Date?
    var category = "其他"
    var reasons: [String] = []
    var rawText: String
}

/// Only explicit source fields are extracted. Category is a rule-based suggestion.
enum PaymentParser {
    static func parse(_ text: String, now: Date = .now) -> RecognizedPayment {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        let lines = normalized.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var result = RecognizedPayment(rawText: text)
        if text.contains("支付宝") { result.paymentChannel = "支付宝" }
        else if text.contains("微信") || text.contains("零钱") { result.paymentChannel = "微信" }

        let knownLabels = ["商户名称", "收款方", "收款商户", "商家名称", "交易对方", "对方账户", "付款方式", "支付方式", "交易单号", "交易订单号", "微信支付订单号", "支付时间", "付款时间", "交易时间", "创建时间", "理由", "服务详情", "账单分类", "标签"]
        func field(_ labels: [String]) -> String? {
            for (index, line) in lines.enumerated() {
                for label in labels where line.hasPrefix(label) {
                    let suffix = String(line.dropFirst(label.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: " :：\t"))
                    if !suffix.isEmpty { return suffix }
                    if index + 1 < lines.count,
                       !knownLabels.contains(where: lines[index + 1].hasPrefix) { return lines[index + 1] }
                }
            }
            return nil
        }
        result.merchant = field(["商户名称", "收款方", "收款商户", "商家名称", "交易对方", "对方账户"])
        result.paymentMethod = field(["付款方式", "支付方式"])
        result.paymentMethod = result.paymentMethod?.trimmingCharacters(in: CharacterSet(charactersIn: " >＞›»"))
        result.transactionID = field(["交易单号", "交易订单号", "微信支付订单号"])
        if let id = result.transactionID,
           id.range(of: "^[A-Za-z0-9_-]{8,}$", options: .regularExpression) == nil {
            result.transactionID = nil
        }

        // Explicit actual-payment labels take precedence over product prices and discounts.
        let labelled = field(["实付金额", "实际支付", "付款金额", "支付金额", "支出金额"])
        let amountPattern = #"(?:[¥￥]|人民币\s*|(?:^|\s)-)\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)(?![0-9.])"#
        let candidates: [String]
        if let labelled {
            candidates = matches(#"([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)(?![0-9.])"#, in: labelled)
        } else {
            candidates = lines.flatMap { line -> [String] in
                if ["优惠", "折扣", "红包", "手续费", "余额", "原价"].contains(where: line.contains) { return [] }
                return matches(amountPattern, in: line)
            }
        }
        let amounts = Set(candidates.compactMap { value -> Int? in
            guard let decimal = Decimal(string: value.replacingOccurrences(of: ",", with: ""),
                locale: Locale(identifier: "en_US_POSIX")), decimal > 0, decimal <= 999_999_999 else { return nil }
            return NSDecimalNumber(decimal: decimal * 100).intValue
        })
        if amounts.count == 1 { result.amountInCents = amounts.first }
        else { result.reasons.append(amounts.isEmpty ? "没有识别到明确的支出金额" : "页面出现多个不同金额") }

        let datePattern = #"(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?)"#
        let dateField = field(["支付时间", "付款时间", "交易时间", "创建时间"])
        let dateText = dateField.flatMap { matches(datePattern, in: $0).first }
            ?? matches(datePattern, in: normalized).first
        if let dateText {
            for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = format
                formatter.isLenient = false
                if let date = formatter.date(from: dateText), date <= now.addingTimeInterval(300) {
                    result.date = date
                    break
                }
            }
        }
        if result.date == nil { result.reasons.append("未识别到交易时间，暂用采集时间") }
        if result.merchant == nil { result.reasons.append("未识别到商户") }
        if result.paymentMethod == nil { result.reasons.append("未识别到扣款方式") }
        if !["支付成功", "付款成功", "交易成功", "自动扣款成功", "扣款成功", "支出"].contains(where: text.contains) {
            result.reasons.append("未确认交易成功或支出状态")
        }
        // User's bookkeeping convention: successful Alipay pocket auto-saving counts as spending.
        let isPocketSaving = text.contains("支付宝小荷包") && text.contains("自动攒") && text.contains("扣款成功")
        if text.contains("账户存取") && !isPocketSaving {
            result.reasons.append("账户存取交易，请核对，不要直接当作消费")
        }
        if ["退款", "转账", "提现", "充值", "还款", "交易关闭", "支付失败", "待付款", "收入"].contains(where: text.contains) {
            result.reasons.append("可能是退款、转账、收入或未完成交易，请核对，不要直接当作消费")
        }
        if ["USD", "HKD", "EUR", "美元", "港币", "欧元", "$", "€"].contains(where: text.contains) {
            result.reasons.append("目前只支持人民币，请核对币种")
        }
        let rules: [(String, [String])] = [
            ("餐饮", ["餐厅", "咖啡", "奶茶", "外卖", "面馆", "饭店"]),
            ("交通", ["地铁", "公交", "滴滴", "停车", "加油", "铁路"]),
            ("购物", ["超市", "便利店", "商场", "京东", "淘宝"]),
            ("医疗", ["医院", "药房", "诊所"]),
            ("住房", ["房租", "物业", "水费", "电费"])
        ]
        for (category, words) in rules where words.contains(where: (result.merchant ?? "").contains) {
            result.category = category
            break
        }
        return result
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
