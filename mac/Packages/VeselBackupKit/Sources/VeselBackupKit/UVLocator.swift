import Foundation

/// Finds uv without a shell `PATH`: a GUI app only sees `/usr/bin:/bin:/usr/sbin:/sbin`.
public enum UVLocator {
    public static func candidates(userHome: URL) -> [URL] {
        [
            URL(filePath: "/opt/homebrew/bin/uv"),
            URL(filePath: "/usr/local/bin/uv"),
            userHome.appending(path: ".local/bin/uv"),
            userHome.appending(path: ".cargo/bin/uv"),
        ]
    }

    public static func locate(
        userHome: URL,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        candidates(userHome: userHome).first { isExecutable($0.path) }
    }
}
