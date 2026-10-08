import SwiftUI

struct ShortcutSetupView: View {
    @Environment(\.openURL) private var openURL
    @State private var openFailed = false
    var body: some View {
        List {
            Section {
                Label("支付后轻点背面，截图识别入账", systemImage: "camera.viewfinder")
                    .font(.headline)
                Text("在微信或支付宝账单详情页触发。截图和文字识别都在本机完成；信息不完整时进入待确认。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("1 · 创建截图记账") {
                Text("在快捷指令中创建新指令，命名为「截图记账」。")
                Button {
                    openURL(URL(string: "shortcuts://create-shortcut")!) { accepted in
                        openFailed = !accepted
                    }
                } label: {
                    Label("前往快捷指令创建", systemImage: "arrow.up.forward.app")
                }
                Text("此按钮打开系统编辑器；需要按下方步骤添加两个动作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("2 · 按顺序添加两个动作") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("截屏", systemImage: "1.circle")
                    Text("搜索系统动作「截屏」（Take Screenshot）并添加。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Label("识别支付截图并记账", systemImage: "2.circle")
                    Text("搜索「资产流」或「AssetFlow」，添加此动作。将「支付截图」参数设为上一步的「截屏」结果，完成后保存。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                Text("不要选择「每次询问」或手动选照片，否则每次记账都会多一步操作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("3 · 绑定轻点背面") {
                Text("打开 iPhone 设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下或三下 → 选择「截图记账」。")
                Text("推荐轻点三下，减少误触。支持操作按钮的 iPhone 也可以在系统设置中绑定此快捷指令。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("4 · 试记一笔") {
                Text("打开一笔微信或支付宝账单详情，确保金额、商户、支付时间和扣款方式清晰，再轻点背面触发。第一次使用按系统提示授权。")
                Text("返回资产流查看明细或「截图待确认」，核对日期、金额和关联账户。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("遇到问题") {
                Text("找不到记账动作：先打开一次资产流，再退出并重新打开快捷指令。确认手机安装的是更新后的版本。")
                Text("没有自动记录：需要在账单详情页主动触发快捷指令；普通付款不会自行启动识别。")
                Text("App 无法代替你绑定轻点背面，也无法读取支付宝或微信的全部账单。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("截图记账引导")
        .navigationBarTitleDisplayMode(.inline)
        .alert("无法打开快捷指令", isPresented: $openFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请确认已安装 Apple「快捷指令」App，然后手动打开并创建「截图记账」。")
        }
    }
}
