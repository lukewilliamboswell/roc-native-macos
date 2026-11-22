# roc-native-macos (spike)

> [!NOTE]
> This is an early proof of concept. My goal is to show how
> [roc-signals](https://github.com/lukewilliamboswell/roc-signals) might look
> for native UI. I'm not sure where this project will go: I've written it for
> a bit of fun, and to help with the development of the reactive engine in
> Roc. If you're interested in this work, let me know.

A native macOS UI platform for Roc. The reactive engine is
[roc-signals](https://github.com/lukewilliamboswell/roc-signals)' pure Roc engine, copied verbatim. The host is
Swift and draws real AppKit controls: no browser, no HTML, no web view.

```sh
scripts/build.sh                # glue, Swift host, linker stubs, every example
./examples/counter/counter      # or stopwatch, todos
```

It needs the Roc 0.1.0 RC1 compiler (`~/roc-macos_apple_silicon-0.1.0_RC1/roc`,
or set `ROC=`), Xcode's `swiftc` and Apple silicon.

## How it fits together

```
app (Roc)  ──Ui / Engine──▶  engine (Core.roc, pure Roc)
                                 │ command stream (roc-signals wire protocol 23)
                                 ▼
                         Swift host (host/Host.swift) ──▶ AppKit views
                                 ▲
             AppKit events, timer results ── one engine turn each
```

- **Engine.** `Core.roc`, `Engine.roc` and the modules they import (`Web`,
  `EntryRoutes`, `Url`, `ReadyIndex`, `Spelling`, `Layout`, `TableCore`, `View`,
  `Seq`, `MarkupAdvice`, `SignalCore`) are byte-identical copies of roc-signals
  `a13ff70e`. Nothing in the engine was changed.
- **Platform root.** `platform/main.roc` is a trimmed copy of roc-signals'
  root. It provides only `roc_engine_init`, `roc_engine_event`,
  `roc_engine_files` (a files-kind event, copied as is), `roc_engine_drop` and
  `roc_engine_version`, with no hosted functions, workers, ports or crypto.
- **`Ui.roc`.** The native vocabulary apps use. Each builder is a plain
  `Engine.element` with a native element name (`ui-vstack`, `ui-button`,
  `ui-text-field`, `ui-checkbox`, `ui-slider`, …). A control's state crosses
  as plain attributes (`value`, `checked`, `disabled`), because the engine
  only allows its `value`/`checked` *props* on HTML inputs.
- **Swift host (`host/`).** Decodes the subset of the command stream the vocabulary
  produces:
  - element, text and comment creation; attributes; listeners; text updates;
  - move, remove and clear;
  - row templates (`TEMPLATE`/`INST`) and their holes;
  - `FX` timers and intervals, and `CANCEL`;
  - storage, via `UserDefaults`;
  - files: handles, reads (`FX` 11), digests (13), URLs (14) and `SAVE`
    (see [Files](#files)).

  It keeps a node tree mirroring what the engine built and gives each `ui-*`
  element one AppKit view. It routes AppKit actions back as turns: `click`,
  `input`, `change`, `submit`, and the files-kind `change` and `drop`. Any
  other command or effect is a clear fatal error, not a silent skip.

## Glue

`glue/SwiftGlue.roc` writes everything the host needs to cross the ABI:

- `roc_swift_abi.h`, the Swift bridging header. Swift can call C functions
  only through a header clang imports; `@_silgen_name` uses Swift's calling
  convention, not the C ABI. The header declares `RocList` and `RocBox`, each
  record a provided procedure returns, the runtime symbols and the provided
  symbols. Record fields, padding and `_Static_assert`s of size, alignment
  and every offset come from the compiler's committed layout facts.
- `RocGlue.swift`:
  - `RocList.ownedBytes` / `.bytes` / `.empty`, which encode a Roc list exactly
    as Roc does;
  - for `List(Box(U64))` (the handles of a files-kind event): `RocBoxU64`, the
    box's layout (refcount word just before the payload, and the address and
    alignment Roc frees it with), and `RocList.ownedBoxesU64`, which builds
    the list. A list whose elements are refcounted carries one more header
    word, the element count, before its refcount (`allocateWithRefcount` in
    the compiler's `src/builtins/utils.zig`), so its header is 16 bytes, not 8.
    Every number comes from the compiler's layout facts (`is_refcounted`, the
    element's and payload's size and alignment). The header exposes them as
    `ROC_BOX_U64_*` constants, which the Swift helpers read, and checks them
    against the C types with `_Static_assert`s;
  - one typed Swift function per provided procedure (`Roc.eventForHost(...)`),
    with its ownership contract.

It covers only the shapes this platform uses (byte lists, opaque boxes,
lists of boxes of an integer, integers, records of those, unit) and 64-bit
hosts. It fails generation,
naming the entry point, on anything else, including hosted functions.
The list helpers were the point: the stock C glue leaves list construction
to the host, and a hand-written encoding was this spike's one real crash
(see Findings).

## Linker inputs: no Apple SDK files

Following roc-gui, the platform ships no Apple SDK material. Roc's linker
links a platform's `targets/macos-sysroot`. `scripts/build_macos_stubs.py`
writes that sysroot as minimal TAPI v4 `.tbd` stubs, built only from the
reviewed catalog `host/interfaces.json`: install names, symbol names
and stated evidence per library. It reads no SDK file. With `--audit` it also
fails the build if `libhost.a` references a symbol the catalog does not own,
so adding one is a reviewed edit.

Swift is compiled with `-disable-autolink-frameworks` and
`-disable-force-load-symbols`, so the frameworks linked are exactly the
catalog's. Roc then links each `X.framework/X.tbd` it finds. The resulting
binaries load only `AppKit`, `Foundation`, `CoreGraphics`, `libSystem`,
`libobjc` and the Swift runtime and overlays in `/usr/lib/swift`.

Unlike roc-gui, the catalog's evidence is per library, not per symbol. Swift
symbols are assigned by the mangled module or extension owner (Swift's
`docs/ABI/Mangling.rst`), and ObjC classes by Apple's documented framework.
Tightening that to per-symbol evidence is follow-up work.

## Effects and threads

Roc runs only on the main thread, and no Roc value or Roc-owned memory ever
crosses to another thread: Roc's reference counts are not atomic, and the
engine state is one value the host passes in and out of each call. An effect
whose work blocks (a file read, a digest, a save) resolves what it needs from
the command on the main thread into plain Swift data (a path, a range), runs
on a background queue over only that data, and hands plain bytes back to the
main thread. There they are encoded as the result payload and enter the
engine as one turn through `Host.send`, the same queue every event uses, so a
result that arrives while a batch is being applied waits its turn. `CANCEL`
removes the effect from the host's job table; a completion is checked against
that table on the main thread, so one for a cancelled or untracked id never
reaches Roc.

**Files.** Reads (`FX` 11), digests (13) and saves follow those rules on a
concurrent `DispatchQueue` (`host/Files.swift`). A job checks its
cancellation flag (an `os_unfair_lock`ed `Bool`, the only state shared with
the main thread) between 1 MiB chunks, so `CANCEL` (an inspected file
superseded, or its site disposed) stops a long digest at the next chunk, and
its completion is dropped. The handle table is touched only on the main
thread; `roc_dealloc` reaching it from another thread is a fatal error.

## Files

A file the user gives the app reaches Roc as a handle, never as bytes, as in
roc-signals (design.md, "Files"). `Ui.file_button(label, handler)` opens an
`NSOpenPanel` (several files may be chosen) and delivers a files-kind `change`
event; `Ui.drop_zone(label, handler)` is an `NSView` registered for dragged
file URLs and delivers `drop`. Both take an `Engine.FilesHandler`, whose
payload is `Received` (`{ files : List(File), refused : U64 }`). Folders and
unreadable paths are left out; no files means no event.

- **Handles.** The host keeps each file as a `FileEntry` (absolute path, size,
  name and a media type from a short extension table, `""` when unknown)
  under a token, and mints a `Box(U64)` holding the token in a fixed table of
  64 slots laid out as the glue reports `Box(U64)`. The event carries the
  file record `minted:u32 refused:u32 (size:u64 name:str type:str)*` and a
  `List(Box(U64))` of the handles into `roc_engine_files`. Tokens encode
  generation, kind and slot as `resources.zig` does, so a stale token never
  resolves. A non-sandboxed app needs no security-scoped bookmark.
- **Release.** Roc owns the boxes. When the last `File` holding one goes,
  Roc frees it with `roc_dealloc(payload - 8)`. `roc_dealloc` offers every
  address to the table first (one range check), as host.zig's `blobs.route`
  does, and the table retires the slot instead of freeing it. After the batch
  has been applied (its `FX` and `SAVE` commands, which may name a handle Roc
  dropped in the same turn, have resolved their entries), the host drains the
  retired slots and drops their entries. A request keeps its own copy of the
  entry until it is answered.
- **Bound.** 64 live handles, as in the browser host. An event with more
  files than free slots delivers the ones that fit and counts the rest in
  `refused`. Retired slots count until they are drained.
- **Reads** (`read_bytes`, `read_utf8`): `len` over the request's `max_bytes`
  or the host's `maxFileBytes` (256 MiB, the browser default;
  `ROC_MAX_FILE_BYTES` lowers it) is `FileFailed(TooLarge)`, unread. Text is
  sent as tag 17 and the engine checks its UTF-8. A file that went away or
  shrank is `Unreadable`.
- **Digests** (`sha256`): streamed through CommonCrypto (`CC_SHA256_Init`,
  `_Update`, `_Final`, in libcommonCrypto, which libSystem re-exports), so
  the range is never held whole. CommonCrypto rather than CryptoKit: three C
  symbols in a library already linked, against a new Swift framework.
- **URLs** (`object_url`): a `file://` URL of the file, which an AppKit view
  can load directly. A range other than the whole file has no URL of its own
  natively and answers `FileFailed(Unavailable)`; the browser's limit of 16
  ranges per handle does not apply.
- **Saves** (`File.save`, `SAVE`): the handle is resolved while the batch is
  applied, then after it an `NSSavePanel` sheet opens with the suggested name
  (one at a time), and the range is copied off the main thread. As in the
  browser, Roc learns nothing of the outcome; it is reported on stderr.

Not built: uploads (`FX` 12), fetched files (`FX` 15), pasted files, files
in a worker's answer, and building files (`Files.build!`), which needs
worker instances.

### Workers (design note, not built)

roc-signals runs a task's job in a separate Wasm instance per Web Worker
(design.md, "Workers"). Natively the same shape fits: one more Roc engine
instance per worker thread, each with its own heap, never sharing a Roc value
with another, because Roc's reference counts are not atomic. A job crosses as
bytes, as `roc_engine_work` takes them: `name:str input:rest` plus the
handles the worker's own table mints for the files it names, and the answer
comes back as `n:u32 (token:u64)*n output:rest`, a plain byte buffer copied
to the main thread and delivered as result tag 10 (with the answer's files
minted in the page's table, through `roc_engine_files` on the effect node).
The pieces that make it work natively:

- **Per-thread runtime symbols.** `roc_alloc`, `roc_dealloc` and the handle
  table route are process-global C symbols. Each would dispatch on a
  thread-local "current instance" (its heap accounting and handle table),
  set by the worker thread before it calls Roc.
- **Hosted effects for jobs.** `File.read!` and the `Files.build!` builder
  are hosted functions, which SwiftGlue does not generate yet. A worker
  thread may call them synchronously: it is the thread the job runs on.
- **Files across instances.** A file crosses as its `FileEntry` (path and
  range), never as a box; each side mints its own handle.
- **Cancellation and faults.** `CANCEL` marks the job; a worker thread cannot
  be killed safely, so `on_cancel: Stop` would poison and discard that
  instance and start a fresh one, and a `roc_crashed` in a worker would have
  to unwind that thread only (today it exits the process).

## Driving an app

`ROC_SCRIPT` drives the real controls through the same action methods
AppKit calls. Steps run every 100 ms; `dump` prints the live view tree:

```sh
ROC_SCRIPT="type:Buy milk;enter;toggle:Buy milk;click:Done;dump;quit" ./examples/todos/todos
```

Steps: `click:<title>`, `type:<text>` (first text field), `enter` (submit its
form), `toggle:<checkbox title>`, `files:<path>,<path>…` (files as if picked
on the first file button or drop zone, with no panel), `drop:<path>,…` (as if
dropped on the first drop zone), `wait:<ms>`, `dump`, `quit`. `ROC_TRACE=1`
logs effect requests, cancellations, minted and released file handles;
`ROC_POISON=1` fills every new allocation with `Z`, to expose reads of
uninitialised memory. A scripted run never takes keyboard focus and never
opens a panel: a save writes to `ROC_SAVE_DIR` when it is set and is skipped
otherwise. `ROC_MAX_FILE_BYTES` lowers the host's file ceiling (to check
`TooLarge`).

```sh
ROC_SAVE_DIR=/tmp ROC_SCRIPT="files:$PWD/README.md;click:Inspect;wait:300;dump;click:Save copy…;wait:200;quit" \
  ./examples/file-inspector/file-inspector
```

roc-signals' `.scm` spec runner is not ported. Its oracle (`Dom.roc`) models
a browser DOM, so it would check the engine but never the AppKit host. A spec
format over the scripted driver, or a `ui-*` oracle, are the two options.

## Examples

| Example | Shows |
|---|---|
| `counter` | Local state (`Engine.state`), buttons, a readout |
| `todos` | A store with a table, `table_view` rows (row templates), a form with Return-to-submit, checkboxes, `when`, and `expect` tests (`roc test examples/todos/main.roc`) |
| `stopwatch` | Store cells, an interval effect owned by `watch_latest` (Stop cancels it), and an `each` list of laps |
| `file-inspector` | `Ui.file_button` and `Ui.drop_zone` delivering `File` handles; for an inspected file its SHA-256 (`sha256`), its first 200 bytes as text or "binary" (`slice`, `read_bytes`), its URL (`object_url`) and "Save copy…" (`File.save`); Clear releases the handles |

## Findings

- **List capacity encoding.** In `capacity_or_alloc_ptr` a list stores
  `capacity << 1`; the low bit marks a seamless slice. The first host stored
  the raw length, so any odd-length payload read as a slice with a bogus
  allocation pointer and crashed in `roc_llvm_rc_decref`. Two-byte clicks
  passed by luck. The Zig glue gets this right; the C glue offers no
  constructor, hence SwiftGlue, which now replaces the C glue entirely.
- **Single-field record builder.** `{ a: Engine.cell(…) }.Engine.Cells` with
  one field is unimplemented in RC1, but `roc build` compiles it to a runtime
  error instead of failing. `roc test` reports it.
- **`watch` vs `watch_latest`.** `watch` never cancels what it issued; a
  start/stop interval needs `watch_latest`.
- **Handles in host memory work as in Wasm.** RC1's native code frees a
  `Box(U64)` at its payload minus 8 with alignment 8, exactly where the glue
  facts put it, so a box minted in a host table (not from `roc_alloc`) is
  released through `roc_dealloc` like the browser host's blob heap, and the
  same token encoding carries over unchanged. A list of such boxes must be
  built with the 16-byte header (element count, then refcount), which Roc
  reads when it releases a seamless slice of the list. A host that wrote the
  8-byte header of a byte list would work until such a slice was released.

## Licence

[UPL 1.0](LICENSE). The engine modules come from roc-signals (UPL 1.0, the
same copyright holder).
