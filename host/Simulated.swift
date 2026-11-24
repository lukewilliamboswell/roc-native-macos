// Spec mode's effects: HTTP requests, timers and intervals the app issues
// are held instead of performed, and answered only by the spec's steps
// (`stub-http`, `fail-http`, `run-effect`, `tick-interval`, `fire-timer`),
// on a virtual clock that only `advance-time` moves. Worker jobs and file
// operations stay real: `await-work` waits for them.
//
// Everything here is main-thread state, and an answer enters the engine
// through `Host.send` from a step, never from inside a turn.

import AppKit

/// One effect the app issued in this window, in issue order.
final class HeldEffect {
    enum Kind { case http(HttpRequest), timer(UInt32), interval(UInt32) }
    enum State { case pending, answered, cancelled }
    let number: Int
    let id: UInt32
    let kind: Kind
    /// The virtual time it was issued at, for an HTTP request's timeout.
    let issuedAt: Int64
    var state = State.pending

    init(number: Int, id: UInt32, kind: Kind, issuedAt: Int64) {
        self.number = number
        self.id = id
        self.kind = kind
        self.issuedAt = issuedAt
    }

    var kindName: String {
        switch kind {
        case .http: return "http"
        case .timer: return "timer"
        case .interval: return "interval"
        }
    }

    var stateName: String {
        switch state {
        case .pending: return "pending"
        case .answered: return "answered"
        case .cancelled: return "cancelled"
        }
    }

    var ms: UInt32 {
        switch kind {
        case .http(let request): return request.timeoutMs
        case .timer(let ms), .interval(let ms): return ms
        }
    }
}

/// The held effects of one window, and the answer staged for the next
/// HTTP request `run-effect` answers.
final class HeldEffects {
    var issued: [HeldEffect] = []
    var staged: (url: String, payload: [UInt8])?
}

extension Host {
    /// In spec mode, hold an HTTP request, timer or interval instead of
    /// performing it; whether it was held.
    func hold(id: UInt32, kind: UInt8, _ r: inout Reader) -> Bool {
        guard let held, let steps = specSteps else { return false }
        let what: HeldEffect.Kind
        switch kind {
        case 1: what = .http(HttpRequest(&r))
        case 3: what = .timer(r.u32())
        case 4: what = .interval(r.u32())
        default: return false
        }
        held.issued.append(HeldEffect(number: held.issued.count + 1, id: id, kind: what, issuedAt: steps.clock))
        trace("HELD \(id) as effect #\(held.issued.count)")
        return true
    }

    /// CANCEL of a held effect; whether it was one.
    func cancelHeld(id: UInt32) -> Bool {
        guard let effect = held?.issued.first(where: { $0.id == id && $0.state == .pending }) else { return false }
        effect.state = .cancelled
        return true
    }

    /// The payload of a timer's or an interval's tick at the virtual time.
    func tick(_ effect: HeldEffect, at now: Int64) {
        var payload: [UInt8] = [5]
        for i in 0..<8 { payload.append(UInt8(truncatingIfNeeded: now >> (8 * Int64(i)))) }
        send(EngineInstance.effectNode, effect.id, payload, as: .timer)
    }

    /// The effect steps, or nil for a verb that is not one.
    func performEffect(_ line: SpecSteps.Line) -> Performed? {
        guard let held, let steps = specSteps else { return nil }
        let f = line.fields
        switch line.verb {
        case "stub-http":
            guard f.count >= 4, let status = UInt16(f[1]), let n = Int(f[3]), f.count >= 4 + 2 * n else { return .failed("stub-http is malformed", nil) }
            if held.staged != nil { return .failed("an answer is already staged, and no run-effect has used it", nil) }
            var headers: [(String, String)] = []
            for i in 0..<n { headers.append((f[4 + 2 * i].lowercased(), f[5 + 2 * i])) }
            headers.sort { $0.0 < $1.0 }
            var payload: [UInt8] = [1, UInt8(status & 0xff), UInt8(status >> 8)]
            payload.append(u32: UInt32(headers.count))
            for (name, value) in headers { payload.append(str: name); payload.append(str: value) }
            payload.append(contentsOf: Array(f[2].utf8))
            held.staged = (url: f[0], payload: payload)
        case "fail-http":
            if held.staged != nil { return .failed("an answer is already staged, and no run-effect has used it", nil) }
            held.staged = (url: "", payload: f.first == "timeout" ? [7] : HttpFailure(f.count > 1 ? f[1] : "").payload)
        case "run-effect":
            guard let k = Int(f.first ?? ""), k >= 1, k <= held.issued.count else { return .failed("there is no effect #\(f.first ?? "") yet: the app has issued \(held.issued.count)", nil) }
            let effect = held.issued[k - 1]
            guard effect.state == .pending else { return .failed("effect #\(k), a \(effect.kindName), is \(effect.stateName), not pending", nil) }
            switch effect.kind {
            case .http(let request):
                guard let staged = held.staged else { return .failed("effect #\(k) is an HTTP request, and no stub-http or fail-http has staged its answer", nil) }
                if !staged.url.isEmpty && staged.url != request.url { return .failed("the staged answer is for \(staged.url), and effect #\(k) requests \(request.url)", nil) }
                held.staged = nil
                effect.state = .answered
                send(EngineInstance.effectNode, effect.id, staged.payload)
            case .timer:
                effect.state = .answered
                tick(effect, at: steps.clock)
            case .interval(let ms):
                return .failed("effect #\(k) is an interval; tick it with (tick-interval \(ms))", nil)
            }
        case "tick-interval":
            let ms = UInt32(f.first ?? "") ?? 0
            let live = held.issued.filter { if case .interval(let p) = $0.kind { return p == ms && $0.state == .pending } else { return false } }
            if live.isEmpty { return .failed("no interval of \(ms) ms is live", nil) }
            for effect in live where effect.state == .pending { tick(effect, at: steps.clock) }
        case "fire-timer":
            let ms = UInt32(f.first ?? "") ?? 0
            guard let effect = held.issued.first(where: { if case .timer(let d) = $0.kind { return d == ms && $0.state == .pending } else { return false } }) else {
                return .failed("no timer of \(ms) ms is pending", nil)
            }
            effect.state = .answered
            tick(effect, at: steps.clock)
        case "advance-time":
            steps.clock += Int64(f.first ?? "") ?? 0
            // An HTTP request whose timeout has passed times out, in issue order.
            for effect in held.issued where effect.state == .pending {
                if case .http(let request) = effect.kind, request.timeoutMs > 0, effect.issuedAt + Int64(request.timeoutMs) <= steps.clock {
                    effect.state = .answered
                    send(EngineInstance.effectNode, effect.id, [7])
                }
            }
        case "await-work":
            return .awaitWork
        case "metrics":
            // The work record's bytes, which the tool decodes (Spec.roc).
            let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
            var hex = ""
            for b in engine.workRecord {
                hex.append(digits[Int(b >> 4)])
                hex.append(digits[Int(b & 15)])
            }
            emit("@\(line.k) obs")
            emit("|work \(hex)")
            // The page heap's counts so far (Runtime.swift).
            emit("|heap allocations \(pageHeap.allocations)")
            emit("|heap reallocations \(pageHeap.reallocations)")
            emit("|heap deallocations \(pageHeap.deallocations)")
            emit("|heap allocated_bytes \(pageHeap.bytes)")
        case "effects":
            emit("@\(line.k) obs")
            for effect in held.issued {
                emit("|effect \(effect.number) \(effect.kindName) \(effect.stateName) \(effect.ms)")
                if case .http(let request) = effect.kind {
                    emit("|request \(effect.number) method \(SpecSteps.escape(request.method))")
                    emit("|request \(effect.number) url \(SpecSteps.escape(request.url))")
                    emit("|request \(effect.number) body \(SpecSteps.escape(request.body))")
                    emit("|request \(effect.number) timeout \(request.timeoutMs)")
                }
            }
            emit("|work \(work.jobs.count)")
            emit("|files \(files.jobs.count)")
        default:
            return nil
        }
        return .next
    }

    /// Whether no worker job or file operation is in flight.
    /// (A cancelled job that runs to its end still holds its worker.)
    var workDone: Bool { work.jobs.isEmpty && work.queue.isEmpty && !work.slots.contains { $0.job != nil } && files.jobs.isEmpty }
}
