# Working in this repository

These are the rules for any agent, human or automated, changing this
repository. `blueprint run check` enforces the ones a machine can check; the
rest need a reviewer.

## Before you open a pull request

Run `blueprint run check` with a current Roc nightly installed as `roc`. It is
the same gate CI runs on `macos-15`: compiler pins, the engine facades,
formatting, the scripts' tests, the `macos.roc` tool's package (`cli/`),
the committed glue, `scripts/build.roc`, `roc test`, every example's recorded scripted runs
(`examples/<example>/tests/`), and the platform bundle with the starter app created, built,
tested and packaged against it through `macos.roc` (`scripts/bundle.roc --test`). A new example needs at
least one recorded case: add `examples/<example>/tests/<case>.script` and run
`blueprint run examples -- --update`. Review the `.expected` diff before you
commit it.

## The engine is roc-signals' engine package

`platform/main.roc` names roc-signals' standalone engine package as
`engine`, and reaches its host contract through `engine.EngineHost`. A
platform cannot expose a package's module, so
`platform/{Engine,Layout,Wire,Worker}.roc` are generated facades that
re-expose the package's modules of the same names, and apps keep writing
`import pf.Engine`. The `engine` stage of the check fails when they are not
what the package gives.

- Never edit the facades: regenerate them with
  `blueprint run build -- engine` (`scripts/src/Facade.roc`) and review the
  diff.
- To take a newer engine, change the `engine` URL in `platform/main.roc`,
  regenerate the facades, and update the version in
  `docs/architecture.adoc` ("Engine"), `THIRD_PARTY_LICENSES.md` and
  `sbom/composition.json`, all in the same commit.
- Nothing in the engine is patched here. A change this platform needs is
  made in roc-signals first, and taken with its release.
- A cost that is the compiler's goes in `patches/roc-compiler/` as a
  standalone reproducer and its write-up; never patch the compiler here.

The native vocabulary belongs in `platform/Ui.roc`, and the root in
`platform/main.roc`.

## No Apple SDK material in linker inputs

The sysroot Roc links against (`platform/targets/macos-sysroot`) is generated
by `scripts/link_inputs.roc` from the reviewed catalog `host/interfaces.json`
alone, and released on its own: `link-inputs.lock.json` selects the release,
and only `publish-link-inputs.yml` writes the lock. Never read, copy or derive
anything from Apple SDK `.tbd` files, headers or framework binaries
(`host/PROVENANCE.md`), and never commit generated stubs or `libhost.a`. A
new symbol the host references fails the build's audit until the catalog
owns it. Add it in a reviewed edit that names its library and the symbol's
own evidence, and never expand the catalog to silence a link error; a
catalog change is a new linker-input release. Keep Swift's
`-disable-autolink-frameworks` and `-disable-force-load-symbols`, and keep
the host reproducible: every path relative, objects at fixed paths,
`libtool -D`.

## Where Roc runs

The page's instance runs on the main thread only: every call into its entry
points (`roc_engine_init`, `roc_engine_event`, `roc_engine_files`,
`roc_engine_drop`) happens on the AppKit main thread, one engine turn at a
time. Work done elsewhere, such as a timer, a network request, a file read
or a worker's answer, hops back with `DispatchQueue.main.async` before it
calls the engine. Never re-enter the engine from inside a turn.

A worker instance runs only on its own worker thread: the worker entry
points (`roc_engine_work`, `_prepare`, `_ask`, `_forget`) are called only
there, through their guarded calls (`Roc.*Guarded`), with that thread's
`WorkerContext` set. Nothing crosses between instances but bytes and
`FileEntry` values: never a Roc list, box or handle. Unwind
(`roc_guard_unwind`) only from a runtime symbol or hosted function inside a
guarded call, holding no lock, and then discard the instance's heap.

## The ABI and the glue

`glue/SwiftGlue.roc` generates `host/roc_swift_abi.h` and `host/RocGlue.swift`
from the compiler's layout facts. They are committed, and the check's `glue`
stage fails when they are not what the `roc` on PATH generates: regenerate
them with `blueprint run build -- glue` and commit the diff with any host
change it needs. Do not hand-edit them, or hand-encode a Roc value in Swift. A list's `capacity_or_alloc_ptr` stores the capacity shifted
left one bit, and its low bit marks a seamless slice; a raw length makes an
odd-length payload read as a slice and crash. Build lists with `RocList.ownedBytes` / `.bytes` /
`.empty`, and call entry points through the typed `Roc.*` functions. When a
provided procedure needs a new shape, extend SwiftGlue so it generates the
shape, rather than working around it in the host. SwiftGlue fails generation
on any shape it does not support.

## Roc compiler gotchas

- The platform, examples, glue and the `macos.roc` tool (`cli/`) are
  checked, built and tested with `roc`, the latest nightly, and formatted
  with `roc fmt`. Pin no compiler in them. Only the scripts under `scripts/`
  pin `roc: "<tag>"`, the `roc-stable` release `Blueprint.roc` names. Format
  scripts with `roc-stable fmt`.
- `app` is a keyword: it cannot name a variable or a record field.
- A function with no arguments is written `() -> T` in annotations and
  `|| ...` in definitions, as `Ui.divider : () -> Elem(ctx)` is.
- A record builder with a single field, `{ a: Engine.cell(…) }.Engine.Cells`,
  is unimplemented in RC1-era compilers. `roc build` still succeeds and the
  app hits a runtime error. `roc test` reports it, so run it, and give a store
  at least two cells.
- `Engine.watch` never cancels what it issued. A start/stop effect such as an
  interval uses `Engine.watch_latest`.

## The tool

`cli/` is `macos.roc`, the app author's tool. `cli/Bundle.roc` is generated
by `scripts/src/Release.roc`: never hand-edit it; `blueprint run check -- tool
--update` rewrites it. `scripts/src/Recorded.roc` is a byte-identical copy of
`cli/Recorded.roc`, the one definition of how a recorded case's output is
compared: change `cli/Recorded.roc` and copy it over. The tool's `build` must
keep working from Linux and Windows: write files and run `roc`, and never
call a macOS program to build. Every failure is one sentence from
`MacOS.explain`.

What `init` writes is `examples/starter`, every tracked file of it: change
the scaffold by changing that example (its cases, `expect`s and fuzz
targets run in `check` like any example's), then regenerate
`cli/Bundle.roc`. Its `AGENTS.md` is the app author's, and says what an
agent working on an app must know; keep it accurate when the tool, the
platform or the starter change. The tool reads an app's root module from
`src/main.roc`, or from `main.roc` at the top for apps made by 0.0.1; keep
both working.

## Change discipline

- `README.md` is the landing page for app authors: keep it short, and keep
  host internals and contributor material out of it. An app author works
  from a release with `macos.roc` and never builds the platform, so nothing
  written for them may need a checkout. Put detail in the `docs/` manual
  (`index.adoc` includes one chapter per file: `apps.adoc` and `ui.adoc` for
  app authors, `architecture.adoc` and `contributing.adoc` for
  contributors). `CONTRIBUTING.md` only points into the manual. Keep
  follow-up work in issues, not in documents. When `platform/Ui.roc`
  changes, update `docs/ui.adoc` in the same commit; when the host's scripted
  steps or `ROC_*` variables change, update `docs/apps.adoc`.
- Unknown commands or effects in the host are fatal errors with a clear
  message, never silent skips.
- Do not commit build outputs (`examples/<name>/<name>`, `platform/targets/`,
  `build/`) or `.blueprint/`. The generated glue in `host/` is the exception:
  it is committed, and regenerated, never edited.
- Do not commit or push unless asked.
