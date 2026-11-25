#!/bin/sh
# Test suite for editable-mark-list.vim. Run it from anywhere:
#
#     test/run.sh            # against `vim`
#     VIM=nvim test/run.sh   # against something else
#
# Exits nonzero if any assertion failed.
#
# Two runs, both under a pty (via script(1)): Vim needs a terminal to draw
# in, and TextChanged only fires from its main input loop. The first types
# driver.ex in as keystrokes with -s; the second sources timed.vim, which
# types from timers. See harness.vim for why both are needed.

set -eu

EML_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export EML_ROOT
VIM=${VIM:-vim}

command -v "$VIM" >/dev/null || { echo "no $VIM in PATH" >&2; exit 1; }
command -v script >/dev/null || { echo "need script(1) to give vim a pty" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Fixtures: a.txt is a1 to a30, and so on.
for f in a b c; do
    i=1
    while [ "$i" -le 30 ]; do echo "$f$i"; i=$((i + 1)); done > "$work/$f.txt"
done

# Only the ':' lines are input; the rest of driver.ex is commentary. Vim reads
# the stream as typed keys, so lines are separated by CR.
grep '^:' "$EML_ROOT/test/driver.ex" | tr '\n' '\r' > "$work/keys"

# Runs $1 under a pty in $work. util-linux and BSD script(1) disagree about
# how to take a command.
#
# stdin is /dev/null on purpose: if script's own stdin is the terminal you
# launched from, it sits there copying it and never exits after vim does. The
# timeout caps a desynced run, where vim waits for a key that never comes.
run() {
    if script -qec true /dev/null >/dev/null 2>&1; then
        runner="script -qec \"$1\" /dev/null"
    else
        runner="script -q /dev/null sh -c \"$1\""
    fi
    ( cd "$work" && TERM=xterm timeout 120 sh -c "$runner" </dev/null >/dev/null 2>&1 )
}

base="$VIM -N -u '$EML_ROOT/test/harness.vim' -i NONE -n"

status=0
run "$base -s '$work/keys'" || status=$?
timed=0
run "$base -c 'source $EML_ROOT/test/timed.vim'" || timed=$?

failed=0
for result in result.txt result-timed.txt; do
    if [ ! -f "$work/$result" ]; then
        echo "vim wrote no $result at all." >&2
        failed=1
        continue
    fi
    cat "$work/$result"
done

for s in "$status" "$timed"; do
    if [ "$s" -eq 124 ]; then
        echo >&2
        echo "TIMED OUT -- vim was still waiting. The results above stop at the" >&2
        echo "last assertion that ran." >&2
    fi
    if [ "$s" -ne 0 ]; then
        failed=1
    fi
done
exit "$failed"
