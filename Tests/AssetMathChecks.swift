import Foundation

@main
struct AssetMathChecks {
    static func main() {
        let a = UUID(), b = UUID()
        let start = Date(timeIntervalSince1970: 1000)
        let later = Date(timeIntervalSince1970: 2000)
        let engine = AssetBalanceEngine(checkpoints: [
            AssetCheckpoint(accountID: a, cents: 10000, date: start),
            AssetCheckpoint(accountID: b, cents: 5000, date: start)], movements: [
                AssetMovement(accountID: a, cents: -2000, date: later),
                AssetMovement(accountID: b, cents: 2000, date: later)])
        precondition(engine.value(accountID: a, at: later) == 8000)
        precondition(engine.value(accountID: b, at: later) == 7000)
        precondition(engine.total(accountIDs: [a, b], at: later) == 15000)
        precondition(engine.value(accountID: a, at: start.addingTimeInterval(-1)) == nil)
        let checked = AssetBalanceEngine(checkpoints: engine.checkpoints + [AssetCheckpoint(accountID: a, cents: 9000, date: later.addingTimeInterval(1))], movements: engine.movements)
        precondition(checked.value(accountID: a, at: later.addingTimeInterval(2)) == 9000)
        precondition(checked.value(accountID: a, at: later) == 8000)
        precondition(AssetMath.cents("28.50") == 2850)
        precondition(AssetMath.cents("-1") == nil)
        precondition(AssetMath.cents("0", allowZero: false) == nil)
        precondition(AssetMath.positionValue("1000", priceText: "39.50") == 3950000)
        precondition(AssetMath.positionValue("1000", priceText: "0.1234") == 12340)
        precondition(AssetMath.positionValue("1.25", priceText: "0.1234") == 15)
        precondition(AssetMath.stockPrice("0.12345") == nil)
        precondition(AssetMath.quantity("0") == nil)
        precondition(AssetMath.quantity("100000001") == nil)
        precondition(AssetMath.convert(10000, rate: Decimal(string: "0.90")!) == 9000)
        precondition(AssetMath.exchangeRate("0") == nil)
        precondition(AssetMath.exchangeRate("0.9") == Decimal(string: "0.9"))
        print("Asset math: 18 checks passed")
    }
}
