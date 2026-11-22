## Who signs the app, and the command lines that sign, verify and notarize
## it. Everything here is pure, so each command line is tested; `Package`
## runs them.
##
## Roc's linker signs the program ad hoc, but that signature covers neither
## `Info.plist` nor `Contents/Resources`, and `codesign --verify --strict`
## rejects the bundle. So `package` always seals the whole bundle when a
## signing tool is here: Apple's `codesign` on a Mac, or `rcodesign` (the
## apple-codesign project, on any system). The bundle holds one program and
## no nested code, so signing the bundle signs the program, with no `--deep`.
##
## A Developer ID signature comes from the keychain (`MACOS_SIGN_IDENTITY`,
## with `codesign`), or from a `.p12` file (`MACOS_SIGN_P12` and
## `MACOS_SIGN_P12_PASSWORD`, with `rcodesign`). It turns on the hardened
## runtime, which notarization needs; the app needs no entitlements under
## it, since Roc compiles ahead of time and the app is not sandboxed.
Sign := [].{

	## A program to run and its arguments, and how to show it, which never
	## holds a secret.
	Step : { program : Str, args : List(Str), shown : Str }

	## A signing tool.
	Tool : [Codesign, Rcodesign]

	## Who signs: ad hoc with a tool, a keychain identity with `codesign`, or
	## a `.p12` file with `rcodesign`.
	Signer : [AdHoc(Tool), Keychain(Str), P12(Str)]

	## What is here: whether this is a Mac, which tools are on PATH, and the
	## environment's `MACOS_SIGN_TOOL`, `MACOS_SIGN_IDENTITY` and
	## `MACOS_SIGN_P12` (empty when unset).
	Here : { mac : Bool, codesign : Bool, rcodesign : Bool, prefer : Str, identity : Str, p12 : Str }

	## Who signs the app: with a Developer ID when `developer`, else ad hoc
	## with the best tool here, or nobody when there is none.
	choose : Here, Bool -> Try([Seal(Signer), Unsealed], [BadSignTool(Str), SignToolMissing(Str), NoDeveloperId(Str)])
	choose = |here, developer| {
		codesign_ok = here.mac and here.codesign
		allowed = match here.prefer {
			"" => { codesign: codesign_ok, rcodesign: here.rcodesign }
			"codesign" if codesign_ok => { codesign: Bool.True, rcodesign: Bool.False }
			"rcodesign" if here.rcodesign => { codesign: Bool.False, rcodesign: Bool.True }
			"codesign" | "rcodesign" => return Err(SignToolMissing(here.prefer))
			other => return Err(BadSignTool(other))
		}
		if developer {
			if !here.identity.is_empty() and allowed.codesign {
				Ok(Seal(Keychain(here.identity)))
			} else if !here.p12.is_empty() and allowed.rcodesign {
				Ok(Seal(P12(here.p12)))
			} else {
				Err(NoDeveloperId(Sign.missing(here, allowed)))
			}
		} else if allowed.codesign {
			Ok(Seal(AdHoc(Codesign)))
		} else if allowed.rcodesign {
			Ok(Seal(AdHoc(Rcodesign)))
		} else {
			Ok(Unsealed)
		}
	}

	## Why there is no Developer ID to sign with, as the end of a sentence.
	missing : Here, { codesign : Bool, rcodesign : Bool } -> Str
	missing = |here, allowed|
		if !here.p12.is_empty() and !allowed.rcodesign {
			"MACOS_SIGN_P12 is set, but rcodesign, which signs with it, is not on PATH"
		} else if !here.identity.is_empty() and !allowed.codesign {
			"MACOS_SIGN_IDENTITY is set, but it names a keychain identity, which only codesign on a Mac signs with; elsewhere set MACOS_SIGN_P12 and MACOS_SIGN_P12_PASSWORD instead"
		} else if here.mac {
			"set MACOS_SIGN_IDENTITY to your Developer ID Application identity in the keychain, or MACOS_SIGN_P12 and MACOS_SIGN_P12_PASSWORD to its .p12 file and password (with rcodesign on PATH)"
		} else {
			"set MACOS_SIGN_P12 and MACOS_SIGN_P12_PASSWORD to your Developer ID Application certificate's .p12 file and password, and put rcodesign on PATH"
		}

	## The steps that sign `bundle`. A `.p12`'s password is read from
	## `password_file`, never given on the command line.
	sign : Signer, Str, Str -> List(Step)
	sign = |signer, bundle, password_file| {
		# codesign refuses files with extended attributes (Finder info, a
		# quarantine flag), which a copied asset may carry.
		clean = step("xattr", ["-cr", bundle])
		match signer {
			AdHoc(Codesign) => [clean, step("codesign", ["--force", "--sign", "-", bundle])]
			AdHoc(Rcodesign) => [step("rcodesign", ["sign", bundle])]
			Keychain(identity) => [clean, step("codesign", ["--force", "--sign", identity, "--options", "runtime", "--timestamp", bundle])]
			P12(file) => [step("rcodesign", ["sign", "--p12-file", file, "--p12-password-file", password_file, "--for-notarization", "--code-signature-flags", "runtime", bundle])]
		}
	}

	## Check a signed bundle as Gatekeeper's own check does.
	verify : Str -> Step
	verify = |bundle| step("codesign", ["--verify", "--strict", "--verbose=2", bundle])

	## The App Store Connect API key notarization uses: the issuer's and the
	## key's ids, and the `.p8` file. `json` is where `rcodesign` keeps the
	## key encoded for it.
	NotaryKey : { issuer : Str, key_id : Str, key_file : Str, json : Str }

	## The steps that notarize the app and staple the ticket to `bundle`:
	## `notarytool` submits `zip` (the signed app) from a Mac, and
	## `rcodesign` submits the bundle from anywhere. The shown command lines
	## leave out the key's ids.
	notarize : Signer, NotaryKey, { bundle : Str, zip : Str } -> List(Step)
	notarize = |signer, key, { bundle, zip }|
		match signer {
			P12(_) | AdHoc(Rcodesign) => [
				{ program: "rcodesign", args: ["encode-app-store-connect-api-key", "--output-path", key.json, key.issuer, key.key_id, key.key_file], shown: "rcodesign encode-app-store-connect-api-key (the API key, to ${key.json})" },
				step("rcodesign", ["notary-submit", "--api-key-file", key.json, "--staple", bundle]),
			]
			_ => [
				{ program: "xcrun", args: ["notarytool", "submit", zip, "--key", key.key_file, "--key-id", key.key_id, "--issuer", key.issuer, "--wait"], shown: "xcrun notarytool submit ${zip} (with the API key) --wait" },
				step("xcrun", ["stapler", "staple", bundle]),
			]
		}

	## The environment variables notarization reads, in the order they are
	## reported missing.
	notary_vars : List(Str)
	notary_vars = ["MACOS_NOTARY_ISSUER", "MACOS_NOTARY_KEY_ID", "MACOS_NOTARY_KEY"]

	## Whether `MACOS_NOTARY_KEY` holds the key itself rather than its path.
	is_pem : Str -> Bool
	is_pem = |text| text.trim().starts_with("-----BEGIN")

	## A sentence's name for who signed.
	describe : Signer -> Str
	describe = |signer|
		match signer {
			AdHoc(Codesign) => "sealed ad hoc with codesign"
			AdHoc(Rcodesign) => "sealed ad hoc with rcodesign"
			Keychain(identity) => "signed by ${identity} with codesign, with the hardened runtime"
			P12(_) => "signed with the Developer ID in MACOS_SIGN_P12 by rcodesign, with the hardened runtime"
		}
}

step : Str, List(Str) -> Sign.Step
step = |program, args| { program, args, shown: Str.join_with([program].concat(args), " ") }

here : Sign.Here
here = { mac: Bool.True, codesign: Bool.True, rcodesign: Bool.False, prefer: "", identity: "", p12: "" }

## Ad hoc: codesign on a Mac, rcodesign elsewhere, nobody without a tool.
expect {
	actual = [
		Sign.choose(here, Bool.False),
		Sign.choose({ ..here, mac: Bool.False, codesign: Bool.False, rcodesign: Bool.True }, Bool.False),
		Sign.choose({ ..here, rcodesign: Bool.True, prefer: "rcodesign" }, Bool.False),
		Sign.choose({ ..here, mac: Bool.False, codesign: Bool.False }, Bool.False),
	]
	actual == [Ok(Seal(AdHoc(Codesign))), Ok(Seal(AdHoc(Rcodesign))), Ok(Seal(AdHoc(Rcodesign))), Ok(Unsealed)]
}

## A Developer ID: the keychain with codesign, a .p12 with rcodesign.
expect {
	actual = [
		Sign.choose({ ..here, identity: "Developer ID Application: Jane (TEAM)" }, Bool.True),
		Sign.choose({ ..here, mac: Bool.False, codesign: Bool.False, rcodesign: Bool.True, p12: "/tmp/id.p12" }, Bool.True),
		Sign.choose({ ..here, rcodesign: Bool.True, p12: "/tmp/id.p12" }, Bool.True),
	]
	actual == [Ok(Seal(Keychain("Developer ID Application: Jane (TEAM)"))), Ok(Seal(P12("/tmp/id.p12"))), Ok(Seal(P12("/tmp/id.p12")))]
}

## Without what a Developer ID needs, or with a tool that is not here, it
## says what is missing.
expect {
	actual = [
		Sign.choose(here, Bool.True),
		Sign.choose({ ..here, p12: "/tmp/id.p12" }, Bool.True),
		Sign.choose({ ..here, prefer: "rcodesign" }, Bool.False),
		Sign.choose({ ..here, prefer: "signtool" }, Bool.False),
	]
	match actual {
		[Err(NoDeveloperId(mac)), Err(NoDeveloperId(no_tool)), Err(SignToolMissing("rcodesign")), Err(BadSignTool("signtool"))] =>
			mac.starts_with("set MACOS_SIGN_IDENTITY") and no_tool.starts_with("MACOS_SIGN_P12 is set, but rcodesign")
		_ => Bool.False
	}
}

## The command lines that sign: a Developer ID turns on the hardened
## runtime and a timestamp, and a password is only ever a file's path.
expect {
	actual = [AdHoc(Codesign), AdHoc(Rcodesign), Keychain("Developer ID Application: Jane (TEAM)"), P12("id.p12")].map(|signer| Sign.sign(signer, "counter.app", ".macos/secrets/p12-password").map(|s| s.shown))
	actual
		== [
			["xattr -cr counter.app", "codesign --force --sign - counter.app"],
			["rcodesign sign counter.app"],
			["xattr -cr counter.app", "codesign --force --sign Developer ID Application: Jane (TEAM) --options runtime --timestamp counter.app"],
			["rcodesign sign --p12-file id.p12 --p12-password-file .macos/secrets/p12-password --for-notarization --code-signature-flags runtime counter.app"],
		]
}

## The identity is one argument, however many spaces it has.
expect Sign.sign(Keychain("Developer ID Application: Jane (TEAM)"), "a.app", "").drop_first(1).first().map_ok(|s| s.args) == Ok(["--force", "--sign", "Developer ID Application: Jane (TEAM)", "--options", "runtime", "--timestamp", "a.app"])

expect Sign.verify("counter.app").shown == "codesign --verify --strict --verbose=2 counter.app"

## notarytool submits the zip and stapler staples the bundle; rcodesign
## does both from the bundle. Neither shows the key's ids.
expect {
	key = { issuer: "ISSUER-UUID", key_id: "KEYID", key_file: "AuthKey.p8", json: ".macos/secrets/notary.json" }
	paths = { bundle: "counter.app", zip: "dist/counter-1.0.zip" }
	mac = Sign.notarize(Keychain("Dev"), key, paths)
	anywhere = Sign.notarize(P12("id.p12"), key, paths)
	mac.map(|s| s.args)
		== [["notarytool", "submit", "dist/counter-1.0.zip", "--key", "AuthKey.p8", "--key-id", "KEYID", "--issuer", "ISSUER-UUID", "--wait"], ["stapler", "staple", "counter.app"]]
		and anywhere.map(|s| s.args) == [["encode-app-store-connect-api-key", "--output-path", ".macos/secrets/notary.json", "ISSUER-UUID", "KEYID", "AuthKey.p8"], ["notary-submit", "--api-key-file", ".macos/secrets/notary.json", "--staple", "counter.app"]]
		and mac.concat(anywhere).all(|s| !s.shown.contains("KEYID") and !s.shown.contains("ISSUER-UUID"))
}

expect Sign.is_pem("\n-----BEGIN PRIVATE KEY-----\nabc\n") and !Sign.is_pem("/home/me/AuthKey_ABC.p8")
