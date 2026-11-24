import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import App
import Meta
import Package
import Sign

## `ci package` and `ci release`: what the release workflow `init` writes
## runs, so that each of its steps is one command and the decisions are here,
## where they are tested.
##
## `ci package` packages the app for a CI run: the version is `--version`,
## else `RELEASE_VERSION` (the workflow's input), else the pushed tag
## without its `v`; it signs with `--sign` or `--notarize` according to which
## secrets are set, and says so when they are not; it decodes
## `MACOS_SIGN_P12_BASE64` to an owner-only file; it installs a pinned,
## checksummed rcodesign when signing needs one and none is on PATH; and it
## takes `SOURCE_DATE_EPOCH` from the last commit when it is unset.
##
## `ci release` attaches `dist/*.zip` to the pushed tag's GitHub release with
## `gh`, creating the release, marked as a pre-release for a tag such as
## `v1.0.0-beta.1`, when there is none.
Ci := [].{

	## The version a CI run packages: `--version`, else the workflow's input,
	## else a pushed tag's name without its `v`.
	version : { flag : Str, input : Str, ref_type : Str, ref_name : Str } -> Try(Str, [NoReleaseVersion(Str)])
	version = |{ flag, input, ref_type, ref_name }|
		if !flag.is_empty() {
			Ok(flag)
		} else if !input.is_empty() {
			Ok(input)
		} else if ref_type == "tag" {
			Ok(ref_name.drop_prefix("v"))
		} else {
			Err(NoReleaseVersion(if (ref_name.is_empty()) "no tag" else "${ref_type} ${ref_name}"))
		}

	## Which signing secrets are set: a certificate as base64 (the workflow's
	## secret), as a path, or as a keychain identity; and which of the
	## notary key's three variables.
	Secrets : { p12_base64 : Bool, p12 : Bool, identity : Bool, notary : List(Str) }

	## How to sign, from the secrets that are set, and what to say about the
	## ones that are not. Part of a notary key is a mistake, not a choice.
	signing : Secrets -> Try({ sign : Bool, notarize : Bool, notices : List(Str) }, [PartialNotaryKey(List(Str))])
	signing = |secrets| {
		certificate = secrets.p12_base64 or secrets.p12 or secrets.identity
		missing = Sign.notary_vars.drop_if(|name| secrets.notary.contains(name))
		notary = if missing.is_empty() {
			Bool.True
		} else if missing.len() == Sign.notary_vars.len() {
			Bool.False
		} else {
			return Err(PartialNotaryKey(missing))
		}
		if !certificate {
			ignored = if (notary) [" The MACOS_NOTARY_* secrets are set, but notarizing needs a certificate too."] else [""]
			Ok({ sign: Bool.False, notarize: Bool.False, notices: ["No MACOS_SIGN_P12_BASE64 secret, so the app is sealed ad hoc: another Mac opens it after one approval in System Settings > Privacy & Security.${Str.join_with(ignored, "")}"] })
		} else if !notary {
			Ok({ sign: Bool.True, notarize: Bool.False, notices: ["No MACOS_NOTARY_* secrets, so the app is signed with the Developer ID but not notarized, and macOS asks before it opens."] })
		} else {
			Ok({ sign: Bool.True, notarize: Bool.True, notices: [] })
		}
	}

	## A notice, as GitHub Actions shows one in a run's summary, or as a line
	## anywhere else.
	notice : Bool, Str -> Str
	notice = |actions, text| if (actions) "::notice::${text}" else "Note: ${text}"

	## The bytes of base64 text, as `base64` writes it: white space is
	## ignored, and `=` pads the end.
	base64 : Str -> Try(List(U8), [NotBase64])
	base64 = |text| {
		digits = text.to_utf8().drop_if(|b| b == ' ' or b == '\n' or b == '\r' or b == '\t')
		unpadded = digits.drop_if(|b| b == '=')
		padding = digits.len() - unpadded.len()
		if digits.len() % 4 != 0 or padding > 2 or digits.take_last(padding).any(|b| b != '=') {
			return Err(NotBase64)
		}
		var $out = []
		var $bits = 0.U32
		var $count = 0.U8
		for b in unpadded {
			value = sextet(b) ? |_| NotBase64
			$bits = $bits.shl_wrap(6).bitwise_or(value)
			$count = $count + 1
			if $count == 4 {
				$out = $out.concat([$bits.shr_zf_wrap(16).to_u8_wrap(), $bits.shr_zf_wrap(8).to_u8_wrap(), $bits.to_u8_wrap()])
				$bits = 0
				$count = 0
			}
		}
		Ok(
			match $count {
				2 => $out.append($bits.shr_zf_wrap(4).to_u8_wrap())
				3 => $out.concat([$bits.shr_zf_wrap(10).to_u8_wrap(), $bits.shr_zf_wrap(2).to_u8_wrap()])
				_ => $out
			},
		)
	}

	## The rcodesign release `ci` installs.
	rcodesign_version : Str
	rcodesign_version = "0.29.0"

	## The rcodesign release's archive for a system, its SHA-256 (from the
	## release's SHA256SUMS), and the program's path inside it.
	rcodesign_asset : [Linux, MacOS, Windows], [X64, Arm64] -> Try({ archive : Str, sha256 : Str, member : Str }, [NoRcodesign])
	rcodesign_asset = |os, arch| {
		v = Ci.rcodesign_version
		{ triple, sha256, ext } = match (os, arch) {
			(Linux, X64) => { triple: "x86_64-unknown-linux-musl", sha256: "dbe85cedd8ee4217b64e9a0e4c2aef92ab8bcaaa41f20bde99781ff02e600002", ext: "tar.gz" }
			(Linux, Arm64) => { triple: "aarch64-unknown-linux-musl", sha256: "4af92c87ddf52f5f2d1258a3b4e56c7dcb8f1b2468df744976c5f139e031961f", ext: "tar.gz" }
			(MacOS, Arm64) => { triple: "aarch64-apple-darwin", sha256: "d1a532150adaf90048260d76359261aa716abafc45c53c5dc18845029184334a", ext: "tar.gz" }
			(MacOS, X64) => { triple: "x86_64-apple-darwin", sha256: "14ef11bedd51a8d95eafd767939ae96d5900e5a61511bef75bb21db6e7c74140", ext: "tar.gz" }
			(Windows, X64) => { triple: "x86_64-pc-windows-msvc", sha256: "54bb500e2da7a8de02fcae0f331d1cac6e6d7173b4281042ff9c528ba3159aaa", ext: "zip" }
			(Windows, Arm64) => return Err(NoRcodesign)
		}
		program = if (os == Windows) "rcodesign.exe" else "rcodesign"
		Ok({ archive: "apple-codesign-${v}-${triple}.${ext}", sha256, member: "apple-codesign-${v}-${triple}/${program}" })
	}

	## Where a release's archive is downloaded from.
	rcodesign_url : Str -> Str
	rcodesign_url = |archive| "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${Ci.rcodesign_version}/${archive}"

	## Whether a tag names a pre-release, as `v1.0.0-beta.1` does.
	prerelease : Str -> Bool
	prerelease = |tag| tag.drop_prefix("v").contains("-")

	## The `gh` steps that attach `zips` to the release of `tag` in
	## `repository`, creating it first unless it `exists`.
	release_steps : { tag : Str, repository : Str, zips : List(Str), exists : Bool } -> List(Sign.Step)
	release_steps = |{ tag, repository, zips, exists }| {
		flag = if (Ci.prerelease(tag)) ["--prerelease"] else []
		create = if (exists) [] else [gh(["release", "create", tag, "--repo", repository, "--verify-tag", "--title", tag, "--generate-notes"].concat(flag))]
		create.append(gh(["release", "upload", tag].concat(zips).concat(["--repo", repository, "--clobber"])))
	}

	## `ci package`: package the app for a CI run.
	package! : { fields : Meta.Fields, how : App.Build } => Try({}, _)
	package! = |{ fields, how }| {
		actions = env!("GITHUB_ACTIONS") == "true"
		chosen = Ci.version({ flag: fields.version, input: env!("RELEASE_VERSION"), ref_type: env!("GITHUB_REF_TYPE"), ref_name: env!("GITHUB_REF_NAME") })?
		given = Package.environment!()
		p12_base64 = env!("MACOS_SIGN_P12_BASE64")
		notary = [("MACOS_NOTARY_ISSUER", given.notary_issuer), ("MACOS_NOTARY_KEY_ID", given.notary_key_id), ("MACOS_NOTARY_KEY", given.notary_key)].keep_if(|(_, v)| !v.is_empty()).map(|(name, _)| name)
		{ sign, notarize, notices } = Ci.signing({ p12_base64: !p12_base64.is_empty(), p12: !given.p12.is_empty(), identity: !given.identity.is_empty(), notary })?
		for text in notices {
			Stdout.line!(Ci.notice(actions, text))?
		}
		outcome = prepare_and_package!({ fields: { ..fields, version: chosen }, sign, notarize, how }, given, p12_base64, actions)
		Package.forget_secrets!()
		outcome.map_ok(|_| {})
	}

	## `ci release`: attach `dist/*.zip` to the pushed tag's release.
	release! : () => Try({}, _)
	release! = || {
		ref_type = env!("GITHUB_REF_TYPE")
		tag = env!("GITHUB_REF_NAME")
		if ref_type != "tag" {
			return Err(NotATag(if (tag.is_empty()) "no tag" else "${ref_type} ${tag}"))
		}
		repository = env!("GITHUB_REPOSITORY")
		if repository.is_empty() {
			return Err(NoRepository)
		}
		if !Cmd.check_available!("gh") {
			return Err(GhMissing)
		}
		listed = Path.list!(Path.utf8(Package.dist)) ?? []
		zips = listed.map(Path.display).keep_if(|path| path.ends_with(".zip")).sort_with(compare)
		if zips.is_empty() {
			return Err(NoZips)
		}
		viewed = Cmd.new("gh").args(["release", "view", tag, "--repo", repository].map(OsStr.from_str)).stdin(Null).stdout(Null).stderr(Null).run!()?
		for { program, args, shown } in Ci.release_steps({ tag, repository, zips, exists: viewed.status == Exited(0) }) {
			Stdout.line!("  ${shown}")?
			ran = Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!()?
			if ran.status != Exited(0) {
				return Err(StepFailed(shown))
			}
		}
		Stdout.line!("Attached ${Str.join_with(zips, ", ")} to the ${if (Ci.prerelease(tag)) "pre-release" else "release"} ${tag} of ${repository}.")?
		Ok({})
	}
}

## Decode the certificate, find or install rcodesign, choose the zip's time,
## and package.
prepare_and_package! : Package.Options, Package.Environment, Str, Bool => Try({ zip : Str, meta : Meta.Resolved }, _)
prepare_and_package! = |options, given, p12_base64, actions| {
	p12 = if p12_base64.is_empty() {
		given.p12
	} else {
		bytes = Ci.base64(p12_base64) ? |_| BadP12Base64
		Package.secret!("developer-id.p12", bytes)?
	}
	mac = Package.on_mac!()
	needs_rcodesign = !p12.is_empty() or !(mac and Cmd.check_available!("codesign"))
	rcodesign = if (needs_rcodesign and !Cmd.check_available!("rcodesign")) rcodesign!()? else "rcodesign"
	source_date_epoch = if given.source_date_epoch.is_empty() {
		match Cmd.new("git").args(["log", "-1", "--format=%ct"].map(OsStr.from_str)).capture!() {
			Ok(text) => text.trim()
			Err(_) => {
				Stdout.line!(Ci.notice(actions, "There is no git history here, so the zip's entries carry 1980-01-01."))?
				""
			}
		}
	} else {
		given.source_date_epoch
	}
	Package.run!(options, { ..given, p12, rcodesign, source_date_epoch })
}

## Install the pinned rcodesign beside the run, checked against its SHA-256,
## and give its path. A copy already installed there is used as it is.
rcodesign! : () => Try(Str, _)
rcodesign! = || {
	target = System.target!()
	os = match target.os() {
		Linux(_) => Linux
		MacOS(_) => MacOS
		Windows(_) => Windows
	}
	arch = match target.arch() {
		Arm64 => Arm64
		X64 => X64
	}
	{ archive, sha256, member } = Ci.rcodesign_asset(os, arch) ? |_| NoRcodesignHere
	temp = env!("RUNNER_TEMP")
	dir = "${if (temp.is_empty()) ".macos" else temp}/rcodesign-${Ci.rcodesign_version}"
	program = "${dir}/${member.split_on("/").last() ?? "rcodesign"}"
	if Path.exists!(Path.utf8(program))? {
		return Ok(program)
	}
	Path.create_all!(Path.utf8(dir))?
	file = "${dir}/${archive}"
	Stdout.line!("Installing rcodesign ${Ci.rcodesign_version}, which signs the app, from ${Ci.rcodesign_url(archive)}")?
	fetched = Cmd.new("curl").args(["-fsSL", "--retry", "3", "-o", file, Ci.rcodesign_url(archive)].map(OsStr.from_str)).inherit_stdio().run!()?
	if fetched.status != Exited(0) {
		return Err(RcodesignDownload(Ci.rcodesign_url(archive)))
	}
	actual = Crypto.SHA256.hash(Path.read_bytes!(Path.utf8(file))?).to_hex()
	if actual != sha256 {
		Path.delete!(Path.utf8(file)) ?? {}
		return Err(RcodesignChecksum({ archive, expected: sha256, actual }))
	}
	unpacked = Cmd.new("tar").args(["-xf", file, "-C", dir, "--strip-components=1", member].map(OsStr.from_str)).inherit_stdio().run!()?
	if unpacked.status != Exited(0) or !(Path.exists!(Path.utf8(program))?) {
		return Err(RcodesignUnpack(file))
	}
	Ok(program)
}

gh : List(Str) -> Sign.Step
gh = |args| { program: "gh", args, shown: Str.join_with(["gh"].concat(args), " ") }

## The value of a base64 digit.
sextet : U8 -> Try(U32, [NotADigit])
sextet = |b|
	if b >= 'A' and b <= 'Z' {
		Ok((b - 'A').to_u32())
	} else if b >= 'a' and b <= 'z' {
		Ok((b - 'a' + 26).to_u32())
	} else if b >= '0' and b <= '9' {
		Ok((b - '0' + 52).to_u32())
	} else if b == '+' {
		Ok(62)
	} else if b == '/' {
		Ok(63)
	} else {
		Err(NotADigit)
	}

## An environment variable's value, or empty when it is unset.
env! : Str => Str
env! = |name| Env.var_str!(OsStr.from_str(name)) ?? ""

compare : Str, Str -> [Before, Same, After]
compare = |a, b| compare_bytes(a.to_utf8(), b.to_utf8())

compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_bytes(xs, ys)
	}

## A flag wins, then the workflow's input, then the pushed tag.
expect {
	actual = [
		Ci.version({ flag: "2.0.0", input: "1.5.0", ref_type: "tag", ref_name: "v1.0.0" }),
		Ci.version({ flag: "", input: "1.5.0", ref_type: "branch", ref_name: "main" }),
		Ci.version({ flag: "", input: "", ref_type: "tag", ref_name: "v1.0.0-beta.1" }),
		Ci.version({ flag: "", input: "", ref_type: "tag", ref_name: "1.0.0" }),
		Ci.version({ flag: "", input: "", ref_type: "branch", ref_name: "main" }),
		Ci.version({ flag: "", input: "", ref_type: "", ref_name: "" }),
	]
	actual == [Ok("2.0.0"), Ok("1.5.0"), Ok("1.0.0-beta.1"), Ok("1.0.0"), Err(NoReleaseVersion("branch main")), Err(NoReleaseVersion("no tag"))]
}

## The secrets that are set decide how the app is signed.
expect {
	none = { p12_base64: Bool.False, p12: Bool.False, identity: Bool.False, notary: [] }
	all_notary = Sign.notary_vars
	ad_hoc = Ci.signing(none)
	signed = Ci.signing({ ..none, p12_base64: Bool.True })
	notarized = Ci.signing({ ..none, p12_base64: Bool.True, notary: all_notary })
	keychain = Ci.signing({ ..none, identity: Bool.True, notary: all_notary })
	partial = Ci.signing({ ..none, p12_base64: Bool.True, notary: ["MACOS_NOTARY_KEY"] })
	notary_only = Ci.signing({ ..none, notary: all_notary })
	flags = [ad_hoc, signed, notarized, keychain].map(|r| r.map_ok(|s| (s.sign, s.notarize)))
	flags == [Ok((Bool.False, Bool.False)), Ok((Bool.True, Bool.False)), Ok((Bool.True, Bool.True)), Ok((Bool.True, Bool.True))]
		and partial == Err(PartialNotaryKey(["MACOS_NOTARY_ISSUER", "MACOS_NOTARY_KEY_ID"]))
		and (notarized ?? { sign: Bool.False, notarize: Bool.False, notices: ["x"] }).notices == []
		and (ad_hoc ?? { sign: Bool.False, notarize: Bool.False, notices: [] }).notices.all(|n| n.starts_with("No MACOS_SIGN_P12_BASE64"))
		and (notary_only ?? { sign: Bool.False, notarize: Bool.False, notices: [] }).notices.all(|n| n.contains("needs a certificate too"))
}

expect [Ci.notice(Bool.True, "x"), Ci.notice(Bool.False, "x")] == ["::notice::x", "Note: x"]

## base64 as `base64` writes it, wrapped or not, padded or not.
expect {
	actual = ["", "Zg==", "Zm8=", "Zm9v", "Zm9vYmFy\nYmF6\n", "/+8A"].map(Ci.base64)
	actual == [Ok([]), Ok("f".to_utf8()), Ok("fo".to_utf8()), Ok("foo".to_utf8()), Ok("foobarbaz".to_utf8()), Ok([0xFF, 0xEF, 0x00])]
}

expect [Ci.base64("Zm9"), Ci.base64("Zm9v!==="), Ci.base64("Z=9v")] == [Err(NotBase64), Err(NotBase64), Err(NotBase64)]

## Each system rcodesign is released for has its archive and checksum.
expect {
	linux = Ci.rcodesign_asset(Linux, X64)
	windows = Ci.rcodesign_asset(Windows, X64)
	linux == Ok({ archive: "apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz", sha256: "dbe85cedd8ee4217b64e9a0e4c2aef92ab8bcaaa41f20bde99781ff02e600002", member: "apple-codesign-0.29.0-x86_64-unknown-linux-musl/rcodesign" })
		and windows.map_ok(|a| a.member) == Ok("apple-codesign-0.29.0-x86_64-pc-windows-msvc/rcodesign.exe")
		and Ci.rcodesign_asset(Windows, Arm64) == Err(NoRcodesign)
		and Ci.rcodesign_url("a.tar.gz") == "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.29.0/a.tar.gz"
}

## A release is created when there is none, as a pre-release for a
## pre-release tag, and the zips are uploaded over any of the same name.
expect {
	fresh = Ci.release_steps({ tag: "v1.0.0-beta.1", repository: "me/counter", zips: ["dist/counter-1.0.0-beta.1.zip"], exists: Bool.False }).map(|s| s.shown)
	again = Ci.release_steps({ tag: "v1.0.0", repository: "me/counter", zips: ["dist/counter-1.0.0.zip"], exists: Bool.True }).map(|s| s.shown)
	fresh
		== [
			"gh release create v1.0.0-beta.1 --repo me/counter --verify-tag --title v1.0.0-beta.1 --generate-notes --prerelease",
			"gh release upload v1.0.0-beta.1 dist/counter-1.0.0-beta.1.zip --repo me/counter --clobber",
		]
		and again == ["gh release upload v1.0.0 dist/counter-1.0.0.zip --repo me/counter --clobber"]
}
