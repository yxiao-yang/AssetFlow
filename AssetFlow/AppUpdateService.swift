import Foundation

struct AppRelease: Decodable, Equatable {
    let version: String
    let build: String
    let minimumOS: String
    let notes: String
    let releaseURL: URL
    let downloadURL: URL

    func validate() throws {
        for value in [version, build, minimumOS] {
            guard !value.isEmpty, value.split(separator: ".", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else {
                throw UpdateError.invalidRelease
            }
        }
        let prefix = "/yxiao-yang/AssetFlow/releases/"
        for url in [releaseURL, downloadURL] {
            guard url.scheme == "https", url.host == "github.com", url.user == nil,
                  url.password == nil, url.port == nil, url.path.hasPrefix(prefix) else {
                throw UpdateError.invalidRelease
            }
        }
        guard downloadURL.path.hasSuffix(".ipa") else { throw UpdateError.invalidRelease }
    }

    func isNewer(than version: String, build: String) -> Bool {
        let order = Self.compare(self.version, version)
        return order == .orderedDescending || (order == .orderedSame && Self.compare(self.build, build) == .orderedDescending)
    }

    func supports(osVersion: String) -> Bool {
        Self.compare(osVersion, minimumOS) != .orderedAscending
    }

    // Missing trailing components are zero: 1.2 and 1.2.0 are the same version.
    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map(String.init)
        let right = rhs.split(separator: ".").map(String.init)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : "0"
            let b = index < right.count ? right[index] : "0"
            let order = a.compare(b, options: .numeric)
            if order != .orderedSame { return order }
        }
        return .orderedSame
    }
}

enum UpdateError: LocalizedError {
    case unpublished, invalidRelease, unavailable
    var errorDescription: String? {
        switch self {
        case .unpublished: "暂未发布可下载的版本，请稍后重试。"
        case .invalidRelease: "版本信息不完整，暂时无法更新。"
        case .unavailable: "暂时无法连接 GitHub，请检查网络后重试。"
        }
    }
}

enum AppUpdateService {
    static let releasesURL = URL(string: "https://github.com/yxiao-yang/AssetFlow/releases")!
    static let manifestURL = URL(string: "https://github.com/yxiao-yang/AssetFlow/releases/latest/download/update.json")!

    static func latest(session: URLSession = .shared) async throws -> AppRelease {
        var request = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.unavailable }
        if http.statusCode == 404 { throw UpdateError.unpublished }
        guard http.statusCode == 200 else { throw UpdateError.unavailable }
        guard data.count <= 128_000 else { throw UpdateError.invalidRelease }
        let release: AppRelease
        do { release = try JSONDecoder().decode(AppRelease.self, from: data) }
        catch { throw UpdateError.invalidRelease }
        try release.validate()
        return release
    }
}
