#!/usr/bin/env bash
# Build the platform's native inputs and every example.
#
#   scripts/build.sh            # glue header, Swift host, sysroot, then every example
#   scripts/build.sh counter    # just one example (after the platform is built)
#   scripts/build.sh --platform # just the platform: glue header, Swift host, sysroot
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
	bundle_example "$name"
}

# A minimal .app beside the bare binary, so `open examples/<name>/<name>.app`
# launches it with a bundle identifier (window tabbing, UserDefaults domain).
# LSMinimumSystemVersion matches the minos Roc's linker writes (11.0).
# The example's assets/ go to Contents/Resources/assets, where the host looks
# (the bare binary finds the same directory beside it). An assets/icon.icns
# becomes the app's icon; `macos.roc build` also makes one from an icon.png,
# which this script does not.
bundle_example() {
	name="$1"
	app="$here/examples/$name/$name.app"
	assets="$here/examples/$name/assets"
	icon=""
	rm -rf "$app"
	mkdir -p "$app/Contents/MacOS"
	cp "$here/examples/$name/$name" "$app/Contents/MacOS/$name"
	if [[ -d $assets ]]; then
		mkdir -p "$app/Contents/Resources"
		cp -R "$assets" "$app/Contents/Resources/assets"
		if [[ -f $assets/icon.icns ]]; then
			cp "$assets/icon.icns" "$app/Contents/Resources/AppIcon.icns"
			icon="<key>CFBundleIconFile</key><string>AppIcon</string>"
		fi
	fi
	cat >"$app/Contents/Info.plist" <<-PLIST
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>CFBundleIdentifier</key><string>dev.roc.native.$name</string>
		<key>CFBundleName</key><string>$name</string>
		<key>CFBundleExecutable</key><string>$name</string>
		<key>CFBundlePackageType</key><string>APPL</string>
		<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
		<key>CFBundleShortVersionString</key><string>0.1</string>
		<key>NSPrincipalClass</key><string>NSApplication</string>
		<key>NSHighResolutionCapable</key><true/>
		<key>LSMinimumSystemVersion</key><string>11.0</string>
		$icon
	</dict>
	</plist>
	PLIST
}

if [[ $# -eq 0 ]]; then
	build_platform
	for dir in "$here"/examples/*/; do build_example "$(basename "$dir")"; done
elif [[ $1 == --platform ]]; then
	build_platform
else
	for name in "$@"; do build_example "$name"; done
fi
