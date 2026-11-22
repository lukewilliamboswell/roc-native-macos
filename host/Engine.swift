// The engine instance across the ABI, through the generated glue.

// MARK: - The engine across the ABI

/// The engine instance: one opaque state box and the two recycled buffers.
/// Every value crosses through the generated glue (`RocGlue.swift`).
final class EngineInstance {
    private var state: RocBox? = nil
    private var cmds = RocList.empty
    private var work = RocList.empty
    private(set) var dropped = false

    static let effectNode: UInt32 = 0xffff_ffff

    var version: UInt32 { Roc.versionForHost() }

    /// The program's declarations (`roc_engine_keys`). The list is the
    /// host's; it is read once at mount and not released (the glue has no
    /// release helper for a returned list).
    func declarations() -> Declarations { Declarations(Roc.keysForHost().bytes) }

    /// Mount with the boot facts the declarations ask for; returns the
    /// mount batch.
    func mount() -> [UInt8] { take(Roc.initForHost(.ownedBytes(bootBytes(declarations())))) }

    /// Teardown (`roc_engine_drop`), once: the state and both buffers move
    /// into Roc. Later calls do nothing.
    func drop() {
        guard let current = state, !dropped else { return }
        state = nil
        dropped = true
        Roc.dropForHost(current, cmds, work)
        cmds = .empty
        work = .empty
    }

    /// One turn; returns its command batch. The state and both buffers move
    /// into Roc and come back in the result.
    func event(node: UInt32, handler: UInt32, payload: [UInt8]) -> [UInt8] {
        guard let current = state else {
            if dropped { return [] }
            fatal("event before mount")
        }
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
