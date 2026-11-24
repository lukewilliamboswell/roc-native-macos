// The engine instance across the ABI, through the generated glue.

import Foundation

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

    /// The last turn's work record, as bytes (`count:u32 (counter:u64)*`,
    /// then the cleanups that ran). The host never reads the counters: a
    /// spec's `metrics` step prints them for the tool to decode.
    var workRecord: [UInt8] { work.bytes }

    /// The program's declarations (`roc_engine_keys`). The list is the
    /// host's; it is read once at mount and not released (the glue has no
    /// release helper for a returned list).
    func declarations() -> Declarations { Declarations(Roc.keysForHost().bytes) }

    /// Mount with the boot facts the declarations ask for; returns the
    /// mount batch.
    func mount(now: Date = Date()) -> [UInt8] {
        let d = declarations()
        declaredPorts = d.ports
        return take(Roc.initForHost(.ownedBytes(bootBytes(d, now: now))))
    }

    /// The ports the program declared, read at mount.
    private(set) var declaredPorts: [PortDeclaration] = []

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

    /// Reload's retirement: the engine takes no more turns, and its state
    /// is left unreleased (`Host.retire`).
    func abandon() {
        state = nil
        dropped = true
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

    /// A files-kind turn: the file record and the handles minted for it
    /// move into Roc with the state and both buffers.
    func files(node: UInt32, handler: UInt32, record: [UInt8], handles: [UnsafeMutableRawPointer]) -> [UInt8] {
        guard let current = state else { fatal("event before mount") }
        state = nil
        return take(Roc.filesForHost(current, cmds, work, node, handler, .ownedBytes(record), .ownedBoxesU64(handles)))
    }

    private func take(_ step: InitForHost) -> [UInt8] {
        state = step.state
        cmds = step.cmds
        work = step.work
        return cmds.bytes
    }
}
