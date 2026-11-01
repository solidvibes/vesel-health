import AppKit
import Darwin
import SwiftUI

@main
struct VeselBackupApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: delegate.controller, loginItem: delegate.loginItem)
        } label: {
            Image(systemName: delegate.controller.state.icon)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: ServerController
    let loginItem = LoginItem()

    override init() {
        umask(0o077)
        controller = ServerController(config: .current())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItem.registerOnFirstLaunch(config: controller.config)
        controller.launch()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await controller.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
