# Working on this app

A native macOS app written in [Roc](https://www.roc-lang.org) on
[roc-native-macos](https://github.com/lukewilliamboswell/roc-native-macos),
whose views are real AppKit controls driven by the
[roc-signals](https://lukewilliamboswell.github.io/roc-signals/docs/guide/)
reactive engine. It starts as an expense tracker; keep its structure and
replace its subject. Every module opens with a `##` comment saying what
belongs in it: read that before changing the module.

## Commands

Run them from this directory. They need Roc on PATH as `roc`.

| Command | What it does |
|---|---|
| `roc macos.roc dev` | start the app with hot reloading; save, then press Command-R in the app |
| `roc macos.roc run` | build `<name>.app` and start it, its output here |
| `roc test src/main.roc` | the `expect` tests alone, of `src/` and `logic/`: fast, on any system |
| `roc macos.roc test` | the `expect` tests, then the specs in `specs/` |
| `roc macos.roc test --update` | rewrite each spec's `expect-dump` with what the app shows now; review the diff |
| `roc macos.roc test --check` | only parse the specs, on any system |
| `roc macos.roc fuzz` | build `fuzz/main.roc` and fuzz each target for 10 seconds |
| `roc macos.roc fuzz --check` | only each target's declared examples, as CI does |
| `roc macos.roc fuzz money-parse --time 120` | one target, for longer |
| `roc fmt src logic fuzz` | format the sources (`roc fmt --check ...` to check) |
| `roc macos.roc build`, `package` | the `.app`, and `dist/<name>-<version>.zip` to share |

`roc macos.roc COMMAND --help` describes a command. The app runs, and
`dev`, `run` and the specs work, only on a Mac (Apple silicon or Intel);
`build`, `package` and `roc test` work anywhere, and `fuzz` on Apple
silicon and Linux x64. Before you finish a change, run `roc fmt src logic
fuzz`, `roc macos.roc test` and `roc macos.roc fuzz --check`.

## Layout

```
src/main.roc       the program: store, window and workers; its header names the platform and logic/
src/Store.roc      shared state (the store's cells) and the decisions that change it, with expects
src/Home.roc       the window: composes the store, the widgets and the effect sites
src/Widgets.roc    reusable widgets, which never import Store
src/Import.roc     a worker task and the effect site that asks for it
logic/main.roc     the logic package's header: its modules, pure Roc with no platform
logic/Money.roc    amounts as cents: parse and format, with expects
logic/Ledger.roc   expenses: entry, totals and the CSV format, with expects
fuzz/main.roc      roc-fuzz targets for logic/: a development program, not part of the app
assets/icon.png    the app's icon, also drawn in the window (Ui.asset_image("icon.png", ...))
specs/*.scm        specs: steps that drive the app's real controls, and what it then shows
specs/fixtures/    files the specs' steps use
macos.json         the app's name, bundle identifier and version
```

Generated and ignored: `.macos/` (builds), `<name>.app`, `dist/`, `.roc-fuzz/`.

## How state flows

A view runs once, when the window opens. An event runs a handler, which
returns writes; the engine applies them and wakes only the views that read
what changed. So:

- State more than one part of the window shares lives in the store
  (`Store.roc`), and changes only through decisions: pure functions that
  return writes (`Store.added`), tested with `Store.store.after(writes)`.
- State one piece of the view cares about is local to it, in
  `Engine.state(initial, |s| ...)` (`Home.form`'s draft, `Widgets.card`'s
  open flag). It starts again when that piece is rebuilt.
- A value that follows from state is not state: `signal.map(...)`, or
  `Engine.derive` when it is costly or read in several places
  (`Home.summary`).
- Effects (saving, a worker job) are asked for by sites that watch a signal
  (`Engine.watch_latest`, `Engine.watch_changes`), and their answers come
  back as writes (`Engine.react`).
- Rules that need no window go in `logic/`, where they are tested with
  `expect` and fuzzed. `src/` imports `logic`; never the other way round.

## Recipes

- **A screen**: a module like `Home.roc` with a `view`; switch screens with
  `Ui.tabs` or `Engine.switch` over a store cell naming the shown one.
- **A widget**: a function in `Widgets.roc` returning `Elem(ctx)` for any
  `ctx`, handed what it shows (values, signals, handlers); local state
  inside it if only it reads that state.
- **A worker**: declare `Worker.task({ name, run! })` as `Import.roc` does,
  add `task.registration()` to `.with_workers([...])` in `src/main.roc`,
  and ask for jobs from an effect site. Only data and `File` handles cross
  to a worker.
- **Logic**: a type module `logic/<Name>.roc`, listed in `logic/main.roc`'s
  `package [...]`, with `expect`s beside it; a property of it as a target in
  `fuzz/main.roc`'s `Fuzz.suite([...])`.
- **An image**: put it in `assets/` and draw it with
  `Ui.asset_image("name.png", { width: Fixed(64), label: "..." })`.
- **A spec**: write `specs/<name>.scm`, a `(test "name" (steps ...))` with
  steps such as `(fill (text-field) "Coffee 4.50")`, `(submit (text-field))`
  and `(click (button "Hide Summary"))`, and end it with `(expect-dump _)`;
  run `roc macos.roc test --update`, which writes the window's tree in, and
  review the diff.

The builders and the steps are documented in
[Build an app](https://lukewilliamboswell.github.io/roc-native-macos/apps.html)
and [the Ui reference](https://lukewilliamboswell.github.io/roc-native-macos/ui.html);
the engine (`Engine`, `Worker`) in the
[roc-signals guide](https://lukewilliamboswell.github.io/roc-signals/docs/guide/);
fuzzing in the [roc-fuzz manual](https://lukewilliamboswell.github.io/roc-fuzz/).

## Gotchas

- A store needs at least two cells: a single-field record builder,
  `{ a: Engine.cell(0) }.Engine.Cells`, compiles but fails at run time.
  `roc test` reports it.
- `Engine.watch` and `Engine.watch_changes` never cancel what they asked
  for when their value changes. Anything that must stop or restart (an
  interval, a request, a worker job superseded by a newer one) belongs
  under `Engine.watch_latest`.
- Roc does not allow shadowing, and a type module's own functions are in
  scope throughout it: a local or a lambda's argument cannot reuse one's
  name (`Ledger` names its line parser `read_line` so `line` stays free).
- A builder's text is a signal. A literal works as one
  (`Ui.text("Spent", {})`); a `Str` value needs `Engine.const(value)`, and
  state needs `.signal()` or `.map`.
- A function with no arguments is `() -> T` in annotations and `|| ...` in
  definitions. `app` is a keyword and cannot name a value or a field.
- `logic/` cannot import the platform: a package that needs `pf.` belongs
  in `src/`.
- A fuzz target's saved and mutated inputs bypass its generator, so a
  property restates its preconditions and returns `Fuzz.reject` outside
  them (`money-round-trip` does).
- A spec's `(button "Save")` finds a button by its title and acts only on
  exactly one, so give buttons distinct titles (`title_display: Hidden`
  keeps an icon-only button's title for this and for VoiceOver), or name the
  K-th of several, `(button "Remove" 2)`.
- Hot reloading keeps the state the old code built until Command-R; after
  changing a cell's or a state's type, press Command-R before anything else.
