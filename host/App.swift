// The application: one window hosting one engine instance.

import AppKit

// MARK: - The application

final class AppDelegate: NSObject, NSApplicationDelegate {
    var host: Host?

    func applicationDidFinishLaunching(_ note: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = ProcessInfo.processInfo.processName
        // `ROC_APPEARANCE=dark` (or `light`) draws the app in that appearance
        // whatever the system's, to check both looks.
        switch ProcessInfo.processInfo.environment["ROC_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        let host = Host(window: window)
        self.host = host
        host.start()
        window.center()
        if let script = ProcessInfo.processInfo.environment["ROC_SCRIPT"] {
            // A scripted run sets control values directly, so it never takes
            // keyboard focus: keystrokes meant for another app stay there.
            window.orderFrontRegardless()
            host.run(script: script)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Closing the window or quitting tears the engine down once.
    func applicationWillTerminate(_ note: Notification) { host?.stop() }
}

extension Host {
    /// Teardown: cancel every effect in flight (HTTP transfers, then timers),
    /// then release the engine (`roc_engine_drop`) once. No turn runs after it.
    func stop() {
        guard !halted, !engine.dropped else { return }
        teardownEffects()
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()
        engine.drop()
        trace("DROP")
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        item.submenu = NSMenu()
        item.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(item)
        app.mainMenu = menu
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
