import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import App
import Meta
import Sign
import Archive

## `package`: build `<name>.app`, seal or sign it, and write
## `dist/<name>-<version>.zip`, which people download and open.
##
## The zip is written here (`Archive`, with roc-zip), so the program keeps its
## execute bit whichever system made it. With `--sign` the app is signed
## with a Developer ID, and with `--notarize` also notarized by Apple and
## the ticket stapled, and then zipped again. The credentials come from the
## environment (`Sign`), and are written only to `.macos/secrets/`, readable
## by the owner alone and removed when packaging ends.
Package := [].{

	## What `package` was asked for: the metadata flags, whether to sign
	## with a Developer ID and to notarize (which implies signing), and what
	## to build (universal, or `--target`'s one Mac).
	Options : { fields : Meta.Fields, sign : Bool, notarize : Bool, how : App.Build }

	## Where the zip goes, in the app's directory.
	dist : Str
	dist = "dist"

	## Where secrets are written while they are needed.
	secrets : Str
	secrets = "${App.work}/secrets"

	## What signing and packaging read from the environment, each empty when
	## unset: `MACOS_SIGN_IDENTITY`, `MACOS_SIGN_P12`,
	## `MACOS_SIGN_P12_PASSWORD`, `MACOS_SIGN_TOOL`, the three
	## `MACOS_NOTARY_*` and `SOURCE_DATE_EPOCH`. `rcodesign` is the program
	## run as rcodesign: `rcodesign` on PATH, or a path `ci` installed it at.
	Environment : { identity : Str, p12 : Str, p12_password : Str, prefer : Str, notary_issuer : Str, notary_key_id : Str, notary_key : Str, source_date_epoch : Str, rcodesign : Str }

	## The environment as it is.
	environment! : () => Environment
	environment! = || {
		identity: env!("MACOS_SIGN_IDENTITY"),
		p12: env!("MACOS_SIGN_P12"),
		p12_password: env!("MACOS_SIGN_P12_PASSWORD"),
		prefer: env!("MACOS_SIGN_TOOL"),
		notary_issuer: env!("MACOS_NOTARY_ISSUER"),
		notary_key_id: env!("MACOS_NOTARY_KEY_ID"),
		notary_key: env!("MACOS_NOTARY_KEY"),
		source_date_epoch: env!("SOURCE_DATE_EPOCH"),
		rcodesign: "rcodesign",
	}

	## Build, sign and zip the app, and give the zip's path and metadata.
	run! : Options, Environment => Try({ zip : Str, meta : Meta.Resolved }, _)
	run! = |options, environment| {
		developer = options.sign or options.notarize
		# Everything that needs no build is decided first, so that a missing
		# credential is reported before a long build.
		here = here!(environment)
		choice = Sign.choose(here, developer)?
		notary = if (options.notarize) Ok(notary_key!(environment)?) else Err(NotAsked)
		match (choice, notary) {
			(Seal(Keychain(_)), Ok(_)) if !Cmd.check_available!("xcrun") => return Err(NotaryToolMissing)
			_ => {}
		}
		password = match choice {
			Seal(P12(file)) => {
				if !(Path.exists!(Path.utf8(file))?) {
					return Err(NoP12File(file))
				}
				Ok(environment.p12_password)
			}
			_ => Err(NoP12)
		}
		match password {
			Ok(text) if text.is_empty() => return Err(NoP12Password)
			_ => {}
		}
		seconds = match environment.source_date_epoch {
			"" => Archive.default_time
			text => U64.from_str(text) ? |_| BadSourceDateEpoch(text)
		}
		{ bundle, meta, .. } = App.build!({ fields: options.fields, how: options.how })?
		zip = "${Package.dist}/${Package.zip_name(meta.name, meta.release, options.how)}"
		outcome = seal_and_zip!({ here, choice, notary, password, seconds, bundle, zip, rcodesign: environment.rcodesign })
		Package.forget_secrets!()
		signed = outcome?
		bytes = Path.read_bytes!(Path.utf8(zip))?
		Stdout.line!("Packaged ${zip} (${Package.size(bytes.len())}, sha256 ${Crypto.SHA256.hash(bytes).to_hex()}): ${meta.name} ${meta.release}, ${signed}.")?
		Stdout.line!(Package.advice(choice, options.notarize))?
		Ok({ zip, meta })
	}

	## The zip's name: the app's name and version, and for a build for one
	## Mac (`--target`) its target, so the two never share a name.
	zip_name : Str, Str, App.Build -> Str
	zip_name = |name, release, how| {
		universal = Meta.zip_name(name, release)
		match how {
			Universal => universal
			Native(target) => "${universal.drop_suffix(".zip")}-${target}.zip"
		}
	}

	## Whether this is a Mac.
	on_mac! : () => Bool
	on_mac! = ||
		match System.target!().os() {
			MacOS(_) => Bool.True
			_ => Bool.False
		}

	## Remove `.macos/secrets/` and everything in it.
	forget_secrets! : () => {}
	forget_secrets! = || {
		if Path.exists!(Path.utf8(Package.secrets)) ?? Bool.False {
			Path.delete_all!(Path.utf8(Package.secrets)) ?? {}
		}
	}

	## Write a secret to `.macos/secrets/<name>`, readable by its owner alone,
	## and give its path.
	secret! : Str, List(U8) => Try(Str, _)
	secret! = |name, bytes| {
		Path.create_all!(Path.utf8(Package.secrets))?
		path = "${Package.secrets}/${name}"
		Path.write_bytes!(Path.utf8(path), [])?
		Path.set_permissions!(Path.utf8(path), OwnerOnly)?
		if !bytes.is_empty() {
			Path.write_bytes!(Path.utf8(path), bytes)?
		}
		Ok(path)
	}

	## A size in bytes, for a person: `1.9 MB`.
	size : U64 -> Str
	size = |bytes|
		if bytes < 1024 {
			"${bytes.to_str()} bytes"
		} else if bytes < 1024 * 1024 {
			tenths(bytes, 1024, "KB")
		} else {
			tenths(bytes, 1024 * 1024, "MB")
		}

	## What to tell the author about who can open the zip.
	advice : [Seal(Sign.Signer), Unsealed], Bool -> Str
	advice = |choice, notarized|
		match choice {
			Seal(Keychain(_)) | Seal(P12(_)) if notarized => "It is notarized: it opens on any Mac with no warning."
			Seal(Keychain(_)) | Seal(P12(_)) => "It is signed with a Developer ID but not notarized, so macOS still asks before it opens; add --notarize to fix that."
			_ => "It is not signed with a Developer ID, so a Mac it is downloaded to asks before it opens it: once, choose Open Anyway in System Settings > Privacy & Security, or run xattr -dr com.apple.quarantine on the app. `roc macos.roc package --help` describes signing it."
		}
}

tenths : U64, U64, Str -> Str
tenths = |bytes, unit, name| {
	scaled = (bytes * 10 + unit // 2) // unit
	"${(scaled // 10).to_str()}.${(scaled % 10).to_str()} ${name}"
}

## Seal or sign the bundle, zip it, and notarize it if asked; then say who
## signed it.
seal_and_zip! : { here : Sign.Here, choice : [Seal(Sign.Signer), Unsealed], notary : Try({ issuer : Str, key_id : Str, key : Str }, [NotAsked]), password : Try(Str, [NoP12]), seconds : U64, bundle : Str, zip : Str, rcodesign : Str } => Try(Str, _)
seal_and_zip! = |{ here, choice, notary, password, seconds, bundle, zip, rcodesign }| {
	verify = here.mac and here.codesign
	signer = match choice {
		Unsealed => {
			Stdout.line!("Neither codesign nor rcodesign is on PATH, so ${bundle} is not sealed: only its program is signed, by Roc's linker. Put rcodesign on PATH to seal it.")?
			write_zip!(bundle, zip, seconds)?
			return Ok("its program signed ad hoc by Roc's linker, the bundle not sealed")
		}
		Seal(s) => s
	}
	password_file = match password {
		Ok(text) => Package.secret!("p12-password", text.to_utf8())?
		Err(NoP12) => ""
	}
	steps!(Sign.sign(signer, bundle, password_file), rcodesign)?
	if verify {
		steps!([Sign.verify(bundle)], rcodesign)?
	}
	write_zip!(bundle, zip, seconds)?
	match notary {
		Err(NotAsked) => Ok(Sign.describe(signer))
		Ok({ issuer, key_id, key }) => {
			key_file = if (Sign.is_pem(key)) Package.secret!("AuthKey.p8", key.to_utf8())? else key
			json = Package.secret!("notary.json", [])?
			Stdout.line!("Submitting ${zip} to Apple's notary service, and waiting for its answer (usually a few minutes)...")?
			steps!(Sign.notarize(signer, { issuer, key_id, key_file, json }, { bundle, zip }), rcodesign)?
			if verify {
				steps!([Sign.verify(bundle)], rcodesign)?
			}
			# The ticket is stapled to the bundle, so zip it again.
			write_zip!(bundle, zip, seconds)?
			Ok("${Sign.describe(signer)}, notarized and stapled")
		}
	}
}

## Zip `bundle` as `zip`, replacing it.
write_zip! : Str, Str, U64 => Try({}, _)
write_zip! = |bundle, zip, seconds| {
	program_dir = "${bundle}/Contents/MacOS/"
	entries = walk!(bundle)?.map(
		|{ path, bytes, dir }|
			if dir {
				{ path: "${path}/", kind: Directory, bytes: [] }
			} else if path.starts_with(program_dir) {
				{ path, kind: Program, bytes }
			} else {
				{ path, kind: Plain, bytes }
			},
	)
	Path.create_all!(Path.utf8(Package.dist))?
	if Path.exists!(Path.utf8(zip))? {
		Path.delete!(Path.utf8(zip))?
	}
	Path.write_bytes!(Path.utf8(zip), Archive.archive(entries, seconds)?)?
	Ok({})
}

## Every directory and file under `dir`, `dir` included, with `/`-separated
## paths; a file with its bytes.
walk! : Str => Try(List({ path : Str, bytes : List(U8), dir : Bool }), _)
walk! = |dir| {
	var $found = [{ path: dir, bytes: [], dir: Bool.True }]
	for entry in Path.list!(Path.utf8(dir))? {
		path = "${dir}/${Path.filename(entry)?.display()}"
		if Path.is_sym_link!(entry)? {
			return Err(LinkInBundle(path))
		} else if Path.is_dir!(entry)? {
			$found = $found.concat(walk!(path)?)
		} else {
			$found = $found.append({ path, bytes: Path.read_bytes!(entry)?, dir: Bool.False })
		}
	}
	Ok($found)
}

## Run each step, showing it; each must succeed. `rcodesign` is the program
## run for a step of rcodesign's.
steps! : List(Sign.Step), Str => Try({}, _)
steps! = |list, rcodesign| {
	for { program, args, shown } in list {
		Stdout.line!("  ${shown}")?
		run = if (program == "rcodesign") rcodesign else program
		ran = Cmd.new(OsStr.from_str(run)).args(args.map(OsStr.from_str)).inherit_stdio().run!()?
		if ran.status != Exited(0) {
			return Err(StepFailed(shown))
		}
	}
	Ok({})
}

## The App Store Connect API key's parts; all three are needed.
notary_key! : Package.Environment => Try({ issuer : Str, key_id : Str, key : Str }, _)
notary_key! = |environment| {
	given = [("MACOS_NOTARY_ISSUER", environment.notary_issuer), ("MACOS_NOTARY_KEY_ID", environment.notary_key_id), ("MACOS_NOTARY_KEY", environment.notary_key)]
	missing = given.keep_if(|(_, value)| value.is_empty()).map(|(name, _)| name)
	if !missing.is_empty() {
		return Err(NoNotaryKey(missing))
	}
	key = environment.notary_key
	if !Sign.is_pem(key) and !(Path.exists!(Path.utf8(key))?) {
		return Err(NoNotaryKeyFile(key))
	}
	Ok({ issuer: environment.notary_issuer, key_id: environment.notary_key_id, key })
}

## The system, the signing tools here, and the signing environment.
here! : Package.Environment => Sign.Here
here! = |environment| {
	mac = Package.on_mac!()
	{
		mac,
		codesign: mac and Cmd.check_available!("codesign"),
		rcodesign: if (environment.rcodesign == "rcodesign") Cmd.check_available!("rcodesign") else Path.exists!(Path.utf8(environment.rcodesign)) ?? Bool.False,
		prefer: environment.prefer,
		identity: environment.identity,
		p12: environment.p12,
	}
}

## An environment variable's value, or empty when it is unset.
env! : Str => Str
env! = |name| Env.var_str!(OsStr.from_str(name)) ?? ""

expect [Package.size(512), Package.size(2048), Package.size(1978576), Package.size(10 * 1024 * 1024)] == ["512 bytes", "2.0 KB", "1.9 MB", "10.0 MB"]

## Only a notarized app opens with no warning.
expect {
	actual = [Package.advice(Seal(P12("id.p12")), Bool.True), Package.advice(Seal(Keychain("Dev")), Bool.False), Package.advice(Seal(AdHoc(Codesign)), Bool.False), Package.advice(Unsealed, Bool.False)]
	match actual {
		[notarized, signed, ad_hoc, unsealed] => notarized.contains("no warning") and signed.contains("--notarize") and ad_hoc.contains("Open Anyway") and unsealed == ad_hoc
		_ => Bool.False
	}
}

## A universal zip is named for the app and version; one Mac's names its target too.
expect [Package.zip_name("My App", "1.0.0-rc.1", Universal), Package.zip_name("My App", "1.2.0", Native("x64mac"))] == ["My-App-1.0.0-rc.1.zip", "My-App-1.2.0-x64mac.zip"]
