import Foundation

final class UpdateResponseProtocol: URLProtocol {
    static var status = 200
    static var payload = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
struct AppUpdateChecks {
    static func main() async throws {
        func release(_ version: String, _ build: String = "2", url: String = "https://github.com/yxiao-yang/AssetFlow/releases/download/v0.1.1/AssetFlow.ipa") -> AppRelease {
            AppRelease(version: version, build: build, minimumOS: "17.0", notes: "", releaseURL: URL(string: "https://github.com/yxiao-yang/AssetFlow/releases/tag/v0.1.1")!, downloadURL: URL(string: url)!)
        }
        let latest = release("0.1.1")
        try latest.validate()
        precondition(latest.isNewer(than: "0.1.0", build: "99"))
        precondition(latest.isNewer(than: "0.1.1", build: "1"))
        precondition(!latest.isNewer(than: "0.1.1", build: "2"))
        precondition(!latest.isNewer(than: "0.2.0", build: "1"))
        precondition(release("1.10").isNewer(than: "1.9", build: "2"))
        precondition(!release("1.2.0").isNewer(than: "1.2", build: "2"))
        precondition(release("1.2", "10").isNewer(than: "1.2", build: "9"))
        precondition(latest.supports(osVersion: "17.0"))
        precondition(!latest.supports(osVersion: "16.9"))
        for bad in [release("1..2"), release("1.0-beta"), release("1", ""), release("1", url: "https://example.com/App.ipa"), release("1", url: "http://github.com/yxiao-yang/AssetFlow/releases/download/v1/App.ipa")] {
            do { try bad.validate(); fatalError("Invalid release accepted") }
            catch UpdateError.invalidRelease { }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        UpdateResponseProtocol.payload = Data("""
        {"version":"0.1.1","build":"2","minimumOS":"17.0","notes":"更新检查","releaseURL":"https://github.com/yxiao-yang/AssetFlow/releases/tag/v0.1.1","downloadURL":"https://github.com/yxiao-yang/AssetFlow/releases/download/v0.1.1/AssetFlow.ipa"}
        """.utf8)
        let fetched = try await AppUpdateService.latest(session: session)
        precondition(fetched.version == "0.1.1" && fetched.notes == "更新检查")
        for status in [404, 500] {
            UpdateResponseProtocol.status = status
            do { _ = try await AppUpdateService.latest(session: session); fatalError("HTTP error accepted") }
            catch let error as UpdateError {
                switch (status, error) {
                case (404, .unpublished), (500, .unavailable): break
                default: fatalError("Wrong error")
                }
            }
        }
        UpdateResponseProtocol.status = 200
        UpdateResponseProtocol.payload = Data("<html>not a manifest</html>".utf8)
        do { _ = try await AppUpdateService.latest(session: session); fatalError("Invalid JSON accepted") }
        catch UpdateError.invalidRelease { }
        print("App update checks passed: versions, OS compatibility, release links, HTTP and JSON errors")
    }
}
