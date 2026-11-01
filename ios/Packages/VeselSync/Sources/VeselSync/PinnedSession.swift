import CryptoKit
import Foundation
import Security
import Synchronization

/// Sends requests to the Mac mini, and only to it: the server is accepted on its certificate's public-key pin alone
/// (the certificate is self-signed, so iOS's own trust check would turn it down). Anything else is rejected.
public final class PinnedSession: BackupTransport {
    private let delegate: PinCheck
    private let session: URLSession

    public init(pin: String) {
        delegate = PinCheck(pin: pin)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        } catch {
            if delegate.sawOtherKey.withLock({ $0 }) { throw BackupTransportError.wrongCertificate }
            throw error
        }
    }
}

final class PinCheck: NSObject, URLSessionTaskDelegate, Sendable {
    let pin: String
    let sawOtherKey = Mutex(false)

    init(pin: String) {
        self.pin = pin
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else { return (.cancelAuthenticationChallenge, nil) }
        guard Self.matches(trust, pin: pin) else {
            sawOtherKey.withLock { $0 = true }
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }

    /// A redirect would carry the token to another address: never follow one.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async
        -> URLRequest?
    {
        nil
    }

    static func matches(_ trust: SecTrust, pin: String) -> Bool {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return false }
        return Self.pin(of: leaf) == pin
    }

    /// SPKI SHA-256 of an EC P-256 certificate, as standard base64. iOS gives the key as the raw 65-byte point,
    /// so the SubjectPublicKeyInfo header goes in front before hashing.
    static func pin(of certificate: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(certificate),
            let point = SecKeyCopyExternalRepresentation(key, nil) as Data?, point.count == 65
        else { return nil }
        return Data(SHA256.hash(data: p256Header + point)).base64EncodedString()
    }

    private static let p256Header = Data([
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ])
}

public protocol BackupTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum BackupTransportError: Error {
    case wrongCertificate
}
