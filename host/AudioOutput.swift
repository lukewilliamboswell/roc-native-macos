// The audio output device a playback session plays to, from Core Audio's
// object properties (`AudioObjectGetPropertyData`): its name and UID, for
// `Audio.Status` (an app keeps a visual offset per device), its latency
// parts, for the timing harness's report (AVTiming.swift), and, under
// `ROC_AUDIO_DEVICE`, choosing a device other than the system's default
// output (docs/architecture.adoc, "Audio/visual timing").

import AVFAudio
import CoreAudio

enum AudioOutput {
    /// A four-character code, as Core Audio's property selectors are.
    static func code(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for b in s.utf8 { v = v << 8 | UInt32(b) }
        return v
    }

    static let system: AudioObjectID = 1  // kAudioObjectSystemObject
    static let global = code("glob"), output = code("outp")

    private static func address(_ selector: String, _ scope: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: code(selector), mScope: scope, mElement: 0)
    }

    // Each property read passes its storage straight to Core Audio, with
    // no generic wrapper: those would need runtime metadata symbols the
    // catalog does not own.

    /// A property of `object` holding one UInt32, or nil.
    static func number(_ object: AudioObjectID, _ selector: String, _ scope: UInt32) -> UInt32? {
        var addr = address(selector, scope)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &v) == 0 ? v : nil
    }

    /// A property of `object` holding one Float64, or nil.
    static func real(_ object: AudioObjectID, _ selector: String, _ scope: UInt32) -> Double? {
        var addr = address(selector, scope)
        var v: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &v) == 0 ? v : nil
    }

    /// A property of `object` holding a list of object IDs.
    static func objects(_ object: AudioObjectID, _ selector: String, _ scope: UInt32) -> [AudioObjectID] {
        var addr = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == 0 ? ids : []
    }

    /// A string property (a CFString the caller owns), as UTF-8.
    static func text(_ object: AudioObjectID, _ selector: String) -> String {
        var addr = address(selector, global)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &s) == 0, let owned = s else { return "" }
        let cf = owned.takeRetainedValue()
        return cf as String
    }

    static func name(_ device: AudioObjectID) -> String { text(device, "lnam") }
    static func uid(_ device: AudioObjectID) -> String { text(device, "uid ") }

    /// The devices that have output streams.
    static func outputs() -> [AudioObjectID] {
        objects(system, "dev#", global).filter { !objects($0, "stm#", output).isEmpty }
    }

    /// The device `engine` plays to.
    static func device(of engine: AVAudioEngine) -> AudioObjectID { engine.outputNode.auAudioUnit.deviceID }

    /// Under `ROC_AUDIO_DEVICE`, play to the output device of that name or
    /// UID; a name that matches none is a fatal error naming the outputs.
    static func choose(for engine: AVAudioEngine) {
        guard let wanted = ProcessInfo.processInfo.environment["ROC_AUDIO_DEVICE"], !wanted.isEmpty else { return }
        let all = outputs()
        guard let id = all.first(where: { name($0) == wanted || uid($0) == wanted }) else {
            fatal("ROC_AUDIO_DEVICE names no output device \"\(wanted)\"; the outputs are \(all.map { "\"\(name($0))\"" }.joined(separator: ", "))")
        }
        do { try engine.outputNode.auAudioUnit.setDeviceID(id) } catch { fatal("audio: could not play to \"\(wanted)\": \(AudioService.describe(error))") }
    }

    /// The device's output latency parts, in its frames: the device's
    /// own latency, its safety offset, its IO buffer, and its first output
    /// stream's latency; and its nominal rate.
    static func latency(_ device: AudioObjectID) -> (device: UInt32, safety: UInt32, buffer: UInt32, stream: UInt32, rate: Double) {
        let streams = objects(device, "stm#", output)
        let stream = streams.isEmpty ? 0 : (number(streams[0], "ltnc", global) ?? 0)
        return (number(device, "ltnc", output) ?? 0, number(device, "saft", output) ?? 0,
                number(device, "fsiz", global) ?? 0, stream, real(device, "nsrt", global) ?? 0)
    }
}
