import Foundation

/// The Terminal set-up's launch daemon. When it is installed, the app stands aside.
public enum DaemonCheck {
    public static let standardPlist = URL(filePath: "/Library/LaunchDaemons/app.vesel.server.plist")

    public static func isInstalled(plist: URL) -> Bool {
        FileManager.default.fileExists(atPath: plist.path)
    }
}
