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
./examples/counter/counter      # or stopwatch, todos, gallery, contacts
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
  `roc_engine_drop` and `roc_engine_version`, with no hosted functions, workers,
  ports, files or crypto.
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
  - storage, via `UserDefaults`.

  It keeps a node tree mirroring what the engine built and gives each `ui-*`
  element one AppKit view. It routes AppKit actions back as turns: `click`,
  `input`, `change`, `submit`, a list row's `select`, and key events. Any
  other command or effect is a clear fatal error, not a silent skip.

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

Steps: `click:<title>`, `type:<text>` (first text field), `write:<text>`
(first text area, `\n` for a line break), `enter` (submit its form),
`toggle:<checkbox title>`, `choose:<title>` (a dropdown item or segment),
`select:<text>` (the list row holding that text), `key:cmd+shift+n` (a key
press delivered as if nothing had focus), `wait:<ms>`, `dump` (window size,
then the view tree; a list shows its visible rows), `quit`. `ROC_TRACE=1`
logs effect requests and cancellations, and each turn's engine and host
time; `ROC_POISON=1` fills every new allocation
with `Z`, to expose reads of uninitialised memory. A scripted run never takes
keyboard focus.

roc-signals' `.scm` spec runner is not ported. Its oracle (`Dom.roc`) models
a browser DOM, so it would check the engine but never the AppKit host. A spec
format over the scripted driver, or a `ui-*` oracle, are the two options.

## Examples

| Example | Shows |
|---|---|
| `counter` | Local state (`Engine.state`), buttons, a readout |
| `todos` | A store with a table, `table_view` rows (row templates) in a `Ui.scroll`, a form with Return-to-submit, a Command-N shortcut, checkboxes, `when`, and `expect` tests (`roc test examples/todos/main.roc`) |
| `gallery` | `tabs` over pages, a dropdown, a text area, SF Symbols, progress bars, styled text, Command-N/Command-K shortcuts |
| `contacts` | 10,000 generated rows in a `Ui.list` (`NSTableView`), a search field filtering through the `table_view` query, row selection |
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
- **Props records work.** A nominal record of `??` defaulted fields as a
  function argument (`Ui.vstack({ align: Fill }, kids)`, `Ui.scroll({}, rows)`)
  checks, builds and runs correctly in RC1.
- **No `Str` order.** `Str` has no `order_relative_to` in RC1, so
  `Engine.sort_by` cannot sort rows by a name; `contacts` sorts by key.
- **Host costs, not engine costs.** For 10k rows the engine's turns are
  milliseconds; the host was seconds until it stopped removing children one
  O(n) scan at a time (removals now compact once per batch) and stopped
  creating AppKit views for list rows nobody had scrolled to.

## Licence

[UPL 1.0](LICENSE). The engine modules come from roc-signals (UPL 1.0, the
same copyright holder).
