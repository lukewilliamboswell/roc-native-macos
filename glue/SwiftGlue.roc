## A glue script for Swift hosts. It writes two files:
##
## - `roc_swift_abi.h`, the C declarations Swift needs to call Roc with the
##   C ABI (Swift calls C functions only through a header clang imports): the
##   list and box types, each record a provided procedure returns, laid out
##   field by field from the compiler's committed layout and checked with
##   static assertions, the runtime symbols the host defines, and the
##   provided symbols. Use it as the host's bridging header.
## - `RocGlue.swift`, which adds what a header leaves to the host:
##   - helpers for the platform's lists of bytes, which encode a list exactly
##     as Roc does (a refcount word before the bytes, the capacity shifted
##     left one bit, since the low bit marks a seamless slice) and read one
##     back;
##   - for each list of host-handle boxes an argument takes (`List(Box(U64))`),
##     the box's layout (where its refcount sits, and the address Roc frees
##     it at) and a constructor for the list, whose allocation carries the
##     element-count word Roc keeps before the refcount of a list with
##     refcounted elements. Both come from the compiler's layout facts, and
##     the header checks them with static assertions;
##   - one typed Swift function per provided procedure, named after it,
##     whose comment states the ownership the call transfers, and a
##     `…Guarded` twin that calls it under a jump point (`roc_guarded_*` in
##     the header), so a host can unwind a crash or a cancellation out of
##     that call alone (`roc_guard_unwind`) instead of ending the process;
##   - for the hosted functions, the `RocHostedFunctions` protocol, one
##     typed static requirement per hosted function, and one `@_cdecl`
##     export per hosted symbol that forwards to the host's conformance,
##     `RocHosted`, so the host implements each one with Swift types and
##     never spells a C signature itself.
##
## Only the shapes this platform uses are supported: byte lists, opaque
## boxes, lists of boxes of an integer (handles), integers, records of
## those, and the unit type; a hosted function takes integers and byte
## lists and returns an integer, a byte list or a box of an integer. Any
## other shape fails the generation with its name. Layout assertions are
## emitted for 64-bit hosts; a 32-bit host is refused.
app [make_glue] { pf: platform glue }

import pf.Types
import pf.File
import pf.TypeRepr
import pf.GlueInput
import pf.TypeTable
import pf.AbiFieldLayout

make_glue : List(Types) -> Try(List(File), Str)
make_glue = |types_list| {
	input = GlueInput.from_types(types_list)
	table = TypeTable.from_list(input.types)
	var $hosted_protocol = ""
	var $hosted_exports = ""
	var $hosted_decls = ""
	for func in input.hosted_functions {
		h = hosted_glue(table, func.name, func.ffi_symbol, func.arg_type_ids, func.ret_type_id, func.type_str)?
		$hosted_protocol = Str.concat($hosted_protocol, h.requirement)
		$hosted_exports = Str.concat($hosted_exports, h.export)
		$hosted_decls = Str.concat($hosted_decls, h.decl)
	}
	var $wrappers = ""
	var $guards = ""
	var $externs = ""
	var $records = ""
	var $named = []
	var $handles = []
	for entry in input.provides_entries {
		match entry.exported {
			ProvidedProcedure(func) => {
				for arg in func.args {
					match handle_list(table, entry.name, arg)? {
						Ok(found) =>
							if !$handles.any(|known| known.inner_name == found.inner_name) {
								$handles = $handles.append(found)
							}
						Err(NotHandles) => {}
					}
				}
				$wrappers = Str.concat($wrappers, procedure(table, entry.name, entry.ffi_symbol, func.args, func.ret)?)
				$guards = Str.concat($guards, guarded_decl(table, entry.name, entry.ffi_symbol, func.args, func.ret)?)
				$externs = Str.concat($externs, extern_decl(table, entry.name, entry.ffi_symbol, func.args, func.ret)?)
				if is_record(table, func.ret) {
					name = record_name(entry.name)
					shape = table.shape_id(func.ret)
					decl = match $named.find_first(|known| known.shape == shape) {
						Ok(known) => "typedef ${known.name} ${name};\n\n"
						Err(_) => record_decl(table, name, func.ret)?
					}
					$records = Str.concat($records, decl)
					$named = $named.append({ shape, name })
				}
			}
			ProvidedData(_) => return Err("SwiftGlue: provided data (${entry.name}) is not supported")
		}
	}
	hosted_header = if ($hosted_decls.is_empty()) "" else Str.concat("\n// Hosted symbols: the host defines them (RocGlue.swift exports each one\n// and forwards it to the host's `RocHosted`); compiled Roc calls them.\n", $hosted_decls)
	header = Str.join_with([header_prelude, Str.join_with($handles.map(handle_asserts), ""), $records, runtime_decls, $externs, hosted_header, guard_prelude, $guards, "#endif\n"], "")
	hosted_swift = if ($hosted_protocol.is_empty()) "" else Str.join_with([hosted_prelude, $hosted_protocol, "}\n\n/// The host's implementation must meet every requirement.\nprivate let rocHostedConformance: RocHostedFunctions.Type = RocHosted.self\n\n", $hosted_exports], "")
	swift = Str.join_with([prelude, Str.join_with($handles.map(handle_helpers), ""), "\n/// The platform's provided procedures.\nenum Roc {\n", $wrappers, "}\n", hosted_swift], "")
	Ok([{ name: "roc_swift_abi.h", content: header }, { name: "RocGlue.swift", content: swift }])
}

header_prelude : Str
header_prelude =
	\\// Generated by glue/SwiftGlue.roc from the platform's checked types. Do not edit.
	\\// The C ABI declarations for a Swift host; use as its bridging header.
	\\#ifndef ROC_SWIFT_ABI_H
	\\#define ROC_SWIFT_ABI_H
	\\
	\\#include <stddef.h>
	\\#include <stdint.h>
	\\#include <stdbool.h>
	\\#include <setjmp.h>
	\\
	\\#if UINTPTR_MAX != UINT64_MAX
	\\#error "SwiftGlue emits layouts for 64-bit hosts only"
	\\#endif
	\\
	\\/// A Roc list: elements, length, then capacity shifted left one bit (low
	\\/// bit set: a seamless slice, and the rest is its allocation pointer).
	\\typedef struct {
	\\    void *_Nullable elements;
	\\    size_t length;
	\\    size_t capacity_or_alloc_ptr;
	\\} RocList;
	\\_Static_assert(sizeof(RocList) == 24, "RocList size");
	\\_Static_assert(offsetof(RocList, length) == 8, "RocList.length offset");
	\\_Static_assert(offsetof(RocList, capacity_or_alloc_ptr) == 16, "RocList.capacity_or_alloc_ptr offset");
	\\
	\\/// A box over a value only Roc can release: pass it back to Roc.
	\\typedef void *_Nullable RocBox;
	\\
	\\

runtime_decls : Str
runtime_decls =
	\\// Runtime symbols the host defines; compiled Roc calls them directly.
	\\// roc_alloc and roc_realloc never return NULL.
	\\void *_Nonnull roc_alloc(size_t length, size_t alignment);
	\\void roc_dealloc(void *_Nullable ptr, size_t alignment);
	\\void *_Nonnull roc_realloc(void *_Nullable ptr, size_t new_length, size_t alignment);
	\\void roc_dbg(const uint8_t *_Nullable bytes, size_t len);
	\\void roc_expect_failed(const uint8_t *_Nullable bytes, size_t len);
	\\void roc_crashed(const uint8_t *_Nullable bytes, size_t len);
	\\
	\\// Provided symbols.
	\\

is_record : TypeTable, U64 -> Bool
is_record = |table, type_id|
	match table.get(type_id) {
		RocRecord(_) => Bool.True
		_ => Bool.False
	}

## A record a provided procedure returns, in the compiler's committed field
## order, with padding fields and assertions of every 64-bit offset.
record_decl : TypeTable, Str, U64 -> Try(Str, Str)
record_decl = |table, name, type_id| {
	layout = table.layout(type_id)
	var $fields = ""
	var $asserts = "_Static_assert(sizeof(${name}) == ${layout.size(Pointer64).to_str()}, \"${name} size\");\n_Static_assert(_Alignof(${name}) == ${layout.alignment(Pointer64).to_str()}, \"${name} alignment\");\n"
	var $pad = 0.U64
	for field in layout.record_fields() {
		size = AbiFieldLayout.size(field, Pointer64)
		if field.is_padding {
			$fields = Str.concat($fields, "    uint8_t _padding${$pad.to_str()}[${size.to_str()}];\n")
			$pad = $pad + 1
		} else {
			c = c_type(table, name, field.type_id)?
			$fields = Str.concat($fields, "    ${c} ${field.name};\n")
			$asserts = Str.concat($asserts, "_Static_assert(offsetof(${name}, ${field.name}) == ${AbiFieldLayout.offset(field, Pointer64).to_str()}, \"${name}.${field.name} offset\");\n")
		}
	}
	Ok("typedef struct {\n${$fields}} ${name};\n${$asserts}\n")
}

## A provided procedure's C declaration.
extern_decl : TypeTable, Str, Str, List(U64), U64 -> Try(Str, Str)
extern_decl = |table, name, symbol, args, ret| {
	var $params = []
	for arg in args {
		$params = $params.append(c_type(table, name, arg)?)
	}
	ret_c = match table.get(ret) {
		RocUnit => "void"
		RocRecord(_) => record_name(name)
		_ => c_type(table, name, ret)?
	}
	params = if ($params.is_empty()) "void" else Str.join_with($params, ", ")
	Ok("${ret_c} ${symbol}(${params});\n")
}

## The C spelling of an argument, result or field type.
c_type : TypeTable, Str, U64 -> Try(Str, Str)
c_type = |table, name, type_id|
	match table.get(type_id) {
		RocU8 => Ok("uint8_t")
		RocU16 => Ok("uint16_t")
		RocU32 => Ok("uint32_t")
		RocU64 => Ok("uint64_t")
		RocI8 => Ok("int8_t")
		RocI16 => Ok("int16_t")
		RocI32 => Ok("int32_t")
		RocI64 => Ok("int64_t")
		RocBool => Ok("bool")
		RocBox(_) => Ok("RocBox")
		RocList(element) =>
			match table.get(element) {
				RocU8 => Ok("RocList")
				RocBox(_) => handle_box(table, name, element).map_ok(|_| "RocList")
				_ => Err("SwiftGlue: ${name} uses a list of something other than U8 or a box of an integer")
			}
		_ => Err("SwiftGlue: ${name} uses a type this glue does not support")
	}

prelude : Str
prelude =
	\\// Generated by glue/SwiftGlue.roc from the platform's checked types. Do not edit.
	\\//
	\\// Requires `roc_swift_abi.h` (also from glue/SwiftGlue.roc) as the bridging header.
	\\
	\\extension RocList {
	\\    /// The empty list, with no allocation.
	\\    static var empty: RocList { RocList(elements: nil, length: 0, capacity_or_alloc_ptr: 0) }
	\\
	\\    /// A new `List(U8)` holding `bytes`, uniquely owned by whoever receives it.
	\\    /// The allocation comes from `roc_alloc`: one refcount word (1, unique)
	\\    /// then the bytes; the capacity is stored shifted left one bit, because
	\\    /// the low bit of `capacity_or_alloc_ptr` marks a seamless slice.
	\\    static func ownedBytes(_ bytes: [UInt8]) -> RocList {
	\\        if bytes.isEmpty { return .empty }
	\\        let header = MemoryLayout<Int>.size
	\\        let base = roc_alloc(header + bytes.count, header)
	\\        base.storeBytes(of: 1, as: Int.self)
	\\        let data = base + header
	\\        bytes.withUnsafeBytes { data.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
	\\        return RocList(elements: data, length: bytes.count, capacity_or_alloc_ptr: bytes.count << 1)
	\\    }
	\\
	\\    /// A copy of a `List(U8)`'s bytes. Reading never changes ownership; a
	\\    /// seamless slice reads its own window.
	\\    var bytes: [UInt8] {
	\\        guard let base = elements, length > 0 else { return [] }
	\\        return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: length))
	\\    }
	\\
	\\    /// Whether this list is a seamless slice into another allocation.
	\\    var isSeamlessSlice: Bool { capacity_or_alloc_ptr & 1 != 0 }
	\\
	\\    /// Release the host's one reference to a `List(U8)` it owns (a hosted
	\\    /// function's list argument, or a list a provided procedure returned).
	\\    /// The refcount word sits just before the allocation's elements (a
	\\    /// seamless slice keeps that address, tagged in the low bit, in place
	\\    /// of its capacity); 0 marks static data, never freed. When the last
	\\    /// reference goes the allocation is freed with `roc_dealloc`. Do not
	\\    /// use the list afterwards.
	\\    func releaseBytes() {
	\\        let data: UnsafeMutableRawPointer
	\\        if isSeamlessSlice {
	\\            guard let at = UnsafeMutableRawPointer(bitPattern: UInt(capacity_or_alloc_ptr & ~1)) else { return }
	\\            data = at
	\\        } else {
	\\            guard let elements else { return }
	\\            data = elements
	\\        }
	\\        let word = MemoryLayout<Int>.size
	\\        let count = (data - word).load(as: Int.self)
	\\        if count == 0 { return }
	\\        (data - word).storeBytes(of: count - 1, as: Int.self)
	\\        if count == 1 { roc_dealloc(data - word, word) }
	\\    }
	\\}
	\\

## One provided procedure as a Swift function.
procedure : TypeTable, Str, Str, List(U64), U64 -> Try(Str, Str)
procedure = |table, name, symbol, args, ret| {
	var $params = []
	var $call = []
	var $index = 0.U64
	for arg in args {
		swift = swift_type(table, name, arg)?
		param = "arg${$index.to_str()}"
		$params = $params.append("_ ${param}: ${swift}")
		$call = $call.append(param)
		$index = $index + 1
	}
	ret_swift = match table.get(ret) {
		RocUnit => "Void"
		RocRecord(_) => record_name(name)
		_ => swift_type(table, name, ret)?
	}
	call_args = Str.join_with($call.map(|c| ", ${c}"), "")
	zero = match table.get(ret) {
		RocBox(_) => "nil"
		_ => "${ret_swift}()"
	}
	guarded_params = Str.join_with(["_ jump: UnsafeMutablePointer<jmp_buf>"].concat($params), ", ")
	guarded = match table.get(ret) {
		RocUnit =>
			\\    static func ${camel(name)}Guarded(${guarded_params}) -> Bool {
			\\        roc_guarded_${symbol}(jump${call_args})
			\\    }
		_ =>
			\\    static func ${camel(name)}Guarded(${guarded_params}) -> ${ret_swift}? {
			\\        var out: ${ret_swift} = ${zero}
			\\        return roc_guarded_${symbol}(jump, &out${call_args}) ? out : nil
			\\    }
	}
	Ok(
		\\    /// `${name}` (`${symbol}`). Every refcounted argument (list or box)
		\\    /// moves into Roc: do not use or release it after the call. The
		\\    /// result is owned by the caller; an opaque box in it can only be
		\\    /// released by passing it back to Roc.
		\\    static func ${camel(name)}(${Str.join_with($params, ", ")}) -> ${ret_swift} {
		\\        ${symbol}(${Str.join_with($call, ", ")})
		\\    }
		\\
		\\    /// `${name}` under the jump point `jump` (`roc_guarded_${symbol}`):
		\\    /// as `${camel(name)}`, except that `roc_guard_unwind(jump)` from
		\\    /// inside the call comes back here with no result (nil, or false),
		\\    /// abandoning everything the call held. The arguments move into
		\\    /// Roc either way.
		\\${guarded}
		\\
		\\
	)
}

## A provided procedure under a jump point: the header's `roc_guarded_*`.
## The jump point is taken in this C frame, which then calls Roc directly,
## so unwinding to it skips only Roc frames and the frame of the runtime
## symbol or hosted function that unwinds. It is never inlined: a frame
## that called `_setjmp` must not become part of its (Swift) caller.
guarded_decl : TypeTable, Str, Str, List(U64), U64 -> Try(Str, Str)
guarded_decl = |table, name, symbol, args, ret| {
	var $params = []
	var $call = []
	var $index = 0.U64
	for arg in args {
		$params = $params.append(", ${c_type(table, name, arg)?} arg${$index.to_str()}")
		$call = $call.append("arg${$index.to_str()}")
		$index = $index + 1
	}
	call = "${symbol}(${Str.join_with($call, ", ")})"
	params = Str.join_with($params, "")
	match table.get(ret) {
		RocUnit => Ok("static __attribute__((noinline)) bool roc_guarded_${symbol}(jmp_buf *_Nonnull jump${params}) {\n    if (_setjmp(*jump) != 0) return false;\n    ${call};\n    return true;\n}\n\n")
		RocRecord(_) => Ok("static __attribute__((noinline)) bool roc_guarded_${symbol}(jmp_buf *_Nonnull jump, ${record_name(name)} *_Nonnull out${params}) {\n    if (_setjmp(*jump) != 0) return false;\n    *out = ${call};\n    return true;\n}\n\n")
		_ => {
			ret_c = c_type(table, name, ret)?
			Ok("static __attribute__((noinline)) bool roc_guarded_${symbol}(jmp_buf *_Nonnull jump, ${ret_c} *_Nonnull out${params}) {\n    if (_setjmp(*jump) != 0) return false;\n    *out = ${call};\n    return true;\n}\n\n")
		}
	}
}

guard_prelude : Str
guard_prelude =
	\\
	\\// Guarded calls. `roc_guarded_<symbol>` takes a jump point and calls the
	\\// provided symbol; `roc_guard_unwind`, called on the same thread from a
	\\// runtime symbol or a hosted function while that call runs, returns to
	\\// it, abandoning the Roc frames between. Only a host that then discards
	\\// everything the abandoned call held (its whole heap) may unwind.
	\\static inline _Noreturn void roc_guard_unwind(jmp_buf *_Nonnull jump) { _longjmp(*jump, 1); }
	\\
	\\

## One hosted function: its C declaration, its typed requirement in
## `RocHostedFunctions` and the `@_cdecl` export that forwards to it.
HostedGlue : { decl : Str, requirement : Str, export : Str }

## The C declaration, Swift requirement and export of a hosted function, or
## the generation error naming it. A unit argument is not ABI-visible.
hosted_glue : TypeTable, Str, Str, List(U64), U64, Str -> Try(HostedGlue, Str)
hosted_glue = |table, name, symbol, arg_ids, ret, type_str| {
	var $c = []
	var $swift = []
	var $call = []
	var $index = 0.U64
	for arg in arg_ids {
		match table.get(arg) {
			RocUnit => {}
			_ => {
				param = "arg${$index.to_str()}"
				$c = $c.append("${hosted_c(table, name, arg)?} ${param}")
				$swift = $swift.append("_ ${param}: ${hosted_swift(table, name, arg)?}")
				$call = $call.append(param)
				$index = $index + 1
			}
		}
	}
	(ret_c, ret_swift) = match table.get(ret) {
		RocBox(_) =>
			match handle_box(table, name, ret) {
				Ok(_) => ("void *_Nonnull", "UnsafeMutableRawPointer")
				Err(e) => return Err(e)
			}
		_ => (hosted_c(table, name, ret)?, hosted_swift(table, name, ret)?)
	}
	method = hosted_method(name)
	c_params = if ($c.is_empty()) "void" else Str.join_with($c, ", ")
	swift_params = Str.join_with($swift, ", ")
	call = Str.join_with($call, ", ")
	requirement =
		\\    /// `${name} : ${type_str}` (`${symbol}`). A list argument is the
		\\    /// host's to release (`releaseBytes`); a list or box it returns
		\\    /// moves to Roc.
		\\    static func ${method}(${swift_params}) -> ${ret_swift}
		\\
		\\
	export =
		\\@_cdecl("${symbol}")
		\\public func ${symbol}_export(${swift_params}) -> ${ret_swift} {
		\\    RocHosted.${method}(${call})
		\\}
		\\
		\\
	Ok({ decl: "${ret_c} ${symbol}(${c_params}); // ${name} : ${type_str}\n", requirement, export })
}

hosted_prelude : Str
hosted_prelude =
	\\
	\\/// The platform's hosted functions, each a static requirement the host
	\\/// meets in its `RocHosted` type; the exports below are the symbols
	\\/// compiled Roc calls, and each forwards to it.
	\\protocol RocHostedFunctions {
	\\

## `Hosted.append_file!` is `hostedAppendFile`.
hosted_method : Str -> Str
hosted_method = |name| {
	words = plain(name).split_on(".").fold([], |acc, part| acc.concat(part.split_on("_")))
	match words {
		[first, .. as rest] => Str.concat(lowered(first), Str.join_with(rest.map(capitalized), ""))
		[] => name
	}
}

lowered : Str -> Str
lowered = |word| {
	bytes = word.to_utf8()
	match bytes {
		[first, .. as rest] if first >= 'A' and first <= 'Z' => Str.from_utf8(List.concat([first + 32], rest)) ?? word
		_ => word
	}
}

## The C spelling of a hosted function's argument or result.
hosted_c : TypeTable, Str, U64 -> Try(Str, Str)
hosted_c = |table, name, type_id|
	match table.get(type_id) {
		RocList(element) =>
			match table.get(element) {
				RocU8 => Ok("RocList")
				_ => Err("SwiftGlue: hosted function ${name} uses a list of something other than U8")
			}
		RocBox(_) => Err("SwiftGlue: hosted function ${name} takes a box")
		RocRecord(_) => Err("SwiftGlue: hosted function ${name} uses a record")
		_ => c_type(table, name, type_id)
	}

## The Swift spelling of a hosted function's argument or result.
hosted_swift : TypeTable, Str, U64 -> Try(Str, Str)
hosted_swift = |table, name, type_id|
	match table.get(type_id) {
		RocList(element) =>
			match table.get(element) {
				RocU8 => Ok("RocList")
				_ => Err("SwiftGlue: hosted function ${name} uses a list of something other than U8")
			}
		RocBox(_) => Err("SwiftGlue: hosted function ${name} takes a box")
		RocRecord(_) => Err("SwiftGlue: hosted function ${name} uses a record")
		_ => swift_type(table, name, type_id)
	}


## The Swift spelling of an argument or result type.
swift_type : TypeTable, Str, U64 -> Try(Str, Str)
swift_type = |table, name, type_id|
	match table.get(type_id) {
		RocU8 => Ok("UInt8")
		RocU16 => Ok("UInt16")
		RocU32 => Ok("UInt32")
		RocU64 => Ok("UInt64")
		RocI8 => Ok("Int8")
		RocI16 => Ok("Int16")
		RocI32 => Ok("Int32")
		RocI64 => Ok("Int64")
		RocBool => Ok("Bool")
		RocBox(_) => Ok("RocBox?")
		RocList(element) =>
			match table.get(element) {
				RocU8 => Ok("RocList")
				RocBox(_) => handle_box(table, name, element).map_ok(|_| "RocList")
				_ => Err("SwiftGlue: ${name} takes a list of something other than U8 or a box of an integer")
			}
		_ => Err("SwiftGlue: ${name} uses a type this glue does not support")
	}

## A list of host-handle boxes (`List(Box(U64))`), as the compiler lays out
## the list's element and the box's payload. Every number here is a
## committed layout fact, not an assumption.
Handles : {
	inner_name : Str,
	inner_c : Str,
	inner_swift : Str,
	element_size : U64,
	element_alignment : U64,
	elements_refcounted : Bool,
	payload_size : U64,
	payload_alignment : U64,
}

## The handle list an argument is, `Err(NotHandles)` when it is not a list
## of boxes, or the generation error naming the entry point when it is one
## this glue cannot construct.
handle_list : TypeTable, Str, U64 -> Try(Try(Handles, [NotHandles]), Str)
handle_list = |table, name, type_id|
	match table.get(type_id) {
		RocList(element) =>
			match table.get(element) {
				RocBox(_) => Ok(Ok(handle_box(table, name, element)?))
				_ => Ok(Err(NotHandles))
			}
		_ => Ok(Err(NotHandles))
	}

## The layout facts of a `Box(int)` list element. Only a payload of a plain
## integer is supported: the host mints such a box and never releases its
## payload, so a payload holding a refcounted value would need a release
## this glue does not generate.
handle_box : TypeTable, Str, U64 -> Try(Handles, Str)
handle_box = |table, name, element| {
	inner = match table.get(element) {
		RocBox(payload) => payload
		_ => return Err("SwiftGlue: ${name} uses a list whose elements are not boxes")
	}
	(inner_name, inner_c, inner_swift) = match table.get(inner) {
		RocU8 => ("U8", "uint8_t", "UInt8")
		RocU16 => ("U16", "uint16_t", "UInt16")
		RocU32 => ("U32", "uint32_t", "UInt32")
		RocU64 => ("U64", "uint64_t", "UInt64")
		RocI8 => ("I8", "int8_t", "Int8")
		RocI16 => ("I16", "int16_t", "Int16")
		RocI32 => ("I32", "int32_t", "Int32")
		RocI64 => ("I64", "int64_t", "Int64")
		_ => return Err("SwiftGlue: ${name} uses a list of boxes of something other than an integer")
	}
	payload = table.layout(inner)
	if payload.contains_refcounted or table.is_refcounted(inner) {
		return Err("SwiftGlue: ${name} uses a list of boxes whose payload is refcounted")
	}
	elem = table.layout(element)
	Ok({
		inner_name,
		inner_c,
		inner_swift,
		element_size: elem.size(Pointer64),
		element_alignment: elem.alignment(Pointer64),
		elements_refcounted: table.is_refcounted(element),
		payload_size: payload.size(Pointer64),
		payload_alignment: payload.alignment(Pointer64),
	})
}

## How many bytes Roc keeps before a list's elements: the refcount word,
## and for refcounted elements the element-count word before it (so a
## seamless slice can release the elements of its whole allocation), padded
## to the element alignment (`allocateWithRefcount`,
## src/builtins/utils.zig).
list_header_bytes : Handles -> U64
list_header_bytes = |h| {
	required : U64
	required = if (h.elements_refcounted) 16 else 8
	required.max(h.element_alignment)
}

## How many bytes Roc keeps before a box's payload: the refcount word,
## padded to the payload alignment (ZigGlue's `allocateBox` with no
## refcounted payload).
box_header_bytes : Handles -> U64
box_header_bytes = |h| (8.U64).max(h.payload_alignment)

## The alignment Roc frees a box's allocation with.
box_alignment : Handles -> U64
box_alignment = |h| (8.U64).max(h.payload_alignment)

## One box's header and payload rounded up to its alignment: the stride of a
## host table of them.
box_stride : Handles -> U64
box_stride = |h| {
	raw = box_header_bytes(h) + h.payload_size
	a = box_alignment(h)
	((raw + a - 1) // a) * a
}

## The header's derived constants for one handle list, and assertions that
## the C types the host uses have the compiler's committed layout.
handle_asserts : Handles -> Str
handle_asserts = |h| {
	n = h.inner_name
	upper = "ROC_BOX_${n}"
	refcounted = if (h.elements_refcounted) "1" else "0"
	\\/// `List(Box(${n}))`, a list of host-handle boxes. From the compiler's
	\\/// committed layouts: an element is a box pointer (${h.element_size.to_str()} bytes, aligned
	\\/// ${h.element_alignment.to_str()}; refcounted: ${refcounted}), and the payload, ${n}, is ${h.payload_size.to_str()} bytes aligned
	\\/// ${h.payload_alignment.to_str()} and holds nothing refcounted.
	\\#define ${upper}_LIST_HEADER_BYTES ${list_header_bytes(h).to_str()}
	\\#define ${upper}_LIST_ELEMENTS_REFCOUNTED ${refcounted}
	\\#define ${upper}_HEADER_BYTES ${box_header_bytes(h).to_str()}
	\\#define ${upper}_ALIGNMENT ${box_alignment(h).to_str()}
	\\#define ${upper}_STRIDE ${box_stride(h).to_str()}
	\\_Static_assert(sizeof(RocBox) == ${h.element_size.to_str()}, "List(Box(${n})) element size");
	\\_Static_assert(_Alignof(RocBox) == ${h.element_alignment.to_str()}, "List(Box(${n})) element alignment");
	\\_Static_assert(sizeof(${h.inner_c}) == ${h.payload_size.to_str()}, "Box(${n}) payload size");
	\\_Static_assert(_Alignof(${h.inner_c}) == ${h.payload_alignment.to_str()}, "Box(${n}) payload alignment");
	\\_Static_assert(${upper}_HEADER_BYTES >= sizeof(intptr_t), "Box(${n}) header holds the refcount word");
	\\_Static_assert(${upper}_LIST_HEADER_BYTES >= (${upper}_LIST_ELEMENTS_REFCOUNTED + 1) * sizeof(intptr_t), "List(Box(${n})) header holds its count and refcount words");
	\\
	\\
}

## The Swift helpers for one handle list: the box layout and the list
## constructor, reading the header's constants.
handle_helpers : Handles -> Str
handle_helpers = |h| {
	n = h.inner_name
	t = h.inner_swift
	upper = "ROC_BOX_${n}"
	count_word = if (h.elements_refcounted)
		\\        // Elements are refcounted, so Roc keeps the element count in
		\\        // the word before the refcount.
		\\        (data - 2 * MemoryLayout<Int>.size).storeBytes(of: boxes.count, as: Int.self)
		\\
	else
		""
	\\
	\\/// `Box(${n})` as the compiler lays it out (`${upper}_*` in the header):
	\\/// a refcount word (1: unique) ends at the payload, the allocation starts
	\\/// `headerBytes` before it, and Roc frees the box with
	\\/// `roc_dealloc(payload - headerBytes, alignment)` when its last reference
	\\/// goes. A host that mints such boxes in a table of its own recognises
	\\/// that address in `roc_dealloc` and must not free it.
	\\enum RocBox${n} {
	\\    static let headerBytes = Int(${upper}_HEADER_BYTES)
	\\    static let alignment = Int(${upper}_ALIGNMENT)
	\\    /// One box, header and payload, rounded up to its alignment.
	\\    static let stride = Int(${upper}_STRIDE)
	\\
	\\    /// Write a unique box holding `value` into the `stride` bytes at
	\\    /// `allocation` (aligned to `alignment`) and return the box.
	\\    static func initialize(at allocation: UnsafeMutableRawPointer, _ value: ${t}) -> UnsafeMutableRawPointer {
	\\        let payload = allocation + headerBytes
	\\        (payload - MemoryLayout<Int>.size).storeBytes(of: 1, as: Int.self)
	\\        payload.storeBytes(of: value, as: ${t}.self)
	\\        return payload
	\\    }
	\\
	\\    /// The address `roc_dealloc` receives when Roc frees `box`.
	\\    static func allocation(of box: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer { box - headerBytes }
	\\
	\\    /// The value `box` holds.
	\\    static func value(of box: UnsafeMutableRawPointer) -> ${t} { box.load(as: ${t}.self) }
	\\}
	\\
	\\extension RocList {
	\\    /// A new `List(Box(${n}))` holding `boxes` in order, uniquely owned by
	\\    /// whoever receives it; each box's reference moves into the list. The
	\\    /// allocation comes from `roc_alloc`: `${upper}_LIST_HEADER_BYTES`
	\\    /// header bytes ending in the refcount word (1, unique), then the box
	\\    /// pointers; the capacity is stored shifted left one bit.
	\\    static func ownedBoxes${n}(_ boxes: [UnsafeMutableRawPointer]) -> RocList {
	\\        if boxes.isEmpty { return .empty }
	\\        let header = Int(${upper}_LIST_HEADER_BYTES)
	\\        let width = MemoryLayout<UnsafeMutableRawPointer>.stride
	\\        let base = roc_alloc(header + boxes.count * width, max(MemoryLayout<Int>.size, MemoryLayout<UnsafeMutableRawPointer>.alignment))
	\\        let data = base + header
	\\        (data - MemoryLayout<Int>.size).storeBytes(of: 1, as: Int.self)
	\\${count_word}        for (i, box) in boxes.enumerated() { (data + i * width).storeBytes(of: box, as: UnsafeMutableRawPointer.self) }
	\\        return RocList(elements: data, length: boxes.count, capacity_or_alloc_ptr: boxes.count << 1)
	\\    }
	\\}
	\\
}

## The name the C glue gives an entry point's record type: `init_for_host`
## is `InitForHost`, and `ask_for_host!` is `AskForHost`.
record_name : Str -> Str
record_name = |name| Str.join_with(plain(name).split_on("_").map(capitalized), "")

## `event_for_host` is `eventForHost`, and `work_for_host!` is `workForHost`.
camel : Str -> Str
camel = |name|
	match plain(name).split_on("_") {
		[first, .. as rest] => Str.concat(first, Str.join_with(rest.map(capitalized), ""))
		[] => name
	}

## A Roc name without the `!` an effectful one ends with.
plain : Str -> Str
plain = |name| if (name.ends_with("!")) Str.from_utf8(name.to_utf8().drop_last(1)) ?? name else name

capitalized : Str -> Str
capitalized = |word| {
	bytes = word.to_utf8()
	match bytes {
		[first, .. as rest] if first >= 'a' and first <= 'z' => Str.from_utf8(List.concat([first - 32], rest)) ?? word
		_ => word
	}
}

expect record_name("init_for_host") == "InitForHost"
expect record_name("ask_for_host!") == "AskForHost"
expect camel("event_for_host") == "eventForHost"
expect camel("work_for_host!") == "workForHost"
expect hosted_method("Hosted.append_file!") == "hostedAppendFile"
expect hosted_method("Hosted.mint!") == "hostedMint"
