// HTTP requests (`FX` kind 1), performed off the main thread by URLSession.
//
// The threading model (README, "Effects and threads"):
//
// - Roc runs only on the main thread. The FX operands are decoded there into
//   `HttpRequest`, a plain Swift value; nothing Roc owns leaves the thread.
// - URLSession performs the request. Its delegate runs on `queue`, a private
//   serial OperationQueue. State that queue owns (`transfers`) is touched only
//   there; the main thread's state (`Host.flights`) only on the main thread.
//   The two meet in exactly two places: main hands a task over with
//   `queue.addOperation` (which also resumes it, so no callback can precede
//   the hand-over), and the queue hands a finished, fully encoded result
//   payload (`[UInt8]`) back with `DispatchQueue.main.async`.
// - On the main thread a payload enters Roc only if its id is still tracked
//   by the same task: CANCEL, a timeout and teardown untrack first, so a late
//   completion is dropped before it reaches the engine. It enters through
//   `Host.send`, which queues while a batch is being applied, so a result is
//   always its own turn and never re-enters Roc mid-batch.

import Foundation

// MARK: - Bounds

/// The largest response body this host reads into the page. The protocol
/// sets none for an HTTP text body; past it the request is answered
/// `Network(...)` and the transfer is stopped.
let maxHttpBodyBytes = 16 << 20

/// The engine already caps `timeout_ms` at 600 s; the host caps it again.
let maxHttpTimeoutMs: UInt32 = 600_000

/// Fetch's redirect limit.
let maxHttpRedirects = 20

// MARK: - The request, as plain Swift data

struct HttpRequest {
    let method: String
    let url: String
    let headers: [(String, String)]
    let body: String
    let timeoutMs: UInt32
    let cache: UInt8
    let credentials: UInt8
    let progressMs: UInt32

    /// `method:str url:str n:u32 (name:str value:str)* body:str timeout_ms:u32
    /// cache:u8 credentials:u8 progress_ms:u32`
    init(_ r: inout Reader) {
        method = r.str()
        url = r.str()
        headers = (0..<r.u32()).map { _ in (r.str(), r.str()) }
        body = r.str()
        timeoutMs = min(r.u32(), maxHttpTimeoutMs)
        cache = r.u8()
        credentials = r.u8()
        progressMs = r.u32()
        if !(1...5).contains(cache) { fatal("FX http: cache policy \(cache) is not 1-5") }
        if !(1...2).contains(credentials) { fatal("FX http: credentials policy \(credentials) is not 1-2") }
        if progressMs != 0 && progressMs < 16 { fatal("FX http: progress_ms \(progressMs) is neither 0 nor at least 16") }
    }

    /// The URLRequest, or nil when the URL is not an absolute http(s) URL.
    ///
    /// cache: Default → useProtocolCachePolicy; NoStore → reload ignoring the
    /// cache, and the response is not stored (see `willCacheResponse`);
    /// Reload → reload ignoring the cache (the response is stored); NoCache →
    /// reload ignoring the cache (URLSession has no conditional revalidation
    /// policy, so this is stricter than Fetch's); ForceCache →
    /// returnCacheDataElseLoad.
    ///
    /// credentials: a native app has no page origin, so every request is
    /// cross-origin: SameOrigin sends and stores no cookies
    /// (`httpShouldHandleCookies = false`); Include uses the shared cookie
    /// store.
    func urlRequest() -> URLRequest? {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https", u.host != nil else {
            return nil
        }
        var q = URLRequest(url: u)
        q.httpMethod = method
        for (name, value) in headers { q.addValue(value, forHTTPHeaderField: name) }
        if method != "GET" && method != "HEAD" && !body.isEmpty { q.httpBody = Data(body.utf8) }
        switch cache {
        case 1: q.cachePolicy = .useProtocolCachePolicy
        case 5: q.cachePolicy = .returnCacheDataElseLoad
        default: q.cachePolicy = .reloadIgnoringLocalCacheData
        }
        q.httpShouldHandleCookies = credentials == 2
        // URLSession's own idle timeout; the request's `timeout_ms` is the
        // host's timer, so it answers `Timeout` exactly when asked.
        q.timeoutInterval = Double(maxHttpTimeoutMs) / 1000
        return q
    }
}

struct HttpFailure {
    let message: String
    init(_ message: String) { self.message = message }
    var payload: [UInt8] { [2] + Array(message.utf8) }
}

// MARK: - The main thread's side

/// One request in flight, owned by the main thread.
final class HttpFlight {
    let id: UInt32
    let progressMs: UInt32
    var task: URLSessionTask?
    var timeout: Timer?
    /// The sampler: at most one waiting report and one timer.
    var sample: Timer?
    var latest: [UInt8]?

    init(id: UInt32, progressMs: UInt32) {
        self.id = id
        self.progressMs = progressMs
    }

    /// Stop every timer; the task is cancelled separately.
    func stop() {
        timeout?.invalidate(); timeout = nil
        sample?.invalidate(); sample = nil
        latest = nil
    }
}

extension Host {
    func startHttp(id: UInt32, _ r: inout Reader) {
        let request = HttpRequest(&r)
        let flight = HttpFlight(id: id, progressMs: request.progressMs)
        flights[id] = flight
        trace("HTTP \(id) \(request.method) \(request.url) timeout \(request.timeoutMs) ms cache \(request.cache) credentials \(request.credentials) progress \(request.progressMs) ms")
        guard let q = request.urlRequest() else {
            // Answered one task later, through the same tracked path, so a
            // CANCEL later in this batch still stops it.
            let failure = HttpFailure("not an absolute http(s) URL: \(request.url)")
            DispatchQueue.main.async { self.finishHttp(id: id, task: nil, failure.payload) }
            return
        }
        if request.timeoutMs > 0 {
            let timer = Timer(timeInterval: Double(request.timeoutMs) / 1000, repeats: false) { [weak self] _ in
                self?.expireHttp(id: id)
            }
            RunLoop.main.add(timer, forMode: .common)
            flight.timeout = timer
        }
        flight.task = http.start(id: id, q, noStore: request.cache == 2, progress: request.progressMs > 0)
    }

    /// CANCEL: untrack first, then stop the transfer. Its completion still
    /// arrives on the main thread, finds no flight and is dropped.
    func cancelHttp(id: UInt32) -> Bool {
        guard let flight = flights.removeValue(forKey: id) else { return false }
        flight.stop()
        flight.task?.cancel()
        return true
    }

    func expireHttp(id: UInt32) {
        guard let flight = flights.removeValue(forKey: id) else { return }
        flight.stop()
        flight.task?.cancel()
        trace("HTTP \(id) timed out")
        send(EngineInstance.effectNode, id, [7])
    }

    /// A terminal payload from the transfer queue (or a refused URL), on the
    /// main thread. It enters Roc only if this very task is still tracked.
    func finishHttp(id: UInt32, task: URLSessionTask?, _ payload: [UInt8]) {
        guard let flight = flights[id], flight.task === task else {
            trace("HTTP \(id) completion dropped: no longer tracked")
            return
        }
        flights.removeValue(forKey: id)
        flight.stop()
        trace("HTTP \(id) finished: tag \(payload.first ?? 0), \(payload.count) bytes")
        send(EngineInstance.effectNode, id, payload)
    }

    /// A progress report: kept as the one waiting sample, delivered when the
    /// sampling timer fires; a newer report replaces it in place.
    func progressHttp(id: UInt32, task: URLSessionTask, _ payload: [UInt8]) {
        guard let flight = flights[id], flight.task === task, flight.progressMs > 0 else { return }
        flight.latest = payload
        guard flight.sample == nil else { return }
        let timer = Timer(timeInterval: Double(flight.progressMs) / 1000, repeats: false) { [weak self, weak flight] _ in
            guard let self, let flight, self.flights[id] === flight else { return }
            flight.sample = nil
            if let report = flight.latest {
                flight.latest = nil
                self.send(EngineInstance.effectNode, id, report)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flight.sample = timer
    }

    /// Teardown: nothing in flight is delivered afterwards.
    func cancelAllHttp() {
        for flight in flights.values { flight.stop(); flight.task?.cancel() }
        flights.removeAll()
        http.invalidate()
    }
}

// MARK: - The transfer queue's side

/// The URLSession and its delegate. Everything below `start` runs on
/// `queue`, and reaches the main thread only through `deliver`.
final class HttpTransport: NSObject, URLSessionDataDelegate {
    /// What the queue keeps for one task: plain data, owned by the queue.
    final class Transfer {
        let id: UInt32
        let noStore: Bool
        let progress: Bool
        var body = Data()
        var redirects = 0
        var failure: String?
        var total: UInt64?
        init(id: UInt32, noStore: Bool, progress: Bool) {
            self.id = id
            self.noStore = noStore
            self.progress = progress
        }
    }

    let queue: OperationQueue
    private var transfers: [Int: Transfer] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
    private var live = false

    /// Called on the main thread with a terminal payload or a progress report.
    var finished: (UInt32, URLSessionTask, [UInt8]) -> Void = { _, _, _ in }
    var progressed: (UInt32, URLSessionTask, [UInt8]) -> Void = { _, _, _ in }

    override init() {
        queue = OperationQueue()
        queue.name = "roc-native-macos.http"
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    /// Main thread: make the task and hand it to the queue, which records it
    /// and resumes it.
    func start(id: UInt32, _ request: URLRequest, noStore: Bool, progress: Bool) -> URLSessionTask {
        live = true
        let task = session.dataTask(with: request)
        let transfer = Transfer(id: id, noStore: noStore, progress: progress)
        queue.addOperation {
            self.transfers[task.taskIdentifier] = transfer
            task.resume()
        }
        return task
    }

    /// Main thread, at teardown.
    func invalidate() {
        if live { session.invalidateAndCancel() }
    }

    private func deliver(_ transfer: Transfer, _ task: URLSessionTask, _ payload: [UInt8]) {
        let id = transfer.id
        DispatchQueue.main.async { self.finished(id, task, payload) }
    }

    private func report(_ transfer: Transfer, _ task: URLSessionTask, direction: UInt8, done: UInt64, total: UInt64?) {
        guard transfer.progress else { return }
        var payload: [UInt8] = [26, direction]
        payload.append(u64: done)
        payload.append(total == nil ? 0 : 1)
        payload.append(u64: total ?? 0)
        let id = transfer.id
        DispatchQueue.main.async { self.progressed(id, task, payload) }
    }

    // MARK: URLSession delegate (on `queue`)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let transfer = transfers[dataTask.taskIdentifier] else { completionHandler(.cancel); return }
        if response.expectedContentLength > Int64(maxHttpBodyBytes) {
            transfer.failure = tooLarge
            completionHandler(.cancel)
            return
        }
        let encoded = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding") != nil
        if response.expectedContentLength >= 0 && !encoded { transfer.total = UInt64(response.expectedContentLength) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = transfers[dataTask.taskIdentifier], transfer.failure == nil else { return }
        if transfer.body.count + data.count > maxHttpBodyBytes {
            transfer.failure = tooLarge
            dataTask.cancel()
            return
        }
        transfer.body.append(data)
        report(transfer, dataTask, direction: 2, done: UInt64(transfer.body.count), total: transfer.total)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let transfer = transfers[task.taskIdentifier] else { return }
        report(transfer, task, direction: 1, done: UInt64(max(0, totalBytesSent)), total: totalBytesExpectedToSend >= 0 ? UInt64(totalBytesExpectedToSend) : nil)
    }

    /// Redirects are followed, as Fetch follows them, to http(s) only and at
    /// most `maxHttpRedirects` times; anything else fails the request.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let transfer = transfers[task.taskIdentifier] else { completionHandler(nil); return }
        transfer.redirects += 1
        let scheme = request.url?.scheme?.lowercased()
        if scheme != "http" && scheme != "https" {
            transfer.failure = "redirect to a non-http(s) URL refused"
        } else if transfer.redirects > maxHttpRedirects {
            transfer.failure = "more than \(maxHttpRedirects) redirects"
        } else {
            completionHandler(request)
            return
        }
        completionHandler(nil)
        task.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        let noStore = transfers[dataTask.taskIdentifier]?.noStore ?? true
        completionHandler(noStore ? nil : proposedResponse)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = transfers.removeValue(forKey: task.taskIdentifier) else { return }
        if let failure = transfer.failure {
            deliver(transfer, task, HttpFailure(failure).payload)
        } else if let error {
            // A cancelled task's completion is delivered like any other; the
            // main thread drops it, since CANCEL untracked it first.
            deliver(transfer, task, HttpFailure(error.localizedDescription).payload)
        } else if let response = task.response as? HTTPURLResponse {
            deliver(transfer, task, httpPayload(response, transfer.body))
        } else {
            deliver(transfer, task, HttpFailure("no HTTP response").payload)
        }
    }

    private var tooLarge: String { "response body is larger than the host's \(maxHttpBodyBytes)-byte limit" }
}

/// Result tag 1: `status:u16 n:u32 (name:str value:str)* body:rest`. Names are
/// lowercased and sorted, as Fetch's `Headers` iterates them. The body is
/// decoded as UTF-8 with replacement and a leading BOM dropped, as Fetch's
/// `text()` does, so the engine never sees text that is not UTF-8.
func httpPayload(_ response: HTTPURLResponse, _ body: Data) -> [UInt8] {
    var payload: [UInt8] = [1]
    let status = UInt16(clamping: response.statusCode)
    payload.append(UInt8(status & 0xff))
    payload.append(UInt8(status >> 8))
    var headers: [(String, String)] = []
    for (key, value) in response.allHeaderFields {
        headers.append((String(describing: key).lowercased(), String(describing: value)))
    }
    headers.sort { $0.0 < $1.0 }
    payload.append(u32: UInt32(headers.count))
    for (name, value) in headers {
        payload.append(str: name)
        payload.append(str: value)
    }
    var bytes = body[...]
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
    payload.append(contentsOf: String(decoding: bytes, as: UTF8.self).utf8)
    return payload
}

extension Array where Element == UInt8 {
    mutating func append(u32 v: UInt32) { for i in 0..<4 { append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) } }
    mutating func append(u64 v: UInt64) { for i in 0..<8 { append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(i)))) } }
    mutating func append(str s: String) {
        let utf8 = Array(s.utf8)
        append(u32: UInt32(utf8.count))
        append(contentsOf: utf8)
    }
}
