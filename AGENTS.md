# Working in this repository

roc-native-macos is a Roc platform for native macOS apps: a Swift host that
draws real AppKit controls, driven by roc-signals' engine, and `macos.roc`,
the tool an app author creates, builds, tests and ships an app with. These
are the rules for anyone changing it, a person or an agent. The manual in
`docs/` holds the detail; this file holds only what every change must keep.

## The gate

`blueprint run check`, with a current Roc nightly on PATH as `roc`, is the
gate CI runs on `macos-15`: compiler pins, generated files, formatting,
`expect` tests, the build, every example's and bench harness's specs, the
build matrix, and the platform bundle driven through `macos.roc` as an
author would. Run it before you open a pull request; its stages are listed
in `docs/contributing.adoc` ("The check gate").

## Invariants

- **No Apple SDK material in linker inputs.** The linker stubs are generated
  from the reviewed catalog `host/interfaces.json` alone
  (`scripts/link_inputs.roc`, `host/PROVENANCE.md`), so the platform can be
  redistributed. Never read, copy or derive anything from SDK `.tbd` files,
  headers or framework binaries, and never commit generated stubs or
  `libhost.a`. A symbol the build's audit names joins the catalog in a
  reviewed edit that names its library and its evidence, never to silence a
  link error; a catalog change is a new linker-input release.
- **Roc runs on the main thread, or on its own worker thread.** The page's
  engine is single-threaded and not re-entrant: its entry points are called
  on the AppKit main thread, one turn at a time, and work done elsewhere
  hops back with `DispatchQueue.main.async`. A worker's entry points run
  only on that worker's thread, through their guarded calls, and only bytes
  and `FileEntry` values cross between instances
  (`docs/architecture.adoc`, "Effects and threads" and "Workers").
- **Generated files are regenerated, never hand-edited**, so they always
  match their generator, and the check fails when they do not:
  - the glue, `host/roc_swift_abi.h` and `host/RocGlue.swift`, from
    `glue/SwiftGlue.roc`: `blueprint run build -- glue`. Extend SwiftGlue
    for a new shape rather than encoding a Roc value by hand in Swift;
  - the engine facades, `platform/{Engine,Layout,Wire,Worker}.roc`:
    `blueprint run build -- engine`;
  - `cli/Bundle.roc`, which embeds the starter as `init`'s scaffold:
    `blueprint run check -- tool --update`;
  - `scripts/src/Spec.roc` and `scripts/src/SpecRun.roc` are byte-identical
    copies of `cli/Spec.roc` and `cli/SpecRun.roc`: change those, then copy.
- **The engine is not patched here.** It is roc-signals' engine package,
  named in `platform/main.roc`, so a change it needs is made in roc-signals
  and taken with a release. Likewise a cost that is the compiler's is
  reported to roc-lang/roc with a standalone reproducer, and its
  workaround links the issue.
- **The tool builds from any system.** An app author may be on Linux or
  Windows, so `macos.roc build` only writes files and runs `roc`; it never
  calls a macOS program.
- **Failures are one sentence.** Every failure of the tool is explained in
  a sentence by `MacOS.explain`; an unknown command or effect in the host
  is a fatal error with a clear message, never a silent skip.

## Where things go

- The native vocabulary in `platform/Ui.roc`; the platform root in
  `platform/main.roc`.
- An app's tests under its `tests/`: specs in `tests/specs/<name>.scm`
  (a `(demo …)` spec is a recording, parsed but never run as a test), the
  files they use in `tests/fixtures/`, fuzz targets in
  `tests/fuzz/main.roc`. Every example and bench harness is laid out so; a
  new example needs at least one spec, recorded with
  `blueprint run examples -- --update` and its diff reviewed.
- What `macos.roc init` writes is `examples/starter`, every tracked file of
  it: change the scaffold there, then regenerate `cli/Bundle.roc`.
- Documentation in the manual, one chapter a file: `docs/apps.adoc` and
  `docs/ui.adoc` for app authors, `docs/architecture.adoc` and
  `docs/contributing.adoc` for contributors. `README.md` is the app
  author's landing page, short and needing no checkout; `CONTRIBUTING.md`
  only points into the manual. Follow-up work goes in issues.

## Change discipline

- Before 1.0, breaking changes are fine: no compatibility paths, and a line
  in the next release's notes.
- Keep the docs in step in the same commit: `docs/ui.adoc` with
  `platform/Ui.roc`, and `docs/apps.adoc` with the tool, the starter, the
  spec grammar or the host's `ROC_*` variables.
- Pin no compiler outside `scripts/`, whose scripts pin the `roc-stable`
  release `Blueprint.roc` names (`docs/contributing.adoc`, "Two compilers").
- Do not commit build outputs (`examples/<name>/<name>`, `platform/targets/`,
  `build/`) or `.blueprint/`.
- Do not commit or push unless asked.
