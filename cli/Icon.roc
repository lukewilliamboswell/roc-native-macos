## The app's icon, from `assets/icon.png` or `assets/icon.icns`.
##
## macOS shows an app's icon from an `.icns` file in the bundle, named by
## `CFBundleIconFile`. An `.icns` is a list of images, each an OSType, a
## big-endian length and the data, and since macOS 10.7 an entry may hold a
## PNG as it is. So a square PNG becomes an icon file with no Apple tool:
## one entry of its size, which macOS scales for the sizes it lacks.
Icon := [].{

	## The icon files an app may have, in `assets/`.
	png : Str
	png = "icon.png"

	icns : Str
	icns = "icon.icns"

	## Where the icon goes in the bundle, and the name `Info.plist` gives it.
	bundled : Str
	bundled = "AppIcon.icns"

	## A square PNG of 16, 32, 64, 128, 256, 512 or 1024 pixels, as the one
	## image of an `.icns`.
	from_png : List(U8) -> Try(List(U8), [NotPng, NotSquare({ width : U32, height : U32 }), UnsupportedSize(U32)])
	from_png = |bytes| {
		signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
		if bytes.take_first(8) != signature or bytes.drop_first(12).take_first(4) != "IHDR".to_utf8() {
			return Err(NotPng)
		}
		width = Icon.be32(bytes, 16)
		height = Icon.be32(bytes, 20)
		if width != height {
			return Err(NotSquare({ width, height }))
		}
		kind = match width {
			16 => "icp4"
			32 => "icp5"
			64 => "icp6"
			128 => "ic07"
			256 => "ic08"
			512 => "ic09"
			1024 => "ic10"
			_ => return Err(UnsupportedSize(width))
		}
		entry = kind.to_utf8().concat(Icon.put32(8 + bytes.len().to_u32_wrap())).concat(bytes)
		Ok("icns".to_utf8().concat(Icon.put32(8 + entry.len().to_u32_wrap())).concat(entry))
	}

	## Whether bytes are an `.icns` file: the `icns` tag and their length.
	is_icns : List(U8) -> Bool
	is_icns = |bytes| bytes.take_first(4) == "icns".to_utf8() and Icon.be32(bytes, 4).to_u64() == bytes.len()

	## The big-endian 32-bit number at `at`; 0 where the bytes run out.
	be32 : List(U8), U64 -> U32
	be32 = |bytes, at| bytes.drop_first(at).take_first(4).fold(0, |n, b| n.shl_wrap(8) + b.to_u32())

	put32 : U32 -> List(U8)
	put32 = |n| [n.shr_zf_wrap(24).to_u8_wrap(), n.shr_zf_wrap(16).to_u8_wrap(), n.shr_zf_wrap(8).to_u8_wrap(), n.to_u8_wrap()]
}

## The start of a PNG's header: its signature, then the IHDR chunk's length,
## type, width and height.
png_head : U32, U32 -> List(U8)
png_head = |width, height| [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13].concat("IHDR".to_utf8()).concat(Icon.put32(width)).concat(Icon.put32(height))

## A 1024-pixel PNG is the one `ic10` entry of an `.icns` that holds it whole.
expect {
	png = png_head(1024, 1024).concat([8, 6, 0, 0, 0])
	icns = Icon.from_png(png) ?? []
	icns.take_first(8) == "icns".to_utf8().concat([0, 0, 0, 45])
		and icns.drop_first(8).take_first(8) == "ic10".to_utf8().concat([0, 0, 0, 37])
		and icns.drop_first(16) == png
		and Icon.is_icns(icns)
}

## Each supported size has its own entry type.
expect {
	kinds = [16, 32, 64, 128, 256, 512].map(|n| Icon.from_png(png_head(n, n)).map_ok(|icns| Str.from_utf8_lossy(icns.drop_first(8).take_first(4))))
	kinds == [Ok("icp4"), Ok("icp5"), Ok("icp6"), Ok("ic07"), Ok("ic08"), Ok("ic09")]
}

## Anything else is refused with the reason.
expect {
	actual = [Icon.from_png("GIF89a".to_utf8()), Icon.from_png(png_head(1024, 512)), Icon.from_png(png_head(100, 100))]
	actual == [Err(NotPng), Err(NotSquare({ width: 1024, height: 512 })), Err(UnsupportedSize(100))]
}

expect !Icon.is_icns("icns".to_utf8().concat([0, 0, 0, 99])) and !Icon.is_icns([])
