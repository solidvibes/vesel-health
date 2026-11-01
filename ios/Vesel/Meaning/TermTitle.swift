import SwiftUI
import VeselCore

/// A title that opens its meaning: a 48 pt button, and for VoiceOver "HRV, what it means, button".
/// A new term is a new `Term` case and its glossary entry; the title only needs the term.
struct TermTitle: View {
    let term: Term
    let title: String
    var font: Font = Theme.Typography.heading
    var isHeader = false
    var yours: String?
    var explanations: [(label: String, explanation: Explanation)] = []
    var more: (title: String, action: () -> Void)?
    @Environment(\.showMeaning) private var showMeaning

    var body: some View {
        Button {
            showMeaning(MeaningRequest(term: term, yours: yours, explanations: explanations, more: more))
        } label: {
            Text(title)
                .font(font)
                .foregroundStyle(Theme.Palette.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), what it means")
        .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

/// A term inside running text: a `vesel-term:<term>` link, in the link colour. The app's `openURL` action opens the sheet and never leaves the app.
enum TermLink {
    static let scheme = "vesel-term"

    static func url(_ term: Term) -> URL {
        URL(string: "\(scheme):\(term.rawValue)") ?? URL(fileURLWithPath: "/")
    }

    static func term(of url: URL) -> Term? {
        let prefix = "\(scheme):"
        guard url.absoluteString.hasPrefix(prefix) else { return nil }
        return Term(rawValue: String(url.absoluteString.dropFirst(prefix.count)))
    }

    /// `string` with the first `phrase` in it (any case) made a link to `term`; unchanged when it isn't there.
    static func text(_ string: String, linking phrase: String, to term: Term) -> AttributedString {
        var text = AttributedString(string)
        guard let range = text.range(of: phrase, options: .caseInsensitive) else { return text }
        text[range].link = url(term)
        return text
    }

    /// For the `openURL` environment: a term link opens its meaning and never reaches the system (an unknown term does nothing); anything else goes to the system.
    @MainActor static func action(show: @escaping @MainActor (MeaningRequest) -> Void) -> OpenURLAction {
        OpenURLAction { url in
            guard url.scheme == scheme else { return .systemAction }
            if let term = term(of: url) { show(MeaningRequest(term: term)) }
            return .handled
        }
    }
}
