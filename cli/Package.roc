import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.System
import App
import Meta
import Sign
import Zip

## `package`: build `<name>.app`, seal or sign it, and write
## `dist/<name>-<version>.zip`, which people download and open.
##
## The zip is written here, byte for byte (`Zip`), so the program keeps its
## execute bit whichever system made it. With `--sign` the app is signed
## with a Developer ID, and with `--notarize` also notarized by Apple and
## the ticket stapled, and then zipped again. The credentials come from the
## environment (`Sign`), and are written only to `.macos/secrets/`, readable
## by the owner alone and removed when packaging ends.
Package := [].{

	## What `package` was asked for: the metadata flags, and whether to sign
	## with a Developer ID and to notarize (which implies signing).
	Options : { fields : Meta.Fields, sign : Bool, notarize : Bool }

	## Where the zip goes, beside `main.roc`.
	dist : Str
	dist = "dist"

	## Where secrets are written while they are needed.
	secrets : Str
	secrets = "${App.work}/secrets"

	run! : Options => Try({}, _)
	run! = |options| {
		developer = options.sign or options.notarize
		# Everything that needs no build is decided first, so that a missing
		# credential is reported before a long build.
		here = here!()
		choice = Sign.choose(here, developer)?
		notary = if (options.notarize) Ok(notary_key!()?) else Err(NotAsked)
		match (choice, notary) {
			(Seal(Keychain(_)), Ok(_)) if !Cmd.check_available!("xcrun") => return Err(NotaryToolMissing)
			_ => {}
		}
		password = match choice {
			Seal(P12(file)) => {
				if !(Path.exists!(Path.utf8(file))?) {
					return Err(NoP12File(file))
				}
				Ok(env!("MACOS_SIGN_P12_PASSWORD"))
			}
			_ => Err(NoP12)
		}
		match password {
			Ok(text) if text.is_empty() => return Err(NoP12Password)
			_ => {}
		}
		seconds = match env!("SOURCE_DATE_EPOCH") {
			"" => Zip.default_time
			text => U64.from_str(text) ? |_| BadSourceDateEpoch(text)
		}
		{ bundle, name, meta } = App.build!(options.fields)?
		zip = "${Package.dist}/${name}-${meta.version}.zip"
		outcome = seal_and_zip!({ here, choice, notary, password, seconds, bundle, zip })
		if Path.exists!(Path.utf8(Package.secrets)) ?? Bool.False {
			Path.delete_all!(Path.utf8(Package.secrets)) ?? {}
		}
		signed = outcome?
		bytes = Path.size_in_bytes!(Path.utf8(zip))?
		Stdout.line!("Packaged ${zip} (${Package.size(bytes)}): ${meta.name} ${meta.version}, ${signed}.")?
		Stdout.line!(Package.advice(choice, options.notarize))?
		Ok({})
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
seal_and_zip! : { here : Sign.Here, choice : [Seal(Sign.Signer), Unsealed], notary : Try({ issuer : Str, key_id : Str, key : Str }, [NotAsked]), password : Try(Str, [NoP12]), seconds : U64, bundle : Str, zip : Str } => Try(Str, _)
seal_and_zip! = |{ here, choice, notary, password, seconds, bundle, zip }| {
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
		Ok(text) => secret!("p12-password", text)?
		Err(NoP12) => ""
	}
	steps!(Sign.sign(signer, bundle, password_file))?
	if verify {
		steps!([Sign.verify(bundle)])?
	}
	write_zip!(bundle, zip, seconds)?
	match notary {
		Err(NotAsked) => Ok(Sign.describe(signer))
		Ok({ issuer, key_id, key }) => {
			key_file = if (Sign.is_pem(key)) secret!("AuthKey.p8", key)? else key
			json = secret!("notary.json", "")?
			Stdout.line!("Submitting ${zip} to Apple's notary service, and waiting for its answer (usually a few minutes)...")?
			steps!(Sign.notarize(signer, { issuer, key_id, key_file, json }, { bundle, zip }))?
			if verify {
				steps!([Sign.verify(bundle)])?
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
	if !Zip.fits(entries) {
		return Err(TooLargeToZip(bundle))
	}
	Path.create_all!(Path.utf8(Package.dist))?
	if Path.exists!(Path.utf8(zip))? {
		Path.delete!(Path.utf8(zip))?
	}
	Path.write_bytes!(Path.utf8(zip), Zip.archive(entries, seconds))?
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

## Run each step, showing it; each must succeed.
steps! : List(Sign.Step) => Try({}, _)
steps! = |list| {
	for { program, args, shown } in list {
		Stdout.line!("  ${shown}")?
		ran = Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!()?
		if ran.status != Exited(0) {
			return Err(StepFailed(shown))
		}
	}
	Ok({})
}

## Write a secret to `.macos/secrets/<name>`, readable by its owner alone,
## and give its path.
secret! : Str, Str => Try(Str, _)
secret! = |name, text| {
	Path.create_all!(Path.utf8(Package.secrets))?
	path = "${Package.secrets}/${name}"
	Path.write_utf8!(Path.utf8(path), "")?
	Path.set_permissions!(Path.utf8(path), OwnerOnly)?
	if !text.is_empty() {
		Path.write_utf8!(Path.utf8(path), text)?
	}
	Ok(path)
}

## The App Store Connect API key's parts, from the environment; all three
## are needed.
notary_key! : () => Try({ issuer : Str, key_id : Str, key : Str }, _)
notary_key! = || {
	var $missing = []
	for name in Sign.notary_vars {
		if env!(name).is_empty() {
			$missing = $missing.append(name)
		}
	}
	missing = $missing
	if !missing.is_empty() {
		return Err(NoNotaryKey(missing))
	}
	key = env!("MACOS_NOTARY_KEY")
	if !Sign.is_pem(key) and !(Path.exists!(Path.utf8(key))?) {
		return Err(NoNotaryKeyFile(key))
	}
	Ok({ issuer: env!("MACOS_NOTARY_ISSUER"), key_id: env!("MACOS_NOTARY_KEY_ID"), key })
}

## The system, the signing tools on PATH, and the signing environment.
here! : () => Sign.Here
here! = || {
	mac = match System.target!().os() {
		MacOS(_) => Bool.True
		_ => Bool.False
	}
	{
		mac,
		codesign: mac and Cmd.check_available!("codesign"),
		rcodesign: Cmd.check_available!("rcodesign"),
		prefer: env!("MACOS_SIGN_TOOL"),
		identity: env!("MACOS_SIGN_IDENTITY"),
		p12: env!("MACOS_SIGN_P12"),
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
