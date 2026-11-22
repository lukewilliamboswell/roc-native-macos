// Effects the engine requests (`FX`), performed by the host.

import AppKit

extension Host {
    // MARK: Effects

    func effect(id: UInt32, kind: UInt8, _ r: inout Reader) {
        switch kind {
        case 1: // HTTP, performed off the main thread (host/Http.swift)
            startHttp(id: id, &r)
        case 3, 4: // timer, interval
            let ms = r.u32()
            let repeats = kind == 4
            let timer = Timer(timeInterval: Double(ms) / 1000, repeats: repeats) { [weak self] _ in
                guard let self else { return }
                if !repeats { self.timers.removeValue(forKey: id) }
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                var payload: [UInt8] = [5]
                for i in 0..<8 { payload.append(UInt8(truncatingIfNeeded: now >> (8 * Int64(i)))) }
                self.send(EngineInstance.effectNode, id, payload)
            }
            RunLoop.main.add(timer, forMode: .common)
            timers[id] = timer
        case 2, 17: // storage reads: answered one task later
            let key = r.str()
            let value = UserDefaults.standard.string(forKey: key)
            DispatchQueue.main.async {
                self.send(EngineInstance.effectNode, id, value.map { [3] + Array($0.utf8) } ?? [4])
            }
        case 5, 6, 7, 20, 22: // subscriptions this host never fires
            break
        case 16, 18: // media and storage change subscriptions: never fire
            _ = r.str()
        default:
            fatal("effect kind \(kind) is not supported by this host")
        }
    }

    /// CANCEL: stop whatever the id names. Nothing it would have answered
    /// reaches the engine afterwards.
    func cancelEffect(id: UInt32) {
        if let timer = timers.removeValue(forKey: id) { timer.invalidate(); return }
        _ = cancelHttp(id: id)
    }

    /// Teardown: cancel everything in flight, so nothing is delivered after it.
    func teardownEffects() {
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()
        cancelAllHttp()
    }

    func makeHttpTransport() -> HttpTransport {
        let transport = HttpTransport()
        transport.finished = { [weak self] id, task, payload in self?.finishHttp(id: id, task: task, payload) }
        transport.progressed = { [weak self] id, task, payload in self?.progressHttp(id: id, task: task, payload) }
        return transport
    }
}
