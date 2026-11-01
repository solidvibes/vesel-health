import Foundation
import Testing
import VeselBackupKit

struct UVLocatorTests {
    let home = URL(filePath: "/Users/owner")

    @Test func homebrewComesFirst() {
        let found = UVLocator.locate(userHome: home) { _ in true }
        #expect(found?.path == "/opt/homebrew/bin/uv")
    }

    @Test func fallsBackToTheUserInstalls() {
        let found = UVLocator.locate(userHome: home) { $0 == "/Users/owner/.cargo/bin/uv" }
        #expect(found?.path == "/Users/owner/.cargo/bin/uv")
    }

    @Test func noUvMeansNothing() {
        #expect(UVLocator.locate(userHome: home) { _ in false } == nil)
    }
}
