# Development environment and tasks for roc-native-macos, realised by roc-blueprint.
#
#     blueprint run check                  # the pull-request gate
#     blueprint run build                  # glue, Swift host, linker stubs, every example
#     blueprint run build -- counter       # one example, after the platform is built
#     blueprint run test                   # roc test on the platform root and the examples
#     blueprint run examples               # every example's recorded scripted runs
#     blueprint run examples -- --update   # record what they print now, as a reviewable diff
#     blueprint run bundle                 # the platform bundle, in build/platform/<hash>.tar.zst
#     blueprint run bundle -- --test       # and an example built and run against it
#     blueprint tasks                      # list every task
#     blueprint update                     # refresh Blueprint.lock
#
# Two Roc compilers have two jobs (roc-automation's model): `roc-stable`,
# pinned below, runs the scripts under scripts/; `roc`, the latest Roc
# nightly, checks, builds and tests the platform and the examples. `roc` is
# never pinned: CI installs it with roc-lang/setup-roc, and a contributor
# installs a current nightly (or a release such as 0.1.0 RC1) as `roc`, so the
# environment expects it on PATH.
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
			# serves the bundle to its consumer test (scripts/bundle.roc), `shasum`
			# checks the engine modules' digests and `git` lists the tracked files
			# the checks read.
			Expect(["roc", "bash", "env", "swiftc", "python3", "shasum", "git"]),
		],
	),
	Shell("default", [Use("dev")]),
	# The per-pull-request gate: compiler pins, formatting, the scripts'
	# tests, the build, `roc test`, every example's recorded runs and the
	# bundle with its consumer test.
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
	# (serve it on localhost and build and run examples/counter against it).
	Task("bundle", [Use("dev"), Run(["scripts/bundle.roc", "--"])]),
	# The tooling compiler, as a log records it.
	Task("tooling-version", [Use("dev"), Run(["roc-stable", "version"])]),
]
