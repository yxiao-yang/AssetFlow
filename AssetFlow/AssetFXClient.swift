import Foundation

enum AssetFXClient {
    struct Rate: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Decimal
    }
    static func fetchHKD() async throws -> Rate {
        let url = URL(string: "https://api.frankfurter.dev/v2/rates?base=HKD&quotes=CNY")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rate = try JSONDecoder().decode([Rate].self, from: data).first(where: { $0.base == "HKD" && $0.quote == "CNY" }),
              rate.rate > 0, rate.rate < 10 else { throw URLError(.cannotParseResponse) }
        return rate
    }
}
