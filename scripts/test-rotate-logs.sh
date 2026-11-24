#!/bin/sh
# Tests for bin/rotate-logs in this repository, against temporary files only.
# Run as: sh scripts/test-rotate-logs.sh. Exit status is the number of failures.
#
# Checks: a log under its limit is left alone; a log over it is archived,
# verified and truncated; archives shift and the oldest is dropped; an archive
# decompresses to the original text; a missing log is ignored; the list can
# come from a configuration file; an invalid entry fails without touching the
# log; and the Agent Mail pruning removes only what it documents.
#
# Every run points the pruning folders at temporary paths, so the tests never
# prune a live Agent Mail installation on the machine that runs them.
set -u
rl=$(cd "$(dirname "$0")/../bin" && pwd)/rotate-logs
d=$(mktemp -d)
# Exported, so that every run below prunes only inside the temporary folder.
export ROTATE_RECLAIM_DIR="$d/no-reclaim" ROTATE_BAK_DIR="$d/no-bak" ROTATE_LOGS_CONF="$d/no-conf"
fail=0
check() { # NAME EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=$((fail + 1)); fi
}
big() { # FILE: write about 3 KB of distinct text
    i=0; : > "$1"
    while [ "$i" -lt 100 ]; do echo "line $i of $1 padding padding padding" >> "$1"; i=$((i + 1)); done
}
run() { ROTATE_LOGS="$d/a.log 1 3
$d/missing.log 1 3" sh "$rl" >/dev/null 2>&1; }

echo small > "$d/a.log"
ROTATE_LOGS="$d/a.log 1024 3" sh "$rl" >/dev/null 2>&1
check "under the limit is untouched" "small" "$(cat "$d/a.log")"
check "under the limit makes no archive" "no" "$([ -e "$d/a.log.0.bz2" ] && echo yes || echo no)"

big "$d/a.log"; cp "$d/a.log" "$d/orig1"; run
check "over the limit is truncated" "0" "$(stat -f %z "$d/a.log")"
check "archive 0 matches the original" "same" "$(bzcat "$d/a.log.0.bz2" | cmp -s - "$d/orig1" && echo same || echo differ)"

big "$d/a.log"; echo second >> "$d/a.log"; run
check "second rotation shifts archive 0 to 1" "same" "$(bzcat "$d/a.log.1.bz2" | cmp -s - "$d/orig1" && echo same || echo differ)"
check "new archive 0 holds the second log" "second" "$(bzcat "$d/a.log.0.bz2" | tail -1)"

big "$d/a.log"; run
big "$d/a.log"; run
check "only 3 archives kept" "3" "$(find "$d" -maxdepth 1 -name 'a.log.*.bz2' | wc -l | tr -d ' ')"
check "no temporary archive left" "0" "$(find "$d" -maxdepth 1 -name '*.tmp' | wc -l | tr -d ' ')"
check "missing log is ignored" "no" "$([ -e "$d/missing.log.0.bz2" ] && echo yes || echo no)"

mkdir -p "$d/r/rotation-old" "$d/r/rotation-new" "$d/r/other-old"
touch -t 202601010000 "$d/r/rotation-old" "$d/r/other-old"
ROTATE_LOGS="$d/none 1 1" ROTATE_RECLAIM_DIR="$d/r" sh "$rl" >/dev/null 2>&1
check "old Agent Mail rotation is pruned" "no" "$([ -e "$d/r/rotation-old" ] && echo yes || echo no)"
check "recent rotation is kept" "yes" "$([ -e "$d/r/rotation-new" ] && echo yes || echo no)"
check "other folders are never pruned" "yes" "$([ -e "$d/r/other-old" ] && echo yes || echo no)"

# Database backups: 30 old hourly backups and 2 recent ones. With keep 24 and
# 3 days, the 24 newest survive (2 recent, 22 old) and 8 old ones go. The
# database, the untimestamped .bak and a near-miss name are never touched.
b=$d/db; mkdir -p "$b"
i=10
while [ "$i" -lt 40 ]; do
    f=$b/storage.sqlite3.bak.202601${i}_000000; : > "$f"; touch -t 202601010000 "$f"; i=$((i + 1))
done
: > "$b/storage.sqlite3.bak.20991230_000000"; : > "$b/storage.sqlite3.bak.20991231_000000"
: > "$b/storage.sqlite3"; : > "$b/storage.sqlite3.bak"; : > "$b/storage.sqlite3.bak.20260101_000000.tmp"
touch -t 202601010000 "$b/storage.sqlite3" "$b/storage.sqlite3.bak" "$b/storage.sqlite3.bak.20260101_000000.tmp"
ROTATE_LOGS="$d/none 1 1" ROTATE_RECLAIM_DIR="$d/r" ROTATE_BAK_DIR="$b" sh "$rl" >/dev/null 2>&1
names() { for p in "$b"/*; do printf '%s\n' "${p##*/}"; done; }
check "24 newest backups are kept" "24" "$(names | grep -cE '^storage\.sqlite3\.bak\.[0-9]{8}_[0-9]{6}$')"
check "both recent backups survive" "2" "$(names | grep -c '2099')"
check "the oldest backup is removed" "no" "$([ -e "$b/storage.sqlite3.bak.20260110_000000" ] && echo yes || echo no)"
check "the database is untouched" "yes" "$([ -e "$b/storage.sqlite3" ] && echo yes || echo no)"
check "the untimestamped .bak is untouched" "yes" "$([ -e "$b/storage.sqlite3.bak" ] && echo yes || echo no)"
check "a near-miss name is untouched" "yes" "$([ -e "$b/storage.sqlite3.bak.20260101_000000.tmp" ] && echo yes || echo no)"

# A configuration file replaces the default list when ROTATE_LOGS is unset.
printf '# comment\n\n%s 1 2\n' "$d/c.log" > "$d/rotate.conf"
big "$d/c.log"
env -u ROTATE_LOGS ROTATE_LOGS_CONF="$d/rotate.conf" sh "$rl" >/dev/null 2>&1
check "a log listed in the configuration file is rotated" "yes" "$([ -e "$d/c.log.0.bz2" ] && echo yes || echo no)"

# An entry whose size or count is not a positive integer fails and is left alone.
big "$d/e.log"; cp "$d/e.log" "$d/orig-e"
ROTATE_LOGS="$d/e.log x 3" sh "$rl" >/dev/null 2>&1; rc=$?
check "an invalid entry exits 1" "1" "$rc"
check "an invalid entry leaves the log untouched" "same" "$(cmp -s "$d/e.log" "$d/orig-e" && echo same || echo differ)"

# ROTATE_PRUNE=0 turns the pruning off.
mkdir -p "$d/r2/rotation-old"; touch -t 202601010000 "$d/r2/rotation-old"
ROTATE_LOGS="$d/none 1 1" ROTATE_RECLAIM_DIR="$d/r2" ROTATE_PRUNE=0 sh "$rl" >/dev/null 2>&1
check "ROTATE_PRUNE=0 prunes nothing" "yes" "$([ -e "$d/r2/rotation-old" ] && echo yes || echo no)"

# A retention setting that is not a whole number stops the pruning.
ROTATE_LOGS="$d/none 1 1" ROTATE_RECLAIM_DIR="$d/r2" ROTATE_RECLAIM_DAYS=abc sh "$rl" >/dev/null 2>&1; rc=$?
check "a bad retention setting exits 1" "1" "$rc"
check "a bad retention setting prunes nothing" "yes" "$([ -e "$d/r2/rotation-old" ] && echo yes || echo no)"

rm -rf "$d"
echo "failures: $fail"
exit "$fail"
