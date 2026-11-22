# Third-party licenses

The repository's own code is under the [UPL 1.0](LICENSE). This file lists
code it copies from elsewhere, the packages it fetches, and what its
applications link at run time.

## Engine modules from roc-signals

The engine modules in `platform/` (`Core`, `Engine`, `Web`, `EntryRoutes`,
`Url`, `ReadyIndex`, `Spelling`, `Layout`, `TableCore`, `View`, `Seq`,
`MarkupAdvice` and `SignalCore`) are unmodified copies from
[roc-signals](https://github.com/lukewilliamboswell/roc-signals). Copyright ©
2026 Luke Boswell, the copyright holder of this repository; Universal Permissive
License (UPL), Version 1.0. `tests/engine-modules.sha256` records their digests.

## URL utility

`platform/Url.roc`, one of those modules, derives from
[basic-webserver](https://github.com/roc-lang/basic-webserver). Copyright ©
2023 Richard Feldman and subsequent Roc authors; Universal Permissive License
(UPL), Version 1.0, in that repository's `LICENSE`. Its parsing tests are a
curated subset informed by web-platform-tests' `url/resources/urltestdata.json`
(BSD-3-Clause), and they keep the source note that names the WPT commit.

## Roc packages the compiler fetches

The compiler fetches these by content-addressed URL. Their source is not copied
into this repository.

- [roc-parser 6.0.0-rc.5](https://github.com/lukewilliamboswell/roc-parser/releases/tag/6.0.0-rc.5),
  which the platform imports. Copyright © 2023 Luke Boswell and subsequent
  authors; UPL Version 1.0.
- [basic-cli 0.28.1](https://github.com/roc-lang/basic-cli/releases/tag/0.28.1),
  the scripts' platform. Copyright © 2022 Richard Feldman and subsequent
  basic-cli authors; UPL Version 1.0. The scripts alone use it, and no
  application links it.
- [roc-lang/http 1.0.0](https://github.com/roc-lang/http/releases/tag/1.0.0),
  which basic-cli uses. Copyright © 2025 Richard Feldman and subsequent Roc
  authors; UPL Version 1.0.
- [roc-blueprint 0.13.0](https://github.com/lukewilliamboswell/roc-blueprint/releases/tag/0.13.0),
  which evaluates `Blueprint.roc`. Copyright © 2026 Luke Boswell and
  subsequent authors; UPL Version 1.0.

## macOS system libraries and generated stubs

Applications link AppKit, Foundation, CoreGraphics, libSystem, libobjc and the
Swift runtime and overlays in `/usr/lib/swift`. macOS supplies all of them at
run time, and the repository does not copy or redistribute any of them.

`scripts/link_inputs.roc` writes the linker stubs in
`platform/targets/macos-sysroot/` from scratch. They are minimal TAPI
descriptions of install names and symbol names, taken only from the reviewed
catalog `host/interfaces.json`. The generator reads no Apple SDK header, `.tbd`
file or framework binary, and the stubs contain no Apple SDK material.

`platform/targets/arm64mac/libhost.a` is this repository's Swift host,
compiled with Xcode's `swiftc`. It holds only the host's own object code, and
links the Swift runtime from the system.
