# Provenance of the macOS linker interfaces

The platform links apps against macOS's own libraries through minimal TAPI
text stubs (`.tbd` files) under `targets/macos-sysroot`. This repository
writes those stubs itself, from scratch, as the release
`linker-inputs-sha256-<manifest digest>` that `link-inputs.lock.json` selects.
They exist only so that Roc's linker can resolve the independently compiled
host's references to libraries that macOS supplies at run time.

## What the stubs contain

Each stub names its targets (`arm64-macos` and `x86_64-macos`, for Apple
silicon and Intel Macs, which link against the one sysroot), one library's
install name, and the symbols the reviewed catalog `host/interfaces.json`
assigns to that library: those of both architectures, then any the catalog
says only one architecture exports (`only`). Nothing else: no reexports, no
versions, no implementation. macOS supplies every implementation when an app
runs. The TAPI text format is openly implemented by LLVM's TextAPI reader and
writer.

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

The project-built `libhost.a`, one for each architecture, is only
inventoried: its unresolved references (`nm -u`, less what it defines itself)
are checked against what the catalog exports for its architecture, and a
reference the catalog does not own there fails the build. That check never
adds to the catalog. A new symbol is a reviewed catalog edit that names its
library and its evidence, and a link error is never silenced by widening the
catalog. A symbol only one architecture has, such as x86-64's
`objc_msgSend_stret` or `stat$INODE64`, names that architecture in `only`,
with the evidence that it is that architecture's alone.

## Roc's run-mode shims

The stubs have one other consumer: the run shims of the Roc compiler,
`libroc_machine_code_shim.a` and `libroc_interpreter_shim.a`, which `roc
main.roc` and `roc run` link the host with in place of the app's object.
Their system imports are listed in the catalog's `run_shim`, and each is
owned by a library with its own evidence under the same rules as the host's:
the public documentation or open-source declaration of the function, and the
open-source Roc or Zig source (roc-lang/roc, ziglang/zig `lib/std`) that
calls it. Three are not documented API. `__ulock_wait` and `__ulock_wake`
are the address wait and wake of apple-oss-distributions/xnu
(`bsd/sys/ulock.h`), which Zig's standard library declares and calls for its
futex. `close$NOCANCEL` is the non-cancellable variant of `close` that Libc's
`sys/cdefs.h` names (`__DARWIN_NOCANCEL`), which Zig's standard library
calls. `_tlv_bootstrap` is the thread-local initializer of
apple-oss-distributions/dyld that every Mach-O thread-local variable names.

The shims are inventoried like the host: the build carves them out of the
`roc` binary, where they are embedded, and checks their `nm -u` against what
the catalog exports for the architecture that `roc` is built for (CI audits
the shims of the Apple silicon and the Intel `roc`). Roc's own source bounds what a macOS shim may import
(`src/machine_code_shim/archive_check.zig`). The shims are Roc's, not Apple
material, and nothing of them is read beyond their symbol tables.

## How the release is made

The producer (`.github/workflows/link-inputs.yml`, running
`scripts/link_inputs.roc`) reads only the catalog, this statement and its own
source. It writes the stubs twice and requires identical archives, links and
runs every example against them with the hosts built from the same commit, on
an Apple silicon and on an Intel Mac, and
writes `build-input-release.json`, which binds the archive's SHA-256 and size
to the source commit and to an input fingerprint over those files and the
tooling compiler. A trusted publisher on the default branch
(`.github/workflows/publish-link-inputs.yml`, roc-automation's
`actions/publish-build-inputs`) verifies the producer run and its
build-provenance attestations, publishes the archive as an immutable release
and commits only `link-inputs.lock.json`. The host's identity, and the Xcode
that built it, are validation evidence and not part of the archive's
identity.
