// The playback session behind `Audio` (platform/Audio.roc): one local file
// played through AVAudioEngine (player → EQ → main mixer → output), with a
// transport, a 10-band EQ and opt-in measurements (AudioAnalysis.swift),
// served as typed ports (Ports.swift). docs/architecture.adoc, "Audio".

import AVFAudio
import AppKit

/// The ports `Audio.ports` declares, as this host serves them.
enum AudioPorts {
    static let command = "roc-native-macos/audio/command"
    static let events = "roc-native-macos/audio/events"
    static let status = "roc-native-macos/audio/status"
    static let analysis = "roc-native-macos/audio/analysis"
    /// How many events wait while the app is busy before more are refused.
    static let eventBound: UInt32 = 64
}

/// The transport's state, as `Audio.State` names it.
enum AudioState: String {
    case idle = "Idle", loading = "Loading", stopped = "Stopped", playing = "Playing", paused = "Paused", ended = "Ended"
}

final class AudioService: PortService {
    weak var host: Host?

    // MARK: Settings

    /// The EQ's band centres in Hz (an ISO octave graphic EQ).
    static let centres: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    /// Each band's width, in octaves.
    static let bandwidth: Float = 1
    /// Band gains are clamped to ±12 dB, the preamp to -24…+12 dB, and the
    /// volume to 0…1. A value that is not a number leaves the setting as it was.
    static let gainRange: ClosedRange<Float> = -12...12
    static let preampRange: ClosedRange<Float> = -24...12
    /// A band whose centre is above this share of the source's sample rate
    /// is bypassed (it keeps its gain, reported, for a later source).
    static let usableShare: Float = 0.45
    /// The manual clock's output format, for `audio:manual`.
    static let manualRate: Double = 48000
    static let manualChunk: AVAudioFrameCount = 1024

    // MARK: State (main thread only)

    /// `audio:manual`: render offline, advanced only by `audio:render`.
    var manual = false
    private var engine: AVAudioEngine?
    private var player = AVAudioPlayerNode()
    private var eq = AudioService.makeEq()
    private var connected: AVAudioFormat?
    private var file: AVAudioFile?
    /// The session's own copy of the file's entry: the backing stays
    /// reachable while it is scheduled, whatever Roc does with the handle.
    private var entry: FileEntry?
    private(set) var track: UInt64 = 0
    /// Every load, seek, stop and restart is a new generation; a completion
    /// or a measurement of an older one is dropped.
    private(set) var generation: UInt64 = 0
    private(set) var state: AudioState = .idle
    /// Where playback stands when it is not playing, in source frames.
    private var cursor: Int64 = 0
    /// The frame the current schedule starts at.
    private var segmentStart: Int64 = 0
    private var wantsPlay = false
    private var endedGeneration: UInt64 = .max
    private(set) var volume: Float = 1
    private(set) var gains = [Float](repeating: 0, count: AudioService.centres.count)
    private(set) var preamp: Float = 0
    private(set) var bypass = false

    // Subscriptions: events, status (with its interval) and analysis.
    private var eventSubs: [UInt32] = []
    private var statusSubs: [UInt32: UInt32] = [:]
    private var analysisSubs: [UInt32: UInt32] = [:]
    private var lastSent: [UInt32: UInt64] = [:]
    private var statusTimer: Timer?
    private var analysisTimer: Timer?
    /// `AudioSurfaceSources` sampled recently: they keep the analysis on.
    var nativeLease: Double = 0
    let analysis = AudioAnalysis()
    private var tapped = false
    /// The output of the last `audio:render`, channel 0, for `audio:tone`.
    private(set) var rendered: [Float] = []
    /// Ended events sent, for `audio:status`.
    private(set) var endings = 0

    init(host: Host) {
        self.host = host
        AVTiming.shared.audio = self
    }

    /// A flat 10-band EQ of one-octave parametric bands at `centres`.
    static func makeEq() -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: AudioService.centres.count)
        for (i, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = AudioService.centres[i]
            band.bandwidth = AudioService.bandwidth
            band.gain = 0
            band.bypass = false
        }
        eq.globalGain = 0
        return eq
    }

    var declarations: [PortDeclaration] {
        [.command(AudioPorts.command), .every(AudioPorts.events, AudioPorts.eventBound), .latest(AudioPorts.status), .latest(AudioPorts.analysis)]
    }

    private var ports: PortHost? { host?.ports }

    // MARK: Commands

    func command(port: String, _ message: PortMessage) {
        guard let value = Json.parse(message.json), let (name, payload) = value.tag else { fatal("audio: a command that is not a tag: \(message.json)") }
        host?.trace("audio: \(name)")
        switch name {
        case "Load":
            guard let p = payload, let t = p["track"]?.uint64, let i = p["file"]?.fileIndex, i < message.files.count
            else { fatal("audio: Load needs a track and a file: \(message.json)") }
            let f = message.files[i]
            guard let host else { return }
            let entry = host.resolve(f.token)
            if f.start != 0 || f.len != entry.size {
                refuse(track: t, "Unsupported", "a byte range of a file; give the whole file")
                return
            }
            load(track: t, path: entry.path, entry: entry)
        case "LoadAsset":
            // A file the app ships in assets/, found as an asset image is;
            // a name outside assets/, or nothing there, fails the load.
            guard let p = payload, let t = p["track"]?.uint64, case .string(let name)? = p["path"]
            else { fatal("audio: LoadAsset needs a track and a path: \(message.json)") }
            switch Assets.lookup(name) {
            case .found(let path): load(track: t, path: path, entry: nil)
            case .missing(let why): refuse(track: t, "Unsupported", why)
            }
        case "Play": play()
        case "Resume": if state == .paused { play() }
        case "Pause": pause()
        case "Stop": stop()
        case "Seek":
            guard let ms = payload?.uint64 else { fatal("audio: Seek needs milliseconds: \(message.json)") }
            seek(ms: ms)
        case "Volume":
            guard let v = payload?.double else { fatal("audio: Volume needs a number: \(message.json)") }
            if !v.isNaN { volume = min(max(Float(v), 0), 1) }
            engine?.mainMixerNode.outputVolume = volume
            publishStatus()
        case "Gain":
            guard let b = payload?["band"]?.uint64, let db = payload?["db"]?.double else { fatal("audio: Gain needs a band and dB: \(message.json)") }
            guard b < UInt64(gains.count) else { fatal("audio: Gain names band \(b); the EQ has bands 0 to \(gains.count - 1)") }
            if !db.isNaN { gains[Int(b)] = min(max(Float(db), AudioService.gainRange.lowerBound), AudioService.gainRange.upperBound) }
            applyEq()
        case "Preamp":
            guard let db = payload?.double else { fatal("audio: Preamp needs dB: \(message.json)") }
            if !db.isNaN { preamp = min(max(Float(db), AudioService.preampRange.lowerBound), AudioService.preampRange.upperBound) }
            applyEq()
        case "Bypass":
            guard case .bool(let on)? = payload else { fatal("audio: Bypass needs a Bool: \(message.json)") }
            bypass = on
            applyEq()
        case "Flat":
            gains = gains.map { _ in 0 }
            preamp = 0
            applyEq()
        case "VisualOffset":
            guard let ms = payload?.double else { fatal("audio: VisualOffset needs milliseconds: \(message.json)") }
            if !ms.isNaN { visualOffsetMs = min(max(ms, AudioService.visualOffsetRange.lowerBound), AudioService.visualOffsetRange.upperBound) }
            AudioSurfaceSources.changed()
            publishStatus()
        case "Close": close()
        default: fatal("audio: unknown command \(name)")
        }
    }

    /// The EQ as set: a change takes effect at the next render and never
    /// touches the schedule, so the playhead stays where it is.
    private func applyEq() {
        let rate = Float(file?.processingFormat.sampleRate ?? 44100)
        for (i, band) in eq.bands.enumerated() {
            band.gain = gains[i]
            band.bypass = AudioService.centres[i] > AudioService.usableShare * rate
        }
        eq.globalGain = preamp
        eq.bypass = bypass
        publishStatus()
    }

    /// A load that cannot start: the source is let go of, as a new load
    /// does, and it fails with `tag` and `why`.
    private func refuse(track t: UInt64, _ tag: String, _ why: String) {
        newGeneration()
        player.stop()
        track = t
        file = nil
        entry = nil
        cursor = 0
        wantsPlay = false
        pendingMs = nil
        state = .idle
        publishStatus()
        event("Failed", fields: [("track", u64(t)), ("error", JsonText.tag(tag, JsonText.string(why)))])
    }

    /// Open the file at `path` as the new source: a file the app was given
    /// (`e`, held while it is the source), or an asset (no entry).
    private func load(track t: UInt64, path: String, entry e: FileEntry?) {
        newGeneration()
        player.stop()
        track = t
        file = nil
        entry = nil
        cursor = 0
        wantsPlay = false
        pendingMs = nil
        let gen = generation
        state = .loading
        entry = e
        anchor()
        publishStatus()
        guard let url = URL(string: "file://" + AudioService.percentEncoded(path)), let queue = host?.files.queue else { fatal("audio: no file URL for \(path)") }
        // Opening reads the header: off the main thread, on the file jobs' queue.
        queue.async {
            var opened: AVAudioFile?
            var failure = (tag: "Corrupt", why: "the file holds no audio")
            do { opened = try AVAudioFile(forReading: url) } catch { failure = AudioService.openFailure(error) }
            DispatchQueue.main.async { [weak self] in self?.loaded(gen, opened, failure) }
        }
    }

    /// The opened file, if its load is still the current one.
    private func loaded(_ gen: UInt64, _ opened: AVAudioFile?, _ failure: (tag: String, why: String)) {
        guard gen == generation, state == .loading, let host, !host.engine.dropped else { return }
        guard let f = opened, f.length > 0 else {
            state = .idle
            entry = nil
            publishStatus()
            event("Failed", fields: [("track", u64(track)), ("error", JsonText.tag(failure.tag, JsonText.string(failure.why)))])
            return
        }
        do { try prepare(f.processingFormat) } catch {
            state = .idle
            entry = nil
            publishStatus()
            event("Failed", fields: [("track", u64(track)), ("error", JsonText.tag("Output", JsonText.string(AudioService.describe(error))))])
            return
        }
        file = f
        applyEq()
        let format = f.processingFormat
        event("Loaded", fields: [("track", u64(track)), ("duration_ms", u64(ms(f.length))), ("frames", u64(UInt64(f.length))), ("sample_rate", "\(Int(format.sampleRate))"), ("channels", "\(format.channelCount)")])
        cursor = pendingMs.map { min(Int64((Double($0) * format.sampleRate / 1000).rounded(.down)), f.length) } ?? 0
        pendingMs = nil
        state = .stopped
        if wantsPlay { play() } else { publishStatus() }
    }

    /// The engine running with the player and the EQ connected at the
    /// source's format (the EQ runs at the source's rate).
    ///
    /// A source of another format gets a new engine, player and EQ (with the
    /// same settings): its node times start at zero again, and nothing the
    /// old graph scheduled or rendered can reach the new one.
    private func prepare(_ format: AVAudioFormat) throws {
        if let old = self.engine, connected != format {
            removeTap()
            old.stop()
            self.engine = nil
            player = AVAudioPlayerNode()
            eq = AudioService.makeEq()
        }
        let engine: AVAudioEngine
        if let e = self.engine {
            engine = e
        } else {
            engine = AVAudioEngine()
            engine.attach(player)
            engine.attach(eq)
            if manual {
                guard let out = AVAudioFormat(standardFormatWithSampleRate: AudioService.manualRate, channels: 2) else { fatal("audio: no manual rendering format") }
                try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: AudioService.manualChunk)
            } else {
                AudioOutput.choose(for: engine)
            }
            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
            connected = format
            self.engine = engine
        }
        engine.mainMixerNode.outputVolume = volume
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        measureOutput()
        updateAnalysis()
    }

    private func play() {
        switch state {
        case .loading: wantsPlay = true
        case .stopped, .ended, .paused:
            guard let f = file else { return }
            if state == .ended { cursor = 0 }
            if state != .paused {
                newGeneration()
                schedule(from: cursor)
            }
            if cursor >= f.length { finish(generation); return }
            ensureRunning()
            startPlayer(from: cursor)
            state = .playing
            anchor()
            publishStatus()
            startTimers()
        case .playing, .idle: break
        }
    }

    private func pause() {
        if state == .loading { wantsPlay = false; return }
        guard state == .playing else { return }
        cursor = frame()
        player.pause()
        state = .paused
        anchor()
        publishStatus()
    }

    /// Stop: the schedule is released and the cursor goes back to the start.
    private func stop() {
        if state == .idle { return }
        newGeneration()
        player.stop()
        cursor = 0
        wantsPlay = false
        if state != .loading { state = file == nil ? .idle : .stopped }
        anchor()
        publishStatus()
    }

    /// Close: stop, and let go of the file and the engine.
    private func close() {
        newGeneration()
        player.stop()
        removeTap()
        engine?.stop()
        file = nil
        entry = nil
        cursor = 0
        wantsPlay = false
        state = .idle
        anchor()
        publishStatus()
    }

    /// Seek to `ms`, clamped to the source's duration. Playing keeps
    /// playing, paused stays paused, and a stopped or ended transport stays
    /// stopped there.
    private func seek(ms: UInt64) {
        let length = file?.length ?? 0
        let target = min(Int64((Double(ms) * sampleRate / 1000).rounded(.down)), length)
        switch state {
        case .idle: return
        case .loading:
            pendingMs = ms
            return
        case .playing:
            newGeneration()
            schedule(from: target)
            if target >= length { finish(generation); return }
            startPlayer(from: target)
        case .paused:
            newGeneration()
            schedule(from: target)
        case .stopped, .ended:
            newGeneration()
            state = .stopped
        }
        cursor = target
        anchor()
        publishStatus()
    }
    /// A seek made while the source was loading, applied once it is open.
    private var pendingMs: UInt64?

    /// Replace the schedule with the source from `start` to its end.
    private func schedule(from start: Int64) {
        player.stop()
        guard let f = file else { return }
        segmentStart = start
        cursor = start
        let frames = f.length - start
        guard frames > 0 else { return }
        let gen = generation
        player.scheduleSegment(f, startingFrame: start, frameCount: AVAudioFrameCount(frames), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // On an AVAudioEngine thread: hop to the main thread, where the
            // generation decides whether this completion still counts.
            DispatchQueue.main.async { self?.finish(gen) }
        }
    }

    /// Natural completion, accepted once, for the current generation only.
    private func finish(_ gen: UInt64) {
        guard gen == generation, endedGeneration != gen, state == .playing || state == .paused || state == .stopped, let f = file else { return }
        endedGeneration = gen
        player.stop()
        cursor = f.length
        state = .ended
        anchor()
        endings += 1
        event("Ended", fields: [("track", u64(track))])
        publishStatus()
    }

    private func newGeneration() {
        generation += 1
        endedGeneration = .max
    }

    private func ensureRunning() {
        guard let engine, !engine.isRunning else { return }
        do { engine.prepare(); try engine.start() } catch {
            event("Failed", fields: [("track", u64(track)), ("error", JsonText.tag("Output", JsonText.string(AudioService.describe(error))))])
        }
    }

    // MARK: The timeline

    /// The source frame playback has rendered to: while playing, the
    /// player's own timeline (which pauses hold) after the segment start.
    func frame() -> Int64 {
        guard state == .playing, let f = file else { return cursor }
        guard let nt = player.lastRenderTime, nt.isSampleTimeValid || nt.isHostTimeValid, let pt = player.playerTime(forNodeTime: nt) else { return segmentStart }
        return min(max(segmentStart + pt.sampleTime, segmentStart), f.length)
    }

    func ms(_ frames: Int64) -> UInt64 {
        guard let rate = file?.processingFormat.sampleRate, rate > 0 else { return 0 }
        return UInt64((Double(max(frames, 0)) * 1000 / rate).rounded(.down))
    }

    var sampleRate: Double { file?.processingFormat.sampleRate ?? 0 }
    var durationFrames: Int64 { file?.length ?? 0 }

    /// How long after it is rendered a sample is heard, in seconds: the
    /// output's presentation latency (0 under the manual clock).
    ///
    /// AVAudioEngine's `outputNode.presentationLatency` counts the device's
    /// own latency alone (1.5 ms on an M2's speakers), so this is the larger
    /// of it and Core Audio's device latency plus its first output stream's
    /// latency (21.2 ms there): the time from an IO cycle's output time
    /// stamp to the sound leaving the device. The safety offset and the IO
    /// buffer come before the time stamp, so neither is added.
    var outputLatency: Double { manual ? 0 : max(engine?.outputNode.presentationLatency ?? 0, deviceLatency) }
    /// The output device's latency plus its stream's, in seconds, as Core
    /// Audio last reported it (`measureOutput`).
    private var deviceLatency = 0.0

    /// Ask Core Audio for the output device's latency again: when the
    /// engine starts, and when its configuration changes (another device).
    private func measureOutput() {
        guard let engine, !manual else { deviceLatency = 0; return }
        let l = AudioOutput.latency(AudioOutput.device(of: engine))
        deviceLatency = l.rate > 0 ? Double(l.device + l.stream) / l.rate : 0
    }

    /// Where the player last started: the node time and the source frame.
    private var started: (node: Int64, source: Int64)?

    /// How far ahead of the last render the player starts, in its frames:
    /// a render cycle or more under a real output, so the start time is
    /// still ahead when the next cycle renders; none under the manual clock.
    static let startLead: Int64 = 2048

    /// Start (or resume) the player at a known node time, so every rendered
    /// frame has a known place on the source timeline.
    private func startPlayer(from source: Int64) {
        if let now = renderedNodeFrames(), sampleRate > 0 {
            let at = now + (manual ? 0 : AudioService.startLead)
            started = (at, source)
            player.play(at: AVAudioTime(sampleTime: at, atRate: sampleRate))
        } else {
            started = nil
            player.play()
        }
    }

    /// The anchor the tap measures against.
    private func anchor() {
        var a = AudioAnchor()
        a.generation = generation
        a.playing = state == .playing && started != nil
        a.startNode = started?.node ?? 0
        a.startSource = started?.source ?? 0
        a.sampleRate = sampleRate
        analysis.setAnchor(a)
        // Every transport change comes through here: on-demand surfaces
        // that read the measurements redraw.
        AudioSurfaceSources.changed()
    }

    /// The player's render time so far, in its frames (the source's rate,
    /// as the EQ's after it): under the manual clock, what has been rendered
    /// at the output's rate, converted (exact, since each source has an
    /// engine of its own whose times start at zero).
    private func renderedNodeFrames() -> Int64? {
        guard let engine, engine.isRunning else { return nil }
        if manual, sampleRate > 0 {
            return Int64((Double(engine.manualRenderingSampleTime) * sampleRate / AudioService.manualRate).rounded(.down))
        }
        guard let t = player.lastRenderTime, t.isSampleTimeValid else { return nil }
        return t.sampleTime
    }

    // MARK: Analysis: on while anyone consumes it

    /// Whether a consumer holds the analysis: a Roc subscription, or a
    /// native source sampled within the last second. Under the manual clock,
    /// whose time only the script moves, only a subscription holds it.
    private var consumed: Bool { !analysisSubs.isEmpty || (!manual && Bench.now() - nativeLease < 1) }

    func updateAnalysis() {
        if consumed, let engine {
            if !analysis.isRunning { analysis.start() }
            if !tapped {
                _ = engine
                let channels = Int(eq.outputFormat(forBus: 0).channelCount)
                guard analysis.attach(to: eq.audioUnit, channels: channels) else { fatal("audio: the EQ's audio unit refused the measuring tap's render notification") }
                tapped = true
                anchor()
            }
        } else {
            removeTap()
            analysis.stop()
        }
    }

    private func removeTap() {
        if tapped { analysis.detach(from: eq.audioUnit); tapped = false }
    }

    /// A native consumer sampled the measurements.
    func sampledNatively() {
        if manual { return }
        let was = consumed
        nativeLease = Bench.now()
        if !was { updateAnalysis() }
        if leaseTimer == nil, !manual {
            leaseTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                if !self.consumed { self.leaseTimer?.invalidate(); self.leaseTimer = nil; self.updateAnalysis() }
            }
            RunLoop.main.add(leaseTimer!, forMode: .common)
        }
    }
    private var leaseTimer: Timer?

    /// How far before the frame being heard the chosen snapshot's window
    /// centre sits: half a window, so the window ends where the listener
    /// is. A meter shows what has been heard; a window centred on the
    /// playhead holds the next 21 ms too, so a click would flash before it
    /// sounds.
    static let alignment = Double(AudioAnalysis.window / 2)

    /// The source frame heard at `time` (`systemUptime` seconds), less the
    /// visual offset: the newest render stamp's node frame, moved on at the
    /// node's rate by the time from its output time stamp to `time` less the
    /// output latency, on the source timeline. Without a stamp to go by
    /// (the manual clock, before the first render, paused or stopped) it
    /// is where playback has rendered to.
    func heardFrame(at time: Double) -> Double {
        guard state == .playing, !manual, let s = started, sampleRate > 0, let st = analysis.latestStamp(), st.host != 0 else { return Double(frame()) }
        let heard = time - outputLatency - visualOffsetMs / 1000
        let node = Double(st.node) + (heard - AVAudioTime.seconds(forHostTime: st.host)) * sampleRate
        return max(Double(s.source), Double(s.source) + node - Double(s.node))
    }

    /// The snapshot of the current generation whose window ends nearest
    /// the frame heard at `time`.
    func audibleSnapshot(at time: Double) -> AudioSnapshot? {
        let history = analysis.snapshots().filter { $0.generation == generation }
        guard !history.isEmpty else { return nil }
        let want = heardFrame(at: time) - AudioService.alignment
        let chosen = history.min { abs(Double($0.centreFrame) - want) < abs(Double($1.centreFrame) - want) }
        drawnCentre = chosen?.centreFrame ?? -1
        drawnShort = chosen.map { (want - Double($0.centreFrame)) * 1000 / sampleRate } ?? 0
        return chosen
    }

    /// The visual offset (`VisualOffset`), in milliseconds: how much later
    /// than the sound the measurements a picture reads are shown.
    private(set) var visualOffsetMs: Double = 0
    static let visualOffsetRange: ClosedRange<Double> = -500...500

    /// When each click found since `AVTiming.mark` was heard, in
    /// `systemUptime` seconds (`audibleTimes`).
    func audibleClicks() -> [Double] { audibleTimes(analysis.clickOnsets()).compactMap { $0 } }

    /// When each source frame of the current start was heard, in
    /// `systemUptime` seconds: the host time of the render stamp holding its
    /// node frame, plus its place in that buffer at the node's rate, plus
    /// the output's presentation latency; nil without a stamp for it.
    func audibleTimes(_ frames: [Int64]) -> [Double?] {
        guard let s = started, sampleRate > 0 else { return frames.map { _ in nil } }
        let stamps = analysis.renderStamps().filter { $0.host != 0 }
        return frames.map { c in
            let node = s.node + (c - s.source)
            guard let st = stamps.last(where: { $0.node <= node && node < $0.node + Int64($0.frames) }) else { return nil }
            return AVAudioTime.seconds(forHostTime: st.host) + Double(node - st.node) / sampleRate + outputLatency
        }
    }

    /// The output device, for the timing report: its name, its
    /// presentation latency as AVAudioEngine reports it, and Core Audio's parts.
    func outputReport() -> String {
        guard let engine, !manual else { return "manual clock" }
        let d = AudioOutput.device(of: engine)
        let l = AudioOutput.latency(d)
        let rate = l.rate > 0 ? l.rate : 48000
        func ms(_ frames: UInt32) -> String { Host.decimal(Double(frames) * 1000 / rate, 1) }
        return "\"\(AudioOutput.name(d))\" compensated \(Host.decimal(outputLatency * 1000, 1)) ms; presentationLatency \(Host.decimal(engine.outputNode.presentationLatency * 1000, 1)) ms; device \(ms(l.device)) + safety \(ms(l.safety)) + stream \(ms(l.stream)) ms, buffer \(l.buffer) frames (\(ms(l.buffer)) ms) at \(Int(rate)) Hz"
    }

    /// The window centre of the snapshot a surface last drew, in source
    /// frames (-1 for none), for AVTiming.
    private(set) var drawnCentre: Int64 = -1
    /// How far before the window wanted the drawn one was, in ms: more
    /// than half a hop when the measurement wanted was not made yet.
    private(set) var drawnShort = 0.0

    // MARK: Subscriptions

    func subscribe(id: UInt32, port: String, _ message: PortMessage) {
        let every = Json.parse(message.json)?["every_ms"]?.uint64.map { UInt32(min(max($0, 16), 60_000)) } ?? 200
        switch port {
        case AudioPorts.events: eventSubs.append(id)
        case AudioPorts.status:
            statusSubs[id] = every
            ports?.emit(id, json: statusJson())
            startTimers()
        case AudioPorts.analysis:
            analysisSubs[id] = every
            updateAnalysis()
            startTimers()
        default: fatal("audio: no subscription \(port)")
        }
    }

    func unsubscribe(id: UInt32) {
        eventSubs.removeAll { $0 == id }
        statusSubs.removeValue(forKey: id)
        if analysisSubs.removeValue(forKey: id) != nil { updateAnalysis() }
        lastSent.removeValue(forKey: id)
        startTimers()
    }

    /// Status while playing and snapshots while measured, each at the
    /// smallest interval its subscribers asked for. The manual clock has no
    /// timers: `audio:render` publishes after each render instead.
    private func startTimers() {
        statusTimer?.invalidate(); statusTimer = nil
        analysisTimer?.invalidate(); analysisTimer = nil
        if manual || state != .playing { return }
        if let every = statusSubs.values.min() {
            statusTimer = Timer(timeInterval: Double(every) / 1000, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(statusTimer!, forMode: .common)
        }
        if let every = analysisSubs.values.min() {
            analysisTimer = Timer(timeInterval: Double(every) / 1000, repeats: true) { [weak self] _ in self?.publishSnapshot() }
            RunLoop.main.add(analysisTimer!, forMode: .common)
        }
    }

    private func tick() {
        if state != .playing { startTimers(); return }
        publishStatus()
    }

    func publishStatus() {
        guard let ports else { return }
        if state != .playing { statusTimer?.invalidate(); statusTimer = nil; analysisTimer?.invalidate(); analysisTimer = nil }
        let json = statusJson()
        for id in statusSubs.keys.sorted() { ports.emit(id, json: json) }
    }

    /// The newest snapshot of the current generation, to each analysis
    /// subscriber that has not had it: a slow app gets the latest only.
    func publishSnapshot() {
        guard let ports, let snap = audibleSnapshot(at: Bench.now()) else { return }
        for id in analysisSubs.keys.sorted() where lastSent[id] != snap.seq {
            lastSent[id] = snap.seq
            ports.emit(id, json: snapshotJson(snap))
        }
    }

    private func event(_ name: String, fields: [(String, String)]) {
        guard let ports else { return }
        let json = JsonText.tag(name, JsonText.object(fields))
        for id in eventSubs where !ports.emit(id, json: json) {
            host?.say("audio: an event for subscription \(id) was refused: \(AudioPorts.eventBound) are waiting")
        }
    }

    func statusJson() -> String {
        let eqJson = JsonText.object([
            ("bypass", bypass ? "true" : "false"),
            ("preamp_db", JsonText.number(preamp)),
            ("gains_db", JsonText.array(gains.map { JsonText.number($0) })),
        ])
        return JsonText.object([
            ("track", u64(track)),
            ("generation", u64(generation)),
            ("state", JsonText.string(state.rawValue)),
            ("position_ms", u64(ms(frame()))),
            ("duration_ms", u64(ms(durationFrames))),
            ("volume", JsonText.number(volume)),
            ("latency_ms", JsonText.number(Float(outputLatency * 1000))),
            ("visual_offset_ms", JsonText.number(Float(visualOffsetMs))),
            ("output", outputJson()),
            ("eq", eqJson),
        ])
    }

    /// The output device's name and UID (`AudioOutput`), empty under the
    /// manual clock or before the engine starts. Read when the status is
    /// sent, so a change of device shows in the next one.
    private func outputJson() -> String {
        var name = "", uid = ""
        if let engine, !manual {
            let d = AudioOutput.device(of: engine)
            name = AudioOutput.name(d)
            uid = AudioOutput.uid(d)
        }
        return JsonText.object([("name", JsonText.string(name)), ("uid", JsonText.string(uid))])
    }

    func snapshotJson(_ s: AudioSnapshot) -> String {
        JsonText.object([
            ("track", u64(track)),
            ("at_ms", JsonText.number(s.atMs)),
            ("rms_db", JsonText.number(s.rmsDb)),
            ("peak_db", JsonText.number(s.peakDb)),
            ("bands_db", JsonText.array(s.bandsDb.map { JsonText.number($0) })),
            ("envelope", JsonText.object([("min", JsonText.array(s.envelopeMin.map { JsonText.number($0) })), ("max", JsonText.array(s.envelopeMax.map { JsonText.number($0) }))])),
        ])
    }

    private func u64(_ v: UInt64) -> String { JsonText.string(String(v)) }

    // MARK: Teardown (quit and reload)

    func teardown() {
        newGeneration()
        statusTimer?.invalidate(); statusTimer = nil
        analysisTimer?.invalidate(); analysisTimer = nil
        leaseTimer?.invalidate(); leaseTimer = nil
        player.stop()
        removeTap()
        analysis.stop()
        engine?.stop()
        engine = nil
        file = nil
        entry = nil
        eventSubs.removeAll(); statusSubs.removeAll(); analysisSubs.removeAll()
        state = .idle
    }

    // MARK: The manual clock (audio:render)

    /// Render `ms` milliseconds of output offline, as the output device
    /// would have pulled them, then publish what changed.
    func render(ms: Int) {
        guard manual else { fatal("script: audio:render needs audio:manual first") }
        guard let engine, engine.isRunning else { fatal("script: audio:render before a source is loaded") }
        guard let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AudioService.manualChunk) else { fatal("audio: no render buffer") }
        var left = Int((Double(ms) * AudioService.manualRate / 1000).rounded())
        rendered.removeAll(keepingCapacity: true)
        while left > 0 {
            let n = AVAudioFrameCount(min(left, Int(AudioService.manualChunk)))
            do {
                let status = try engine.renderOffline(n, to: out)
                if status != .success { fatal("audio: offline render answered \(status.rawValue)") }
            } catch { fatal("audio: offline render failed: \(AudioService.describe(error))") }
            if let data = out.floatChannelData { rendered.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(out.frameLength))) }
            left -= Int(n)
            // Offline, the render notification delivers each render as this
            // loop renders it, far faster than the worker measures: wait while its ring is all
            // but full, so no chunk is overwritten. A dropped chunk restarts
            // the rolling window, and where it restarted would depend on the
            // worker's speed, so a spec's measurements would not repeat.
            if tapped { awaitAnalysisRoom() }
            if state == .playing, frame() >= durationFrames { finish(generation) }
        }
        // The tap is called within each render, so everything rendered is
        // in the ring: let the worker measure it, so what is published next
        // is the same on every run.
        if tapped, let to = renderedNodeFrames() {
            let deadline = Bench.now() + 2
            while Bench.now() < deadline {
                if analysis.drained || analysis.isStalled { break }
                Thread.sleep(forTimeInterval: 0.002)
            }
            let c = analysis.counters()
            host?.trace("audio: rendered to \(Int(to)), tapped to \(Int(c.tappedTo)) in chunks of \(c.chunkFrames), \(Int(c.tapped)) taps, \(Int(c.consumed)) consumed, \(Int(c.busy)) busy")
        }
        publishStatus()
        publishSnapshot()
    }

    /// Under the manual clock: wait, at most 2 s, until the analysis ring
    /// has room for another chunk, unless a spec stalled the worker.
    private func awaitAnalysisRoom() {
        let deadline = Bench.now() + 2
        while Bench.now() < deadline, !analysis.isStalled, analysis.counters().waiting >= AudioAnalysis.slotCount - 1 {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    // MARK: Errors

    static func describe(_ error: Error) -> String { error.localizedDescription }

    /// Why a file did not open, as `Audio.Error`'s tag and text: Core
    /// Audio's status code, found in the error's description (the longest
    /// run of digits), named by its four-character code. `typ?` and `fmt?`
    /// are formats the decoder does not play; anything else is a file that is
    /// not the audio it claims to be.
    static func openFailure(_ error: Error) -> (tag: String, why: String) {
        var best: [UInt8] = [], run: [UInt8] = []
        for c in Array(describe(error).utf8) + [0x20] {
            if (c >= 0x30 && c <= 0x39) || (c == 0x2d && run.isEmpty) { run.append(c) } else {
                if run.count > best.count { best = run }
                run = []
            }
        }
        guard let code = Int(String(decoding: best, as: UTF8.self)), code >= -2147483648, code <= 4294967295 else { return ("Corrupt", "the file did not open as audio") }
        let u = UInt32(truncatingIfNeeded: code)
        let bytes = [u >> 24, u >> 16, u >> 8, u].map { UInt8(truncatingIfNeeded: $0) }
        let fourCC = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7f } ? "'" + String(decoding: bytes, as: UTF8.self) + "'" : String(code)
        switch fourCC {
        case "'typ?'": return ("Unsupported", "not a file type the decoder plays (\(fourCC))")
        case "'fmt?'": return ("Unsupported", "a data format the decoder does not play (\(fourCC))")
        case "'dta?'": return ("Corrupt", "the file's data is not valid audio (\(fourCC))")
        default: return ("Corrupt", "the file did not open as audio (Core Audio \(fourCC))")
        }
    }

    /// A path as a `file://` URL's path: every byte but the unreserved ones
    /// and `/` percent-encoded.
    static func percentEncoded(_ path: String) -> String {
        let digits = Array("0123456789ABCDEF")
        var out = ""
        for b in path.utf8 {
            let c = Character(UnicodeScalar(b))
            if (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a) || (b >= 0x30 && b <= 0x39) || "-._~/".utf8.contains(b) {
                out.append(c)
            } else {
                out += "%" + String(digits[Int(b >> 4)]) + String(digits[Int(b & 15)])
            }
        }
        return out
    }
}
