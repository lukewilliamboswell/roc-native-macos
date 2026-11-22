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

Quitting, or closing the window, invalidates the timers and calls
`roc_engine_drop` once; no turn runs after it. A Roc crash or a host fatal
error prints the message, shows it in an alert, then exits with status 1.
Under `ROC_SCRIPT` it never shows the alert. The modal loop
runs no turns, so a timer cannot re-enter Roc after a crash. `dbg` still
prints to stderr.

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
