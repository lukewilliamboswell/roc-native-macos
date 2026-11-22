# Provenance of the macOS linker interfaces

The platform links apps against macOS's own libraries through minimal TAPI
text stubs (`.tbd` files) under `targets/macos-sysroot`. This repository
writes those stubs itself, from scratch, as the release
`linker-inputs-sha256-<manifest digest>` that `link-inputs.lock.json` selects.
They exist only so that Roc's linker can resolve the independently compiled
host's references to libraries that macOS supplies at run time.

## What the stubs contain

Each stub names its target (`arm64-macos`), one library's install name, and
the symbols the reviewed catalog `host/interfaces.json` assigns to that
library. Nothing else: no reexports, no versions, no implementation. macOS
supplies every implementation when an app runs. The TAPI text format is
openly implemented by LLVM's TextAPI reader and writer.

## Where the catalog's facts come from

`host/interfaces.json` records, for every library, its install name and the
public evidence for it, and for every symbol, the public evidence that the
library declares it. The evidence is limited to:

- Apple's public developer documentation (developer.apple.com), which
  establishes the spelling of a class, function or constant;
- identified open-source declarations: apple-oss-distributions (Libc,
  libdispatch, libplatform, CommonCrypto, objc4, dyld), the Swift project
  (swiftlang/swift, swift-foundation, swift-corelibs-foundation,
  swift-corelibs-libdispatch), LLVM and clang; and
- the C and POSIX standards and the manual pages they are documented in.

A Swift symbol's evidence names the declaration it mangles. That name comes
from the open-source Swift demangler, run on the catalog's own mangled names,
and the declaration is in the open-source module the catalog names.

## What is never read

The producer reads no Apple SDK headers, `.tbd` files, framework binaries,
dylibs, object files, symbol tables or generated SDK metadata, and no other
installed macOS software, and none of those supplies a symbol, an install
name or an ownership to the catalog. The linker-input release redistributes
no Apple SDK file and no framework implementation.

## How the host is used

The project-built `libhost.a` is only inventoried: its unresolved references
(`nm -u`, less what it defines itself) are checked against the catalog, and a
reference the catalog does not own fails the build. That check never adds
to the catalog. A new symbol is a reviewed catalog edit that names its
library and its evidence, and a link error is never silenced by widening the
catalog.

## How the release is made

The producer (`.github/workflows/link-inputs.yml`, running
`scripts/link_inputs.roc`) reads only the catalog, this statement and its own
source. It writes the stubs twice and requires identical archives, links and
runs every example against them with a host built from the same commit, and
writes `build-input-release.json`, which binds the archive's SHA-256 and size
to the source commit and to an input fingerprint over those files and the
tooling compiler. A trusted publisher on the default branch
(`.github/workflows/publish-link-inputs.yml`, roc-automation's
`actions/publish-build-inputs`) verifies the producer run and its
build-provenance attestations, publishes the archive as an immutable release
and commits only `link-inputs.lock.json`. The host's identity, and the Xcode
that built it, are validation evidence and not part of the archive's
identity.
