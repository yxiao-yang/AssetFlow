import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, system
    static let storageKey = "appAppearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "白天模式"
        case .dark: "夜间模式"
        case .system: "跟随系统"
        }
    }
    var icon: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .system: "circle.lefthalf.filled"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

struct SettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    private var selection: Binding<AppAppearance> {
        Binding(get: { AppAppearance(rawValue: appearance) ?? .system },
                set: { appearance = $0.rawValue })
    }
    var body: some View {
        Form {
            Section {
                Picker("外观模式", selection: selection) {
                    ForEach(AppAppearance.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("外观")
            } footer: {
                Text("选择后立即应用于整个 App，并在下次打开时保留。跟随系统会随 iPhone 的外观设置自动切换。")
            }
            Section("记账") {
                NavigationLink { ShortcutSetupView() } label: {
                    Label("截图记账快捷指令", systemImage: "camera.viewfinder")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsToolbar: ToolbarContent {
    @Binding var showing: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showing = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("设置")
        }
    }
}
