app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import cli.Stdout

## Any app shows it: run `roc check --watch main.roc` (or `roc main.roc`,
## and save a file it reads) in an empty directory, stop it, and the
## directory has a `.zig-cache/` it did not have before, whatever
## `XDG_CACHE_HOME` says.
main! = |_args| Stdout.line!("hi")
