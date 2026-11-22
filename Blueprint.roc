# Development environment and tasks for roc-native-macos, realised by roc-blueprint.
#
#     blueprint run check                  # the pull-request gate
#     blueprint run build                  # glue, Swift host, linker stubs, every example
#     blueprint run build -- counter       # one example, after the platform is built
#     blueprint run test                   # roc test on the platform root and the examples
#     blueprint run examples               # every example's recorded scripted runs
#     blueprint run examples -- --update   # record what they print now, as a reviewable diff
#     blueprint run bundle                 # the platform bundle, in build/platform/<hash>.tar.zst
#     blueprint run bundle -- --test       # and a counter made with macos.roc against it
#     blueprint run release -- test DIR    # every archived example against DIR's bundle
#     blueprint tasks                      # list every task
#     blueprint update                     # refresh Blueprint.lock
#
# Two Roc compilers have two jobs (roc-automation's model): `roc-stable`,
# pinned below, runs the scripts under scripts/; `roc`, the latest Roc
# nightly, checks, builds and tests the platform and the examples. `roc` is
# never pinned: CI installs it with roc-automation's setup-roc-nightly, and a
# contributor installs a current nightly (or a release such as 0.1.0 RC1) as
# `roc`, so the environment expects it on PATH.
#
# The host is Swift and links AppKit, so the environment is Apple silicon
# macOS only, and Xcode's `swiftc` comes from the machine.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.13.0/DBtzmMfrSgt6nCGVAcZYCVPxWbhpqw3MXpm6sdQzMn4v.tar.zst" }

import pf.Recipes

# The scripts' tooling compiler (`roc-stable`): every script's `roc` header
# field names this release, and `check` fails until they match. It is the
# same release roc-signals' scripts use.
roc_stable_program = Fetch("roc-stable", Recipes.roc_nightly("nightly-2026-11-14-a87808d"))

config = [
	Name("roc-native-macos"),
	Systems(["aarch64-darwin"]),
	Environment(
		"dev",
		[
			Programs([roc_stable_program]),
			# Every bundle the scripts depend on, including dependencies of
			# dependencies: `roc-stable deps scripts/check_all.roc` lists them.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
				"https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
			]),
			# `bash` runs scripts/build.sh, `swiftc` builds the host, `python3`
			# generates the linker stubs (scripts/build_macos_stubs.py) and
			# serves the bundle to its consumer tests (scripts/bundle.roc,
			# scripts/release.roc), `shasum` checks the engine modules' digests
			# and the release files', `git` lists the tracked files the checks
			# read, `zip` and `unzip` write and read the examples archive, and
			# `xcodebuild` names the Xcode a release's notes record.
			Expect(["roc", "bash", "env", "swiftc", "python3", "shasum", "git", "zip", "unzip", "xcodebuild"]),
		],
	),
	Shell("default", [Use("dev")]),
	# The per-pull-request gate: compiler pins, formatting, the scripts'
	# tests, the macos.roc tool's tests, the build, `roc test`, every
	# example's recorded runs and the bundle with its consumer test.
	# `check -- STAGE...` runs only the named stages, in order.
	Task("check", [Use("dev"), Run(["scripts/check_all.roc", "--"])]),
	# scripts/build.sh defaults to the RC1 compiler's install path; the task
	# builds with the `roc` on PATH, as `check` does.
	Task("build", [Use("dev"), Run(["env", "ROC=roc", "scripts/build.sh"])]),
	Task("test", [Use("dev"), Run(["scripts/check_all.roc", "--", "test"])]),
	Task("examples", [Use("dev"), Run(["scripts/check_all.roc", "--", "examples"])]),
	# The platform bundle an app's header names: builds the platform's
	# native inputs, then `roc bundle`s the platform modules, libhost.a, the
	# generated linker stubs and the notices into build/platform/.
	# `-- --output-dir DIR`, `-- --prebuilt` (skip the build) and `-- --test`
	# (serve it on localhost and init, build and test a counter against it
	# with the macos.roc tool).
	Task("bundle", [Use("dev"), Run(["scripts/bundle.roc", "--"])]),
	# The release steps after the bundle (scripts/release.roc), which
	# .github/workflows/release.yml runs: `-- tool VERSION DIR [--base-url URL]`
	# makes the macos.roc tool, `-- archive VERSION DIR` writes the examples
	# archive, `-- test DIR [--binaries BIN]` builds and runs every
	# archived example against DIR's bundle served on localhost (and inits,
	# builds and tests a counter with DIR's macos.roc), and
	# `-- notes VERSION DIR OUT` renders the release notes.
	Task("release", [Use("dev"), Run(["scripts/release.roc", "--"])]),
	# The tooling compiler, as a log records it.
	Task("tooling-version", [Use("dev"), Run(["roc-stable", "version"])]),
]
