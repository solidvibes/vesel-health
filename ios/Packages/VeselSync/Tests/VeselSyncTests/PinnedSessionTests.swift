import Foundation
import Security
import Testing
@testable import VeselSync

struct PinnedSessionTests {
    /// `openssl x509 -inform DER -in Fixtures/test-cert.der -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64`
    static let fixturePin = "Kks/Xwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8="

    func certificate() throws -> SecCertificate {
        let url = try #require(Bundle.module.url(forResource: "test-cert", withExtension: "der", subdirectory: "Fixtures"))
        return try #require(SecCertificateCreateWithData(nil, try Data(contentsOf: url) as CFData))
    }

    func trust() throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(try certificate(), SecPolicyCreateSSL(true, "localhost" as CFString), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test func thePinMatchesOpenSSLs() throws {
        #expect(PinCheck.pin(of: try certificate()) == Self.fixturePin)
    }

    @Test func theServerIsAcceptedOnTheRightPinOnly() throws {
        #expect(PinCheck.matches(try trust(), pin: Self.fixturePin))
        #expect(!PinCheck.matches(try trust(), pin: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
    }

    @Test func theQRIsRead() throws {
        let token = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234"
        let parsed = try #require(BackupConfig.parse("vesel-backup://mini.local:8443?token=\(token)&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D"))
        #expect(parsed.config == BackupConfig(host: "mini.local", port: 8443, pin: Self.fixturePin))
        #expect(parsed.token == token)
        #expect(parsed.config.baseURL.absoluteString == "https://mini.local:8443")
    }

    @Test func localhostIsTakenForTheSimulatorTest() throws {
        let parsed = BackupConfig.parse(
            "vesel-backup://localhost:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D")
        #expect(parsed?.config.host == "localhost")
    }

    @Test func redirectsAreNeverFollowed() async throws {
        let url = URL(string: "https://mini.local:8443/v1/status")!
        let task = URLSession.shared.dataTask(with: url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://example.com/"]))
        let next = await PinCheck(pin: Self.fixturePin).urlSession(
            .shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://example.com/")!))
        #expect(next == nil)
    }

    @Test func aPlusInThePinIsNotASpace() throws {
        let parsed = BackupConfig.parse(
            "vesel-backup://mini.local:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=%2B%2Bs%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D")
        #expect(parsed?.config.pin == "++s/Xwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8=")
    }

    @Test(arguments: [
        "https://mini.local:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D",
        "vesel-backup://mini.local?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D",
        "vesel-backup://mini.local:8443?token=short&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D",
        "vesel-backup://mini.local:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=bm90YXBpbg%3D%3D",
        "vesel-backup://mini.local:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234",
        "vesel-backup://backup.example.com:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D",
        "vesel-backup://203.0.113.7:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D",
        "vesel-backup://.local:8443?token=abcdefghijklmnopqrstuvwxyzABCDEFGHIJ-_01234&pin=Kks%2FXwow0yL7Acs7Cgh2obwaD2FTDtTAMRAJHLXgXJ8%3D",
        "hello",
    ])
    func anythingElseIsNotABackupQR(_ text: String) {
        #expect(BackupConfig.parse(text) == nil)
    }
}
