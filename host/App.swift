// The application: one window hosting one engine instance.

import AppKit

// MARK: - The application

/// The app's window. AppKit keeps a window within its screen's visible
/// area when it is shown, so the size a window settles at would depend on
/// the display a spec runs on (a runner's 1024x768 screen with its Dock
/// shortens a tall window). In a spec the window keeps the size the host
/// gives it, within the room the spec's `(screen-size W H)` sets; otherwise
/// it is constrained as any window is, and the host keeps it within its
/// screen (`Host.windowRoom`).
final class HostWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        driven ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var host: Host?

    func applicationDidFinishLaunching(_ note: Notification) {
        let window = HostWindow(
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
        let spec = specText.map(SpecSteps.init)
        if let spec { host.drive(spec) }
        host.start()
        window.center()
        if let spec {
            // As a script does, a spec sets control values directly and
            // never takes keyboard focus.
            window.orderFrontRegardless()
            host.run(spec: spec)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Sized again for the screen it is shown on.
            host.refit()
        }
        window.delegate = self
        host.bench?.shown(host)
    }

    /// The window moved to another screen, or the screens changed: the
    /// window keeps within the room it now has (`Host.windowRoom`).
    /// After the change, between turns: AppKit may report it from inside
    /// a resize the host itself made.
    func windowDidChangeScreen(_ note: Notification) { DispatchQueue.main.async { self.host?.refit() } }
    func applicationDidChangeScreenParameters(_ note: Notification) { DispatchQueue.main.async { self.host?.refit() } }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Closing the window or quitting tears the engine down once.
    func applicationWillTerminate(_ note: Notification) { host?.stop() }

    /// Reload (Cmd-R, or a spec's `(reload)` step): retire the engine and
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
        if let spec = old.specSteps { fresh.drive(spec) }
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
        // Nodes hold their parents strongly: let go, so the old tree is freed.
        root.walk { $0.parent = nil }
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
