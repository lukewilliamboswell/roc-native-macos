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
./examples/counter/counter      # or stopwatch, todos, http-fetch
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
  root. It provides only `roc_engine_keys`, `roc_engine_init`,
  `roc_engine_event`, `roc_engine_drop` and `roc_engine_version`, with no
  hosted functions, workers, ports, files or crypto. `roc_engine_keys`
  returns the engine's declarations without roc-signals' section 12
  (protocol facts): that CBOR item needs the cbor package and
  `ProtocolFacts`, and this host binds no roles from it.
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

  It keeps a node tree mirroring what the engine built and gives each `ui-*`
  element one AppKit view. It routes AppKit actions back as turns: `click`,
  `input`, `change` and `submit`. Any other command or effect is a clear fatal
  error, not a silent skip.

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
  - one typed Swift function per provided procedure (`Roc.eventForHost(...)`),
    with its ownership contract.

It covers only the shapes this platform uses (byte lists, opaque boxes,
integers, records of those, unit) and 64-bit hosts. It fails generation,
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

## Driving an app

`ROC_SCRIPT` drives the real controls through the same action methods
AppKit calls. Steps run every 100 ms; `dump` prints the live view tree:

```sh
ROC_SCRIPT="type:Buy milk;enter;toggle:Buy milk;click:Done;dump;quit" ./examples/todos/todos
```

```sh
ROC_TRACE=1 ROC_SCRIPT="type:https://example.com;enter;wait:3000;dump;quit" ./examples/http-fetch/http-fetch
```

Steps: `click:<title>`, `type:<text>` (first text field), `enter` (submit its
form), `toggle:<checkbox title>`, `wait:<ms>`, `dump`, `quit` (through the
same teardown as quitting). `ROC_TRACE=1`
logs effect requests, cancellations and the teardown (`DROP`); `ROC_POISON=1` fills every new allocation
with `Z`, to expose reads of uninitialised memory. A scripted run never takes
keyboard focus.

roc-signals' `.scm` spec runner is not ported. Its oracle (`Dom.roc`) models
a browser DOM, so it would check the engine but never the AppKit host. A spec
format over the scripted driver, or a `ui-*` oracle, are the two options.

## Examples

| Example | Shows |
|---|---|
| `counter` | Local state (`Engine.state`), buttons, a readout |
| `todos` | A store with a table, `table_view` rows (row templates), a form with Return-to-submit, checkboxes, `when`, saving to local storage and reading it back at boot, and `expect` tests (`roc test examples/todos/main.roc`) |
| `stopwatch` | Store cells, an interval effect owned by `watch_latest` (Stop cancels it), and an `each` list of laps |
| `http-fetch` | `Engine.http` under `watch_latest`: Fetch, Cancel (a pure cancel), a second Fetch superseding the first, an optional 2 s timeout, and transfer progress (`with_progress`) |

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

## Licence

[UPL 1.0](LICENSE). The engine modules come from roc-signals (UPL 1.0, the
same copyright holder).
