import Bundle

## The GitHub Actions workflow `init` writes, `.github/workflows/release.yml`:
## on a pushed tag `v1.2.0` it runs the app's tests on a Mac (its `expect`s,
## its recorded cases and, when it has `fuzz/main.roc`, its fuzz targets'
## examples), then packages the app on Linux, signed and notarized when the
## repository has the secrets, and attaches the zip to the tag's release.
##
## Every step that does something is one `roc macos.roc` command (`test`,
## `fuzz --check`, `ci package`, `ci release`; `Ci` decides what each
## does), so the workflow holds no script. It works with no secrets at all, packaging the
## app sealed ad hoc, so `init` writes it for every app. Every action is
## pinned by its full commit SHA, the jobs that see secrets have a read-only
## token, the one job that writes holds no secret, and secrets and inputs
## reach the tool only through the environment.
Workflow := [].{

	## Where `init` writes it.
	path : Str
	path = ".github/workflows/release.yml"

	## The Roc nightly the workflow installs: the one this release of the
	## platform was tested with, or the latest when that is not a nightly.
	nightly : Str -> Str
	nightly = |roc_version| if (roc_version.starts_with("nightly-")) roc_version else ""

	## The workflow, for the release this copy of the tool belongs to.
	text : Str
	text = Workflow.for_release(Bundle.version, Bundle.roc_version)

	for_release : Str, Str -> Str
	for_release = |version, roc_version| {
		tag = Workflow.nightly(roc_version)
		checkout = setup(if (tag.is_empty()) "''" else tag)
		\\# Written by `roc macos.roc init` (roc-native-macos ${version}).
		\\#
		\\# Packages the app for people to download. Push a tag such as v1.2.0 (or
		\\# v1.2.0-beta.1, a pre-release) and this runs the app's tests on a
		\\# Mac, builds the app on Linux, signs and notarizes it when the secrets
		\\# below exist, and attaches <name>-1.2.0.zip to the tag's GitHub release.
		\\# "Run workflow" packages the version you give as a workflow artifact, and
		\\# publishes nothing. Each step is a `roc macos.roc` command;
		\\# `roc macos.roc ci --help` describes what ci package and ci release do.
		\\#
		\\# With no secrets the app is sealed ad hoc, and opens on another Mac after
		\\# one approval in System Settings. With a Developer ID and an App Store
		\\# Connect API key it opens with no warning. Add them as secrets of the
		\\# repository or of its release environment (Settings > Secrets and
		\\# variables > Actions, or Settings > Environments > release):
		\\#
		\\#   MACOS_SIGN_P12_BASE64    your Developer ID Application certificate, a .p12
		\\#                            file, base64-encoded: base64 -i developer-id.p12
		\\#   MACOS_SIGN_P12_PASSWORD  the password it was exported with
		\\#   MACOS_NOTARY_ISSUER      the API key's issuer ID
		\\#   MACOS_NOTARY_KEY_ID      the API key's ID
		\\#   MACOS_NOTARY_KEY         the API key's .p8 file, its contents
		\\#
		\\# With only the first two the app is signed but not notarized. APP_DIR is
		\\# the app's directory in the repository, the one holding macos.json.
		\\name: Release
		\\
		\\on:
		\\  push:
		\\    tags: ['v*']
		\\  workflow_dispatch:
		\\    inputs:
		\\      version:
		\\        description: The version to package, such as 1.2.0
		\\        required: true
		\\        type: string
		\\
		\\permissions: {}
		\\
		\\concurrency:
		\\  group: release-\${{ github.ref }}
		\\  cancel-in-progress: false
		\\
		\\env:
		\\  APP_DIR: .
		\\
		\\jobs:
		\\  # The recorded cases run the app, which needs an Apple silicon Mac;
		\\  # roc-fuzz runs there too.
		\\  test:
		\\    name: Run the tests
		\\    runs-on: macos-15
		\\    timeout-minutes: 30
		\\    permissions:
		\\      contents: read
		\\    steps:
		\\${checkout}
		\\      - name: Test
		\\        working-directory: \${{ env.APP_DIR }}
		\\        run: roc macos.roc test
		\\      # The fuzz targets' declared examples, when the app has fuzz/main.roc.
		\\      - name: Fuzz
		\\        if: hashFiles(format('{0}/fuzz/main.roc', env.APP_DIR)) != ''
		\\        working-directory: \${{ env.APP_DIR }}
		\\        run: roc macos.roc fuzz --check
		\\
		\\  # Building needs no Mac: Linux builds the app, and rcodesign, which ci
		\\  # package installs when there is a certificate, signs and notarizes it.
		\\  package:
		\\    name: Package the app
		\\    needs: test
		\\    runs-on: ubuntu-24.04
		\\    timeout-minutes: 45
		\\    # The secrets can be the release environment's, which settings can
		\\    # limit to tags and to reviewers' approval.
		\\    environment: release
		\\    permissions:
		\\      contents: read
		\\    steps:
		\\${checkout}
		\\      - name: Package
		\\        working-directory: \${{ env.APP_DIR }}
		\\        env:
		\\          RELEASE_VERSION: \${{ inputs.version }}
		\\          MACOS_SIGN_P12_BASE64: \${{ secrets.MACOS_SIGN_P12_BASE64 }}
		\\          MACOS_SIGN_P12_PASSWORD: \${{ secrets.MACOS_SIGN_P12_PASSWORD }}
		\\          MACOS_NOTARY_ISSUER: \${{ secrets.MACOS_NOTARY_ISSUER }}
		\\          MACOS_NOTARY_KEY_ID: \${{ secrets.MACOS_NOTARY_KEY_ID }}
		\\          MACOS_NOTARY_KEY: \${{ secrets.MACOS_NOTARY_KEY }}
		\\        run: roc macos.roc ci package
		\\      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
		\\        with:
		\\          name: app
		\\          path: \${{ env.APP_DIR }}/dist/*.zip
		\\          if-no-files-found: error
		\\
		\\  # Only this job may write to the repository, and it holds no secret.
		\\  release:
		\\    name: Attach the zip to the release
		\\    needs: package
		\\    if: github.event_name == 'push'
		\\    runs-on: ubuntu-24.04
		\\    timeout-minutes: 15
		\\    permissions:
		\\      contents: write # to create the release and upload the zip to it
		\\    steps:
		\\${checkout}
		\\      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
		\\        with:
		\\          name: app
		\\          path: \${{ env.APP_DIR }}/dist
		\\      - name: Attach
		\\        working-directory: \${{ env.APP_DIR }}
		\\        env:
		\\          GH_TOKEN: \${{ github.token }}
		\\        run: roc macos.roc ci release
		\\
	}
}

## Every job's first steps: the repository, and Roc.
setup : Str -> Str
setup = |nightly_tag|
	\\      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
	\\        with:
	\\          persist-credentials: false
	\\      - uses: lukewilliamboswell/roc-automation/actions/setup-roc-nightly@acc5efdcd929b38e665cd3ae6e694d1c4887f9c7
	\\        with:
	\\          nightly-tag: ${nightly_tag}
	\\          cache: 'false'

## A release tested with a nightly pins it; otherwise the latest is used.
expect [Workflow.nightly("nightly-2026-11-14-a87808d"), Workflow.nightly("development"), Workflow.nightly("0.1.0_RC1")] == ["nightly-2026-11-14-a87808d", "", ""]

## The workflow names the release, pins its Roc, passes the secrets in the
## environment, pins every action by its SHA, and runs nothing but the tool.
expect {
	text = Workflow.for_release("0.2.0", "nightly-2026-11-14-a87808d")
	lines = text.split_on("\n")
	runs = lines.keep_if(|line| line.trim().starts_with("run:"))
	text.starts_with("# Written by `roc macos.roc init` (roc-native-macos 0.2.0).\n")
		and lines.keep_if(|line| line == "          nightly-tag: nightly-2026-11-14-a87808d").len() == 3
		and text.contains("          MACOS_SIGN_P12_BASE64: ${"$"}{{ secrets.MACOS_SIGN_P12_BASE64 }}\n")
		and lines.keep_if(|line| line.contains("secrets.")).all(|line| line.trim().starts_with("MACOS_"))
		and lines.keep_if(|line| line.trim().starts_with("- uses:")).all(|line| line.split_on("@").last().map_ok(|pin| (pin.split_on(" ").first() ?? "").count_utf8_bytes()) == Ok(40))
		and runs.map(|line| line.trim()) == ["run: roc macos.roc test", "run: roc macos.roc fuzz --check", "run: roc macos.roc ci package", "run: roc macos.roc ci release"]
		and !text.contains("run: |")
}

## Without a nightly to pin, the workflow installs the latest.
expect Workflow.for_release("development", "development").contains("          nightly-tag: ''\n")
