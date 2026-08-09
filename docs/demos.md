# Demos

<<<<<<< HEAD
`apfel-plus` ships with real shell wrappers in `demo/`. This page keeps the longer walkthroughs that used to live in `README.md`; the quicker per-script overview stays in [../demo/README.md](../demo/README.md).

## Getting the demos

The demos are embedded in the `apfel-plus` binary, so you can write them out no matter how you installed apfel-plus (homebrew-core, the tariqwest tap, or a source build):
=======
`apfel` ships with real shell wrappers in `demo/`. This page keeps the longer walkthroughs; the per-script overview stays in [../demo/README.md](../demo/README.md).

## Getting the demos

The demos are embedded in the `apfel` binary - write them out no matter how you installed apfel (homebrew-core, the tap, or source):
>>>>>>> upstream/main

```bash
apfel-plus demos ./apfel-demos
```

<<<<<<< HEAD
This writes every demo script (executable) plus a `README.md` into `./apfel-demos`. Pass a different directory to put them elsewhere, and re-run after `brew upgrade apfel-plus` to refresh them. There is deliberately no `brew install --with-demo` option: homebrew-core does not support formula options, so a brew flag could never behave the same on core and on the tap - a built-in `apfel-plus demos` command does.

The tariqwest tap additionally installs each demo as an `apfel-plus-<name>` companion command (e.g. `apfel-plus-cmd`); `apfel-plus demos` is the channel-independent way to get the raw, editable scripts.
=======
This writes every demo (executable) plus a `README.md` into `./apfel-demos` (pass another directory to relocate). Re-run after `brew upgrade apfel` to refresh. There is deliberately no `brew install --with-demo` flag: homebrew-core does not support formula options, so it could never behave the same on core and tap - a built-in `apfel demos` command does.

The Arthur-Ficial tap additionally installs each demo as an `apfel-<name>` command (e.g. `apfel-cmd`); `apfel demos` is the channel-independent way to get the raw, editable scripts.
>>>>>>> upstream/main

## [../demo/cmd](../demo/cmd)

Natural language to shell command:

```bash
demo/cmd "find all .log files modified today"
# $ find . -name "*.log" -type f -mtime -1

demo/cmd -x "show disk usage sorted by size"   # -x = execute after confirm
demo/cmd -c "list open ports"                  # -c = copy to clipboard
```

### Shell function version

Add this to your `.zshrc` and use `cmd` from anywhere:

```bash
# cmd - natural language to shell command (apfel-plus). Add to .zshrc:
cmd(){ local x c r a; while [[ $1 == -* ]]; do case $1 in -x)x=1;shift;; -c)c=1;shift;; *)break;; esac; done; r=$(apfel-plus -q -s 'Output only a shell command.' "$*" | sed '/^```/d;/^#/d;s/\x1b\[[0-9;]*[a-zA-Z]//g;s/^[[:space:]]*//;/^$/d' | head -1); [[ $r ]] || { echo "no command generated"; return 1; }; printf '\e[32m$\e[0m %s\n' "$r"; [[ $c ]] && printf %s "$r" | pbcopy && echo "(copied)"; [[ $x ]] && { printf 'Run? [y/N] '; read -r a; [[ $a == y ]] && eval "$r"; }; return 0; }
```

```bash
cmd find all swift files larger than 1MB
cmd -c show disk usage sorted by size
cmd -x what process is using port 3000
cmd list all git branches merged into main
cmd count lines of code by language
```

## [../demo/oneliner](../demo/oneliner)

Complex pipe chains from plain English:

```bash
demo/oneliner "sum the third column of a CSV"
# $ awk -F',' '{sum += $3} END {print sum}' file.csv

demo/oneliner "count unique IPs in access.log"
# $ awk '{print $1}' access.log | sort | uniq -c | sort -rn
```

## [../demo/mac-narrator](../demo/mac-narrator)

Your Mac's inner monologue:

```bash
demo/mac-narrator
demo/mac-narrator --watch
```

## Also In `demo/`

- [../demo/wtd](../demo/wtd) - "what's this directory?" project orientation
- [../demo/explain](../demo/explain) - explain a command, error, or code snippet
- [../demo/naming](../demo/naming) - naming suggestions for functions, variables, and files
- [../demo/port](../demo/port) - identify what is using a port
- [../demo/gitsum](../demo/gitsum) - summarize recent git activity
