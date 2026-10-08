import Foundation

struct PaymentOCRLine {
    let text: String
    let confidence: Float
    let bounds: CGRect
}

enum PaymentOCRText {
    // Vision commonly reports 0.5 for valid numeric fields in Chinese bills.
    // Combine this cutoff with strict amount/date validation rather than rejecting those fields.
    static let reviewConfidenceThreshold: Float = 0.5
    static func assemble(_ lines: [PaymentOCRLine]) -> (text: String, confidence: Float) {
        var rows: [[PaymentOCRLine]] = []
        for line in lines.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let last = rows.last, let anchor = last.first,
               abs(anchor.bounds.midY - line.bounds.midY) <= max(anchor.bounds.height, line.bounds.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        let text = rows.map { $0.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        // Header icons and small footer labels must not veto clearly recognized numeric fields.
        let critical = lines.filter {
            $0.text.range(of: #"^\s*[¥￥+−－–-]?\s*\d+(?:,\d{3})*(?:\.\d{1,2})\s*$"#, options: .regularExpression) != nil ||
            $0.text.range(of: #"\d{4}(?:[-/]|年)\d{1,2}(?:[-/]|月)\d{1,2}日?"#, options: .regularExpression) != nil
        }
        return (text, critical.map(\.confidence).min() ?? 1)
    }
}
