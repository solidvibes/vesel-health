import Foundation

/// The one line `setup.sh --qr-text` prints. Holds the token: never log it, store it or copy it.
public struct PairingCode: Sendable, Equatable, CustomStringConvertible {
    public let text: String
    public let host: String

    public static func parse(_ line: String) -> PairingCode? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: text),
            components.scheme == "vesel-backup",
            components.port == 8443,
            let host = components.host, !host.isEmpty,
            let items = components.queryItems,
            let token = items.first(where: { $0.name == "token" })?.value,
            token.wholeMatch(of: /[A-Za-z0-9_-]{43}/) != nil,
            let pin = items.first(where: { $0.name == "pin" })?.value,
            Data(base64Encoded: pin)?.count == 32
        else { return nil }
        return PairingCode(text: text, host: host)
    }

    public var description: String { "PairingCode(\(host))" }
}
