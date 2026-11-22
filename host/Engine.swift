// The engine instance across the ABI, through the generated glue.

// MARK: - The engine across the ABI

/// The engine instance: one opaque state box and the two recycled buffers.
/// Every value crosses through the generated glue (`RocGlue.swift`).
final class EngineInstance {
    private var state: RocBox? = nil
    private var cmds = RocList.empty
    private var work = RocList.empty

    static let effectNode: UInt32 = 0xffff_ffff

    var version: UInt32 { Roc.versionForHost() }

    /// Mount with empty boot bytes (every default); returns the mount batch.
    func mount() -> [UInt8] { take(Roc.initForHost(.empty)) }

    /// One turn; returns its command batch. The state and both buffers move
    /// into Roc and come back in the result.
    func event(node: UInt32, handler: UInt32, payload: [UInt8]) -> [UInt8] {
        guard let current = state else { fatal("event before mount") }
        state = nil
        return take(Roc.eventForHost(current, cmds, work, node, handler, .ownedBytes(payload)))
    }

    private func take(_ step: InitForHost) -> [UInt8] {
        state = step.state
        cmds = step.cmds
        work = step.work
        return cmds.bytes
    }
}
