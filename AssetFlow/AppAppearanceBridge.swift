import SwiftUI
import UIKit

/// Apply appearance at the window so sheets and their navigation bars share the same setting.
struct AppAppearanceBridge: UIViewRepresentable {
    let appearance: AppAppearance

    func makeUIView(context: Context) -> AppearanceView { AppearanceView() }
    func updateUIView(_ view: AppearanceView, context: Context) { view.appearance = appearance }

    final class AppearanceView: UIView {
        var appearance = AppAppearance.system {
            didSet { applyAppearance() }
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyAppearance()
        }
        private func applyAppearance() {
            let style: UIUserInterfaceStyle
            switch appearance {
            case .light: style = .light
            case .dark: style = .dark
            case .system: style = .unspecified
            }
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}
