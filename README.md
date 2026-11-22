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
./examples/counter/counter      # or stopwatch, todos, http-fetch, file-inspector, gallery, contacts
open examples/counter/counter.app
```

Each example is built twice over: the bare binary, and a minimal `.app`
bundle beside it (`Contents/MacOS/<name>` and an `Info.plist` with
`CFBundleIdentifier` `dev.roc.native.<name>`). Launched from the bundle,
AppKit has a bundle identifier, so it no longer warns that it cannot index
window tabs. The two keep separate `UserDefaults` domains (`todos` versus
`dev.roc.native.todos`), so they do not share saved values.

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
  root. It provides `roc_engine_keys`, `roc_engine_init`,
  `roc_engine_event`, `roc_engine_files` (a files-kind event, copied as is),
  `roc_engine_drop` and `roc_engine_version`, with no hosted functions,
  workers, ports or crypto. `roc_engine_keys` returns the engine's
  declarations without roc-signals' section 12 (protocol facts): that CBOR
  item needs the cbor package and `ProtocolFacts`, and this host binds no
  roles from it.
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
  - `FX` HTTP (kind 1) through `URLSession`, with timeouts, cancellation
    and transfer progress (see [Effects and threads](#effects-and-threads));
  - local storage, via `UserDefaults`, and session storage, in memory for
    the life of the process.
  - files: handles, reads (`FX` 11), digests (13), URLs (14) and `SAVE`
    (see [Files](#files)).

  It keeps a node tree mirroring what the engine built and gives each `ui-*`
  element one AppKit view. It routes AppKit actions back as turns: `click`,
  `input`, `change`, `submit`, a list row's `select`, key events, and the
  files-kind `change` and `drop`. Any other command or effect is a clear fatal
  error, not a silent skip.

## The `Ui` vocabulary

| Builder | Element | AppKit view |
|---|---|---|
| `vstack`, `hstack` | `ui-vstack`, `ui-hstack` | `NSStackView` |
| `form` | `ui-form` | vertical `NSStackView`; Return submits |
| `scroll` | `ui-scroll` | `NSScrollView` around a vertical `NSStackView` |
| `list`, `row` | `ui-list`, `ui-row` | view-based `NSTableView`; each `ui-row` is a table row |
| `title`, `label`, `label_s`, `text`, `text_s`, `readout_s` | `ui-title`, `ui-label`, `ui-readout` | `NSTextField` label |
| `button`, `button_s`, `action_button`, `submit_button` | `ui-button` | `NSButton` |
| `text_field`, `text_area` | `ui-text-field`, `ui-text-area` | `NSTextField`; `NSTextView` in an `NSScrollView` |
| `checkbox`, `slider` | `ui-checkbox`, `ui-slider` | `NSButton` (checkbox), `NSSlider` |
| `dropdown` | `ui-dropdown` | `NSPopUpButton` |
| `segmented`, `tabs` | `ui-segmented` | `NSSegmentedControl`; `tabs` adds an `Engine.switch` of pages |
| `image` | `ui-image` | `NSImageView` of an SF Symbol |
| `progress`, `busy` | `ui-progress` | `NSProgressIndicator` bar, determinate or indeterminate |
| `shortcut` | `ui-shortcut` | hidden; an `Engine.on_document_key` handler |
| `file_button` | `ui-file-button` | `NSButton` opening an `NSOpenPanel` |
| `drop_zone` | `ui-drop-zone` | an `NSView` registered for dragged file URLs |
| `divider`, `spacer` | `ui-divider`, `ui-spacer` | `NSBox` separator, flexible `NSView` |

Configuration is a props record of defaulted fields, first, beside the
children: `Ui.vstack({ spacing: 12, align: Fill }, kids)`, `Ui.vstack({}, kids)`,
`Ui.text({ font: Caption, color: Secondary }, "Saved")`, `Ui.scroll({ height: 200 }, rows)`.
It crosses as plain attributes the host reads: `spacing`, `padding`, `align`
on stacks; `height`, `min-height` on scrolls, lists and text areas; `font`
(body, title, headline, caption, mono) and `color` (AppKit's semantic
colours: primary, secondary, tertiary, accent, red, orange, green, blue) on
text. Styling is deliberately minimal here.

**Window sizing.** Without a scroll area or list the window fits its content
exactly, as before. Once one appears, the window opens tall enough for the
scroll area's `height` and from then on only grows when the content around
it needs more room. The user can resize it; the scroll area (which hugs
least) takes the slack, down to its `min-height`. Vertical stacks that hold
one use `.fill` distribution; the others keep `.gravityAreas`.

**Lists.** `Ui.list({}, Engine.table_view(...))` puts the site's rows in a
view-based `NSTableView`. The table's row model follows the node tree: each
engine insert, remove or move of a row is one `insertRows`, `removeRows` or
`moveRow`, inside one `beginUpdates` per batch; a batch of more than 64 row
changes (a mount, a new query, a `CLEAR`) reloads once instead. A row's own
view is its cell view (row heights by Auto Layout,
`usesAutomaticRowHeights`). A template row inside a list gets its views only
when the table first asks for it, so 10,000 rows cost AppKit views for the
visible ones. `examples/contacts` mounts 10k rows in about 0.6 s of engine
time and 0.1 s of host time; a search that drops thousands of rows takes
tens of milliseconds in the host. The engine still draws every row that
passes the query (`Engine.every_row`): windowing the `table_view` to the
rows in sight (a `window` signal fed by the table's scroll position, with
the table told the full count) is follow-up work, and the next cost to cut.

**Keys.** The host decodes the keymaps the engine renders (property rows 4
and 5) and matches an AppKit key event as design.md specifies: entries
restricted to outside text entry, exact matches in order, then
physical-key fallbacks (`KeyK`), then `every`; Ctrl, Alt and Meta exact, Shift
exact except for a punctuation or symbol chord, one ASCII letter without
case. The nearest element at or above the focused view whose keymap hears
the key gets a kind-4 payload; failing that, the most recently mounted
document handler (`Engine.on_document_key`, `Ui.shortcut`) that hears it.
A heard `prevent` entry swallows the event, so AppKit never sees it. Key
names follow the DOM (`Enter`, `Escape`, `ArrowUp`, …) and codes the ANSI
layout. Not done: the `stop` policy has no AppKit meaning here (one handler
hears each key), menus and their key equivalents, and `keyup` for keys
AppKit consumes itself.

## Boot and lifecycle

Before mount the host reads the program's declarations (`roc_engine_keys`:
storage keys, media queries, zone span, startup profile) and sends real
boot facts (`host/Boot.swift`, Appendix B "Boot"):

| Section | Value |
|---|---|
| 1 location | `/` |
| 2 local storage | the declared keys that exist in `UserDefaults` |
| 3, 4 online, visible | true |
| 6 media | `(prefers-color-scheme: dark)` / `light` from the system setting; any other query false |
| 7 time | now, in ms |
| 8 seed | 16 bytes from `arc4random_buf` |
| 9 languages | `Locale.preferredLanguages` (1–16, each ≤ 64 bytes; `en-US` if none) |
| 10 time zone | `TimeZone.current` over the declared days each side of now, with its transitions |
| 11 session storage | the declared keys this process has stored |
| 13 mount root | an HTML `div`, or a profile-1 program's declared root |
| 14 startup | profile 0, or profile 1 fresh with no entry |

So `todos` saves its table under the local key `todos` and reads it back at
the next launch (`Engine.boot_storage`, `Engine.watch_changes`).

Quitting, or closing the window, cancels every effect in flight and calls
`roc_engine_drop` once; no turn runs after it. A Roc crash or a host fatal
error prints the message, shows it in an alert, then exits with status 1.
Under `ROC_SCRIPT` it never shows the alert. The modal loop
runs no turns, so a timer cannot re-enter Roc after a crash. `dbg` still
prints to stderr.

## Effects and threads

Roc runs on the main thread only. An effect that blocks or waits (HTTP now;
files and anything later) follows the same rules, which play the part
roc-signals' Workers play on the web: the work leaves the thread, Roc
does not.

1. **Nothing Roc owns crosses a thread.** The `FX` operands are decoded on
   the main thread into a plain Swift value (`HttpRequest`). The engine
   state, the command and work lists and every Roc allocation stay on the
   main thread.
2. **Work runs on the effect's own queue.** `URLSession` performs HTTP with
   its delegate on a private serial `OperationQueue`. State that queue
   owns (each transfer's buffer and redirect count) is touched only there;
   state the main thread owns (`Host.flights`: the task, its timers) only
   there. They meet in two places: the main thread hands a task over with
   `queue.addOperation`, which also resumes it, so no callback precedes the
   hand-over; the queue hands back a finished, already encoded result
   payload (`[UInt8]`: status, headers, body) with `DispatchQueue.main.async`.
3. **The main thread decides whether a result exists.** A payload enters
   Roc only if its id is still tracked, by the same task. `CANCEL`, a
   timeout and teardown untrack the id *first*, then cancel the task, so a
   completion that races them is dropped on the main thread and never
   reaches the engine (which would also drop it, as stale). Even a request
   refused before it starts (a bad URL) answers one task later through the
   same check, so a `CANCEL` later in the same batch still wins.
4. **One result, one turn, through the UI's queue.** Results enter through
   `Host.send`, as AppKit events do, which queues while a batch is being
   applied: a completion never re-enters Roc mid-batch.
5. **Teardown cancels everything in flight** (`teardownEffects`, from `Host.stop` on
   `applicationWillTerminate`, which the scripted `quit` also reaches), and invalidates the
   session.

HTTP bounds and mappings:

- **Timeout.** `timeout_ms` (0 = none, capped at 600 s by the engine and
  again by the host) is a main-thread `Timer`; on expiry the id is
  untracked, the task cancelled and `Timeout` (tag 7) delivered.
  URLSession's own idle timeout is set to the same 600 s cap and, if it
  fires, is a `Network` error.
- **Body size.** The host reads at most 16 MiB (`maxHttpBodyBytes`) of a
  response body, checked against `Content-Length` and as bytes arrive; past
  it the transfer is stopped and answered `Network("response body is larger
  than the host's … limit")`. The protocol sets no limit for a text body.
- **Text.** The body crosses as tag 1's `body:rest`, which the engine
  requires to be UTF-8. As Fetch's `text()` does, the host decodes it as
  UTF-8 with replacement (U+FFFD) and drops a leading BOM, whatever the
  `charset`. Header names are lowercased and sorted, as Fetch's `Headers`
  iterates them.
- **URLs and redirects.** Only absolute `http(s)` URLs are fetched (there is
  no page to resolve a relative one against); anything else is `Network`.
  Redirects are followed to `http(s)` only, at most 20 times (URLSession
  stops a loop sooner, at 16); otherwise `Network`.
- **Request body.** Sent only for a method other than `GET`/`HEAD` and a
  non-empty body, as roc-signals' runtime does.
- **Cache.** `Default` → `useProtocolCachePolicy`; `NoStore` →
  `reloadIgnoringLocalCacheData`, and the response is not stored
  (`willCacheResponse` answers nil); `Reload` →
  `reloadIgnoringLocalCacheData`; `NoCache` → `reloadIgnoringLocalCacheData`
  too (URLSession has no conditional-revalidation policy, so this is
  stricter than Fetch's); `ForceCache` → `returnCacheDataElseLoad`.
- **Credentials.** A native app has no page origin, so every request is
  cross-origin: `SameOrigin` sends and stores no cookies
  (`httpShouldHandleCookies = false`), `Include` uses the shared cookie
  store. Authentication challenges get URLSession's default handling.
- **Progress** (tag 26) is reported only when the engine asked for it
  (`progress_ms > 0`, which it sets only for a site with a progress
  handler). The queue posts each count to the main thread; there one waiting
  report per request is replaced in place and delivered by one sampling
  timer every `progress_ms`. Completion, cancellation and timeout discard a
  waiting report, so none follows the final result. `Receiving` counts
  decoded bytes; its total is `Known` only for a `Content-Length` without a
  `Content-Encoding`. `Sending` reports a request body.
- **Not yet:** kind 15 (a response body as a file) and kind 12 (a file as
  the body) need the file heap; they remain a clear fatal error.

**Files.** Reads (`FX` 11), digests (13) and saves follow those rules on a
concurrent `DispatchQueue` (`host/Files.swift`). A job checks its
cancellation flag (an `os_unfair_lock`ed `Bool`, the only state shared with
the main thread) between 1 MiB chunks, so `CANCEL` (an inspected file
superseded, or its site disposed) stops a long digest at the next chunk, and
its completion is dropped. The handle table is touched only on the main
thread; `roc_dealloc` reaching it from another thread is a fatal error. The rules above apply unchanged; `Host.files.jobs` plays the part of `Host.flights`.

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

```sh
ROC_TRACE=1 ROC_SCRIPT="type:https://example.com;enter;wait:3000;dump;quit" ./examples/http-fetch/http-fetch
```

Steps: `click:<title>`, `type:<text>` (first text field), `write:<text>`
(first text area, `\n` for a line break), `enter` (submit its form),
`toggle:<checkbox title>`, `choose:<title>` (a dropdown item or segment),
`select:<text>` (the list row holding that text), `key:cmd+shift+n` (a key
press delivered as if nothing had focus), `files:<path>,<path>…` (files as if
picked on the first file button or drop zone, with no panel), `drop:<path>,…`
(as if dropped on the first drop zone), `wait:<ms>`, `dump` (window size, then
the view tree; a list shows its visible rows), `quit` (through the same
teardown as quitting). `ROC_TRACE=1` logs effect requests, cancellations,
minted and released file handles, the teardown (`DROP`), and each turn's
engine and host time; `ROC_POISON=1` fills every new allocation with `Z`, to
expose reads of uninitialised memory. A scripted run never takes keyboard
focus and never opens a panel: a save writes to `ROC_SAVE_DIR` when it is set
and is skipped otherwise. `ROC_MAX_FILE_BYTES` lowers the host's file ceiling
(to check `TooLarge`). Local storage is in memory for a scripted run, unless
`ROC_STORAGE_SUITE=<name>` names a `UserDefaults` suite.

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
| `todos` | A store with a table, `table_view` rows (row templates) in a `Ui.scroll`, a form with Return-to-submit, a Command-N shortcut, checkboxes, `when`, saving to local storage and reading it back at boot, and `expect` tests (`roc test examples/todos/main.roc`) |
| `gallery` | `tabs` over pages, a dropdown, a text area, SF Symbols, progress bars, styled text, Command-N/Command-K shortcuts |
| `contacts` | 10,000 generated rows in a `Ui.list` (`NSTableView`), a search field filtering through the `table_view` query, row selection |
| `stopwatch` | Store cells, an interval effect owned by `watch_latest` (Stop cancels it), and an `each` list of laps |
| `http-fetch` | `Engine.http` under `watch_latest`: Fetch, Cancel (a pure cancel), a second Fetch superseding the first, an optional 2 s timeout, and transfer progress (`with_progress`) |
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
- **Props records work.** A nominal record of `??` defaulted fields as a
  function argument (`Ui.vstack({ align: Fill }, kids)`, `Ui.scroll({}, rows)`)
  checks, builds and runs correctly in RC1.
- **No `Str` order.** `Str` has no `order_relative_to` in RC1, so
  `Engine.sort_by` cannot sort rows by a name; `contacts` sorts by key.
- **Host costs, not engine costs.** For 10k rows the engine's turns are
  milliseconds; the host was seconds until it stopped removing children one
  O(n) scan at a time (removals now compact once per batch) and stopped
  creating AppKit views for list rows nobody had scrolled to.

## Development

The repository follows
[roc-automation](https://github.com/lukewilliamboswell/roc-automation). With
[Blueprint](https://github.com/lukewilliamboswell/roc-blueprint) 0.13.0 and a
current Roc nightly (or RC1) installed as `roc`, run `blueprint run check`.
It is the pull-request gate, the same one CI runs. See [AGENTS.md](AGENTS.md) for the
repository's rules, and [docs/roc-automation-review.adoc](docs/roc-automation-review.adoc)
for what is adopted so far. Report vulnerabilities as [SECURITY.md](SECURITY.md)
describes.

## Licence

[UPL 1.0](LICENSE). The engine modules come from roc-signals (UPL 1.0, the
same copyright holder).

Third-party notices are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
