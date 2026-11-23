## A universal program: the Apple silicon and Intel builds of an app in one
## Mach-O file, as Apple's `lipo -create` writes it, but written here, so
## that `build` makes it on macOS, Linux and Windows alike.
##
## A universal ("fat") file is a big-endian header, the magic `ca fe ba be`
## and the number of slices, then for each slice its CPU type and subtype,
## where it starts, how long it is and the power of two it is aligned to,
## then the slices themselves, each a whole thin program padded to its
## alignment. A slice is copied byte for byte, so the ad hoc signature
## Roc's linker gave each program still covers it, and macOS runs the slice
## for its own CPU.
Universal := [].{

	## The CPU types of a Mach-O header (`CPU_TYPE_X86_64` and `CPU_TYPE_ARM64`).
	x86_64 : U32
	x86_64 = 0x01000007

	arm64 : U32
	arm64 = 0x0100000C

	## One thin 64-bit program and what its header says it is for.
	Slice : { cputype : U32, cpusubtype : U32, bytes : List(U8) }

	## A thin 64-bit Mach-O program for Apple silicon or Intel: its magic
	## `cf fa ed fe` and its CPU type and subtype, little-endian.
	slice : List(U8) -> Try(Slice, [NotAProgram])
	slice = |bytes| {
		if bytes.take_first(4) != [0xCF, 0xFA, 0xED, 0xFE] or bytes.len() < 32 {
			return Err(NotAProgram)
		}
		cputype = Universal.le32(bytes, 4)
		if cputype != Universal.x86_64 and cputype != Universal.arm64 {
			return Err(NotAProgram)
		}
		Ok({ cputype, cpusubtype: Universal.le32(bytes, 8), bytes })
	}

	## The alignment of a slice, as a power of two: a page of the CPU's, as
	## `lipo` aligns them (16 KiB on Apple silicon, 4 KiB on Intel).
	align : U32 -> U32
	align = |cputype| if (cputype == Universal.arm64) 14 else 12

	## One universal program from thin ones, one per CPU, in order of
	## alignment (the Intel slice first) as `lipo` orders them.
	merge : List(List(U8)) -> Try(List(U8), [NotAProgram, SameCpu])
	merge = |programs| {
		var $slices = []
		for program in programs {
			found = Universal.slice(program)?
			if $slices.any(|s| s.cputype == found.cputype) {
				return Err(SameCpu)
			}
			$slices = $slices.append(found)
		}
		ordered = $slices.sort_with(|a, b| if (a.cputype < b.cputype) Before else if (a.cputype > b.cputype) After else Same)
		header_len = 8 + 20 * ordered.len()
		var $records = []
		var $body = []
		var $at = header_len
		for s in ordered {
			step = Universal.shl(1, Universal.align(s.cputype)).to_u64()
			start = ($at + step - 1) // step * step
			$body = $body.concat(List.repeat(0, start - $at)).concat(s.bytes)
			$records = $records.concat([s.cputype, s.cpusubtype, start.to_u32_wrap(), s.bytes.len().to_u32_wrap(), Universal.align(s.cputype)].map(Universal.be32).join())
			$at = start + s.bytes.len()
		}
		Ok([0xCA, 0xFE, 0xBA, 0xBE].concat(Universal.be32(ordered.len().to_u32_wrap())).concat($records).concat($body))
	}

	## The CPU types a universal program holds, from its header.
	cpus : List(U8) -> List(U32)
	cpus = |bytes| {
		if bytes.take_first(4) != [0xCA, 0xFE, 0xBA, 0xBE] {
			return []
		}
		count = Universal.read_be32(bytes, 4).to_u64()
		var $found = []
		var $index = 0
		while $index < count {
			$found = $found.append(Universal.read_be32(bytes, 8 + 20 * $index))
			$index = $index + 1
		}
		$found
	}

	shl : U32, U32 -> U32
	shl = |n, by| n.shl_wrap(by.to_u8_wrap())

	le32 : List(U8), U64 -> U32
	le32 = |bytes, at| {
		byte = |i| (bytes.get(at + i) ?? 0).to_u32()
		byte(0) + byte(1).shl_wrap(8) + byte(2).shl_wrap(16) + byte(3).shl_wrap(24)
	}

	read_be32 : List(U8), U64 -> U32
	read_be32 = |bytes, at| bytes.drop_first(at).take_first(4).fold(0, |n, b| n.shl_wrap(8) + b.to_u32())

	be32 : U32 -> List(U8)
	be32 = |n| [n.shr_zf_wrap(24).to_u8_wrap(), n.shr_zf_wrap(16).to_u8_wrap(), n.shr_zf_wrap(8).to_u8_wrap(), n.to_u8_wrap()]
}

## The start of a thin program's header for a CPU, and some bytes after it.
thin : U32, U64 -> List(U8)
thin = |cputype, len| [0xCF, 0xFA, 0xED, 0xFE, cputype.to_u8_wrap(), cputype.shr_zf_wrap(8).to_u8_wrap(), cputype.shr_zf_wrap(16).to_u8_wrap(), cputype.shr_zf_wrap(24).to_u8_wrap(), 3, 0, 0, 0].concat(List.repeat(7, len - 12))

## Intel first, each slice at its page, padded with zeros, byte for byte.
expect {
	arm = thin(Universal.arm64, 40)
	intel = thin(Universal.x86_64, 48)
	fat = Universal.merge([arm, intel]) ?? []
	header = [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2]
		.concat([1, 0, 0, 7, 0, 0, 0, 3, 0, 0, 0x10, 0, 0, 0, 0, 48, 0, 0, 0, 12])
		.concat([1, 0, 0, 12, 0, 0, 0, 3, 0, 0, 0x40, 0, 0, 0, 0, 40, 0, 0, 0, 14])
	fat.take_first(48) == header
		and fat.sublist({ start: 0x1000, len: 48 }) == intel
		and fat.sublist({ start: 0x4000, len: 40 }) == arm
		and fat.len() == 0x4000 + 40
		and fat.sublist({ start: 48, len: 0x1000 - 48 }).all(|b| b == 0)
		and Universal.cpus(fat) == [Universal.x86_64, Universal.arm64]
}

## Only thin programs for Apple silicon or Intel, one of each.
expect {
	arm = thin(Universal.arm64, 40)
	actual = [Universal.merge([arm, arm]), Universal.merge([arm, [0xCA, 0xFE, 0xBA, 0xBE]]), Universal.merge([arm, thin(0x01000012, 40)])]
	actual == [Err(SameCpu), Err(NotAProgram), Err(NotAProgram)]
}

expect Universal.slice(thin(Universal.x86_64, 40)).map_ok(|s| (s.cputype, s.cpusubtype)) == Ok((0x01000007, 3)) and Universal.cpus([1, 2]) == []
