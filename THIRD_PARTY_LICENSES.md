# Third-party licenses

The repository's own code is under the [UPL 1.0](LICENSE). This file lists
code it copies from elsewhere, the packages it fetches, and what its
applications link at run time.

## Roc packages the compiler fetches

The compiler fetches these by content-addressed URL. Their source is not copied
into this repository.

- [roc-signals 0.8.0-rc2](https://github.com/lukewilliamboswell/roc-signals/releases/tag/0.8.0-rc2)'s
  engine package, which the platform imports and re-exposes as `Engine`,
  `Layout`, `Wire` and `Worker`. Copyright © 2026 Luke Boswell; UPL Version
  1.0. Its `Url` module derives from
  [basic-webserver](https://github.com/roc-lang/basic-webserver) (Copyright ©
  2023 Richard Feldman and subsequent Roc authors; UPL Version 1.0).
- [roc-parser 6.0.0-rc.5](https://github.com/lukewilliamboswell/roc-parser/releases/tag/6.0.0-rc.5),
  which the engine package imports. Copyright © 2023 Luke Boswell and
  subsequent authors; UPL Version 1.0.
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
