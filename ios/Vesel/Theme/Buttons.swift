import SwiftUI

/// Ink pill: the one main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.onPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
            .padding(.horizontal, Theme.Spacing.s24)
            .background(Theme.Palette.primary, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Glass pill: everything that isn't the main action.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.text)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
            .padding(.horizontal, Theme.Spacing.s24)
            .glassEffect(.regular.interactive(), in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Error-coloured pill for actions that can't be undone.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.onError)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
            .padding(.horizontal, Theme.Spacing.s24)
            .background(Theme.Palette.error, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var veselPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var veselSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var veselDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}
