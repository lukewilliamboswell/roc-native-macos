## Sorting the files a listener drops or picks into songs and lyric files,
## and pairing them: `Track.m4a` dropped with `Track.lrc` takes those words.
##
## A file is a song or a lyric file by its extension, ignoring case. A song
## and a lyric file pair when they share a basename (the name without its
## extension, ignoring case) and the pair is unique: exactly one song and
## one lyric file of that basename among the files given together. Anything
## else stays unpaired, for the listener to attach with Add lyrics…, which
## also settles an ambiguous name.
Pairing := [].{

	## Extensions the starter treats as songs. The macOS decoder still
	## decides whether the contents can play.
	song_extensions : List(Str)
	song_extensions = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac", "opus", "ogg"]

	## The extensions read as lyrics: timed `.lrc` and plain `.txt`.
	lyric_extensions : List(Str)
	lyric_extensions = ["lrc", "txt"]

	## What a file is, by its name.
	Kind : [Song, LyricFile, Other]

	kind : Str -> Kind
	kind = |name| {
		ext = Pairing.split(name).ext
		if Pairing.song_extensions.contains(ext) {
			Song
		} else if Pairing.lyric_extensions.contains(ext) {
			LyricFile
		} else {
			Other
		}
	}

	## A file name's basename and extension, both lowercased. A name with no
	## dot, or only a leading one (`.lrc`), has no extension.
	split : Str -> { base : Str, ext : Str }
	split = |name| {
		lower = name.with_ascii_lowercased()
		parts = lower.split_on(".")
		match parts {
			[_] => { base: lower, ext: "" }
			["", _] => { base: lower, ext: "" }
			_ => { base: Str.join_with(parts.drop_last(1), "."), ext: parts.last() ?? "" }
		}
	}

	## How the files given together sort out, by their index in the list:
	## each song with the index of its lyric file if it has a unique one, the
	## lyric files no song took, and how many files were neither.
	Paired : { songs : List({ song : U64, lyrics : [NoLyrics, LyricsAt(U64)] }), unpaired : List(U64), others : U64 }

	pair : List(Str) -> Paired
	pair = |names| {
		indexed = names.map_with_index(|name, index| { index, kind: Pairing.kind(name), base: Pairing.split(name).base })
		songs = indexed.keep_if(|f| f.kind == Song)
		lyrics = indexed.keep_if(|f| f.kind == LyricFile)
		partner = |song| {
			same_songs = songs.keep_if(|s| s.base == song.base).len()
			match lyrics.keep_if(|l| l.base == song.base) {
				[only] if same_songs == 1 => LyricsAt(only.index)
				_ => NoLyrics
			}
		}
		paired = songs.map(|song| { song: song.index, lyrics: partner(song) })
		taken = paired.keep_oks(
			|p|
				match p.lyrics {
					LyricsAt(i) => Ok(i)
					NoLyrics => Err(NoLyrics)
				},
		)
		{
			songs: paired,
			unpaired: lyrics.map(|l| l.index).drop_if(|i| taken.contains(i)),
			others: indexed.keep_if(|f| f.kind == Other).len(),
		}
	}

	## A song's title as the player shows it: its name without the extension.
	title : Str -> Str
	title = |name|
		match name.split_on(".") {
			[_] => name
			["", _] => name
			parts => Str.join_with(parts.drop_last(1), ".")
		}
}

## Use the last extension and ignore case when comparing basenames.
expect Pairing.split("Track.Final.M4A") == { base: "track.final", ext: "m4a" } and Pairing.split("README") == { base: "readme", ext: "" } and Pairing.split(".lrc") == { base: ".lrc", ext: "" }

## Classify audio and lyric extensions separately.
expect Pairing.kind("a.FLAC") == Song and Pairing.kind("a.lrc") == LyricFile and Pairing.kind("a.png") == Other

## Drop the extension from the display title and keep its case.
expect Pairing.title("Track.Final.m4a") == "Track.Final" and Pairing.title("Track") == "Track"

## A unique basename pairs, ignoring case and order; the rest stay apart.
expect {
	paired = Pairing.pair(["clicks.lrc", "Clicks.wav", "other.mp3", "cover.png", "loose.txt"])
	paired == { songs: [{ song: 1, lyrics: LyricsAt(0) }, { song: 2, lyrics: NoLyrics }], unpaired: [4], others: 1 }
}

## Two lyric files, or two songs, of one basename are ambiguous: no pair.
expect {
	two_lyrics = Pairing.pair(["a.m4a", "a.lrc", "a.txt"])
	two_songs = Pairing.pair(["a.m4a", "a.mp3", "a.lrc"])
	two_lyrics.songs == [{ song: 0, lyrics: NoLyrics }]
		and two_lyrics.unpaired == [1, 2]
		and two_songs.songs == [{ song: 0, lyrics: NoLyrics }, { song: 1, lyrics: NoLyrics }]
		and two_songs.unpaired == [2]
}
