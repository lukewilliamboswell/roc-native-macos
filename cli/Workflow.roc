import Bundle

## The GitHub Actions workflow `init` writes, `.github/workflows/release.yml`:
## on a pushed tag `v1.2.0` it runs the app's recorded cases on a Mac, then
## packages the app on Linux, signed and notarized when the repository has
## the secrets, and attaches the zip to the tag's release.
##
## It works with no secrets at all, packaging the app sealed ad hoc, so
## `init` writes it for every app. Every action is pinned by its full commit
## SHA, every job's token is read-only but the one that publishes, which
## holds no secret, and secrets reach the tool only through the environment.
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
		pinned = if (tag.is_empty()) "''" else tag
		\\# Written by `roc macos.roc init` (roc-native-macos ${version}).
		\\#
		\\# Packages the app for people to download. Push a tag such as v1.2.0 and
		\\# this runs the app's recorded cases on a Mac, builds the app on Linux,
		\\# signs and notarizes it when the secrets below exist, and attaches
		\\# <name>-1.2.0.zip to the tag's GitHub release. "Run workflow" packages the
		\\# version you give as a workflow artifact, and publishes nothing.
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
		\\# the app's directory in the repository, the one holding main.roc.
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
		\\  # The recorded cases run the app, which needs an Apple silicon Mac.
		\\  test:
		\\    name: Run the recorded cases
		\\    runs-on: macos-15
		\\    timeout-minutes: 30
		\\    permissions:
		\\      contents: read
		\\    steps:
		\\      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
		\\        with:
		\\          persist-credentials: false
		\\      - uses: lukewilliamboswell/roc-automation/actions/setup-roc-nightly@acc5efdcd929b38e665cd3ae6e694d1c4887f9c7
		\\        with:
		\\          nightly-tag: ${pinned}
		\\          cache: 'false'
		\\      - name: Test
		\\        working-directory: \${{ env.APP_DIR }}
		\\        run: roc macos.roc test
		\\
		\\  # Building needs no Mac: Linux builds the app, and rcodesign signs and
		\\  # notarizes it.
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
		\\      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
		\\        with:
		\\          persist-credentials: false
		\\      - uses: lukewilliamboswell/roc-automation/actions/setup-roc-nightly@acc5efdcd929b38e665cd3ae6e694d1c4887f9c7
		\\        with:
		\\          nightly-tag: ${pinned}
		\\          cache: 'false'
		\\      - name: Install rcodesign
		\\        run: |
		\\          dir="$RUNNER_TEMP/rcodesign"
		\\          mkdir -p "$dir"
		\\          release=https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.29.0
		\\          curl -fsSL --retry 3 -o "$dir/rcodesign.tar.gz" "$release/apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz"
		\\          echo "dbe85cedd8ee4217b64e9a0e4c2aef92ab8bcaaa41f20bde99781ff02e600002  $dir/rcodesign.tar.gz" | sha256sum --check --strict
		\\          tar -xzf "$dir/rcodesign.tar.gz" -C "$dir" --strip-components=1 apple-codesign-0.29.0-x86_64-unknown-linux-musl/rcodesign
		\\          echo "$dir" >> "$GITHUB_PATH"
		\\      - name: Choose the version
		\\        id: version
		\\        env:
		\\          EVENT: \${{ github.event_name }}
		\\          REQUESTED: \${{ inputs.version }}
		\\        run: |
		\\          if [ "$EVENT" = workflow_dispatch ]; then version="$REQUESTED"; else version="\${GITHUB_REF_NAME#v}"; fi
		\\          if ! echo "$version" | grep -Eq '^[0-9]+([.][0-9]+){0,2}$'; then
		\\            echo "::error::$version is not a version such as 1.2.0 (from a tag such as v1.2.0)"
		\\            exit 1
		\\          fi
		\\          echo "version=$version" >> "$GITHUB_OUTPUT"
		\\      - name: Package
		\\        working-directory: \${{ env.APP_DIR }}
		\\        env:
		\\          VERSION: \${{ steps.version.outputs.version }}
		\\          P12_BASE64: \${{ secrets.MACOS_SIGN_P12_BASE64 }}
		\\          MACOS_SIGN_P12_PASSWORD: \${{ secrets.MACOS_SIGN_P12_PASSWORD }}
		\\          MACOS_NOTARY_ISSUER: \${{ secrets.MACOS_NOTARY_ISSUER }}
		\\          MACOS_NOTARY_KEY_ID: \${{ secrets.MACOS_NOTARY_KEY_ID }}
		\\          MACOS_NOTARY_KEY: \${{ secrets.MACOS_NOTARY_KEY }}
		\\        run: |
		\\          flags=()
		\\          if [ -n "$P12_BASE64" ]; then
		\\            p12="$RUNNER_TEMP/developer-id.p12"
		\\            (umask 077 && printf '%s' "$P12_BASE64" | base64 --decode > "$p12")
		\\            export MACOS_SIGN_P12="$p12"
		\\            if [ -n "$MACOS_NOTARY_KEY" ]; then
		\\              flags+=(--notarize)
		\\            else
		\\              flags+=(--sign)
		\\              echo "::notice::No MACOS_NOTARY_KEY secret, so the app is signed but not notarized, and macOS asks before it opens."
		\\            fi
		\\          else
		\\            echo "::notice::No MACOS_SIGN_P12_BASE64 secret, so the app is sealed ad hoc: another Mac opens it after one approval in System Settings > Privacy & Security."
		\\          fi
		\\          status=0
		\\          SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" roc macos.roc package --version "$VERSION" "\${flags[@]}" || status=$?
		\\          rm -f "$RUNNER_TEMP/developer-id.p12"
		\\          exit "$status"
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
		\\    timeout-minutes: 10
		\\    permissions:
		\\      contents: write # to create the release and upload the zip to it
		\\    steps:
		\\      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
		\\        with:
		\\          name: app
		\\          path: dist
		\\      - name: Attach
		\\        env:
		\\          GH_TOKEN: \${{ github.token }}
		\\          TAG: \${{ github.ref_name }}
		\\        run: |
		\\          if ! gh release view "$TAG" --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1; then
		\\            gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --verify-tag --title "$TAG" --generate-notes
		\\          fi
		\\          gh release upload "$TAG" dist/*.zip --repo "$GITHUB_REPOSITORY" --clobber
		\\
	}
}

## A release tested with a nightly pins it; otherwise the latest is used.
expect [Workflow.nightly("nightly-2026-11-14-a87808d"), Workflow.nightly("development"), Workflow.nightly("0.1.0_RC1")] == ["nightly-2026-11-14-a87808d", "", ""]

## The workflow names the release, pins its Roc, and passes the secrets in
## the environment, never on a command line.
expect {
	text = Workflow.for_release("0.2.0", "nightly-2026-11-14-a87808d")
	lines = text.split_on("\n")
	text.starts_with("# Written by `roc macos.roc init` (roc-native-macos 0.2.0).\n")
		and text.contains("          nightly-tag: nightly-2026-11-14-a87808d\n")
		and text.contains("          P12_BASE64: ${"$"}{{ secrets.MACOS_SIGN_P12_BASE64 }}\n")
		and lines.keep_if(|line| line.contains("secrets.")).all(|line| line.trim().starts_with("P12_BASE64:") or line.trim().starts_with("MACOS_"))
		and lines.keep_if(|line| line.trim().starts_with("- uses:")).all(|line| line.contains("@") and line.split_on("@").last().map_ok(|pin| pin.split_on(" ").first() ?? "").map_ok(|sha| sha.count_utf8_bytes() == 40) == Ok(Bool.True))
}

## Without a nightly to pin, the workflow installs the latest.
expect Workflow.for_release("development", "development").contains("          nightly-tag: ''\n")
