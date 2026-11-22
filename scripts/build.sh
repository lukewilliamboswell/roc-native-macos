#!/usr/bin/env bash
# Build the platform's native inputs and every example.
#
#   scripts/build.sh            # glue header, Swift host, sysroot, then every example
#   scripts/build.sh counter    # just one example (after the platform is built)
#
# ROC defaults to the 0.1.0 RC1 compiler; override with ROC=/path/to/roc.
set -euo pipefail

ROC="${ROC:-$HOME/roc-macos_apple_silicon-0.1.0_RC1/roc}"
here="$(cd "$(dirname "$0")/.." && pwd)"
platform="$here/platform"
targets="$platform/targets/arm64mac"

build_platform() {
	# 1. Glue: SwiftGlue writes the C ABI header Swift imports as its bridging
	#    header (roc_swift_abi.h) and Swift helpers for Roc lists and typed
	#    entry points (RocGlue.swift).
	"$ROC" glue "$here/glue/SwiftGlue.roc" "$here/host" "$platform/main.roc" >/dev/null

	# 2. The Swift host as a static library. Swift's framework autolinking and
	#    FORCE_LOAD symbols are off: the frameworks the host links are exactly
	#    the ones the catalog generates stubs for.
	mkdir -p "$targets"
	swiftc -O -parse-as-library -static -emit-library -module-name RocHost \
		-Xfrontend -disable-force-load-symbols -Xfrontend -disable-autolink-frameworks \
		-import-objc-header "$here/host/roc_swift_abi.h" \
		"$here"/host/*.swift -o "$targets/libhost.a"

	# 3. The sysroot Roc's linker uses for this platform: TAPI stubs generated
	#    from the reviewed catalog alone. No Apple SDK file is read or bundled.
	python3 -I "$here/scripts/build_macos_stubs.py" "$here/host/interfaces.json" \
		"$platform/targets/macos-sysroot" --audit "$targets/libhost.a"
}

build_example() {
	name="$1"
	echo "building examples/$name"
	(cd "$here/examples/$name" && "$ROC" build main.roc --output="$here/examples/$name/$name")
}

if [[ $# -eq 0 ]]; then
	build_platform
	for dir in "$here"/examples/*/; do build_example "$(basename "$dir")"; done
else
	for name in "$@"; do build_example "$name"; done
fi
