import Foundation

struct RecognizedPayment {
    var isIncome = false
    var amountInCents: Int?
    var merchant: String?
    var productDescription: String?
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
        let normalized = text.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        let lines = normalized.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var result = RecognizedPayment(rawText: text)
        if text.contains("支付宝") { result.paymentChannel = "支付宝" }
        else if text.contains("微信") || text.contains("零钱") { result.paymentChannel = "微信" }

        let isYuebaoYield = text.contains("余额宝") && text.contains("收益发放")
        result.isIncome = isYuebaoYield
        if isYuebaoYield {
            result.paymentChannel = "支付宝"
            result.category = "理财收益"
        }

        let knownLabels = ["商户名称", "收款方", "收款商户", "商家名称", "交易对方", "对方账户", "收款方全称", "商品说明", "商品", "商户全称", "收单机构", "当前状态", "商户单号", "付款方式", "支付方式", "交易单号", "交易订单号", "微信支付订单号", "支付时间", "付款时间", "交易时间", "创建时间", "理由", "服务详情", "账单分类", "标签"]
        func field(_ labels: [String]) -> String? {
            for (index, line) in lines.enumerated() {
                for label in labels.sorted(by: { $0.count > $1.count }) where line.hasPrefix(label) {
                    let suffix = String(line.dropFirst(label.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: " :：\t"))
                    if !suffix.isEmpty { return suffix }
                    if index + 1 < lines.count,
                       !knownLabels.contains(where: lines[index + 1].hasPrefix) { return lines[index + 1] }
                }
            }
            return nil
        }
        result.merchant = field(["商户全称", "商户名称", "收款方全称", "收款方名称", "收款方", "收款商户", "商家名称", "交易对方", "对方账户"])
        // Alipay detail pages show the display name immediately above the large transaction amount.
        // Keep this separate from the legal payee name (which can be a masked individual).
        if (text.contains("账单详情") || lines.contains("账单")), let amountIndex = lines.firstIndex(where: {
            $0.range(of: #"^\s*[¥￥+\-]?\s*\d+(?:,\d{3})*(?:\.\d{1,2})\s*$"#, options: .regularExpression) != nil
        }), amountIndex > 0 {
            let header = lines[amountIndex - 1].trimmingCharacters(in: CharacterSet(charactersIn: " >＞〉›»"))
            if !["账单详情", "支付宝", "微信支付", "交易成功", "支付成功"].contains(header),
               !knownLabels.contains(where: header.hasPrefix),
               header.rangeOfCharacter(from: .letters) != nil {
                result.merchant = header
            }
        }
        if result.paymentChannel == nil, text.contains("账单管理"),
           field(["付款方式"]) != nil, field(["商品说明", "收款方全称"]) != nil {
            result.paymentChannel = "支付宝"
        }
        if let productIndex = lines.firstIndex(where: { $0.hasPrefix("商品说明") || $0.hasPrefix("商品 ") || $0 == "商品" }) {
            let label = lines[productIndex].hasPrefix("商品说明") ? "商品说明" : "商品"
            var parts = [String(lines[productIndex].dropFirst(label.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :"))]
            for line in lines.dropFirst(productIndex + 1) {
                if knownLabels.contains(where: line.hasPrefix) { break }
                parts.append(line)
            }
            let product = parts.filter { !$0.isEmpty }.joined(separator: " ")
            if !product.isEmpty { result.productDescription = product }
        }
        result.paymentMethod = field(["付款方式", "支付方式"])
        result.paymentMethod = result.paymentMethod?.trimmingCharacters(in: CharacterSet(charactersIn: " >＞›»"))
        if isYuebaoYield {
            result.merchant = "余额宝"
            result.paymentMethod = "余额宝"
        }
        result.transactionID = field(["交易单号", "交易订单号", "微信支付订单号"])
        if let id = result.transactionID,
           id.range(of: "^[A-Za-z0-9_-]{8,}$", options: .regularExpression) == nil {
            result.transactionID = nil
        }

        // Explicit actual-payment labels take precedence over product prices and discounts.
        let labelled = field(isYuebaoYield ? ["收益金额", "到账金额", "收入金额"] : ["实付金额", "实际支付", "付款金额", "支付金额", "支出金额"])
        let amountPattern = #"(?:[¥￥]|人民币\s*|(?:^|\s)-)\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)(?![0-9.])"#
        let candidates: [String]
        if let labelled {
            candidates = matches(#"([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)(?![0-9.])"#, in: labelled)
        } else if isYuebaoYield {
            // Yield bills show an unsigned amount without a currency marker.
            candidates = lines.flatMap { matches(#"^\s*[+¥￥]?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*$"#, in: $0) }
        } else {
            candidates = lines.flatMap { line -> [String] in
                if ["优惠", "折扣", "红包", "手续费", "余额", "原价"].contains(where: line.contains) { return [] }
                // Spaced OCR date separators (2026 - 10 - 07) are not negative amounts.
                if line.range(of: #"\d{4}\s*(?:[-/]|年)\s*\d{1,2}\s*(?:[-/]|月)\s*\d{1,2}"#, options: .regularExpression) != nil { return [] }
                return matches(amountPattern, in: line)
            }
        }
        let amounts = Set(candidates.compactMap { value -> Int? in
            guard let decimal = Decimal(string: value.replacingOccurrences(of: ",", with: ""),
                locale: Locale(identifier: "en_US_POSIX")), decimal > 0, decimal <= 999_999_999 else { return nil }
            return NSDecimalNumber(decimal: decimal * 100).intValue
        })
        if amounts.count == 1 { result.amountInCents = amounts.first }
        else { result.reasons.append(amounts.isEmpty ? "没有识别到明确的交易金额" : "页面出现多个不同金额") }

        // Vision can insert spaces around Chinese date units/colons, or split the time onto a new line.
        let datePattern = #"(\d{4}\s*(?:[-/]|年)\s*\d{1,2}\s*(?:[-/]|月)\s*\d{1,2}(?:\s*日\s*|\s+|T)\d{1,2}\s*:\s*\d{2}(?:\s*:\s*\d{2})?)(?![\d:])"#
        let dateField = field(["支付时间", "付款时间", "交易时间", "创建时间"])
        let dateText = dateField.flatMap { matches(datePattern, in: $0).first }
            ?? matches(datePattern, in: normalized).first
        if let dateText {
            let dateText = dateText
                .replacingOccurrences(of: #"\s*([年月日:/-])\s*"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: "年", with: "-")
                .replacingOccurrences(of: "月", with: "-").replacingOccurrences(of: "日", with: " ")
                .replacingOccurrences(of: "T", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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
        if isYuebaoYield && lines.contains(where: { $0.range(of: #"^\s*-\s*[0-9]+(?:\.[0-9]{1,2})?\s*$"#, options: .regularExpression) != nil }) {
            result.reasons.append("收益页面金额为负，请核对收支类型")
        }
        let exceptional = ["退款", "转账", "提现", "充值", "还款", "交易关闭", "支付失败", "待付款"] + (isYuebaoYield ? [] : ["收入"])
        if exceptional.contains(where: text.contains) {
            result.reasons.append("可能是退款、转账、收入或未完成交易，请核对，不要直接当作消费")
        }
        if ["USD", "HKD", "EUR", "美元", "港币", "欧元", "$", "€"].contains(where: text.contains) {
            result.reasons.append("目前只支持人民币，请核对币种")
        }
        let rules: [(String, [String])] = [
            ("餐饮", ["餐厅", "咖啡", "奶茶", "外卖", "面馆", "饭店", "板面", "零食"]),
            ("交通", ["地铁", "公交", "滴滴", "停车", "加油", "铁路"]),
            ("购物", ["超市", "便利店", "商场", "京东", "淘宝"]),
            ("医疗", ["医院", "药房", "诊所"]),
            ("住房", ["房租", "物业", "水费", "电费"])
        ]
        let categoryContext = (result.productDescription ?? "") + " " + (result.merchant ?? "")
        let contextualRules: [(String, [String])] = [("娱乐", ["足道", "足疗", "SPA", "影院", "电影"])] + rules
        for (category, words) in contextualRules where !result.isIncome && words.contains(where: categoryContext.localizedCaseInsensitiveContains) {
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
