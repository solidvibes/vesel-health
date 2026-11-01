import SwiftUI

/// A tab's page: blobs behind, a large title (with an optional accessory beside it), then the content.
struct TabScreen<Accessory: View, Content: View>: View {
    let title: String
    let onTitleTap: (() -> Void)?
    let warm: Bool
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        title: String,
        onTitleTap: (() -> Void)? = nil,
        warm: Bool = false,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onTitleTap = onTitleTap
        self.warm = warm
        self.accessory = accessory()
        self.content = content()
    }

    @ViewBuilder private var heading: some View {
        let text = Text(title)
            .font(Theme.Typography.display)
            .foregroundStyle(Theme.Palette.text)
        if let onTitleTap {
            Button(action: onTitleTap) { text.frame(minHeight: Theme.Size.tapTarget, alignment: .leading) }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint("Opens a calendar to pick a day")
        } else {
            text.accessibilityAddTraits(.isHeader)
        }
    }

    var body: some View {
        ZStack {
            BlobBackground(warm: warm)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s24) {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s12) {
                            heading
                            accessory
                        }
                    } else {
                        HStack {
                            heading
                            Spacer()
                            accessory
                        }
                    }
                    content
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.s16)
                .padding(.bottom, Theme.Spacing.s48 * 2)
            }
            TopFade()
        }
    }
}

/// The page colour fading out under the clock, so scrolled content doesn't run into it. Never takes a tap.
struct TopFade: View {
    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [Theme.Palette.background, Theme.Palette.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: proxy.safeAreaInsets.top + Theme.Spacing.s24)
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
