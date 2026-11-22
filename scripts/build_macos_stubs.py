#!/usr/bin/env python3
"""Write the platform's macOS linker interfaces from the reviewed catalog.

The Roc linker links a platform's `targets/macos-sysroot` (with
`-syslibroot`, `-F <sysroot>/System/Library/Frameworks`, `-L <sysroot>/usr/lib`
and `-framework` for every `X.framework/X.tbd` it finds there). This script
writes that sysroot as minimal TAPI v4 text stubs generated from
`host/interfaces.json` alone: install names and the selected symbol
names, nothing else. It reads no Apple SDK headers, TBDs, frameworks or
dylibs, and the platform bundle ships no Apple SDK file. macOS supplies every
implementation at run time.

    build_macos_stubs.py CATALOG SYSROOT [--audit LIBHOST]

With `--audit`, the host archive's unresolved references (from `nm -u`) are
checked against the catalog first: a reference the catalog does not own
fails the build, so adding one is a reviewed catalog change, never automatic.
The archive is only inventoried; it never adds to the catalog.
"""

import json
import pathlib
import re
import shutil
import subprocess
import sys

TARGET = "arm64-macos"
# Symbols the Roc application object itself provides at the final link.
ROC_PROVIDED = re.compile(r"_roc_engine_\w+")


def load(catalog_path):
    catalog = json.loads(pathlib.Path(catalog_path).read_text())
    if catalog.get("schema_version") != 1 or catalog.get("target") != TARGET:
        sys.exit(f"{catalog_path}: expected schema_version 1 for {TARGET}")
    owners = {}
    paths = set()
    for library in catalog["libraries"]:
        path = library["path"]
        if path in paths or path.startswith("/") or ".." in path.split("/"):
            sys.exit(f"{catalog_path}: bad or repeated path {path}")
        paths.add(path)
        if not library["install_name"].startswith("/") or not library.get("evidence"):
            sys.exit(f"{catalog_path}: {library['name']} needs an absolute install name and evidence")
        for symbol in library["symbols"]:
            if not re.fullmatch(r"[A-Za-z_$][A-Za-z0-9_$.]*", symbol):
                sys.exit(f"{catalog_path}: {symbol!r} is not a symbol name")
            if symbol in owners:
                sys.exit(f"{catalog_path}: {symbol} is owned by both {owners[symbol]} and {library['name']}")
            owners[symbol] = library["name"]
    return catalog, owners


def audit(libhost, owners):
    out = subprocess.run(["nm", "-u", libhost], check=True, capture_output=True, text=True).stdout
    wanted = {line.strip() for line in out.splitlines() if line.strip() and not line.endswith(":")}
    # One member of the archive may reference another's definitions.
    defined = subprocess.run(["nm", "-gUj", libhost], check=True, capture_output=True, text=True).stdout
    wanted -= {line.strip() for line in defined.splitlines() if line.strip() and not line.endswith(":")}
    missing = sorted(s for s in wanted if s not in owners and not ROC_PROVIDED.fullmatch(s))
    if missing:
        sys.exit("the host references system symbols the catalog does not own; review and add them to "
                 "host/interfaces.json:\n  " + "\n  ".join(missing))
    # Symbols the catalog keeps for the linker itself and for Roc-compiled
    # code are not the host's references, so an unused one is only noted.
    unused = sorted(set(owners) - wanted)
    if unused:
        print(f"note: catalog symbols the host archive does not reference (linker or Roc code may): {' '.join(unused)}", file=sys.stderr)


def tbd(library):
    lines = ["--- !tapi-tbd", "tbd-version: 4", f"targets: [ {TARGET} ]",
             f"install-name: '{library['install_name']}'"]
    symbols = sorted(library["symbols"])
    if symbols:
        lines += ["exports:", f"  - targets: [ {TARGET} ]", "    symbols:"]
        lines += [f"      - '{symbol}'" for symbol in symbols]
    return "\n".join(lines + ["..."]) + "\n"


def main(argv):
    if len(argv) not in (3, 5) or (len(argv) == 5 and argv[3] != "--audit"):
        sys.exit(__doc__)
    catalog, owners = load(argv[1])
    if len(argv) == 5:
        audit(argv[4], owners)
    sysroot = pathlib.Path(argv[2])
    if sysroot.exists():
        shutil.rmtree(sysroot)
    for library in catalog["libraries"]:
        destination = sysroot / library["path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(tbd(library))
    print(f"wrote {len(catalog['libraries'])} interfaces ({len(owners)} symbols) to {sysroot}")


if __name__ == "__main__":
    main(sys.argv)
