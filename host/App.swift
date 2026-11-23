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
        host.bench?.shown(host)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Closing the window or quitting tears the engine down once.
    func applicationWillTerminate(_ note: Notification) { host?.stop() }

    /// Reload (Cmd-R, or the scripted `reload` step): retire the engine and
    /// mount a fresh one in the same window, as a browser reloads a page.
    /// Local and session storage carry over; everything else starts again.
    /// Under `roc main.roc` the mount is a Roc entry point, so it runs the
    /// newest code hot reloading has loaded (docs/apps.adoc, "Hot reloading").
    @discardableResult
    func reload() -> Host? {
        guard let old = host, !halted else { return nil }
        old.retire()
        let fresh = Host(window: old.window)
        host = fresh
        fresh.start()
        fresh.trace("RELOAD")
        return fresh
    }

    @objc func reloadEngine(_ sender: Any?) { reload() }

    /// Whether this program offers Reload: a bare program (a development
    /// build, or `roc main.roc`'s), not an app bundle a person was given.
    static var reloads: Bool { !Bundle.main.bundlePath.hasSuffix(".app") }
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

    /// Reload's half of teardown: cancel every effect in flight and stop
    /// listening, but leave the engine's state unreleased. After a hot
    /// reload, `roc_engine_drop` runs the newest code, which may describe a
    /// different `Store` than the state was built with; leaking one state
    /// per reload is the safe trade in development.
    func retire() {
        guard !engine.dropped else { return }
        teardownEffects()
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        engine.abandon()
    }
}

@main
struct Main {
    static func main() {
        Bench.launched = Bench.now()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        item.submenu = NSMenu()
        let delegate = AppDelegate()
        if AppDelegate.reloads {
            item.submenu?.addItem(withTitle: "Reload", action: #selector(AppDelegate.reloadEngine(_:)), keyEquivalent: "r").target = delegate
        }
        item.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(item)
        app.mainMenu = menu
        app.delegate = delegate
        app.run()
    }
}
