import SwiftUI

struct AppUpdateView: View {
    @State private var checking = false
    @State private var release: AppRelease?
    @State private var errorMessage: String?
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    private var currentOS: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    private var hasUpdate: Bool { release?.isNewer(than: version, build: build) ?? false }

    var body: some View {
        Form {
            Section {
                LabeledContent("当前版本", value: "\(version) (\(build))")
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Text(checking ? "正在检查…" : "检查更新")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(checking)
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            if let release {
                Section(hasUpdate ? "发现新版本" : "版本状态") {
                    if hasUpdate {
                        LabeledContent("最新版本", value: "\(release.version) (\(release.build))")
                        if !release.notes.isEmpty { Text(release.notes) }
                        if release.supports(osVersion: currentOS) {
                            Link("下载新版 IPA", destination: release.downloadURL)
                            Link("查看发布说明", destination: release.releaseURL)
                        } else {
                            Text("此版本需要 iOS \(release.minimumOS) 或更高版本。")
                        }
                    } else {
                        Text("当前已是最新版本。")
                    }
                }
            }
            Section {
                Link("打开 GitHub 发布页面", destination: AppUpdateService.releasesURL)
            } header: {
                Text("通过 SideStore 更新")
            } footer: {
                Text("下载 IPA 并保存到“文件”，然后在 SideStore 的 My Apps 中点击 + 导入安装。使用原来的 Apple 账号，保留旧应用并覆盖安装；不要删除应用，以免丢失本地账本。刷新签名只延长使用期限，不会下载新版。")
            }
        }
        .navigationTitle("检查更新")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func check() async {
        guard !checking else { return }
        checking = true
        release = nil
        errorMessage = nil
        defer { checking = false }
        do { release = try await AppUpdateService.latest() }
        catch is CancellationError { }
        catch let error as UpdateError { errorMessage = error.localizedDescription }
        catch { errorMessage = UpdateError.unavailable.localizedDescription }
    }
}
